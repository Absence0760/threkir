package com.runapp.watchwear

import com.runapp.watchwear.recording.RouteMath
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/// Pins the Kotlin half of the `race_finish` parity pair. The cases mirror
/// the Dart suite: in-zone closest approach, jitter in and out of the zone,
/// a loop course's early pass, and an out-and-back that runs past the line on
/// the way out.
class RaceFinishTest {

    private val finishLat = 51.5
    private val finishLng = -0.1
    private val metresPerDegLat = 6_371_000.0 * Math.PI / 180.0
    private val t0 = 1_800_000_000_000L

    /// A fix [northM] metres due north of the finish line.
    private fun fix(northM: Double, coveredM: Double, atS: Int) = RaceFinish.Fix(
        lat = finishLat + northM / metresPerDegLat,
        lng = finishLng,
        epochMs = t0 + atS * 1000L,
        coveredM = coveredM,
    )

    private fun detector(courseM: Double = 5000.0) =
        RaceFinishDetector(finishLat, finishLng, courseM)

    @Test
    fun `finish is the closest approach inside the zone, settled when distance grows`() {
        val d = detector()
        assertNull(d.offer(fix(50.0, 4950.0, 0)))
        assertNull(d.offer(fix(25.0, 4975.0, 5)))
        assertNull(d.offer(fix(12.0, 4988.0, 8)))
        assertNull(d.offer(fix(4.0, 4996.0, 11)))
        assertTrue(d.isCandidate)
        val f = d.offer(fix(9.0, 5005.0, 14))
        assertNotNull(f)
        assertEquals(t0 + 11_000L, f!!.epochMs)
        assertEquals(4.0, f.distanceToFinishM, 0.05)
        assertEquals(4996.0, f.coveredM, 0.0)
        assertFalse(d.isCandidate)
    }

    @Test
    fun `jitter out of the zone settles at the best fix seen inside it`() {
        val d = detector()
        assertNull(d.offer(fix(40.0, 4960.0, 0)))
        assertNull(d.offer(fix(28.0, 4972.0, 3)))
        val f = d.offer(fix(31.0, 4975.0, 6))
        assertEquals(t0 + 3_000L, f!!.epochMs)
        // Once settled, a fix that jitters back in cannot move the finish.
        assertEquals(f, d.offer(fix(2.0, 4980.0, 9)))
    }

    @Test
    fun `a single fix outside the zone before entry is not a finish`() {
        val d = detector()
        assertNull(d.offer(fix(31.0, 4990.0, 0)))
        assertNull(d.offer(fix(35.0, 4995.0, 3)))
        assertFalse(d.isCandidate)
        assertNull(d.finaliseNow())
    }

    @Test
    fun `loop course does not finish at the start or on an early pass`() {
        val d = detector()
        // Start line == finish line: inside the zone at zero distance.
        assertNull(d.offer(fix(0.0, 0.0, 0)))
        assertNull(d.offer(fix(10.0, 10.0, 4)))
        assertNull(d.offer(fix(40.0, 40.0, 12)))
        // A mid-course pass by the line, well short of 90 %.
        assertNull(d.offer(fix(8.0, 2500.0, 900)))
        assertNull(d.offer(fix(50.0, 2550.0, 915)))
        assertFalse(d.isCandidate)
        // The real finish.
        assertNull(d.offer(fix(15.0, 4985.0, 1800)))
        assertNull(d.offer(fix(6.0, 4994.0, 1803)))
        val f = d.offer(fix(12.0, 5000.0, 1806))
        assertEquals(t0 + 1_803_000L, f!!.epochMs)
    }

    @Test
    fun `out-and-back past the line on the way out finishes only on the way back`() {
        val d = detector(courseM = 10_000.0)
        // Outbound: the line sits 1 km in, so the runner crosses it at 10 %.
        assertNull(d.offer(fix(-20.0, 980.0, 300)))
        assertNull(d.offer(fix(0.0, 1000.0, 306)))
        assertNull(d.offer(fix(20.0, 1020.0, 312)))
        assertFalse(d.isCandidate)
        // Back: approaching from the north at 99 %+.
        assertNull(d.offer(fix(20.0, 9980.0, 3000)))
        assertNull(d.offer(fix(1.0, 9999.0, 3006)))
        val f = d.offer(fix(-18.0, 10_018.0, 3012))
        assertEquals(t0 + 3_006_000L, f!!.epochMs)
    }

