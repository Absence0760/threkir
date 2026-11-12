package com.runapp.watchwear.complications

import com.runapp.watchwear.recording.DistanceUnit
import com.runapp.watchwear.recording.RecordingRepository
import com.runapp.watchwear.recording.RecordingRepository.Stage
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Locale

/// What the watch-face complication shows in each state. The mapping onto
/// `ComplicationData` needs the Android framework and is compiled, not run,
/// here; everything it renders is decided by these pure functions.
class RunComplicationContentTest {

    private val now = 1_800_000_000_000L

    private fun metrics(
        stage: Stage,
        distanceM: Double = 5_123.0,
        elapsedMs: Long = 754_000L,
        paceSecPerKm: Double? = 330.0,
        unit: DistanceUnit = DistanceUnit.KM,
    ) = RecordingRepository.Metrics(
        stage = stage,
        distanceM = distanceM,
        elapsedMs = elapsedMs,
        paceSecPerKm = paceSecPerKm,
        preferredUnit = unit,
    )

    private val lastRun = LastRun(
        runId = "r1",
        distanceM = 10_000.0,
        durationS = 3_000,
        unit = "mi",
        finishedAtMs = now - 86_400_000L,
    )

    @Test
    fun `recording shows distance and pace and hands the face a live anchor`() {
        val c = complicationContent(metrics(Stage.Recording), lastRun, now, Locale.US)
        assertEquals(ComplicationState.RECORDING, c.state)
        assertEquals("5.12 km", c.distance)
        assertEquals("12:34", c.elapsed)
        assertEquals("5.12 km · 5:30/km", c.detail)
        // The face counts up from here itself, so it must be the run's
        // active start, not wall-clock start: paused time is already out.
        assertEquals(now - 754_000L, c.liveSinceEpochMs)
    }

    @Test
    fun `recording honours the run's unit`() {
        val c = complicationContent(
            metrics(Stage.Recording, distanceM = 16_093.44, paceSecPerKm = 300.0, unit = DistanceUnit.MI),
            null,
            now,
            Locale.US,
        )
        assertEquals("10.0 mi", c.distance)
        assertEquals("10.0 mi · 8:02/mi", c.detail)
    }

    @Test
    fun `recording with no pace yet shows the placeholder, not a zero`() {
        val c = complicationContent(metrics(Stage.Recording, paceSecPerKm = null), null, now, Locale.US)
        assertEquals("5.12 km · —:—/km", c.detail)
    }

    @Test
    fun `a negative elapsed anchors at now rather than in the future`() {
        val c = complicationContent(metrics(Stage.Recording, elapsedMs = -5_000L), null, now, Locale.US)
        assertEquals(now, c.liveSinceEpochMs)
    }

    @Test
    fun `paused freezes the elapsed time and drops the live anchor`() {
        val c = complicationContent(metrics(Stage.Paused), lastRun, now, Locale.US)
        assertEquals(ComplicationState.PAUSED, c.state)
        assertNull("a paused run must not keep counting on the face", c.liveSinceEpochMs)
        assertEquals("12:34", c.elapsed)
        assertEquals("12:34 · 5.12 km", c.detail)
    }

    @Test
    fun `idle shows the last run in the unit it was recorded in`() {
        val c = complicationContent(metrics(Stage.Idle), lastRun, now, Locale.US)
        assertEquals(ComplicationState.LAST_RUN, c.state)
        assertEquals("6.21 mi", c.distance)
        assertEquals("50:00", c.elapsed)
        assertEquals("6.21 mi · 50:00", c.detail)
        assertNull(c.liveSinceEpochMs)
    }

    @Test
    fun `a finished run waiting to be banked still reads as idle`() {
        val c = complicationContent(metrics(Stage.Finished), lastRun, now, Locale.US)
        assertEquals(ComplicationState.LAST_RUN, c.state)
    }

    @Test
    fun `idle with no last run is the start prompt`() {
        assertEquals(
            ComplicationState.NO_RUN,
            complicationContent(metrics(Stage.Idle), null, now, Locale.US).state,
        )
    }

    @Test
    fun `an unusable last-run distance is the start prompt, not NaN km`() {
        val broken = lastRun.copy(distanceM = Double.NaN)
        assertEquals(
            ComplicationState.NO_RUN,
            complicationContent(metrics(Stage.Idle), broken, now, Locale.US).state,
        )
        assertEquals(
            ComplicationState.NO_RUN,
            complicationContent(metrics(Stage.Idle), lastRun.copy(distanceM = -1.0), now, Locale.US).state,
        )
    }

    @Test
    fun `an unknown unit token falls back to kilometres`() {
        val c = complicationContent(metrics(Stage.Idle), lastRun.copy(unit = "yards"), now, Locale.US)
        assertEquals("10.0 km", c.distance)
    }

    @Test
    fun `the decimal separator follows the locale`() {
        val c = complicationContent(metrics(Stage.Recording), null, now, Locale.GERMANY)
        assertEquals("5,12 km", c.distance)
    }

    @Test
    fun `the editor preview is constant and never live`() {
        val p = previewContent(Locale.US)
        assertEquals(ComplicationState.RECORDING, p.state)
        assertNull("the platform caches the preview; a live anchor would freeze stale", p.liveSinceEpochMs)
        assertEquals("5.00 km", p.distance)
        assertEquals("26:15", p.elapsed)
        assertEquals("5.00 km · 5:15/km", p.detail)
        assertEquals(p, previewContent(Locale.US))
    }

    @Test
    fun `distance is pushed once a minute while recording and never while paused`() {
        assertEquals(120, COMPLICATION_PUSH_TICKS)
        assertFalse(isComplicationPushTick(0, Stage.Recording))
        assertFalse(isComplicationPushTick(60, Stage.Recording))
        assertTrue(isComplicationPushTick(120, Stage.Recording))
        assertTrue(isComplicationPushTick(240, Stage.Recording))
        assertFalse(isComplicationPushTick(120, Stage.Paused))
        assertFalse(isComplicationPushTick(120, Stage.Idle))
        assertFalse(isComplicationPushTick(120, Stage.Finished))
    }
}
