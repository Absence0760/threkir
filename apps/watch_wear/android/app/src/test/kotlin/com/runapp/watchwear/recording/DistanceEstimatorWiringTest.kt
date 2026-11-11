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
        val gated = onGps.indexOf("if (!track)")
        assertTrue("onGps must gate the line on the fix's verdict", gated >= 0)
        assertTrue("the estimator takes the fix before the track gate", fed in 0 until gated)
    }

    @Test
    fun `every fix the estimator took is stored, with its distM and its track verdict`() {
        // docs/features/gps_distance.md § Stored track: the server replays the
        // stored track, so a fix past the 30 m gate is stored flagged
        // `offTrack` rather than left out.
        val onGps = body(serviceSrc, ON_GPS)
        val fed = onGps.indexOf("distanceEstimator.addFix(")
        val stored = onGps.indexOf("trackWriter?.append(p, distM = newDistance, offTrack = !track, segmentStart = segmentStart)")
        assertTrue("onGps must store every fed fix, flagged by the gate's verdict", stored >= 0)
        assertFalse("no fix is gated out of the stored track", onGps.contains("if (track) trackWriter?.append("))
        assertTrue("the fix is stored after the estimator has credited it", stored > fed)
        assertFalse("no fix is stored without its distM", onGps.contains("trackWriter?.append(p)"))
    }

    @Test
    fun `the finished run and the checkpoint claim a complete track only when one was written`() {
        val stop = body(serviceSrc, "private fun stopRecording()")
        assertTrue(stop.contains("trackComplete = storedPoints > 0"))
        assertTrue(serviceSrc.contains("trackComplete = file.pointCount > 0"))
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
    fun `a canopy fix feeds distance and pace and is stored, but stays off the map and the route match`() {
        assertTrue(gpsSrc.contains("loc.accuracy > ESTIMATOR_ACCURACY_CAP_M) continue"))
        val onFix = body(serviceSrc, "private fun onFix(p: GpsPoint, fromReceiver: Boolean)")
        assertTrue(onFix.contains("onGps(p, track = verdict.track)"))
        val onGps = body(serviceSrc, "private fun onGps(p: GpsPoint, track: Boolean)")
        val fed = onGps.indexOf("distanceEstimator.addFix(")
        val stored = onGps.indexOf("trackWriter?.append(p, distM = newDistance, offTrack = !track, segmentStart = segmentStart)")
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
        assertTrue(stop.contains("distanceStepOverChordM = stepOverChordM"))
        // Counted before the writer closes, so the server can tell a track
        // that lost its segment marks (metadata.distance_segments).
        assertTrue(stop.indexOf("trackWriter?.segmentCount") in 0 until stop.indexOf("trackWriter?.close()"))
        assertTrue(stop.contains("distanceSegments = storedSegments"))
        val checkpoint = body(serviceSrc, "private suspend fun writeCheckpoint()")
        assertTrue(checkpoint.contains("distanceSegments = file.segmentCount"))
    }

    /// A pause or source switch banks each segment's step-over-chord metres
    /// beside its step metres, so the run total covers every segment (v1.7),
    /// whole: the steps finish() commits past a segment's last fix are all
    /// over-chord, because the stored track marks the next segment's first
    /// fix and the server's replay ends this one where the watch did (v1.8).
    @Test
    fun `every segment's step-over-chord metres are banked`() {
        val close = body(serviceSrc, CLOSE_SEGMENT)
        assertTrue(close.contains("bankedStepOverChordM += segment.stepOverChordM"))
        assertTrue(
            "finish() runs before the segment's over-chord metres are banked",
            close.indexOf("segment.finish(") in 0 until close.indexOf("bankedStepOverChordM += segment.stepOverChordM"),
        )
        assertFalse("nothing is held back from the bank any more", serviceSrc.contains("heldBoundaryStepM"))
        assertTrue(serviceSrc.contains("bankedStepOverChordM + distanceEstimator.stepOverChordM"))
    }

    /// The first fix stored after a segment closes mid-run is marked
    /// `segmentStart`, once, so the server replays the segments apart (v1.8).
    @Test
    fun `the first stored fix after a segment close marks the segment's start`() {
        val close = body(serviceSrc, CLOSE_SEGMENT)
        assertTrue(close.contains("markSegmentStart = true"))
        val onGps = body(serviceSrc, ON_GPS)
        val read = onGps.indexOf("val opensSegment = markSegmentStart")
        val clear = onGps.indexOf("markSegmentStart = false")
        val stored = onGps.indexOf("segmentStart = segmentStart)")
        assertTrue("onGps reads the mark under the distance lock and clears it", read in 0 until clear)
        assertTrue("the stored fix carries it", clear < stored)
        val start = serviceSrc.indexOf("private fun startRecording(")
        assertTrue(
            "a new run starts unmarked",
            serviceSrc.indexOf("markSegmentStart = false", start) in start until serviceSrc.indexOf("livePace.seal()", start),
        )
    }

    private companion object {
        const val ON_GPS = "private fun onGps(p: GpsPoint, track: Boolean)"
        const val CLOSE_SEGMENT = "private fun closeDistanceSegment(learnStride: Boolean"
    }
}
