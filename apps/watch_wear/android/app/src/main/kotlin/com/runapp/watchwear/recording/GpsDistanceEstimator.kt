package com.runapp.watchwear.recording

import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.sqrt

/// GPS distance estimator, spec v1.3 (forward filter) — the Wear OS port of
/// `scripts/gps_distance/reference.py`, which is the spec. Read
/// `docs/features/gps_distance.md` before changing anything here: every port
/// replays `fixtures/gps_distance_vectors.json` to 1e-3 m, so a change to one
/// port alone fails its vector test (`GpsDistanceEstimatorTest`).
///
/// `t` is seconds on a clock monotonic within the run. `expectedIntervalS`
/// is the interval the recorder samples GPS at on purpose: it scales the gap
/// and fresh-fix windows. `initialStrideM` carries a stride learned earlier
/// (e.g. before a pause) and is ignored outside the stride bounds.
///
/// The watch runs only the forward (causal) filter; the spec's smoother is
/// ported where the saved figure is computed from a whole run (phone, web,
/// server).
class GpsDistanceEstimator(
    val maxSpeedMps: Double = 10.0,
    val expectedIntervalS: Double = 1.0,
    initialStrideM: Double? = null,
) {

    private val intervalScale = if (expectedIntervalS.isFinite() && expectedIntervalS > 1.0) expectedIntervalS else 1.0
    private val gapS = GAP_S * intervalScale
    private val freshFixS = FRESH_FIX_S * intervalScale

    var gpsDistanceM = 0.0
        private set
    var stepDistanceM = 0.0
        private set
    var strideM: Double? = initialStrideM?.takeIf { it.isFinite() && it >= MIN_STRIDE_M && it <= MAX_STRIDE_M }
        private set

    val distanceM: Double get() = gpsDistanceM + stepDistanceM

    var rScale = 1.0
        private set
    var rejectedFixes = 0
        private set
    var zuptFixes = 0
        private set
    var dopplerTrusted = true
        private set
    var dopplerScale = 1.0
        private set

    private var lat0: Double? = null
    private var lng0: Double? = null
    private var x: Axis? = null
    private var y: Axis? = null
    private var lastT: Double? = null
    private var winSteps = 0L
    private var winM = 0.0
    private var lastSteps: Long? = null
    private var lastStepT: Double? = null
    private var pendingStepM = 0.0

    private var rejectStreak = 0
    private var xcDoppler = 0.0
    private var xcPos = 0.0
    private var xcTime = 0.0
    private var xcPersistS = 0.0
    private var xcLastX = 0.0
    private var xcLastY = 0.0
    private var xcLastT = 0.0
    private var dsPos = 0.0
    private var dsDop = 0.0
    private var dsTime = 0.0
    // (x, y, t, dop, bearing) of the last fix whose position the filter took.
    private var dsLastX = 0.0
    private var dsLastY = 0.0
    private var dsLastT = 0.0
    private var dsLastDop: Double? = null
    private var dsLastBearing: Double? = null
    private var stepsSeen = false
    private var lastStepIncT = 0.0
    private var zuptReleased = false
    private var zuptAnchorX: Double? = null
    private var zuptAnchorY = 0.0

    /// The pedometer says stationary: steps seen this run, none for
    /// ZUPT_NO_STEP_S, and trusted Doppler not contradicting it.
    private fun zuptDue(t: Double, dop: Double?): Boolean {
        if (!stepsSeen || zuptReleased || t - lastStepIncT <= ZUPT_NO_STEP_S) return false
        return !(dop != null && dopplerTrusted && dop >= ZUPT_DOPPLER_OVERRIDE_MPS)
    }

    private fun setDsLast(x: Double, y: Double, t: Double, dop: Double?, bearing: Double?) {
        dsLastX = x
        dsLastY = y
        dsLastT = t
        dsLastDop = dop
        dsLastBearing = bearing?.takeIf { it.isFinite() }
    }

    fun addFix(
        t: Double,
        lat: Double,
        lng: Double,
        accuracyM: Double? = null,
        speedMps: Double? = null,
        speedAccuracyMps: Double? = null,
        bearingDeg: Double? = null,
    ): Double {
        if (!valid(t) || !valid(lat) || !valid(lng)) return 0.0
        if (lat0 == null) {
            lat0 = lat
            lng0 = lng
        }
        val zx = Math.toRadians(wrapLng(lng - lng0!!)) * EARTH_RADIUS_M * cos(Math.toRadians(lat0!!))
        val zy = Math.toRadians(lat - lat0!!) * EARTH_RADIUS_M
        val sigma = accuracyM?.takeIf { it.isFinite() && it > 0 } ?: MIN_POS_SIGMA_M
        val s = max(sigma, MIN_POS_SIGMA_M)
        val rStated = s * s
        val r = max(rStated * rScale, MIN_POS_SIGMA_M * MIN_POS_SIGMA_M)
        val prevT = lastT
        if (prevT != null && t <= prevT) return 0.0
        val doppler = dopplerSpeed(speedMps, speedAccuracyMps, maxSpeedMps)
        val dop = doppler?.first
        if (prevT == null || t - prevT > gapS) {
            // (Re-)anchor. Steps buffered across a real gap are committed now.
            if (prevT != null) stepDistanceM += pendingStepM
            pendingStepM = 0.0
            x = Axis(zx, r)
            y = Axis(zy, r)
            lastT = t
            xcLastX = zx
            xcLastY = zy
            xcLastT = t
            setDsLast(zx, zy, t, dop, bearingDeg)
            rejectStreak = 0
            zuptAnchorX = null
            return 0.0
        }
        // The gap closed inside the gap window, so the filter integrates it: drop the buffer.
        pendingStepM = 0.0
        val dt = t - prevT
        lastT = t
        val ax = x!!
        val ay = y!!
        ax.predict(dt)
        ay.predict(dt)

        // 1. Innovation gate on the predicted position.
        val yx = zx - ax.p
        val yy = zy - ay.p
        val pax = ax.a
        val pay = ay.a
        val nis = yx * yx / (pax + r) + yy * yy / (pay + r)
        val accepted = nis <= GATE_CHI2
        if (accepted) {
            rejectStreak = 0
            ax.updatePos(zx, r)
            ay.updatePos(zy, r)
            // 2. Adaptive R: covariance matching, sample clamped, EMA, bounded.
            val sample = min(max(((yx * yx - pax) + (yy * yy - pay)) / (2.0 * rStated), 0.0), R_SCALE_MAX)
            val ema = (1.0 - R_SCALE_ALPHA) * rScale + R_SCALE_ALPHA * sample
            rScale = min(max(ema, R_SCALE_MIN), R_SCALE_MAX)
        } else {
            rejectedFixes += 1
            rejectStreak += 1
            if (rejectStreak > GATE_MAX_REJECTS) {
                ax.resetPos(zx, r)
                ay.resetPos(zy, r)
                rejectStreak = 0
                xcLastX = zx
                xcLastY = zy
                xcLastT = t
                setDsLast(zx, zy, t, dop, bearingDeg)
            }
        }

        // 3. Pedometer zero-velocity update.
        var zupt = zuptDue(t, dop)
        var chord: Double? = null
        if (zupt) {
            val anchorX = zuptAnchorX
            if (anchorX == null) {
                zuptAnchorX = ax.p
                zuptAnchorY = ay.p
            } else {
                val moved = hypot(ax.p - anchorX, ay.p - zuptAnchorY)
                if (moved > ZUPT_RELEASE_M) {
                    // The pedometer stalled while the runner moved: stop trusting it until it counts again.
                    zuptReleased = true
                    zuptAnchorX = null
                    zupt = false
                    chord = moved
                }
            }
        } else {
            zuptAnchorX = null
        }
        if (zupt) {
            zuptFixes += 1
            val rz = ZUPT_VEL_SIGMA_MPS * ZUPT_VEL_SIGMA_MPS
            ax.updateVel(0.0, rz)
            ay.updateVel(0.0, rz)
        }

        // 4. Doppler-vs-position cross-check: Doppler speed against the raw
        //    fixes' displacement projected on the Doppler bearing.
        val bearing = bearingDeg?.takeIf { it.isFinite() }
        if (accepted) {
            val span = t - xcLastT
            if (dop != null && !zupt && bearing != null &&
                dop >= POS_ONLY_STATIONARY_SPEED_MPS && span <= XCHECK_MAX_SPAN_S
            ) {
                val b = Math.toRadians(bearing)
                val u = ((zx - xcLastX) * sin(b) + (zy - xcLastY) * cos(b)) / span
                if (xcTime == 0.0) {
                    xcDoppler = dop
                    xcPos = dop
                } else {
                    val alpha = min(1.0, span / XCHECK_TAU_S)
                    xcDoppler += alpha * (dop - xcDoppler)
                    xcPos += alpha * (u - xcPos)
                }
                xcTime += span
                if (xcTime >= XCHECK_MIN_S) {
                    val diff = abs(xcDoppler - xcPos)
                    val ref = abs(xcPos)
                    val flip = if (dopplerTrusted) {
                        diff > max(XCHECK_ENTER_ABS_MPS, XCHECK_ENTER_REL * ref)
                    } else {
                        diff < max(XCHECK_EXIT_ABS_MPS, XCHECK_EXIT_REL * ref)
                    }
                    xcPersistS = if (flip) xcPersistS + span else 0.0
                    if (xcPersistS >= XCHECK_PERSIST_S) {
                        dopplerTrusted = !dopplerTrusted
                        xcPersistS = 0.0
                    }
                }
            }
            xcLastX = zx
            xcLastY = zy
            xcLastT = t

            // 4b. Doppler scale (v1.3): exponentially forgotten integrals of the
            //     fixes' displacement along the span's mean Doppler bearing and of
            //     the trapezoid Doppler distance over the same span.
            val ldop = dsLastDop
            val lb = dsLastBearing
            val dsSpan = t - dsLastT
            if (!zupt && dop != null && ldop != null && bearing != null && lb != null &&
                dop >= DSCALE_MIN_SPEED_MPS && ldop >= DSCALE_MIN_SPEED_MPS && dsSpan <= XCHECK_MAX_SPAN_S
            ) {
                val turn = abs(bearing - lb) % 360.0
                if (min(turn, 360.0 - turn) <= DSCALE_MAX_TURN_DEG) {
                    val b0 = Math.toRadians(lb)
                    val b1 = Math.toRadians(bearing)
                    val ux = sin(b0) + sin(b1)
                    val uy = cos(b0) + cos(b1)
                    val n = hypot(ux, uy)
                    val w = exp(-dsSpan / DSCALE_TAU_S)
                    dsPos = w * dsPos + ((zx - dsLastX) * ux + (zy - dsLastY) * uy) / n
                    dsDop = w * dsDop + 0.5 * (ldop + dop) * dsSpan
                    dsTime += dsSpan
                    if (dsTime >= DSCALE_MIN_S && dsDop > 0.0) {
                        dopplerScale = min(max(dsPos / dsDop, DSCALE_MIN), DSCALE_MAX)
                    }
                }
            }
            setDsLast(zx, zy, t, dop, bearingDeg)
        }

        // 5. Doppler velocity update.
        val useDop = if (dop != null && dopplerTrusted) dop * dopplerScale else null
        if (useDop != null && !zupt && bearing != null && useDop >= STATIONARY_SPEED_MPS) {
            val sv = max(doppler!!.second, MIN_SPEED_SIGMA_MPS)
            val rv = sv * sv
            val b = Math.toRadians(bearing)
            ax.updateVel(useDop * sin(b), rv)
            ay.updateVel(useDop * cos(b), rv)
        }

        // 6. Credit.
        val inc = when {
            chord != null -> chord
            zupt -> 0.0
            else -> {
                val speed: Double
                val floor: Double
                if (useDop != null) {
                    speed = useDop
                    floor = STATIONARY_SPEED_MPS
                } else {
                    speed = hypot(ax.v, ay.v)
                    floor = POS_ONLY_STATIONARY_SPEED_MPS
                }
                if (speed < floor) 0.0 else min(speed, maxSpeedMps) * dt
            }
        }
        gpsDistanceM += inc
        winM += inc
        return inc
    }

    fun addSteps(t: Double, cumulativeSteps: Long?) {
        if (!valid(t) || cumulativeSteps == null) return
        val prev = lastSteps
        val prevT = lastStepT
        lastSteps = cumulativeSteps
        lastStepT = t
        if (prev == null || cumulativeSteps < prev || prevT == null || t <= prevT) return
        val d = cumulativeSteps - prev
        if (d > 0) {
            stepsSeen = true
            lastStepIncT = t
            zuptReleased = false
        }
        val fixT = lastT
        if (fixT != null && t - fixT <= freshFixS) {
            winSteps += d
            if (winSteps >= STRIDE_WINDOW_STEPS) {
                val stride = winM / winSteps
                if (stride in MIN_STRIDE_M..MAX_STRIDE_M) {
                    val current = strideM
                    strideM = if (current == null) {
                        stride
                    } else {
                        (1 - STRIDE_EMA_ALPHA) * current + STRIDE_EMA_ALPHA * stride
                    }
                }
                winSteps = 0
                winM = 0.0
            }
            return
        }
        winSteps = 0
        winM = 0.0
        val stride = strideM ?: return
        pendingStepM += min(d * stride, maxSpeedMps * (t - prevT))
    }

    /// A fresh estimator for the segment after a pause: same configuration,
    /// seeded with this one's stride, which is itself the carried stride when
    /// this segment learned none.
    fun nextSegment(): GpsDistanceEstimator =
        GpsDistanceEstimator(maxSpeedMps, expectedIntervalS, strideM)

    fun finish(t: Double) {
        val fixT = lastT
        if (fixT != null && valid(t) && t - fixT > gapS) stepDistanceM += pendingStepM
        pendingStepM = 0.0
    }

    private class Axis(var p: Double, posVar: Double) {
        var v = 0.0
        var a = posVar
        var b = 0.0
        var c = INIT_VEL_VAR

        fun predict(dt: Double) {
            p += v * dt
            val na = a + 2.0 * dt * b + dt * dt * c + Q_ACCEL * dt * dt * dt / 3.0
            val nb = b + dt * c + Q_ACCEL * dt * dt / 2.0
            val nc = c + Q_ACCEL * dt
            a = na
            b = nb
            c = nc
        }

        fun updatePos(z: Double, r: Double) {
            val s = a + r
            val k0 = a / s
            val k1 = b / s
            val y = z - p
            p += k0 * y
            v += k1 * y
            val oa = a
            val ob = b
            val oc = c
            a = (1 - k0) * oa
            b = (1 - k0) * ob
            c = oc - k1 * ob
        }

        fun updateVel(z: Double, r: Double) {
            val s = c + r
            val k0 = b / s
            val k1 = c / s
            val y = z - v
            p += k0 * y
            v += k1 * y
            val oa = a
            val ob = b
            val oc = c
            a = oa - k0 * ob
            b = (1 - k1) * ob
            c = (1 - k1) * oc
        }

        /// Gate lock-out re-anchor: position jumps to z, velocity is kept.
        fun resetPos(z: Double, r: Double) {
            p = z
            a = r
            b = 0.0
        }
    }

    companion object {
        const val SPEC_ID = "kalman_v1"
        const val SPEC_VERSION = "1.3"

        private const val EARTH_RADIUS_M = 6371008.8
        private const val Q_ACCEL = 0.6
        private const val MIN_POS_SIGMA_M = 3.0
        private const val INIT_VEL_VAR = 25.0
        private const val MIN_SPEED_SIGMA_MPS = 0.3
        private const val DEFAULT_SPEED_SIGMA_MPS = 0.5
        private const val MAX_SPEED_SIGMA_MPS = 1.5
        private const val STATIONARY_SPEED_MPS = 0.4
        private const val POS_ONLY_STATIONARY_SPEED_MPS = 0.8
        private const val GAP_S = 10.0
        private const val FRESH_FIX_S = 2.0
        private const val STRIDE_WINDOW_STEPS = 50
        private const val MIN_STRIDE_M = 0.4
        private const val MAX_STRIDE_M = 2.5
        private const val STRIDE_EMA_ALPHA = 0.2
        private const val GATE_CHI2 = 13.8155
        private const val GATE_MAX_REJECTS = 5
        private const val R_SCALE_ALPHA = 0.05
        private const val R_SCALE_MIN = 1.0
        private const val R_SCALE_MAX = 9.0
        private const val XCHECK_TAU_S = 60.0
        private const val XCHECK_MIN_S = 120.0
        private const val XCHECK_ENTER_ABS_MPS = 0.4
        private const val XCHECK_ENTER_REL = 0.15
        private const val XCHECK_EXIT_ABS_MPS = 0.2
        private const val XCHECK_EXIT_REL = 0.08
        private const val XCHECK_PERSIST_S = 60.0
        private const val XCHECK_MAX_SPAN_S = 5.0
        private const val DEBIAS_FULL_MPS = 0.5
        private const val DEBIAS_ZERO_MPS = 1.0
        private const val DSCALE_TAU_S = 600.0
        private const val DSCALE_MIN_S = 60.0
        private const val DSCALE_MIN = 0.8
        private const val DSCALE_MAX = 1.25
        private const val DSCALE_MIN_SPEED_MPS = 1.5
        private const val DSCALE_MAX_TURN_DEG = 45.0
        private const val ZUPT_NO_STEP_S = 6.0
        private const val ZUPT_VEL_SIGMA_MPS = 0.1
        private const val ZUPT_DOPPLER_OVERRIDE_MPS = 1.0
        private const val ZUPT_RELEASE_M = 40.0

        private fun valid(x: Double): Boolean = x.isFinite()

        /// Wraps a longitude difference (inputs within [-180, 180]) into [-180, 180).
        private fun wrapLng(d: Double): Double = when {
            d >= 180.0 -> d - 360.0
            d < -180.0 -> d + 360.0
            else -> d
        }

        /// Usable, debiased Doppler speed and its sigma, or null.
        private fun dopplerSpeed(speedMps: Double?, speedAccuracyMps: Double?, maxSpeedMps: Double): Pair<Double, Double>? {
            val sp = speedMps?.takeIf { it.isFinite() && it >= 0.0 && it <= maxSpeedMps } ?: return null
            val reported = speedAccuracyMps != null && speedAccuracyMps.isFinite() && speedAccuracyMps > 0
            val sa = if (reported) speedAccuracyMps else DEFAULT_SPEED_SIGMA_MPS
            if (sa > MAX_SPEED_SIGMA_MPS) return null
            var s = sp
            if (reported && s < DEBIAS_ZERO_MPS) {
                val w = if (s <= DEBIAS_FULL_MPS) 1.0 else (DEBIAS_ZERO_MPS - s) / (DEBIAS_ZERO_MPS - DEBIAS_FULL_MPS)
                s = sqrt(max(0.0, s * s - w * sa * sa))
            }
            return s to sa
        }

        /// Every tunable constant by its reference name, so the vector test can
        /// hold each one to the fixture's `constants` block.
        internal val CONSTANTS: Map<String, Double> = mapOf(
            "EARTH_RADIUS_M" to EARTH_RADIUS_M,
            "Q_ACCEL" to Q_ACCEL,
            "MIN_POS_SIGMA_M" to MIN_POS_SIGMA_M,
            "INIT_VEL_VAR" to INIT_VEL_VAR,
            "MIN_SPEED_SIGMA_MPS" to MIN_SPEED_SIGMA_MPS,
            "DEFAULT_SPEED_SIGMA_MPS" to DEFAULT_SPEED_SIGMA_MPS,
            "MAX_SPEED_SIGMA_MPS" to MAX_SPEED_SIGMA_MPS,
            "STATIONARY_SPEED_MPS" to STATIONARY_SPEED_MPS,
            "POS_ONLY_STATIONARY_SPEED_MPS" to POS_ONLY_STATIONARY_SPEED_MPS,
            "GAP_S" to GAP_S,
            "FRESH_FIX_S" to FRESH_FIX_S,
            "STRIDE_WINDOW_STEPS" to STRIDE_WINDOW_STEPS.toDouble(),
            "MIN_STRIDE_M" to MIN_STRIDE_M,
            "MAX_STRIDE_M" to MAX_STRIDE_M,
            "STRIDE_EMA_ALPHA" to STRIDE_EMA_ALPHA,
            "GATE_CHI2" to GATE_CHI2,
            "GATE_MAX_REJECTS" to GATE_MAX_REJECTS.toDouble(),
            "R_SCALE_ALPHA" to R_SCALE_ALPHA,
            "R_SCALE_MIN" to R_SCALE_MIN,
            "R_SCALE_MAX" to R_SCALE_MAX,
            "XCHECK_TAU_S" to XCHECK_TAU_S,
            "XCHECK_MIN_S" to XCHECK_MIN_S,
            "XCHECK_ENTER_ABS_MPS" to XCHECK_ENTER_ABS_MPS,
            "XCHECK_ENTER_REL" to XCHECK_ENTER_REL,
            "XCHECK_EXIT_ABS_MPS" to XCHECK_EXIT_ABS_MPS,
            "XCHECK_EXIT_REL" to XCHECK_EXIT_REL,
            "XCHECK_PERSIST_S" to XCHECK_PERSIST_S,
            "XCHECK_MAX_SPAN_S" to XCHECK_MAX_SPAN_S,
            "DEBIAS_FULL_MPS" to DEBIAS_FULL_MPS,
            "DEBIAS_ZERO_MPS" to DEBIAS_ZERO_MPS,
            "DSCALE_TAU_S" to DSCALE_TAU_S,
            "DSCALE_MIN_S" to DSCALE_MIN_S,
            "DSCALE_MIN" to DSCALE_MIN,
            "DSCALE_MAX" to DSCALE_MAX,
            "DSCALE_MIN_SPEED_MPS" to DSCALE_MIN_SPEED_MPS,
            "DSCALE_MAX_TURN_DEG" to DSCALE_MAX_TURN_DEG,
            "ZUPT_NO_STEP_S" to ZUPT_NO_STEP_S,
            "ZUPT_VEL_SIGMA_MPS" to ZUPT_VEL_SIGMA_MPS,
            "ZUPT_DOPPLER_OVERRIDE_MPS" to ZUPT_DOPPLER_OVERRIDE_MPS,
            "ZUPT_RELEASE_M" to ZUPT_RELEASE_M,
        )

        /// Same ceilings as the phone's `ActivityType.maxSpeedMps`
        /// (`packages/core_models/lib/src/activity_type.dart`), so a ride
        /// recorded on the wrist is not clamped to running speed.
        fun maxSpeedMpsFor(activityType: String): Double = when (activityType) {
            "walk" -> 5.0
            "hike" -> 6.0
            "cycle" -> 25.0
            else -> 10.0
        }
    }
}
