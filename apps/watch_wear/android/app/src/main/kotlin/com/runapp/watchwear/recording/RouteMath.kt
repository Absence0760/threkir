package com.runapp.watchwear.recording

import kotlin.math.PI
import kotlin.math.asin
import kotlin.math.cos
import kotlin.math.pow
import kotlin.math.sin
import kotlin.math.sqrt

/// Pure route-geometry helpers used during a run.
///
/// [routeProgress] ports the web `route_geometry.ts` `progressAlongRoute`
/// matcher (as does `packages/run_recorder`'s `_routeProgress` and watchOS's
/// `RouteGeometry.project`), over this file's own equirectangular projection.
/// Keep the implementations in step; any change to the matcher lands on every
/// port.
///
/// Live on the recording hot path: `RunRecordingService.onGps` calls
/// `routeProgress` once per GPS sample (only when a route is selected),
/// passing the previous match back in, and `RunningScreen` renders the
/// off-route banner + "X to go" badge from the resulting
/// `offRouteDistanceM` / `remainingM`.
///
/// All positions are `(latitude, longitude)` in decimal degrees.
/// All distances are in metres. Equirectangular projection is accurate
/// enough for running-route segments (a few km at most) — do not reuse
/// for long-haul geodesy.
object RouteMath {

    // Matcher tuning — the values web `route_geometry.ts` uses.
    private const val LOOKAHEAD_M = 200.0
    private const val BACKTRACK_M = 50.0

    /// The off-route alert threshold: a windowed match further off the line
    /// than this sends the matcher looking further along the route.
    private const val REACQUIRE_M = 40.0
    private const val FWD_BIAS_PER_M = 0.05
    private const val BACK_BIAS_PER_M = 0.5
    private const val MAX_BIAS_M = 20.0
    private const val CONTINUITY_PER_M = 1e-6

    /// Where a runner FOLLOWING [route] is along it, given the previous match.
    ///
    /// Only the stretch from [BACKTRACK_M] behind [previousAlongM] to
    /// [LOOKAHEAD_M] past `previousAlongM + travelledM` is searched (the start
    /// of the route when there is no previous match): on a loop the finish is
    /// as near as the start, an out-and-back's return leg lies on its outbound
    /// one and a figure-eight crosses itself, so a whole-line nearest search
    /// read a loop runner at the start as finished. Within the window a tie
    /// between overlapping legs goes to forward progress, with a bias capped at
    /// [MAX_BIAS_M] so it never outweighs real distance off the line. When
    /// nothing in the window is within [REACQUIRE_M], or the runner projects
    /// past its far end, the rest of the route ahead is searched, so a runner who skips ahead or returns after a signal
    /// gap is re-acquired; a runner still off the line keeps the windowed
    /// match, unless there is no previous match to keep.
    ///
    /// `offRouteDistanceM` is the distance to the nearest point on the WHOLE
    /// route: a runner standing on the line is not off it, whichever lap or
    /// leg the matcher has them on. Null for <2-point routes, or when no
    /// segment yields a usable projection.
    fun routeProgress(
        pos: LatLng,
        route: List<LatLng>,
        previousAlongM: Double? = null,
        travelledM: Double = 0.0,
    ): RouteProgress? {
        if (route.size < 2) return null
        val n = route.size - 1
        val segStart = DoubleArray(n)
        val segLen = DoubleArray(n)
        val tFree = DoubleArray(n)
        var total = 0.0
        var minDist = Double.POSITIVE_INFINITY
        for (i in 0 until n) {
            val a = route[i]
            val b = route[i + 1]
            segStart[i] = total
            segLen[i] = haversineM(a.lat, a.lng, b.lat, b.lng)
            total += segLen[i]
            val proj = projectPointOnSegment(pos.lat, pos.lng, a.lat, a.lng, b.lat, b.lng)
            tFree[i] = proj.t
            if (proj.distance < minDist) minDist = proj.distance
        }
        if (!minDist.isFinite() || !total.isFinite()) return null

        val hasPrevious = previousAlongM != null && previousAlongM.isFinite()
        val previous = if (hasPrevious) previousAlongM!!.coerceIn(0.0, total) else 0.0
        val travelled = if (travelledM.isFinite() && travelledM > 0) travelledM else 0.0
        val anchor = minOf(total, previous + travelled)
        val lo = if (hasPrevious) maxOf(0.0, previous - BACKTRACK_M) else 0.0

        // `pastEnd` marks a match pinned to `toM` while the runner projects
        // beyond it.
        data class Match(val along: Double, val offset: Double, val pastEnd: Boolean)

        fun best(fromM: Double, toM: Double): Match? {
            var found: Match? = null
            var bestCost = Double.POSITIVE_INFINITY
            for (i in 0 until n) {
                val s = segStart[i]
                val len = segLen[i]
                if (s > toM || s + len < fromM) continue
                val tLo = if (len > 0) maxOf(0.0, (fromM - s) / len) else 0.0
                val tHi = if (len > 0) minOf(1.0, (toM - s) / len) else 0.0
                val t = minOf(tHi, maxOf(tLo, tFree[i]))
                val offset = distanceAtT(pos, route[i], route[i + 1], t)
                val along = s + t * len
                val gap = along - anchor
                val bias = minOf(
                    MAX_BIAS_M,
                    if (gap >= 0) gap * FWD_BIAS_PER_M else -gap * BACK_BIAS_PER_M,
                )
                val cost = offset + bias + kotlin.math.abs(gap) * CONTINUITY_PER_M
                if (cost < bestCost) {
                    bestCost = cost
                    found = Match(along, offset, tFree[i] > t)
                }
            }
            return found
        }

        var match = best(lo, anchor + LOOKAHEAD_M)
        if (match == null || match.offset > REACQUIRE_M || match.pastEnd) {
            val ahead = best(lo, total)
            if (ahead != null &&
                (match == null ||
                    (ahead.offset < match.offset && (!hasPrevious || ahead.offset <= REACQUIRE_M)))
            ) {
                match = ahead
            }
        }
        if (match == null) return null
        val along = match.along.coerceIn(0.0, total)
        return RouteProgress(
            offRouteDistanceM = minDist,
            remainingM = maxOf(0.0, total - along),
            alongM = along,
        )
    }

