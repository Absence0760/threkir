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
