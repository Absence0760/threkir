package com.runapp.watchwear.workout

import java.io.File
import java.time.LocalDate
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.double
import kotlinx.serialization.json.int
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/// The Kotlin step runner against the phone's reference runner, through the
/// shared vectors (`fixtures/watch_workout_payload.json` § runner_vectors,
/// replayed against the Dart runner by
/// `packages/run_recorder/test/workout_runner_vectors_test.dart`).
class WorkoutRunnerTest {

    private val fixture: JsonObject = run {
        val f = File("../../../../fixtures/watch_workout_payload.json")
        Json.parseToJsonElement(f.readText()).jsonObject
    }

    private fun workoutOf(steps: List<PushedStep>, unpaced: Boolean = false) = PushedWorkout(
        planWorkoutId = "pw-1",
        scheduledDate = LocalDate.of(2026, 10, 16),
        workoutKind = "interval",
        unpaced = unpaced,
        steps = steps,
    )

    private fun stepOf(o: JsonObject) = PushedStep(
        kind = StepKind.fromToken(o["kind"]!!.jsonPrimitive.content)!!,
        repIndex = o["rep_index"]?.jsonPrimitive?.intOrNull,
        repTotal = o["rep_total"]?.jsonPrimitive?.intOrNull,
        distanceM = o["distance_m"]?.jsonPrimitive?.intOrNull,
        durationS = o["duration_s"]?.jsonPrimitive?.intOrNull,
        paceSPerKm = o["pace_s_per_km"]!!.jsonPrimitive.int,
        toleranceSPerKm = o["tolerance_s_per_km"]!!.jsonPrimitive.int,
    )

    private fun token(e: WorkoutEvent): String? = when (e) {
        is WorkoutEvent.Transition -> "transition:${e.currentIndex}"
        is WorkoutEvent.Warning -> "warning"
        WorkoutEvent.Complete -> "complete"
        is WorkoutEvent.PaceDrift -> null
    }

    @Test
    fun `the shared vectors replay to the reference runner's results`() {
        val vectors = fixture["runner_vectors"]!!.jsonArray
        assertTrue(vectors.isNotEmpty())
        for (v in vectors) {
            val vec = v.jsonObject
            val name = vec["name"]!!.jsonPrimitive.content
            val runner = WorkoutRunner(workoutOf(vec["steps"]!!.jsonArray.map { stepOf(it.jsonObject) }))
            for (t in vec["ticks"]!!.jsonArray) {
                val tick = t.jsonObject
                val events = runner.onTotals(
                    distanceM = tick["distance_m"]!!.jsonPrimitive.double,
                    elapsedS = tick["elapsed_s"]!!.jsonPrimitive.double,
                    nowMs = 0L,
                ).toMutableList()
                if (tick["skip"]?.jsonPrimitive?.booleanOrNull == true) events += runner.skipStep()
                assertEquals(
                    "$name tick $tick",
                    tick["events"]!!.jsonArray.map { it.jsonPrimitive.content },
                    events.mapNotNull(::token),
                )
                assertEquals("$name tick $tick", tick["index_after"]!!.jsonPrimitive.int, runner.currentIndex)
            }
            val want = vec["results"]!!.jsonArray
            val got = runner.snapshotResults()
            assertEquals(name, want.size, got.size)
            for ((i, w) in want.withIndex()) {
                val r = w.jsonObject
                assertEquals("$name $i", r["step_index"]!!.jsonPrimitive.int, got[i].stepIndex)
                assertEquals("$name $i", r["kind"]!!.jsonPrimitive.content, got[i].kind)
                assertEquals("$name $i", r["status"]!!.jsonPrimitive.content, got[i].status)
                assertEquals("$name $i", r["duration_s"]!!.jsonPrimitive.int, got[i].durationS)
                assertEquals("$name $i", r["actual_pace_sec_per_km"]!!.jsonPrimitive.int, got[i].actualPaceSPerKm)
                assertEquals("$name $i", r["actual_distance_m"]!!.jsonPrimitive.double, got[i].actualDistanceM, 1e-6)
            }
            assertEquals(name, vec["adherence"]!!.jsonPrimitive.content, runner.adherence())
        }
    }

    private val rep = PushedStep(StepKind.Rep, 1, 1, distanceM = 1000, durationS = null, paceSPerKm = 240, toleranceSPerKm = 10)