    /// Perpendicular distance from [pos] to the point `t` of the way along
    /// segment A-B, in the same equirectangular frame as
    /// [projectPointOnSegment].
    private fun distanceAtT(pos: LatLng, a: LatLng, b: LatLng, t: Double): Double {
        val metresPerDegreeLng = METRES_PER_DEGREE * cos(toRad(a.lat))
        val px = (pos.lng - a.lng) * metresPerDegreeLng
        val py = (pos.lat - a.lat) * METRES_PER_DEGREE
        val bx = (b.lng - a.lng) * metresPerDegreeLng
        val by = (b.lat - a.lat) * METRES_PER_DEGREE
        val dx = px - bx * t
        val dy = py - by * t
        return sqrt(dx * dx + dy * dy)
    }

    /// Project P onto segment A-B and return both the perpendicular
    /// distance and the parameter `t ∈ [0, 1]` along the segment.
    /// `t=0` means "at A", `t=1` means "at B".
    internal fun projectPointOnSegment(
        pLat: Double, pLng: Double,
        aLat: Double, aLng: Double,
        bLat: Double, bLng: Double,
    ): Projection {
        val metresPerDegreeLat = METRES_PER_DEGREE
        val metresPerDegreeLng = METRES_PER_DEGREE * cos(toRad(aLat))

        val px = (pLng - aLng) * metresPerDegreeLng
        val py = (pLat - aLat) * metresPerDegreeLat
        val bx = (bLng - aLng) * metresPerDegreeLng
        val by = (bLat - aLat) * metresPerDegreeLat

        val lenSq = bx * bx + by * by
        if (lenSq == 0.0) {
            return Projection(distance = sqrt(px * px + py * py), t = 0.0)
        }
        var t = (px * bx + py * by) / lenSq
        t = t.coerceIn(0.0, 1.0)
        val cx = bx * t
        val cy = by * t
        val dx = px - cx
        val dy = py - cy
        return Projection(distance = sqrt(dx * dx + dy * dy), t = t)
    }

    /// Great-circle distance in metres between two lat/lng points.
    internal fun haversineM(
        aLat: Double, aLng: Double,
        bLat: Double, bLng: Double,
    ): Double {
        val r = 6_371_000.0
        val dLat = toRad(bLat - aLat)
        val dLng = toRad(bLng - aLng)
        val a = sin(dLat / 2).pow(2.0) +
            cos(toRad(aLat)) * cos(toRad(bLat)) * sin(dLng / 2).pow(2.0)
        return r * 2 * asin(sqrt(a))
    }

    private fun toRad(deg: Double): Double = deg * PI / 180.0

    private const val METRES_PER_DEGREE = 111_320.0

    data class LatLng(val lat: Double, val lng: Double)

    data class Projection(val distance: Double, val t: Double)

    /// Output of [routeProgress], all in metres: the off-route distance (to
    /// the nearest point anywhere on the route), the distance remaining to the
    /// route end from the matched point, and how far along the route that
    /// point is — what the caller passes back as the next `previousAlongM`.
    data class RouteProgress(
        val offRouteDistanceM: Double,
        val remainingM: Double,
        val alongM: Double,
    )
}
