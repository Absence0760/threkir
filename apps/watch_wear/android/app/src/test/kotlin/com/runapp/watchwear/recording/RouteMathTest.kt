package com.runapp.watchwear.recording

import com.runapp.watchwear.recording.RouteMath.LatLng
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/// Route-geometry math is the kernel of the off-route alert + the
/// "X to go" badge. These tests mirror the behavioural expectations of
/// web `progressAlongRoute` and its ports (`packages/run_recorder`, watchOS
/// `RouteGeometry`) — any change that breaks symmetry here must land on
/// every port.
class RouteMathTest {

    // Tolerances: equirectangular projection is accurate to ~1 m over
    // running-route segments, but unit-test tolerances can be tighter
    // because we build fixtures with exact Cartesian geometry in mind.
    private val metreTolerance = 1.0
    private val tTolerance = 1e-3

    // A tiny ~100m E-W segment in central Berlin. Lat/lng chosen so the
    // 111,320 m/° lat approximation and cos(lat)·111,320 m/° lng give
    // clean numbers.
    private val berlinA = LatLng(52.5200, 13.4050)
    private val berlinB = LatLng(52.5200, 13.4065) // ~101 m east of A

    @Test
    fun `offRouteDistance returns null for empty route`() {
        assertNull(RouteMath.routeProgress(berlinA, emptyList())?.offRouteDistanceM)
    }

    @Test
    fun `offRouteDistance returns null for single-point route`() {
        assertNull(RouteMath.routeProgress(berlinA, listOf(berlinA))?.offRouteDistanceM)
    }

    @Test
    fun `offRouteDistance zero when point lies exactly on segment`() {
        val mid = LatLng(52.5200, (13.4050 + 13.4065) / 2)
        val d = RouteMath.routeProgress(mid, listOf(berlinA, berlinB))?.offRouteDistanceM
        assertNotNull(d)
        assertEquals(0.0, d!!, metreTolerance)
    }

    @Test
    fun `offRouteDistance perpendicular distance matches expected`() {
        // ~50m north of the segment midpoint.
        val off = LatLng(52.5200 + 50.0 / 111_320.0, (13.4050 + 13.4065) / 2)
        val d = RouteMath.routeProgress(off, listOf(berlinA, berlinB))?.offRouteDistanceM
        assertNotNull(d)
        assertEquals(50.0, d!!, metreTolerance)
    }

    @Test
    fun `offRouteDistance clamps at endpoints when projection is past segment end`() {
        // ~30m east of point B (past the end of the segment). The closest
        // point on the finite segment is B itself.
        val past = LatLng(52.5200, 13.4065 + 30.0 / (111_320.0 * kotlin.math.cos(Math.toRadians(52.5200))))
        val d = RouteMath.routeProgress(past, listOf(berlinA, berlinB))?.offRouteDistanceM
        assertNotNull(d)
        assertEquals(30.0, d!!, metreTolerance)
    }

    @Test
    fun `offRouteDistance picks minimum across multiple segments`() {
        // Three-segment route: A→B, B→C, C→D.
        val c = LatLng(52.5210, 13.4065) // ~111 m north of B
        val d = LatLng(52.5210, 13.4080) // ~101 m east of C
        val route = listOf(berlinA, berlinB, c, d)

        // Sit 10 m off segment B→C; should be the winning (minimum)
        // distance over all four candidates.
        val near = LatLng(52.5205, 13.4065 + 10.0 / (111_320.0 * kotlin.math.cos(Math.toRadians(52.5205))))
        val off = RouteMath.routeProgress(near, route)?.offRouteDistanceM
        assertNotNull(off)
        assertEquals(10.0, off!!, metreTolerance)
    }

    @Test
    fun `routeRemaining returns null for empty route`() {
        assertNull(RouteMath.routeProgress(berlinA, emptyList())?.remainingM)
    }

    @Test
    fun `routeRemaining returns null for single-point route`() {
        assertNull(RouteMath.routeProgress(berlinA, listOf(berlinA))?.remainingM)
    }

    @Test
    fun `routeRemaining at start of segment equals full segment length`() {
        val r = RouteMath.routeProgress(berlinA, listOf(berlinA, berlinB))?.remainingM
        assertNotNull(r)
        val expected = RouteMath.haversineM(
            berlinA.lat, berlinA.lng, berlinB.lat, berlinB.lng,
        )
        assertEquals(expected, r!!, metreTolerance)
    }