    @Test
    fun `pace drift fires on a paced step and is rate-limited to 45 s`() {
        val runner = WorkoutRunner(workoutOf(listOf(rep)))
        runner.onTotals(0.0, 0.0, nowMs = 0)
        // 100 m in 40 s = 400 s/km against 240: well behind.
        val first = runner.onTotals(100.0, 40.0, nowMs = 40_000).filterIsInstance<WorkoutEvent.PaceDrift>()
        assertEquals(1, first.size)
        assertFalse(first.single().ahead)
        assertEquals(160, first.single().deltaSPerKm)
        assertTrue(runner.onTotals(110.0, 44.0, nowMs = 44_000).none { it is WorkoutEvent.PaceDrift })
        assertTrue(runner.onTotals(300.0, 120.0, nowMs = 85_000).any { it is WorkoutEvent.PaceDrift })
    }

    @Test
    fun `a standing start is not graded until 50 m in 20 s`() {
        // Issue #1300: 19 m in 15 s read way behind under the old 5 m / 1 s gate.
        val slow = WorkoutRunner(workoutOf(listOf(rep)))
        slow.onTotals(0.0, 0.0, nowMs = 0)
        assertTrue(slow.onTotals(19.0, 15.0, nowMs = 15_000).none { it is WorkoutEvent.PaceDrift })
        assertTrue(slow.onTotals(49.0, 40.0, nowMs = 40_000).none { it is WorkoutEvent.PaceDrift })
        val late = slow.onTotals(50.0, 40.0, nowMs = 40_000).filterIsInstance<WorkoutEvent.PaceDrift>()
        assertEquals(560, late.single().deltaSPerKm)
        assertFalse(late.single().ahead)

        val fast = WorkoutRunner(workoutOf(listOf(rep)))
        fast.onTotals(0.0, 0.0, nowMs = 0)
        assertTrue(fast.onTotals(120.0, 19.0, nowMs = 19_000).none { it is WorkoutEvent.PaceDrift })
        val due = fast.onTotals(120.0, 20.0, nowMs = 20_000).filterIsInstance<WorkoutEvent.PaceDrift>()
        assertEquals(73, due.single().deltaSPerKm)
        assertTrue(due.single().ahead)
    }

    @Test
    fun `drift reads the step's trailing 200 m, not its whole average`() {
        // Issue #1300: a slow first 50 m kept the cumulative average way behind
        // long after the runner reached the target.
        val steady = PushedStep(StepKind.Steady, null, null, distanceM = 8047, durationS = null, paceSPerKm = 348, toleranceSPerKm = 10)
        val runner = WorkoutRunner(workoutOf(listOf(steady)))
        runner.onTotals(0.0, 0.0, nowMs = 0)
        assertTrue(runner.onTotals(50.0, 40.0, nowMs = 40_000).any { it is WorkoutEvent.PaceDrift })
        // Until the step passes 250 m its window still holds the slow start.
        for (i in 1..6) runner.onTotals(50.0 + i * 28.736, 40.0 + i * 10, nowMs = 40_000L + i * 10_000)
        val later = (7..21).flatMap { i ->
            runner.onTotals(50.0 + i * 28.736, 40.0 + i * 10, nowMs = 40_000L + i * 10_000)
        }
        // The average stays way behind (383 s/km at the end); the last 200 m read 348.
        assertTrue(later.none { it is WorkoutEvent.PaceDrift })
    }

    @Test
    fun `the drift window restarts with each step`() {
        val recovery = PushedStep(StepKind.Recovery, null, null, distanceM = 400, durationS = null, paceSPerKm = 400, toleranceSPerKm = 10)
        val shortRep = rep.copy(distanceM = 400)
        val runner = WorkoutRunner(workoutOf(listOf(shortRep, recovery)))
        runner.onTotals(0.0, 0.0, nowMs = 0)
        for (i in 1..24) runner.onTotals(i * 400.0 / 24, i * 4.0, nowMs = i * 4_000L)
        assertEquals(1, runner.currentIndex)
        // The recovery at its own 400 s/km; a window reaching into the rep would read fast.
        val events = (1..6).flatMap { i -> runner.onTotals(400.0 + i * 10, 96.0 + i * 4, nowMs = 96_000L + i * 4_000) }
        assertTrue(events.none { it is WorkoutEvent.PaceDrift })
    }

    @Test
    fun `a carried overshoot is timed from the new step's own start`() {
        val shortRep = rep.copy(distanceM = 100)
        val steady = PushedStep(StepKind.Steady, null, null, distanceM = 400, durationS = null, paceSPerKm = 240, toleranceSPerKm = 10)
        val runner = WorkoutRunner(workoutOf(listOf(shortRep, steady)))
        runner.onTotals(0.0, 0.0, nowMs = 0)
        // 150 m in 45 s crosses the rep and carries 50 m and 15 s into the steady.
        runner.onTotals(150.0, 45.0, nowMs = 45_000)
        assertEquals(1, runner.currentIndex)
        assertTrue(runner.onTotals(160.0, 48.0, nowMs = 48_000).none { it is WorkoutEvent.PaceDrift })
        // 70 m in 21 s of the step = 300 s/km, 60 behind a 10 s tolerance.
        val due = runner.onTotals(170.0, 51.0, nowMs = 51_000).filterIsInstance<WorkoutEvent.PaceDrift>()
        assertEquals(60, due.single().deltaSPerKm)
    }

