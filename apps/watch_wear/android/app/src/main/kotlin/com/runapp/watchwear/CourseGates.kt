package com.runapp.watchwear

import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.sqrt

/// The start and finish boxes of a course and the edges it is timed by: a
/// one-way Kotlin port of the box half of the `course_gates` pair (web
/// `apps/web/src/lib/races/course_gates.ts`, the phone's
/// `apps/mobile_android/lib/course_gates.dart`), held to the same
/// `fixtures/course_gates_cases.json` § `boxParts` and § `timingEdges`
/// (`CourseGatesTest`). Only what the live course timer reads is ported; the
/// route relation, warnings and race preflight stay on the phone and web.
/// Names follow the Dart half (decisions § 2589).

const val COURSE_GATE_BOX_DEPTH_M = 10.0
const val COURSE_GATE_SHARED_SPOT_M = 10.0
const val COURSE_GATE_SHARED_SPOT_DEG = 20.0

data class GatePoint(val lat: Double, val lng: Double)

enum class GateWhich { START, FINISH }

enum class GateBoxSide { BEHIND, AHEAD, CENTRED }

enum class GateBoxLayout { APART, SHARED }

/// One box on a course map. [which] is null for the one box a start and
/// finish at one spot share.
data class GateBoxPart(
    val which: GateWhich?,
    val box: List<GatePoint>,
    val line: Pair<GatePoint, GatePoint>,
)

data class GateBoxMarker(val which: GateWhich?, val at: GatePoint)

data class GateBoxParts(
    val layout: GateBoxLayout,
    val parts: List<GateBoxPart>,
    val markers: List<GateBoxMarker>,
)

data class GateTimingEdges(
    val layout: GateBoxLayout,
    val startExit: Gate,
    val finishEntry: Gate,
    val depthM: Double,
)

private fun rad(deg: Double): Double = deg * Math.PI / 180.0
private fun deg(r: Double): Double = r * 180.0 / Math.PI

private fun wrapLng(d: Double): Double = when {
    d >= 180.0 -> d - 360.0
    d < -180.0 -> d + 360.0
    else -> d
}

/// Any finite bearing into [0, 360).
fun normalizeBearing(deg: Double): Double {
    val b = ((deg % 360.0) + 360.0) % 360.0
    return if (b >= 360.0) 0.0 else b
}

/// Smallest angle between two bearings, 0..180.
fun bearingDelta(a: Double, b: Double): Double {
    val d = kotlin.math.abs(normalizeBearing(a) - normalizeBearing(b))
    return if (d > 180.0) 360.0 - d else d
}

/// [p] on the tangent plane at [origin]: metres east (first) and north.
internal fun planeXY(origin: GatePoint, p: GatePoint): Pair<Double, Double> = Pair(
    rad(wrapLng(p.lng - origin.lng)) * GATE_EARTH_RADIUS_M * cos(rad(origin.lat)),
    rad(p.lat - origin.lat) * GATE_EARTH_RADIUS_M,
)

internal fun fromPlane(origin: GatePoint, x: Double, y: Double): GatePoint = GatePoint(
    origin.lat + deg(y / GATE_EARTH_RADIUS_M),
    wrapLng(origin.lng + deg(x / (GATE_EARTH_RADIUS_M * cos(rad(origin.lat))))),
)

internal fun bearingTo(from: GatePoint, to: GatePoint): Double {
    val (x, y) = planeXY(from, to)
    return normalizeBearing(deg(atan2(x, y)))
}

internal fun offsetPoint(origin: GatePoint, bearingDeg: Double, distM: Double): GatePoint =
    fromPlane(origin, distM * sin(rad(bearingDeg)), distM * cos(rad(bearingDeg)))

private fun centre(g: Gate) = GatePoint(g.lat, g.lng)

/// The line's two ends, left of travel first.
fun gateLineEnds(gate: Gate): Pair<GatePoint, GatePoint> {
    val b = rad(gate.bearingDeg)
    val ex = gate.halfWidthM * cos(b)
    val ey = -gate.halfWidthM * sin(b)
    val c = centre(gate)
    return Pair(fromPlane(c, -ex, -ey), fromPlane(c, ex, ey))
}

/// The box on one side of a line, [depthM] deep, from [from] to [to] of the
/// half-width along it: the near edge first (its
/// left end, then its right), then the far right and far left corners. A
/// [GateBoxSide.CENTRED] box runs from half its depth behind the line to half
/// ahead, its near edge the one behind.
fun gateBox(gate: Gate, depthM: Double, side: GateBoxSide, from: Double = -1.0, to: Double = 1.0): List<GatePoint> {
    val b = rad(gate.bearingDeg)
    val ax = gate.halfWidthM * cos(b)
    val ay = -gate.halfWidthM * sin(b)
    val (near, far) = when (side) {
        GateBoxSide.AHEAD -> 0.0 to depthM
        GateBoxSide.BEHIND -> 0.0 to -depthM
        GateBoxSide.CENTRED -> -depthM / 2 to depthM / 2
    }
    val c = centre(gate)
    fun at(f: Double, k: Double) = fromPlane(c, f * ax + k * sin(b), f * ay + k * cos(b))
    return listOf(at(from, near), at(to, near), at(to, far), at(from, far))
}