    @Test
    fun `routeRemaining at end of segment is zero`() {
        val r = RouteMath.routeProgress(berlinB, listOf(berlinA, berlinB))?.remainingM
        assertNotNull(r)
        assertEquals(0.0, r!!, metreTolerance)
    }

    @Test
    fun `routeRemaining at midpoint is half the segment length`() {
        val mid = LatLng(52.5200, (13.4050 + 13.4065) / 2)
        val r = RouteMath.routeProgress(mid, listOf(berlinA, berlinB))?.remainingM
        assertNotNull(r)
        val segLen = RouteMath.haversineM(
            berlinA.lat, berlinA.lng, berlinB.lat, berlinB.lng,
        )
        assertEquals(segLen / 2, r!!, metreTolerance)
    }

    @Test
    fun `routeRemaining sums across multiple segments past closest projection`() {
        val c = LatLng(52.5210, 13.4065)
        val d = LatLng(52.5210, 13.4080)
        val route = listOf(berlinA, berlinB, c, d)

        // Start from A — expect full route length.
        val total = RouteMath.routeProgress(berlinA, route)?.remainingM
        val expected = RouteMath.haversineM(berlinA.lat, berlinA.lng, berlinB.lat, berlinB.lng) +
            RouteMath.haversineM(berlinB.lat, berlinB.lng, c.lat, c.lng) +
            RouteMath.haversineM(c.lat, c.lng, d.lat, d.lng)
        assertNotNull(total)
        assertEquals(expected, total!!, metreTolerance * 3)
    }

    @Test
    fun `routeRemaining correctly drops to last-segment length when past midpoint`() {
        val c = LatLng(52.5210, 13.4065)
        val d = LatLng(52.5210, 13.4080)
        val route = listOf(berlinA, berlinB, c, d)

        // Stand exactly on C — the remainder should be exactly C→D.
        val r = RouteMath.routeProgress(c, route)?.remainingM
        val expected = RouteMath.haversineM(c.lat, c.lng, d.lat, d.lng)
        assertNotNull(r)
        assertEquals(expected, r!!, metreTolerance)
    }

    @Test
    fun `projectPointOnSegment clamps t at zero when point is before segment start`() {
        // ~30m west of A (before the start).
        val before = LatLng(52.5200, 13.4050 - 30.0 / (111_320.0 * kotlin.math.cos(Math.toRadians(52.5200))))
        val proj = RouteMath.projectPointOnSegment(
            before.lat, before.lng,
            berlinA.lat, berlinA.lng,
            berlinB.lat, berlinB.lng,
        )
        assertEquals(0.0, proj.t, tTolerance)
        assertEquals(30.0, proj.distance, metreTolerance)
    }

    @Test
    fun `projectPointOnSegment clamps t at one when point is after segment end`() {
        val past = LatLng(52.5200, 13.4065 + 30.0 / (111_320.0 * kotlin.math.cos(Math.toRadians(52.5200))))
        val proj = RouteMath.projectPointOnSegment(
            past.lat, past.lng,
            berlinA.lat, berlinA.lng,
            berlinB.lat, berlinB.lng,
        )
        assertEquals(1.0, proj.t, tTolerance)
        assertEquals(30.0, proj.distance, metreTolerance)
    }

    @Test
    fun `projectPointOnSegment returns raw distance when segment is zero-length`() {
        val proj = RouteMath.projectPointOnSegment(
            52.5201, 13.4051,
            berlinA.lat, berlinA.lng,
            berlinA.lat, berlinA.lng, // zero-length segment
        )
        assertEquals(0.0, proj.t, tTolerance)
        assertTrue(proj.distance > 0.0)
    }

    @Test
    fun `haversineM matches equirectangular within tolerance for short segments`() {
        val h = RouteMath.haversineM(berlinA.lat, berlinA.lng, berlinB.lat, berlinB.lng)
        // ~1.5e-3 degrees at lat 52.52 × ~67,800 m/°lng ≈ 101 m.
        assertEquals(101.7, h, metreTolerance)
    }

    @Test
    fun `routeProgress returns null for routes under two points`() {
        assertNull(RouteMath.routeProgress(berlinA, emptyList()))
        assertNull(RouteMath.routeProgress(berlinA, listOf(berlinA)))
    }

