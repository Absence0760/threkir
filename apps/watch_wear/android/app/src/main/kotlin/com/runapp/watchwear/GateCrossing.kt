package com.runapp.watchwear

import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.sqrt

/// Timing-line ("gate") crossing detection, spec `gate_crossing v1` (issue
/// #1304, decisions § 2362). A pure port of the `gate_crossing` pair (Dart
/// side `apps/mobile_android/lib/gate_crossing.dart`, web side
/// `apps/web/src/lib/geo/gate_crossing.ts`). No Android, no I/O, no clock.
/// All three read `fixtures/gate_crossing_cases.json`, so a rule changes there
/// or nowhere.

const val GATE_EARTH_RADIUS_M = 6_371_008.8

// Provisional until the #1304 calibration session measures them.
const val GATE_MAX_GAP_S = 10.0
const val GATE_MAX_HOP_M = 50.0
const val GATE_REJECT_GAP_S = 60.0
const val GATE_HALF_WIDTH_RACE_M = 15.0
const val GATE_HALF_WIDTH_SEGMENT_M = 15.0

/// A line through ([lat], [lng]), perpendicular to the direction of travel
/// [bearingDeg] (clockwise from north), reaching [halfWidthM] either side.
data class Gate(
    val lat: Double,
    val lng: Double,
    val bearingDeg: Double,
    val halfWidthM: Double,
)

/// One distinct, trusted fix, timed at its own fix instant ([tMs], epoch
/// milliseconds), with the distance the recording had covered by then.
data class GateFix(
    val lat: Double,
    val lng: Double,
    val tMs: Double,
    val coveredM: Double,
)

enum class GateDirection { FORWARD, BACKWARD }

data class GateCrossing(
    val direction: GateDirection,
    /// Where between the two fixes the line was crossed, 0..1.
    val fraction: Double,
    val tMs: Double,
    val coveredM: Double,
    /// Lateral offset from the centre, positive to the right of travel.
    val offsetM: Double,
    /// The pair was more than maxGapS apart or hopped more than maxHopM.
    val gapped: Boolean,
)

data class GateCrossingOptions(
    val maxGapS: Double = GATE_MAX_GAP_S,
    val maxHopM: Double = GATE_MAX_HOP_M,
    val rejectGapS: Double = GATE_REJECT_GAP_S,
)

/// [s]: signed distance past the line along travel. [u]: lateral offset.
data class GateProjection(val s: Double, val u: Double)

private fun rad(deg: Double): Double = deg * Math.PI / 180.0

private fun wrapLng(d: Double): Double = when {
    d >= 180.0 -> d - 360.0
    d < -180.0 -> d + 360.0
    else -> d
}

private fun gateUsable(gate: Gate): Boolean =
    gate.lat.isFinite() && gate.lng.isFinite() && gate.bearingDeg.isFinite() &&
        gate.halfWidthM.isFinite() && gate.halfWidthM >= 0.0

/// ([lat], [lng]) on the tangent plane at the gate centre, on the gate's axes.
fun gateProjection(gate: Gate, lat: Double, lng: Double): GateProjection {
    val x = rad(wrapLng(lng - gate.lng)) * GATE_EARTH_RADIUS_M * cos(rad(gate.lat))
    val y = rad(lat - gate.lat) * GATE_EARTH_RADIUS_M
    val sinB = sin(rad(gate.bearingDeg))
    val cosB = cos(rad(gate.bearingDeg))
    return GateProjection(s = x * sinB + y * cosB, u = x * cosB - y * sinB)
}

/// Streaming form: [offer] each fix as it arrives; the call that completes a
/// crossing returns it. [settle] ends the stream and returns every crossing.
class GateCrossingDetector(
    val gate: Gate,
    val options: GateCrossingOptions = GateCrossingOptions(),
) {
    private class Projected(val fix: GateFix, val s: Double, val u: Double)

    private val usable = gateUsable(gate)
    private var prev: Projected? = null
    private val found = mutableListOf<GateCrossing>()
    private var settled = false

    val crossings: List<GateCrossing> get() = found.toList()

    fun offer(fix: GateFix): GateCrossing? {
        if (settled || !usable) return null
        if (!fix.lat.isFinite() || !fix.lng.isFinite() || !fix.tMs.isFinite() || !fix.coveredM.isFinite()) {
            return null
        }
        val before = prev
        if (before != null && fix.tMs <= before.fix.tMs) return null

        val p = gateProjection(gate, fix.lat, fix.lng)
        val cur = Projected(fix, p.s, p.u)
        prev = cur
        if (before == null) return null

        val crossing = cross(before, cur)
        if (crossing != null) found.add(crossing)
        return crossing
    }

    fun settle(): List<GateCrossing> {
        settled = true
        return found.toList()
    }

    private fun cross(a: Projected, b: Projected): GateCrossing? {
        val direction = when {
            a.s < 0.0 && b.s >= 0.0 -> GateDirection.FORWARD
            a.s >= 0.0 && b.s < 0.0 -> GateDirection.BACKWARD
            else -> return null
        }

        val dtS = (b.fix.tMs - a.fix.tMs) / 1000.0
        if (dtS > options.rejectGapS) return null

        val f = -a.s / (b.s - a.s)
        val offsetM = a.u + f * (b.u - a.u)
        if (abs(offsetM) > gate.halfWidthM) return null

        val ds = b.s - a.s
        val du = b.u - a.u
        val hopM = sqrt(ds * ds + du * du)
        return GateCrossing(
            direction = direction,
            fraction = f,
            tMs = a.fix.tMs + f * (b.fix.tMs - a.fix.tMs),
            coveredM = a.fix.coveredM + f * (b.fix.coveredM - a.fix.coveredM),
            offsetM = offsetM,
            gapped = dtS > options.maxGapS || hopM > options.maxHopM,
        )
    }
}

/// Batch form: every crossing of [track] through [gate], in order.
fun crossingsOf(
    track: List<GateFix>,
    gate: Gate,
    options: GateCrossingOptions = GateCrossingOptions(),
): List<GateCrossing> {
    val detector = GateCrossingDetector(gate, options)
    for (fix in track) detector.offer(fix)
    return detector.settle()
}
