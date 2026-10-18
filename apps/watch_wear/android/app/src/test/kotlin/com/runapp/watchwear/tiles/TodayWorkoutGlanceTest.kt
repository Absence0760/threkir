package com.runapp.watchwear.tiles

import com.runapp.watchwear.WearLocales
import com.runapp.watchwear.complications.ComplicationState
import com.runapp.watchwear.complications.LastRun
import com.runapp.watchwear.complications.decodeLastRun
import com.runapp.watchwear.complications.encodeLastRun
import com.runapp.watchwear.complications.todayComplicationContent
import com.runapp.watchwear.recording.DistanceUnit
import com.runapp.watchwear.workout.PushedStep
import com.runapp.watchwear.workout.PushedWorkout
import com.runapp.watchwear.workout.StepKind
import com.runapp.watchwear.workout.WorkoutPush
import com.runapp.watchwear.workout.parseWorkoutPush
import java.io.File
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZonedDateTime
import java.util.Locale
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/// The "today" state the tile and the complication share: which workout is
/// offered, how it is summarised, and when it stops being today's.
class TodayWorkoutGlanceTest {

    private val utc: ZoneId = ZoneId.of("UTC")

    private fun step(
        kind: StepKind,
        distanceM: Int? = null,
        durationS: Int? = null,
    ) = PushedStep(
        kind = kind,
        repIndex = null,
        repTotal = null,
        distanceM = distanceM,
        durationS = durationS,
        paceSPerKm = 300,
        toleranceSPerKm = 8,
    )

    private fun workout(
        steps: List<PushedStep>,
        kind: String = "interval",
        date: LocalDate = LocalDate.of(2026, 10, 16),
        id: String = "pw-1",
    ) = PushedWorkout(
        planWorkoutId = id,
        scheduledDate = date,
        workoutKind = kind,
        unpaced = false,
        steps = steps,
    )

    private fun lastRun(unit: String = "km", planWorkoutId: String? = null) = LastRun(
        runId = "r1",
        distanceM = 5_000.0,
        durationS = 1_500,
        unit = unit,
        finishedAtMs = 0L,
        planWorkoutId = planWorkoutId,
    )

    /// The payloads the phone's encoder is held to, so the headline is pinned
    /// on the exact shape the wrist receives.
    private val fixturePushes: Map<String, WorkoutPush> by lazy {
        val f = File("../../../../fixtures/watch_workout_payload.json")
        val root = Json.parseToJsonElement(f.readText()).jsonObject
        root["cases"]!!.jsonArray.associate { c ->
            val case = c.jsonObject
            case["name"]!!.jsonPrimitive.content to parseWorkoutPush(case["payload"].toString())
        }
    }

    private fun fixtureWorkout(name: String): PushedWorkout =
        (fixturePushes.getValue(name) as WorkoutPush.Workout).workout

    @Test
    fun `a repeat session is named by its reps in metres`() {
        assertEquals("3 × 400 m", workoutHeadline(fixtureWorkout("intervals"), DistanceUnit.KM, Locale.US))
        // Track reps are written in metres in both systems.
        assertEquals("3 × 400 m", workoutHeadline(fixtureWorkout("intervals"), DistanceUnit.MI, Locale.US))
    }

    @Test
    fun `timed reps are named by their time`() {
        assertEquals("2 × 1:00", workoutHeadline(fixtureWorkout("walk_run"), DistanceUnit.KM, Locale.US))
    }

    @Test
    fun `reps that differ fall back to the session total`() {
        val ladder = workout(
            listOf(
                step(StepKind.Rep, distanceM = 400),
                step(StepKind.Recovery, durationS = 90),
                step(StepKind.Rep, distanceM = 800),
            ),
        )
        assertEquals("1.20 km", workoutHeadline(ladder, DistanceUnit.KM, Locale.US))
    }

    @Test
    fun `a single rep is not a repeat session`() {
        val one = workout(listOf(step(StepKind.Warmup, distanceM = 2_000), step(StepKind.Rep, distanceM = 3_000)))
        assertEquals("5.00 km", workoutHeadline(one, DistanceUnit.KM, Locale.US))
    }

    @Test
    fun `a steady session is named by its distance in the runner's unit and locale`() {
        val easy = workout(listOf(step(StepKind.Steady, distanceM = 12_000)), kind = "easy")
        assertEquals("12.0 km", workoutHeadline(easy, DistanceUnit.KM, Locale.US))
        assertEquals("7.46 mi", workoutHeadline(easy, DistanceUnit.MI, Locale.US))
        assertEquals("12,0 km", workoutHeadline(easy, DistanceUnit.KM, Locale.GERMANY))
    }

    @Test
    fun `an all-timed session is named by its total time`() {
        val timed = workout(listOf(step(StepKind.Steady, durationS = 45 * 60)), kind = "easy")
        assertEquals("45:00", workoutHeadline(timed, DistanceUnit.KM, Locale.US))
        val long = workout(listOf(step(StepKind.Steady, durationS = 5_400)), kind = "long")
        assertEquals("1:30:00", workoutHeadline(long, DistanceUnit.KM, Locale.US))
    }

    @Test
    fun `today's push is offered with its kind, shape and step count`() {
        val push = fixturePushes.getValue("intervals")
        val today = (push as WorkoutPush.Workout).workout.scheduledDate
        val glance = todayGlance(push, lastRun = null, today = today, zone = utc, locale = Locale.US)
        assertNotNull(glance)
        glance!!
        assertEquals("pw-intervals", glance.planWorkoutId)
        assertEquals(PlanKind.INTERVAL, glance.kind)
        assertEquals("3 × 400 m", glance.headline)
        assertEquals(7, glance.stepCount)
        assertEquals(
            ZonedDateTime.of(2026, 10, 17, 0, 0, 0, 0, utc).toInstant().toEpochMilli(),
            glance.validUntilEpochMs,
        )
    }