    // ── Following a route that passes the same place twice ──────────────

    // Metres east/north of the equator origin, in this file's own 111,320 m/°
    // projection so the expected lengths stay readable.
    private fun en(eastM: Double, northM: Double) =
        LatLng(northM / 111_320.0, eastM / 111_320.0)

    // 500 m square, start == finish, run anticlockwise: east, north, west,
    // south. The closing leg runs down x = 0 into the start.
    private val squareLoop = listOf(en(0.0, 0.0), en(500.0, 0.0), en(500.0, 500.0), en(0.0, 500.0), en(0.0, 0.0))
    private val squareLoopM = 4 * RouteMath.haversineM(0.0, 0.0, 0.0, 500.0 / 111_320.0)

    @Test
    fun `routeProgress has a loop runner at the start with the whole loop to go`() {
        // 1 m east and 3 m north of the start: nearer the CLOSING leg (1 m) than
        // the opening one (3 m), which a whole-line nearest search snaps to —
        // reading the lap as finished the instant the run starts.
        val p = RouteMath.routeProgress(en(1.0, 3.0), squareLoop)!!
        assertEquals(squareLoopM, p.remainingM, 5.0)
        assertEquals(1.0, p.offRouteDistanceM, 0.5)
    }

    @Test
    fun `routeProgress keeps a lap of the loop on route and winds down to the finish`() {
        var prev: Double? = null
        var last: RouteMath.RouteProgress? = null
        val legs = listOf(
            doubleArrayOf(0.0, 0.0, 500.0, 0.0),
            doubleArrayOf(500.0, 0.0, 500.0, 500.0),
            doubleArrayOf(500.0, 500.0, 0.0, 500.0),
            doubleArrayOf(0.0, 500.0, 0.0, 0.0),
        )
        for (l in legs) {
            for (s in 0..50) {
                val p = RouteMath.routeProgress(
                    en(l[0] + (l[2] - l[0]) * s / 50, l[1] + (l[3] - l[1]) * s / 50),
                    squareLoop,
                    previousAlongM = prev,
                )!!
                assertTrue("off route ${p.offRouteDistanceM}", p.offRouteDistanceM < 0.5)
                prev = p.alongM
                last = p
            }
        }
        assertEquals(0.0, last!!.remainingM, 1.0)
    }

    @Test
    fun `routeProgress puts an out-and-back runner past the turnaround on the return leg`() {
        val outAndBack = listOf(en(0.0, 0.0), en(1000.0, 0.0), en(0.0, 0.0))
        val legM = RouteMath.haversineM(0.0, 0.0, 0.0, 1000.0 / 111_320.0)
        var prev: Double? = null
        for (m in 0..100) {
            prev = RouteMath.routeProgress(en(m * 10.0, 0.0), outAndBack, previousAlongM = prev)!!.alongM
        }
        var last = RouteMath.routeProgress(en(1000.0, 0.0), outAndBack, previousAlongM = prev)!!
        for (m in 99 downTo 90) {
            last = RouteMath.routeProgress(en(m * 10.0, 0.0), outAndBack, previousAlongM = last.alongM)!!
        }
        assertEquals(legM * 0.9, last.remainingM, 1.0)
        assertEquals(0.0, last.offRouteDistanceM, 0.5)
    }

    @Test
    fun `routeProgress still flags a runner who leaves the loop`() {
        val p = RouteMath.routeProgress(en(250.0, 120.0), squareLoop, previousAlongM = 250.0)!!
        assertEquals(120.0, p.offRouteDistanceM, 1.0)
        assertTrue("off route ${p.offRouteDistanceM}", p.offRouteDistanceM > 40.0)
        assertEquals(250.0, p.alongM, 2.0)
    }

    @Test
    fun `routeProgress uses distance travelled to pick the leg after a gap`() {
        val outAndBack = listOf(en(0.0, 0.0), en(1000.0, 0.0), en(0.0, 0.0))
        val legM = RouteMath.haversineM(0.0, 0.0, 0.0, 1000.0 / 111_320.0)
        val p = RouteMath.routeProgress(en(900.0, 0.0), outAndBack, previousAlongM = 0.0, travelledM = legM * 1.1)!!
        assertEquals(legM * 1.1, p.alongM, 1.0)
    }
}
