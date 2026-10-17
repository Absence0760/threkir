package com.runapp.watchwear.workout

import java.io.File
import java.time.LocalDate
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/// The phone -> watch today's-workout payload, read off the fixture the phone's
/// encoder is held to (`apps/mobile_android/test/watch_workout_push_test.dart`)
/// and the watchOS decoder reads too (`PushedWorkoutTests.swift`). A payload
/// the phone writes must decode here to the same steps; every rejected shape
/// must be refused whole, never partly loaded.
class WorkoutPushFixtureTest {

    private val fixture: JsonObject = run {
        // Gradle runs tests with cwd = `apps/watch_wear/android/app`.
        val f = File("../../../../fixtures/watch_workout_payload.json")
        Json.parseToJsonElement(f.readText()).jsonObject
    }

    private fun decode(payload: JsonObject): WorkoutPush = parseWorkoutPush(payload.toString())

    @Test
    fun `every payload the phone writes decodes to its steps`() {
        val cases = fixture["cases"]!!.jsonArray
        assertTrue("fixture has no cases", cases.isNotEmpty())
        for (c in cases) {
            val case = c.jsonObject
            val payload = case["payload"]!!.jsonObject
            val push = decode(payload)
            assertTrue("${case["name"]}: $push", push is WorkoutPush.Workout)
            val w = (push as WorkoutPush.Workout).workout
            assertEquals(payload["plan_workout_id"]!!.jsonPrimitive.content, w.planWorkoutId)
            assertEquals(
                LocalDate.parse(payload["scheduled_date"]!!.jsonPrimitive.content),
                w.scheduledDate,
            )
            assertEquals(payload["workout_kind"]!!.jsonPrimitive.content, w.workoutKind)
            assertEquals(payload["unpaced"]!!.jsonPrimitive.content.toBoolean(), w.unpaced)
            val want = payload["steps"]!!.jsonArray
            assertEquals(want.size, w.steps.size)
            for ((i, el) in want.withIndex()) {
                val s = el.jsonObject
                val got = w.steps[i]
                assertEquals("step $i kind", s["kind"]!!.jsonPrimitive.content, got.kind.token)
                assertEquals("step $i rep_index", s["rep_index"]?.jsonPrimitive?.int, got.repIndex)
                assertEquals("step $i rep_total", s["rep_total"]?.jsonPrimitive?.int, got.repTotal)
                assertEquals("step $i distance", s["distance_m"]?.jsonPrimitive?.int, got.distanceM)
                assertEquals("step $i duration", s["duration_s"]?.jsonPrimitive?.int, got.durationS)
                assertEquals("step $i pace", s["pace_s_per_km"]!!.jsonPrimitive.int, got.paceSPerKm)
                assertEquals(
                    "step $i tolerance",
                    s["tolerance_s_per_km"]!!.jsonPrimitive.int,
                    got.toleranceSPerKm,
                )
            }
        }
    }

    @Test
    fun `the nothing-today payloads clear rather than reject`() {
        for (p in fixture["none_payloads"]!!.jsonArray) {
            assertEquals("$p", WorkoutPush.None, decode(p.jsonObject))
        }
    }

    @Test
    fun `every rejected shape is refused whole`() {
        val rejected = fixture["rejected_payloads"]!!.jsonArray
        assertTrue(rejected.isNotEmpty())
        for (r in rejected) {
            val entry = r.jsonObject
            assertEquals(
                entry["why"]!!.jsonPrimitive.content,
                WorkoutPush.Rejected,
                decode(entry["payload"]!!.jsonObject),
            )
        }
    }

    @Test
    fun `text that is not a JSON object is rejected`() {
        for (raw in listOf(null, "", "not json", "[1,2]", "1")) {
            assertEquals("$raw", WorkoutPush.Rejected, parseWorkoutPush(raw))
        }
    }

    @Test
    fun `more steps than the cap is rejected rather than truncated`() {
        fun payload(n: Int) = buildJsonObject {
            put("v", 1)
            put("plan_workout_id", "x")
            put("scheduled_date", "2026-10-16")
            put("workout_kind", "interval")
            put("unpaced", false)
            put("steps", buildJsonArray {
                repeat(n) {
                    add(buildJsonObject {
                        put("kind", "rep")
                        put("distance_m", 200)
                        put("pace_s_per_km", 240)
                        put("tolerance_s_per_km", 10)
                    })
                }
            })
        }
        assertTrue(decode(payload(MAX_WORKOUT_STEPS)) is WorkoutPush.Workout)
        assertEquals(WorkoutPush.Rejected, decode(payload(MAX_WORKOUT_STEPS + 1)))
    }

    @Test
    fun `a workout is offered only on its own day`() {
        val payload = fixture["cases"]!!.jsonArray.first().jsonObject["payload"]!!.jsonObject
        val w = (decode(payload) as WorkoutPush.Workout).workout
        assertTrue(w.isFor(w.scheduledDate))
        assertFalse(w.isFor(w.scheduledDate.plusDays(1)))
        assertFalse(w.isFor(w.scheduledDate.minusDays(1)))
    }

    @Test
    fun `the payload version matches the phone writer`() {
        val src = File("../../../../apps/mobile_android/lib/watch_workout_push.dart").readText()
        val phone = Regex("""const int kWatchWorkoutPayloadVersion = (\d+);""").find(src)
            ?.groupValues?.get(1)?.toInt()
        assertEquals(phone, WORKOUT_PAYLOAD_VERSION)
    }
}