    @Test
    fun `a push for another day is not today's`() {
        val push = WorkoutPush.Workout(workout(listOf(step(StepKind.Steady, distanceM = 5_000))))
        assertNull(todayGlance(push, null, LocalDate.of(2026, 10, 17), utc))
        assertNull(todayGlance(push, null, LocalDate.of(2026, 10, 15), utc))
    }

    @Test
    fun `nothing today, a refused payload, or no push at all offers nothing`() {
        val today = LocalDate.of(2026, 10, 16)
        assertNull(todayGlance(WorkoutPush.None, null, today, utc))
        assertNull(todayGlance(WorkoutPush.Rejected, null, today, utc))
        assertNull(todayGlance(null, null, today, utc))
    }

    @Test
    fun `a workout this watch already ran is not offered again`() {
        val push = WorkoutPush.Workout(workout(listOf(step(StepKind.Steady, distanceM = 5_000)), id = "pw-done"))
        val today = LocalDate.of(2026, 10, 16)
        assertNull(todayGlance(push, lastRun(planWorkoutId = "pw-done"), today, utc))
        assertNotNull(todayGlance(push, lastRun(planWorkoutId = "pw-other"), today, utc))
        assertNotNull(todayGlance(push, lastRun(planWorkoutId = null), today, utc))
    }

    @Test
    fun `the distance unit is the last run's, km before any run`() {
        val push = WorkoutPush.Workout(workout(listOf(step(StepKind.Steady, distanceM = 8_000)), kind = "easy"))
        val today = LocalDate.of(2026, 10, 16)
        assertEquals("8.00 km", todayGlance(push, null, today, utc, Locale.US)!!.headline)
        assertEquals("4.97 mi", todayGlance(push, lastRun(unit = "mi"), today, utc, Locale.US)!!.headline)
    }

    @Test
    fun `the glance ends at the real day boundary across a DST change`() {
        // Sao Paulo began DST at local midnight on 2018-11-04, so that day
        // started at 01:00; "+24 h from midnight" would be an hour early.
        val zone = ZoneId.of("America/Sao_Paulo")
        val end = startOfNextDayMs(LocalDate.of(2018, 11, 3), zone)
        assertEquals(
            ZonedDateTime.of(2018, 11, 4, 1, 0, 0, 0, zone).toInstant().toEpochMilli(),
            end,
        )
        // An ordinary day ends at the next local midnight.
        val ny = ZoneId.of("America/New_York")
        assertEquals(
            ZonedDateTime.of(2026, 10, 17, 0, 0, 0, 0, ny).toInstant().toEpochMilli(),
            startOfNextDayMs(LocalDate.of(2026, 10, 16), ny),
        )
    }

    @Test
    fun `the watch's day is read in its own zone`() {
        val instant = ZonedDateTime.of(2026, 10, 17, 2, 0, 0, 0, utc).toInstant().toEpochMilli()
        assertEquals(LocalDate.of(2026, 10, 17), localDate(instant, utc))
        assertEquals(LocalDate.of(2026, 10, 16), localDate(instant, ZoneId.of("America/Los_Angeles")))
    }

    @Test
    fun `an unknown kind still shows, under the generic label`() {
        assertEquals(PlanKind.OTHER, PlanKind.of("fartlek"))
        assertEquals(PlanKind.OTHER, PlanKind.of("rest"))
        assertEquals(PlanKind.MARATHON_PACE, PlanKind.of("marathon_pace"))
    }

    @Test
    fun `every workout_kind the plan can push has its own label`() {
        // The `workout_kind` enum, read from the migrations that create and
        // extend it. `rest` has no steps, so the phone never pushes it.
        val migrations = WearLocales.findUp("apps/backend/supabase/migrations")
            ?: error("could not locate the Supabase migrations")
        val sql = migrations.listFiles()!!.filter { it.extension == "sql" }.sortedBy { it.name }
            .joinToString("\n") { it.readText() }
        val created = Regex("""create type workout_kind as enum \(([^)]*)\)""").find(sql)
            ?: error("no `create type workout_kind` in the migrations")
        val values = Regex("""'([a-z_]+)'""").findAll(created.groupValues[1]).map { it.groupValues[1] }.toMutableSet()
        Regex("""alter type workout_kind add value(?: if not exists)? '([a-z_]+)'""")
            .findAll(sql).forEach { values += it.groupValues[1] }
        assertTrue("walk_run must be among $values", "walk_run" in values)
        val pushable = values - "rest"
        val labelled = PlanKind.entries.mapNotNull { it.token }.toSet()
        assertEquals(pushable, labelled)
    }

    @Test
    fun `the complication's today content carries the kind and the shape`() {
        val glance = TodayGlance("pw-1", PlanKind.TEMPO, "8.00 km", 3, 0L)
        val content = todayComplicationContent(glance)
        assertEquals(ComplicationState.TODAY, content.state)
        assertEquals(PlanKind.TEMPO, content.kind)
        assertEquals("8.00 km", content.detail)
        assertNull(content.liveSinceEpochMs)
    }

    @Test
    fun `a last-run entry written before the plan workout field still decodes`() {
        val old = """{"runId":"r1","distanceM":5000.0,"durationS":1500,"unit":"km","finishedAtMs":1}"""
        val decoded = decodeLastRun(old)
        assertNotNull(decoded)
        assertNull(decoded!!.planWorkoutId)
        val round = decodeLastRun(encodeLastRun(lastRun(planWorkoutId = "pw-9")))
        assertEquals("pw-9", round!!.planWorkoutId)
    }
}
