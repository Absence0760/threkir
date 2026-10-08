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
            val est = GpsDistanceEstimator(
                maxSpeedMps = sc["maxSpeedMps"]!!.jsonPrimitive.double,
                expectedIntervalS = sc["expectedIntervalS"]!!.jsonPrimitive.double,
                initialStrideM = sc.num("initialStrideM"),
            )
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
        for (required in listOf(
            "gap_with_steps", "short_gap_with_steps", "trailing_gap_with_steps", "invalid_inputs",
            "sparse_15s", "sparse_60s_position_only", "sparse_without_interval_hint",
            "seeded_stride_gap_fill", "seeded_stride_out_of_range",
        )) {
            assertTrue("fixture lost scenario $required", required in names)
        }
    }

    private fun learnStride(est: GpsDistanceEstimator) {
        val degPerM = 180.0 / (Math.PI * 6371008.8)
        est.addFix(0.0, 45.0, 7.0, 5.0, 0.0, 0.5, 0.0)
        est.addSteps(0.5, 0)
        for (i in 1..20) {
            est.addFix(i.toDouble(), 45.0 + 3.0 * i * degPerM, 7.0, 5.0, 3.0, 0.5, 0.0)
            est.addSteps(i + 0.5, 3L * i)
        }
    }

    @Test
    fun `the next segment carries the learned stride and the configuration`() {
        val first = GpsDistanceEstimator(maxSpeedMps = 6.0, expectedIntervalS = 15.0)
        learnStride(first)
        assertEquals(1.0, first.strideM!!, tolerance)
        val next = first.nextSegment()
        assertEquals(1.0, next.strideM!!, tolerance)
        assertEquals(6.0, next.maxSpeedMps, 0.0)
        assertEquals(15.0, next.expectedIntervalS, 0.0)
        assertEquals(0.0, next.distanceM, 0.0)
    }

    @Test
    fun `a segment that learned nothing passes on the stride it was seeded with`() {
        val seeded = GpsDistanceEstimator(initialStrideM = 0.95)
        assertEquals(0.95, seeded.nextSegment().nextSegment().strideM!!, 0.0)
        assertNull(GpsDistanceEstimator().nextSegment().strideM)
        assertNull(GpsDistanceEstimator(initialStrideM = 3.0).strideM)
    }

    @Test
    fun `a carried stride blends with the next learned one`() {
        val est = GpsDistanceEstimator(initialStrideM = 0.95)
        learnStride(est)
        assertEquals(0.96, est.strideM!!, tolerance)
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
