package com.runapp.watchwear.recording

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.double
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.long
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/// Replays the shared golden vectors (`fixtures/gps_distance_vectors.json`,
/// generated from `scripts/gps_distance/reference.py`) and holds the Kotlin
/// port to the reference after every single event, not only at the end.
class GpsDistanceEstimatorTest {

    private val fixture: JsonObject = run {
        val f = File("../../../../fixtures/gps_distance_vectors.json")
        Json.parseToJsonElement(f.readText()).jsonObject
    }

    private val tolerance = fixture["tolerance_m"]!!.jsonPrimitive.double

    private fun JsonObject.num(key: String): Double? =
        this[key]?.takeIf { it !is JsonNull }?.jsonPrimitive?.doubleOrNull

    private fun expectedOrNull(e: JsonElement?): Double? =
        e?.takeIf { it !is JsonNull }?.jsonPrimitive?.doubleOrNull

    @Test
    fun `every scenario matches the reference after every event`() {
        val scenarios = fixture["scenarios"]!!.jsonArray
        assertTrue("no scenarios in the fixture", scenarios.isNotEmpty())
        for (el in scenarios) {
            val sc = el.jsonObject
            val name = sc["name"]!!.jsonPrimitive.content
            val est = GpsDistanceEstimator(maxSpeedMps = sc["maxSpeedMps"]!!.jsonPrimitive.double)
            val events = sc["events"]!!.jsonArray
            val expected = sc["expected"]!!.jsonObject
            val after = expected["distanceAfterEachEventM"]!!.jsonArray
            assertEquals("$name: one expectation per event", events.size, after.size)

            events.forEachIndexed { i, evEl ->
                val ev = evEl.jsonObject
                val t = ev["t"]!!.jsonPrimitive.double
                when (val type = ev["type"]!!.jsonPrimitive.content) {
                    "fix" -> est.addFix(
                        t = t,
                        lat = ev["lat"]!!.jsonPrimitive.double,
                        lng = ev["lng"]!!.jsonPrimitive.double,
                        accuracyM = ev.num("acc"),
                        speedMps = ev.num("speed"),
                        speedAccuracyMps = ev.num("speedAcc"),
                        bearingDeg = ev.num("bearing"),
                    )
                    "steps" -> est.addSteps(t, ev["count"]?.takeIf { it !is JsonNull }?.jsonPrimitive?.long)
                    "finish" -> est.finish(t)
                    else -> throw AssertionError("$name: unknown event type $type")
                }
                assertEquals(
                    "$name: distance after event $i",
                    after[i].jsonPrimitive.double,
                    est.distanceM,
                    tolerance,
                )
            }

            assertEquals("$name: gpsDistanceM", expected["gpsDistanceM"]!!.jsonPrimitive.double, est.gpsDistanceM, tolerance)
            assertEquals("$name: stepDistanceM", expected["stepDistanceM"]!!.jsonPrimitive.double, est.stepDistanceM, tolerance)
            val stride = expectedOrNull(expected["strideM"])
            if (stride == null) {
                assertNull("$name: strideM", est.strideM)
            } else {
                assertNotNull("$name: strideM", est.strideM)
                assertEquals("$name: strideM", stride, est.strideM!!, tolerance)
            }
        }
    }

    @Test
    fun `the fixture covers the step-fill paths, so the replay above exercises them`() {
        val names = fixture["scenarios"]!!.jsonArray.map { it.jsonObject["name"]!!.jsonPrimitive.content }
        for (required in listOf("gap_with_steps", "short_gap_with_steps", "trailing_gap_with_steps", "invalid_inputs")) {
            assertTrue("fixture lost scenario $required", required in names)
        }
    }

    @Test
    fun `a ride is not clamped to running speed`() {
        assertEquals(10.0, GpsDistanceEstimator.maxSpeedMpsFor("run"), 0.0)
        assertEquals(5.0, GpsDistanceEstimator.maxSpeedMpsFor("walk"), 0.0)
        assertEquals(6.0, GpsDistanceEstimator.maxSpeedMpsFor("hike"), 0.0)
        assertEquals(25.0, GpsDistanceEstimator.maxSpeedMpsFor("cycle"), 0.0)
        assertEquals(10.0, GpsDistanceEstimator.maxSpeedMpsFor("something-new"), 0.0)
    }
}
