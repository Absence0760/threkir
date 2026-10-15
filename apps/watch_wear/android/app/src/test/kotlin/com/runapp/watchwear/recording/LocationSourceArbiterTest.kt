package com.runapp.watchwear.recording

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/// The receiver-vs-fused arbitration `RunRecordingService` delegates to,
/// mirroring `RunRecorder`'s source arbitration tests in
/// `packages/run_recorder/test/run_recorder_test.dart`. Times are arrival
/// milliseconds on a monotonic clock.
class LocationSourceArbiterTest {

    private val good = 5.0

    private fun s(seconds: Int): Long = seconds * 1_000L

    // ─────────── the receiver taking the run ───────────

    @Test fun `fused feeds until the receiver has delivered three steady fixes`() {
        val a = LocationSourceArbiter()
        assertTrue(a.onFusedFix(s(0), live = true).feed)
        assertFalse("first receiver fix only starts the streak", a.onGnssFix(good, s(0), live = true).feed)
        assertFalse("two is not enough", a.onGnssFix(good, s(1), live = true).feed)
        assertTrue("fused still feeds while the streak builds", a.onFusedFix(s(1), live = true).feed)
        assertTrue("the third steady fix takes the run", a.onGnssFix(good, s(2), live = true).feed)
        assertFalse("fused is dropped while the receiver is current", a.onFusedFix(s(3), live = true).feed)
        assertTrue(a.onGnssFix(good, s(3), live = true).feed)
    }

    @Test fun `a gap longer than 12 s restarts the streak`() {
        val a = LocationSourceArbiter()
        a.onGnssFix(good, s(0), live = true)
        a.onGnssFix(good, s(1), live = true)
        assertFalse("13 s after the last fix is a fresh streak of one", a.onGnssFix(good, s(14), live = true).feed)
        assertFalse(a.onGnssFix(good, s(15), live = true).feed)
        assertTrue(a.onGnssFix(good, s(16), live = true).feed)
    }

    @Test fun `a gap of exactly 12 s keeps the streak`() {
        val a = LocationSourceArbiter()
        a.onGnssFix(good, s(0), live = true)
        a.onGnssFix(good, s(12), live = true)
        assertTrue(a.onGnssFix(good, s(24), live = true).feed)
    }

    @Test fun `receiver fixes the accuracy gate drops neither count nor hold fused off`() {
        val a = LocationSourceArbiter()
        a.onGnssFix(good, s(0), live = true)
        a.onGnssFix(good, s(1), live = true)
        assertFalse(a.onGnssFix(FIX_ACCURACY_GATE_M + 0.1, s(2), live = true).feed)
        assertFalse(a.onGnssFix(null, s(2), live = true).feed)
        assertTrue("canopy fixes did not complete the streak", a.onFusedFix(s(2), live = true).feed)
        assertTrue(a.onGnssFix(FIX_ACCURACY_GATE_M, s(3), live = true).feed)

        for (t in 4..20) {
            val canopy = a.onGnssFix(45.0, s(t), live = true)
            assertTrue("a canopy fix within the estimator's cap still feeds distance", canopy.feed)
            assertFalse("but never the track", canopy.track)
        }
        assertTrue("17 s of canopy fixes is a silent receiver", a.onFusedFix(s(20), live = true).feed)
        assertFalse("past the receiver, canopy fixes are dropped", a.onGnssFix(45.0, s(21), live = true).feed)
    }

    @Test fun `a receiver fix past the estimator cap is dropped even on the receiver`() {
        val a = takeReceiver(LocationSourceArbiter())
        assertFalse(a.onGnssFix(ESTIMATOR_ACCURACY_CAP_M + 0.1, s(3), live = true).feed)
        val atCap = a.onGnssFix(ESTIMATOR_ACCURACY_CAP_M, s(4), live = true)
        assertTrue(atCap.feed)
        assertFalse(atCap.track)
    }

    @Test fun `a coarse fused fix feeds distance but not the track`() {
        val a = LocationSourceArbiter()
        val coarse = a.onFusedFix(s(0), live = true, accuracyM = 40.0)
        assertTrue(coarse.feed)
        assertFalse(coarse.track)
        assertTrue(a.onFusedFix(s(1), live = true, accuracyM = FIX_ACCURACY_GATE_M).track)
    }

    @Test fun `the arbitration gate is configurable apart from the track gate`() {
        val a = LocationSourceArbiter(arbitrationGateM = 20.0)
        for (t in 0..2) a.onGnssFix(25.0, s(t), live = true)
        assertFalse("25 m fixes do not take the run at a 20 m gate", a.onReceiver)
        takeReceiver(a)
        assertTrue(a.onReceiver)
        val fix = a.onGnssFix(25.0, s(3), live = true)
        assertTrue(fix.feed)
        assertTrue("25 m is inside the 30 m track gate", fix.track)
    }

    // ─────────── fused standing in ───────────

