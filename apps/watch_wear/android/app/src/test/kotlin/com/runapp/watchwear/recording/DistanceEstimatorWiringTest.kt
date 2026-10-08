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
    fun `every gated fix reaches the estimator with its Doppler inputs on a monotonic clock`() {
        val onGps = body(serviceSrc, "private fun onGps(p: GpsPoint)")
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
        val close = body(serviceSrc, "private fun closeDistanceSegment()")
        assertTrue("finish() commits steps buffered across a trailing gap", close.contains(".finish("))
        assertTrue(
            "the next segment keeps the learned stride",
            close.contains("distanceEstimator = segment.nextSegment()"),
        )
    }

    @Test
    fun `the finished run carries the step-filled share to the queue`() {
        val stop = body(serviceSrc, "private fun stopRecording()")
        assertTrue(stop.contains("distanceStepFilledM = stepFilledM"))
    }
}