    @Test
    fun `the distance gate is inclusive at exactly 90 percent`() {
        assertTrue(RaceFinish.meetsDistanceGate(4500.0, 5000.0))
        assertFalse(RaceFinish.meetsDistanceGate(4499.9, 5000.0))
        assertFalse(RaceFinish.meetsDistanceGate(9_999.0, 0.0))
    }

    @Test
    fun `finaliseNow settles a pending closest approach`() {
        val d = detector()
        assertNull(d.offer(fix(20.0, 4980.0, 0)))
        assertNull(d.offer(fix(7.0, 4993.0, 4)))
        val f = d.finaliseNow()
        assertEquals(t0 + 4_000L, f!!.epochMs)
        assertEquals(f, d.finish)
    }

    @Test
    fun `forCourse needs the course's finish point and a positive distance`() {
        assertNull(RaceFinishDetector.forCourse(null, null, 5000.0))
        assertNull(RaceFinishDetector.forCourse(finishLat, null, 5000.0))
        assertNull(RaceFinishDetector.forCourse(finishLat, finishLng, null))
        assertNull(RaceFinishDetector.forCourse(finishLat, finishLng, 0.0))
        assertNull(RaceFinishDetector.forCourse(finishLat, finishLng, Double.NaN))
        val d = RaceFinishDetector.forCourse(finishLat, finishLng, 5000.0)!!
        assertNull(d.offer(fix(3.0, 4990.0, 0)))
        assertTrue(d.isCandidate)
    }

    @Test
    fun `manual finish at 90 percent or more, DNF short of it, finish without a course`() {
        assertEquals(RaceFinish.Outcome.MANUAL_FINISH, RaceFinish.manualOutcome(4500.0, 5000.0))
        assertEquals(RaceFinish.Outcome.DNF, RaceFinish.manualOutcome(4499.0, 5000.0))
        assertEquals(RaceFinish.Outcome.MANUAL_FINISH, RaceFinish.manualOutcome(10.0, null))
        assertEquals("dnf", RaceFinish.Outcome.DNF.finisherStatus)
        assertNull(RaceFinish.Outcome.DNF.finishMethod)
        assertEquals("auto", RaceFinish.Outcome.AUTO_FINISH.finishMethod)
    }

    @Test
    fun `gun time corrects the device clock by the server offset`() {
        val gun = t0
        // Device clock runs 4 s behind the server: offset = +4000.
        val finishDevice = t0 + 3_600_000L - 4_000L
        assertEquals(3600, RaceFinish.gunTimeS(finishDevice, 4_000L, gun))
        // No estimate: the device clock is taken as-is.
        assertEquals(3596, RaceFinish.gunTimeS(finishDevice, null, gun))
        assertNull(RaceFinish.gunTimeS(finishDevice, 4_000L, null))
        assertNull(RaceFinish.gunTimeS(t0 - 10_000L, 0L, gun))
    }

    @Test
    fun `chip time is wall time from the runner's own start and duration prefers gun`() {
        assertEquals(1830, RaceFinish.chipTimeS(t0 + 1_830_500L, t0))
        assertEquals(0, RaceFinish.chipTimeS(t0 - 5L, t0))
        assertEquals(1845, RaceFinish.durationS(1845, 1830))
        assertEquals(1830, RaceFinish.durationS(null, 1830))
    }

    @Test
    fun `clock offset is taken against the round-trip midpoint`() {
        // Sent at 1000, received at 1400, server stamped 5200: midpoint 1200.
        assertEquals(4_000L, RaceFinish.clockOffsetMs(5_200L, 1_000L, 1_400L))
        assertEquals(-300L, RaceFinish.clockOffsetMs(900L, 1_000L, 1_400L))
    }
}