    @Test
    fun `ticks between fixes do not read as a slowdown`() {
        val steady = PushedStep(StepKind.Steady, null, null, distanceM = 1000, durationS = null, paceSPerKm = 300, toleranceSPerKm = 10)
        val runner = WorkoutRunner(workoutOf(listOf(steady)))
        runner.onTotals(0.0, 0.0, nowMs = 0)
        for (i in 1..10) runner.onTotals(i * 20.0, i * 6.0, nowMs = i * 6_000L)
        // A 6 s GPS hiccup: 200 m over 66 s would read 330 s/km, way behind.
        val ticks = (61..66).flatMap { s -> runner.onTotals(200.0, s.toDouble(), nowMs = s * 1_000L) }
        assertTrue(ticks.none { it is WorkoutEvent.PaceDrift })
    }

    @Test
    fun `a walk-run session never grades pace`() {
        val runner = WorkoutRunner(workoutOf(listOf(rep), unpaced = true))
        runner.onTotals(0.0, 0.0, nowMs = 0)
        assertTrue(runner.onTotals(100.0, 40.0, nowMs = 40_000).none { it is WorkoutEvent.PaceDrift })
        assertFalse(runner.view().paced)
    }

    @Test
    fun `skip before any totals does nothing`() {
        val runner = WorkoutRunner(workoutOf(listOf(rep)))
        assertTrue(runner.skipStep().isEmpty())
        assertEquals(0, runner.currentIndex)
    }

    @Test
    fun `the step in progress is a skipped row, so a crash keeps the review`() {
        val runner = WorkoutRunner(workoutOf(listOf(rep, rep)))
        runner.onTotals(0.0, 0.0, 0)
        runner.onTotals(400.0, 100.0, 0)
        val review = runner.review()
        assertEquals("pw-1", review.planWorkoutId)
        assertEquals("partial", review.adherence)
        assertEquals(listOf("skipped"), review.steps.map { it.status })
        assertEquals(400.0, review.steps.single().actualDistanceM, 0.0)
    }

    @Test
    fun `the view counts down on the step's own axis`() {
        val timed = PushedStep(StepKind.Recovery, 1, 1, distanceM = null, durationS = 90, paceSPerKm = 390, toleranceSPerKm = 10)
        val runner = WorkoutRunner(workoutOf(listOf(rep, timed)))
        runner.onTotals(0.0, 0.0, 0)
        runner.onTotals(250.0, 60.0, 0)
        assertEquals(750.0, runner.view().remainingM!!, 1e-9)
        assertEquals(null, runner.view().remainingS)
        runner.onTotals(1000.0, 240.0, 0)
        runner.onTotals(1050.0, 270.5, 0)
        assertEquals(60, runner.view().remainingS)
        assertEquals(null, runner.view().remainingM)
        runner.onTotals(1100.0, 330.0, 0)
        assertTrue(runner.isComplete)
        assertEquals(null, runner.view().step)
        assertFalse(runner.ownsPaceCues)
    }

    @Test
    fun `the review writes the phone's step-result keys`() {
        val runner = WorkoutRunner(workoutOf(listOf(rep)))
        runner.onTotals(0.0, 0.0, 0)
        runner.onTotals(1000.0, 250.0, 0)
        val meta = runner.review().metadataEntries()
        assertEquals(setOf("plan_workout_id", "workout_step_results", "workout_adherence"), meta.keys)
        val row = meta["workout_step_results"]!!.jsonArray.single().jsonObject
        assertEquals(
            setOf(
                "step_index", "kind", "rep_index", "rep_total", "target_distance_m",
                "actual_distance_m", "target_pace_sec_per_km", "actual_pace_sec_per_km",
                "tolerance_sec_per_km", "duration_s", "status",
            ),
            row.keys,
        )
        assertEquals("completed", meta["workout_adherence"]!!.jsonPrimitive.content)
        assertEquals(250, row["actual_pace_sec_per_km"]!!.jsonPrimitive.int)
    }

    @Test
    fun `an unmeasured pace is written as null, as the phone writes it`() {
        val runner = WorkoutRunner(workoutOf(listOf(rep)))
        runner.onTotals(0.0, 0.0, 0)
        runner.onTotals(2.0, 0.5, 0)
        val row = runner.review().metadataEntries()["workout_step_results"]!!.jsonArray.single().jsonObject
        assertEquals(JsonNull, row["actual_pace_sec_per_km"])
    }
}
