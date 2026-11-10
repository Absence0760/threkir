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
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.int
import kotlinx.serialization.json.long
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/// Replays the shared golden vectors (`fixtures/gps_distance_vectors.json`,
/// generated from `scripts/gps_distance/reference.py`) and holds the Kotlin
/// port to the reference after every single event, not only at the end. The
/// scenario list comes from the fixture, so a scenario added there is
/// replayed here without a code change.
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
    fun `the fixture is spec v1_4 and every constant matches it`() {
        assertEquals("gps-distance-estimator v1.6", fixture["spec"]!!.jsonPrimitive.content)
        assertEquals("1.6", GpsDistanceEstimator.SPEC_VERSION)
        val constants = fixture["constants"]!!.jsonObject
        assertFalse("port declares no constants", GpsDistanceEstimator.CONSTANTS.isEmpty())
        for ((name, value) in GpsDistanceEstimator.CONSTANTS) {
            val want = constants[name]
            assertNotNull("fixture has no constant $name", want)
            assertEquals(name, want!!.jsonPrimitive.double, value, 0.0)
        }
    }

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
                learnStride = sc["learnStride"]!!.jsonPrimitive.boolean,
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
            assertEquals("$name: rejectedFixes", expected["rejectedFixes"]!!.jsonPrimitive.int, est.rejectedFixes)
            assertEquals("$name: zuptFixes", expected["zuptFixes"]!!.jsonPrimitive.int, est.zuptFixes)
            assertEquals("$name: rScale", expected["rScale"]!!.jsonPrimitive.double, est.rScale, 1e-6)
            assertEquals("$name: dopplerScale", expected["dopplerScale"]!!.jsonPrimitive.double, est.dopplerScale, 1e-6)
            assertEquals("$name: dopplerTrusted", expected["dopplerTrusted"]!!.jsonPrimitive.boolean, est.dopplerTrusted)
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
    fun `a segment that may not learn keeps its seed, and passes the flag on unless told otherwise`() {
        val fused = GpsDistanceEstimator(initialStrideM = 0.95, learnStride = false)
        learnStride(fused)
        assertEquals(0.95, fused.strideM!!, 0.0)
        val stillFused = fused.nextSegment()
        assertFalse(stillFused.learnStride)
        val receiver = fused.nextSegment(learnStride = true)
        assertTrue(receiver.learnStride)
        learnStride(receiver)
        assertEquals(0.96, receiver.strideM!!, tolerance)
    }

    @Test
    fun `a fix stating worse than 50 m is ignored outright`() {
        val est = GpsDistanceEstimator()
        assertEquals(0.0, est.addFix(0.0, 40.0, -75.0, 51.0), 0.0)
        est.addFix(1.0, 40.0, -75.0, 50.0)
        est.addFix(2.0, 40.00003, -75.0, 51.0, 3.0, 0.3, 0.0)
        assertEquals(0.0, est.distanceM, 0.0)
    }

    private val eastMPerDeg = 111195.0 * Math.cos(40.0 * Math.PI / 180.0)

    private fun eastward(): GpsDistanceEstimator {
        val est = GpsDistanceEstimator(initialStrideM = 0.5, learnStride = false)
        for (i in 0..25) {
            est.addFix(i.toDouble(), 40.0, -75.0 + 4.0 * i / eastMPerDeg, 3.0, 4.0, 0.3, 90.0)
            est.addSteps(i + 0.5, 4L * i + 2)
        }
        return est
    }

    @Test
    fun `a late step batch tops a gap up without counting its chord twice`() {
        // Steps at 0.5 m credit 2 m/s, so the straight 30 s gap's 116 m chord
        // lower bound wins. The batch after the resuming fix moves 10 m of
        // that credit from the chord to the steps and adds nothing (v1.6).
        val est = eastward()
        est.addSteps(50.0, 202)
        est.addFix(55.0, 40.0, -75.0 + 220.0 / eastMPerDeg, 3.0, 4.0, 0.3, 90.0)
        val before = est.distanceM
        val steps = est.stepDistanceM
        est.addSteps(56.5, 228)
        assertEquals(before, est.distanceM, 1e-9)
        assertEquals(10.0, est.stepDistanceM - steps, 1e-9)
    }

    @Test
    fun `a late sample stamped inside a gap shares only its own interval`() {
        // 2 steps over (50, 51] at a 0.5 m stride credit 1 m; sharing the rest
        // of the gap, which the fix at 55 closed before the sample arrived, at
        // the sample's rate would credit 5 m (v1.6).
        val est = eastward()
        est.addSteps(50.0, 202)
        est.addFix(55.0, 40.0, -75.0 + 110.0 / eastMPerDeg, 3.0, 4.0, 0.3, 90.0)
        val before = est.distanceM
        val steps = est.stepDistanceM
        est.addSteps(51.0, 204)
        assertEquals(1.0, est.distanceM - before, 1e-9)
        assertEquals(1.0, est.stepDistanceM - steps, 1e-9)
    }

    @Test
    fun `a stretch credits no steps taken before its first fix`() {
        val est = GpsDistanceEstimator(initialStrideM = 1.0, learnStride = false)
        for (i in 0 until 30) est.addSteps(i + 0.5, 4L * i)
        est.addFix(30.0, 40.0, -75.0, 3.0)
        est.finish(31.0)
        assertEquals(0.0, est.distanceM, 0.0)
    }
}
