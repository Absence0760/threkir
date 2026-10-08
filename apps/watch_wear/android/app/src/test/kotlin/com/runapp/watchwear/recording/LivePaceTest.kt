package com.runapp.watchwear.recording

import kotlin.math.PI
import kotlin.math.cos
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test

/// Live pace is the GPS distance estimator's distance gained over ~200 m. The
/// zig-zag cases drive the same estimator + window pair `RunRecordingService`
/// does; the expected values come from `scripts/gps_distance/reference.py`
/// over the same track (300.0 s/km with Doppler, 299.9 s/km from positions).
class LivePaceTest {

    /// A steady 5:00/km (10/3 m/s) due north, one fix a second, each fix
    /// 1.25 m either side of the true line. Every hop is 4.17 m for 3.33 m
    /// of progress, so a hop-sum reads 4:00/km.
    private fun zigZagPace(doppler: Boolean): Double? {
        val speed = 10.0 / 3.0
        val degLatPerM = 1.0 / 111_195.0
        val degLngPerM = degLatPerM / cos(51.5 * PI / 180.0)
        val estimator = GpsDistanceEstimator()
        val window = LivePaceWindow()
        for (i in 0 until 121) {
            val t = i.toDouble()
            estimator.addFix(
                t = t,
                lat = 51.5 + i * speed * degLatPerM,
                lng = -0.1 + (if (i % 2 == 1) 1.25 else -1.25) * degLngPerM,
                accuracyM = 5.0,
                speedMps = if (doppler) speed else null,
                speedAccuracyMps = if (doppler) 0.5 else null,
                bearingDeg = if (doppler) 0.0 else null,
            )
            window.add(t, estimator.distanceM)
        }
        return window.secondsPerKm
    }

    @Test
    fun `a zig-zag at 5 min per km reads 5 min per km with Doppler`() {
        assertEquals(300.0, zigZagPace(doppler = true)!!, 1.0)
    }

    @Test
    fun `a zig-zag at 5 min per km reads 5 min per km from positions alone`() {
        assertEquals(300.0, zigZagPace(doppler = false)!!, 3.0)
    }

    @Test
    fun `the window reads only the last 200 m`() {
        val w = LivePaceWindow()
        // 90 m at 1 m/s, then 250 m at 5 m/s.
        for (i in 0..9) w.add(i * 10.0, i * 10.0)
        for (j in 1..5) w.add(90.0 + j * 10, 90.0 + j * 50)
        assertEquals(200.0, w.secondsPerKm!!, 0.001)
    }

    @Test
    fun `pace is withheld until five fixes and 50 m`() {
        val w = LivePaceWindow()
        for (i in 0..3) w.add(i * 10.0, i * 50.0)
        assertNull("four fixes", w.secondsPerKm)
        w.add(40.0, 200.0)
        assertNotNull(w.secondsPerKm)

        val slow = LivePaceWindow()
        for (i in 0..5) slow.add(i * 5.0, i * 4.0)
        assertNull("20 m is under the 50 m floor", slow.secondsPerKm)
    }

    @Test
    fun `a seal drops the pre-pause window`() {
        val w = LivePaceWindow()
        for (i in 0..4) w.add(i * 10.0, i * 50.0)
        w.seal()
        // The next segment's estimator restarts at 0 m, 600 s later.
        for (i in 0..5) w.add(640.0 + i * 5, i * 15.0)
        assertEquals(333.3, w.secondsPerKm!!, 0.1)
    }

    @Test
    fun `a gap the estimator re-anchors over seals the window`() {
        val w = LivePaceWindow()
        for (i in 0..4) w.add(i * 10.0, i * 50.0)
        w.add(52.0, 200.0)
        assertNull("no window may span the 12 s gap", w.secondsPerKm)
        for (i in 1..8) w.add(52.0 + i * 10, 200.0 + i * 40)
        assertEquals(250.0, w.secondsPerKm!!, 0.001)
    }

    @Test
    fun `a fix that does not advance the clock is ignored`() {
        val w = LivePaceWindow()
        for (i in 0..4) w.add(i * 10.0, i * 50.0)
        val before = w.secondsPerKm
        w.add(40.0, 500.0)
        assertEquals(before!!, w.secondsPerKm!!, 0.0)
    }
}