/// Whether a start line and a finish line sit at one spot: a loop's or an
/// out-and-back's.
fun gatesShareSpot(start: Gate, finish: Gate): Boolean {
    val (x, y) = planeXY(centre(start), centre(finish))
    if (sqrt(x * x + y * y) > COURSE_GATE_SHARED_SPOT_M) return false
    val d = bearingDelta(start.bearingDeg, finish.bearingDeg)
    return d <= COURSE_GATE_SHARED_SPOT_DEG || d >= 180.0 - COURSE_GATE_SHARED_SPOT_DEG
}

/// The start and finish boxes a course map draws (decisions § 2582).
fun gateBoxParts(start: Gate?, finish: Gate?, depthM: Double = COURSE_GATE_BOX_DEPTH_M): GateBoxParts {
    fun part(which: GateWhich?, gate: Gate) = GateBoxPart(
        which = which,
        box = gateBox(
            gate,
            depthM,
            when (which) {
                null -> GateBoxSide.CENTRED
                GateWhich.START -> GateBoxSide.BEHIND
                GateWhich.FINISH -> GateBoxSide.AHEAD
            },
        ),
        line = gateLineEnds(gate),
    )
    fun marker(which: GateWhich?, gate: Gate, away: Double, distM: Double) =
        GateBoxMarker(which, offsetPoint(centre(gate), away, distM))
    fun back(g: Gate) = g.bearingDeg + 180.0

    if (start != null && finish != null && gatesShareSpot(start, finish)) {
        return GateBoxParts(
            layout = GateBoxLayout.SHARED,
            parts = listOf(part(null, start)),
            markers = listOf(marker(null, start, back(start), depthM / 2)),
        )
    }
    return GateBoxParts(
        layout = GateBoxLayout.APART,
        parts = listOfNotNull(
            start?.let { part(GateWhich.START, it) },
            finish?.let { part(GateWhich.FINISH, it) },
        ),
        markers = listOfNotNull(
            start?.let { marker(GateWhich.START, it, back(it), depthM) },
            finish?.let { marker(GateWhich.FINISH, it, it.bearingDeg, depthM) },
        ),
    )
}

private fun edgeGate(a: GatePoint, b: GatePoint, bearingDeg: Double, halfWidthM: Double): Gate {
    val (x, y) = planeXY(a, b)
    val mid = fromPlane(a, x / 2, y / 2)
    return Gate(lat = mid.lat, lng = mid.lng, bearingDeg = normalizeBearing(bearingDeg), halfWidthM = halfWidthM)
}

/// The edges a course with both lines is timed by (decisions § 2589):
/// leaving the start box forward crosses [GateTimingEdges.startExit],
/// entering the finish box crosses [GateTimingEdges.finishEntry]. Apart, they
/// are the lines; at a shared spot, the box's far edge out and its near edge
/// back on a loop, or its far edge facing back on an out-and-back.
fun gateTimingEdges(start: Gate, finish: Gate, depthM: Double = COURSE_GATE_BOX_DEPTH_M): GateTimingEdges {
    val boxes = gateBoxParts(start, finish, depthM)
    if (boxes.layout == GateBoxLayout.SHARED) {
        val box = boxes.parts[0].box
        val nearL = box[0]
        val nearR = box[1]
        val farR = box[2]
        val farL = box[3]
        val sameWay = bearingDelta(start.bearingDeg, finish.bearingDeg) <= 90.0
        return GateTimingEdges(
            layout = boxes.layout,
            startExit = edgeGate(farL, farR, start.bearingDeg, start.halfWidthM),
            finishEntry = if (sameWay) {
                edgeGate(nearL, nearR, start.bearingDeg, start.halfWidthM)
            } else {
                edgeGate(farR, farL, start.bearingDeg + 180.0, start.halfWidthM)
            },
            depthM = depthM,
        )
    }
    val s = boxes.parts[0].box
    val f = boxes.parts[1].box
    return GateTimingEdges(
        layout = boxes.layout,
        startExit = edgeGate(s[0], s[1], start.bearingDeg, start.halfWidthM),
        finishEntry = edgeGate(f[0], f[1], finish.bearingDeg, finish.halfWidthM),
        depthM = depthM,
    )
}

/// Whether a course's end line is also its start line: within the start
/// line's reach, facing within 90 degrees of it. On such a loop the finish
/// opens the next lap. The `segments` pair's `linesChain`.
fun linesChain(start: Gate, end: Gate): Boolean {
    if (courseHaversineM(start.lat, start.lng, end.lat, end.lng) > start.halfWidthM) return false
    val turn = (((end.bearingDeg - start.bearingDeg) % 360.0) + 540.0) % 360.0 - 180.0
    return kotlin.math.abs(turn) < 90.0
}

/// The `segments` pair's `haversineMetres`: 6,371,000 m, the argument clamped
/// before the arc, so the timer's distances are the matcher's to the bit.
internal fun courseHaversineM(lat1: Double, lng1: Double, lat2: Double, lng2: Double): Double {
    val r = 6_371_000.0
    val dLat = (lat2 - lat1) * Math.PI / 180.0
    val dLng = (lng2 - lng1) * Math.PI / 180.0
    val sinLat = sin(dLat / 2)
    val sinLng = sin(dLng / 2)
    val a = sinLat * sinLat + cos(lat1 * Math.PI / 180.0) * cos(lat2 * Math.PI / 180.0) * sinLng * sinLng
    val clamped = if (a > 1.0) 1.0 else if (a < 0.0) 0.0 else a
    return r * 2 * kotlin.math.asin(sqrt(clamped))
}
