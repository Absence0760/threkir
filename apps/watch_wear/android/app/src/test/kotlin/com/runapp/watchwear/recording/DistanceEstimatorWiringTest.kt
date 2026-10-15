package com.runapp.watchwear.recording

import java.io.File
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/// Source-level guard on how the recording service feeds the shared distance
/// estimator (docs/features/gps_distance.md). The service is Android-bound and
/// not host-JVM testable without Robolectric, so the wiring is pinned by
/// source grep per the module's convention (see `CheckpointHandoffWiringTest`);
/// the arithmetic itself is held to the golden vectors by
/// `GpsDistanceEstimatorTest`.
class DistanceEstimatorWiringTest {

    private val serviceSrc: String =
        File("src/main/kotlin/com/runapp/watchwear/recording/RunRecordingService.kt").readText()

    private val gpsSrc: String =
        File("src/main/kotlin/com/runapp/watchwear/GpsRecorder.kt").readText()

    private fun body(src: String, signature: String): String {
        val block = Regex("""${Regex.escape(signature)}[\s\S]*?\n    \}""").find(src)
        assertTrue("expected a $signature body", block != null)
        return block!!.value
    }

    @Test
    fun `every fed fix reaches the estimator with its Doppler inputs on a monotonic clock`() {
        val onGps = body(serviceSrc, ON_GPS)
        assertTrue(onGps.contains("distanceEstimator.addFix("))
        for (arg in listOf("p.accuracyM", "p.speedMps", "p.speedAccuracyMps", "p.bearingDeg")) {
            assertTrue("onGps must pass $arg", onGps.contains(arg))
        }
        assertTrue(
            "the estimator's clock is elapsedRealtime, never the wall-clock fix stamp",
            onGps.contains("p.elapsedRealtimeMs ?: SystemClock.elapsedRealtime()"),
        )
        assertFalse("raw hop-summing must not come back", serviceSrc.contains("haversineM("))
    }

    @Test
    fun `a fix past the track gate still feeds the estimator`() {
        val onGps = body(serviceSrc, ON_GPS)
        val fed = onGps.indexOf("distanceEstimator.addFix(")
        val gated = onGps.indexOf("if (track)")
        assertTrue("onGps must gate the track on the fix's verdict", gated >= 0)
        assertTrue("the estimator takes the fix before the track gate", fed in 0 until gated)
    }

    @Test
    fun `a stored fix carries the distance credited through it`() {
        val onGps = body(serviceSrc, ON_GPS)
        val fed = onGps.indexOf("distanceEstimator.addFix(")
        val stored = onGps.indexOf("trackWriter?.append(p, distM = newDistance)")
        assertTrue("onGps must write distM, the run's credited distance", stored >= 0)
        assertTrue("only a fix within the track gate is stored", onGps.contains("if (track) trackWriter?.append("))
        assertTrue("the fix is stored after the estimator has credited it", stored > fed)
        assertFalse("no fix is stored without its distM", onGps.contains("trackWriter?.append(p)"))
    }

    @Test
    fun `optional Location fields are read only when the platform reports them`() {
        assertTrue(gpsSrc.contains("if (loc.hasSpeed()) loc.speed"))
        assertTrue(gpsSrc.contains("if (loc.hasSpeedAccuracy()) loc.speedAccuracyMetersPerSecond"))
        assertTrue(gpsSrc.contains("if (loc.hasBearing()) loc.bearing"))
        assertTrue(gpsSrc.contains("if (loc.hasAccuracy()) loc.accuracy"))
    }

    @Test
    fun `the pedometer feeds the estimator`() {
        assertTrue(serviceSrc.contains("distanceEstimator.addSteps(realtimeS(), stepsThisRun.toLong())"))
    }

    @Test
    fun `a pause closes the segment so the paused span is never credited`() {
        assertTrue(body(serviceSrc, "private fun pauseRecording()").contains("closeDistanceSegment()"))
        assertTrue(body(serviceSrc, "private fun stopRecording()").contains("closeDistanceSegment()"))
        val close = body(serviceSrc, CLOSE_SEGMENT)
        assertTrue("finish() commits steps buffered across a trailing gap", close.contains(".finish("))
        assertTrue(
            "the next segment keeps the learned stride",
            close.contains("distanceEstimator = segment.nextSegment(learnStride)"),
        )
    }

    @Test
    fun `a source switch opens a segment that learns stride only on the receiver`() {
        assertTrue(serviceSrc.contains("closeDistanceSegment(learnStride = onReceiver)"))
        assertTrue(serviceSrc.contains("segment.nextSegment(learnStride = onReceiver)"))
    }

    @Test
    fun `live pace reads the estimator's distance, sealed with every segment`() {
        val onGps = body(serviceSrc, ON_GPS)
        assertTrue(onGps.contains("livePace.add(t, distanceEstimator.distanceM)"))
        assertTrue(onGps.contains("livePace.secondsPerKm"))
        assertFalse(
            "pace is the rolling window, not the whole-run average",
            onGps.contains("elapsedS / newDistance"),
        )
        assertTrue(body(serviceSrc, CLOSE_SEGMENT).contains("livePace.seal()"))
    }

    @Test
    fun `a canopy fix feeds distance and pace but stays off the track, the map and the route match`() {
        assertTrue(gpsSrc.contains("loc.accuracy > ESTIMATOR_ACCURACY_CAP_M) continue"))
        val onFix = body(serviceSrc, "private fun onFix(p: GpsPoint, fromReceiver: Boolean)")
        assertTrue(onFix.contains("onGps(p, track = verdict.track)"))
        val onGps = body(serviceSrc, "private fun onGps(p: GpsPoint, track: Boolean)")
        val fed = onGps.indexOf("distanceEstimator.addFix(")
        val stored = onGps.indexOf("if (track) trackWriter?.append(p, distM = newDistance)")
        val offTrackReturn = onGps.indexOf("if (!track) {")
        val routeMatch = onGps.indexOf("RouteMath.routeProgress(")
        val overlay = onGps.indexOf("trackOverlay.add(posLL)")
        assertTrue("the fix is credited before anything else", fed in 0 until stored)
        assertTrue("an off-track fix returns before the route match", offTrackReturn in stored until routeMatch)
        assertTrue("and before the map overlay", offTrackReturn < overlay)
    }

    @Test
    fun `only a receiver segment learns stride`() {
        assertTrue(
            "every session starts on fused, which may not teach stride",
            Regex("""GpsDistanceEstimator\(\s*GpsDistanceEstimator\.maxSpeedMpsFor\(activity\),\s*learnStride = false,""")
                .containsMatchIn(serviceSrc),
        )
        val onFix = body(serviceSrc, "private fun onFix(p: GpsPoint, fromReceiver: Boolean)")
        assertTrue(onFix.contains("closeDistanceSegment(learnStride = onReceiver)"))
        assertTrue(onFix.contains("segment.nextSegment(learnStride = onReceiver)"))
        val close = body(serviceSrc, "private fun closeDistanceSegment(learnStride: Boolean")
        assertTrue(close.contains("distanceEstimator = segment.nextSegment(learnStride)"))
    }

    @Test
    fun `the finished run carries the step-filled share to the queue`() {
        val stop = body(serviceSrc, "private fun stopRecording()")
        assertTrue(stop.contains("distanceStepFilledM = stepFilledM"))
    }

    private companion object {
        const val ON_GPS = "private fun onGps(p: GpsPoint, track: Boolean)"
        const val CLOSE_SEGMENT = "private fun closeDistanceSegment(learnStride: Boolean"
    }
}