    @Test fun `fused stays aside through 12 s of receiver silence and feeds after`() {
        val a = takeReceiver(LocationSourceArbiter())
        assertFalse(a.onFusedFix(s(14), live = true).feed)
        assertTrue(a.onFusedFix(s(15), live = true).feed)
        assertEquals("mixed", a.locationProvider())
    }

    @Test fun `the receiver needs a fresh steady streak to take the run back`() {
        val a = takeReceiver(LocationSourceArbiter())
        assertTrue(a.onFusedFix(s(20), live = true).feed)
        assertFalse(a.onGnssFix(good, s(21), live = true).feed)
        assertFalse(a.onGnssFix(good, s(22), live = true).feed)
        assertTrue(a.onFusedFix(s(22), live = true).feed)
        assertTrue(a.onGnssFix(good, s(23), live = true).feed)
        assertFalse(a.onFusedFix(s(24), live = true).feed)
    }

    // ─────────── segment roll ───────────

    @Test fun `a switch rolls the segment only after a fix has been recorded`() {
        val first = LocationSourceArbiter()
        first.onGnssFix(good, s(0), live = true)
        first.onGnssFix(good, s(1), live = true)
        val take = first.onGnssFix(good, s(2), live = true)
        assertTrue(take.feed)
        assertFalse("nothing recorded yet, so there is no segment to end", take.rollSegment)

        val a = LocationSourceArbiter()
        assertTrue(a.onFusedFix(s(0), live = true).feed)
        a.onGnssFix(good, s(0), live = true)
        a.onGnssFix(good, s(1), live = true)
        val toReceiver = a.onGnssFix(good, s(2), live = true)
        assertTrue(toReceiver.feed)
        assertTrue(toReceiver.rollSegment)
        assertFalse("a steady receiver does not roll again", a.onGnssFix(good, s(3), live = true).rollSegment)

        val toFused = a.onFusedFix(s(16), live = true)
        assertTrue(toFused.feed)
        assertTrue(toFused.rollSegment)
        assertFalse(a.onFusedFix(s(17), live = true).rollSegment)
    }

    @Test fun `a paused fix is arbitrated but neither fed nor rolls`() {
        val a = LocationSourceArbiter()
        assertTrue(a.onFusedFix(s(0), live = true).feed)
        a.onGnssFix(good, s(0), live = false)
        a.onGnssFix(good, s(1), live = false)
        val paused = a.onGnssFix(good, s(2), live = false)
        assertFalse(paused.feed)
        assertFalse(paused.rollSegment)
        assertFalse("the receiver took the run while paused", a.onFusedFix(s(3), live = true).feed)
        val resumed = a.onGnssFix(good, s(3), live = true)
        assertTrue(resumed.feed)
        assertFalse(resumed.rollSegment)
        assertEquals("mixed", a.locationProvider())

        val onlyPaused = LocationSourceArbiter()
        for (t in 0..5) onlyPaused.onGnssFix(good, s(t), live = false)
        assertEquals("paused fixes are not counted", "fused", onlyPaused.locationProvider())
    }

    // ─────────── reopen throttle ───────────

    @Test fun `the receiver reopens at most every 30 s`() {
        val a = LocationSourceArbiter()
        assertTrue("the first open of a session is always allowed", a.mayOpenReceiver(s(100)))
        assertFalse(a.mayOpenReceiver(s(101)))
        assertFalse(a.mayOpenReceiver(s(129) + 999))
        assertTrue(a.mayOpenReceiver(s(130)))
        assertFalse(a.mayOpenReceiver(s(131)))
    }

    // ─────────── location_provider ───────────

    @Test fun `location provider names the stream the recorded fixes came from`() {
        val fused = LocationSourceArbiter()
        assertEquals("no fix recorded reads as fused", "fused", fused.locationProvider())
        fused.onFusedFix(s(0), live = true)
        assertEquals("fused", fused.locationProvider())

        val gps = takeReceiver(LocationSourceArbiter())
        assertEquals("gps", gps.locationProvider())

        val mixed = LocationSourceArbiter()
        mixed.onFusedFix(s(0), live = true)
        takeReceiver(mixed)
        assertEquals("mixed", mixed.locationProvider())
    }

    @Test fun `reset starts a session on fused with nothing counted and the receiver free to open`() {
        val a = takeReceiver(LocationSourceArbiter())
        a.onFusedFix(s(20), live = true)
        assertTrue(a.mayOpenReceiver(s(20)))
        a.reset()
        assertEquals("fused", a.locationProvider())
        assertTrue("fused feeds a fresh session", a.onFusedFix(s(21), live = true).feed)
        assertTrue(a.mayOpenReceiver(s(21)))
        assertFalse("the streak restarted too", a.onGnssFix(good, s(21), live = true).feed)
    }

    /// Three steady receiver fixes at 0, 1 and 2 s, the last of which takes
    /// the run.
    private fun takeReceiver(a: LocationSourceArbiter): LocationSourceArbiter {
        for (t in 0..2) a.onGnssFix(good, s(t), live = true)
        return a
    }
}
