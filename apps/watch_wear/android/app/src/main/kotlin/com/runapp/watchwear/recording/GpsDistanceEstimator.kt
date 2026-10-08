package com.runapp.watchwear.recording

import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

/// GPS distance estimator, spec v1.1 — the Wear OS port of
/// `scripts/gps_distance/reference.py`, which is the spec. Read
/// `docs/features/gps_distance.md` before changing anything here: every port
/// replays `fixtures/gps_distance_vectors.json` to 1e-3 m, so a change to one
/// port alone fails its vector test (`GpsDistanceEstimatorTest`).
///
/// `t` is seconds on a clock monotonic within the run. `expectedIntervalS`
/// is the interval the recorder samples GPS at on purpose: it scales the gap
/// and fresh-fix windows. `initialStrideM` carries a stride learned earlier
/// (e.g. before a pause) and is ignored outside the stride bounds.
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
        val zx = Math.toRadians(lng - lng0!!) * EARTH_RADIUS_M * cos(Math.toRadians(lat0!!))
        val zy = Math.toRadians(lat - lat0!!) * EARTH_RADIUS_M
        val sigma = accuracyM?.takeIf { it.isFinite() && it > 0 } ?: MIN_POS_SIGMA_M
        val s = max(sigma, MIN_POS_SIGMA_M)
        val r = s * s
        val prevT = lastT
        if (prevT != null && t <= prevT) return 0.0
        if (prevT == null || t - prevT > gapS) {
            if (prevT != null) stepDistanceM += pendingStepM
            pendingStepM = 0.0
            x = Axis(zx, r)
            y = Axis(zy, r)
            lastT = t
            return 0.0
        }
        pendingStepM = 0.0
        val dt = t - prevT
        lastT = t
        val ax = x!!
        val ay = y!!
        ax.predict(dt)
        ay.predict(dt)
        ax.updatePos(zx, r)
        ay.updatePos(zy, r)

        val doppler = speedMps?.takeIf { it.isFinite() && it >= 0.0 && it <= maxSpeedMps }?.let { sp ->
            val sa = speedAccuracyMps?.takeIf { it.isFinite() && it > 0 } ?: DEFAULT_SPEED_SIGMA_MPS
            if (sa > MAX_SPEED_SIGMA_MPS) return@let null
            val bearing = bearingDeg?.takeIf { it.isFinite() }
            if (bearing != null && sp >= STATIONARY_SPEED_MPS) {
                val sv = max(sa, MIN_SPEED_SIGMA_MPS)
                val rv = sv * sv
                val b = Math.toRadians(bearing)
                ax.updateVel(sp * sin(b), rv)
                ay.updateVel(sp * cos(b), rv)
            }
            sp
        }

        val speed: Double
        val floor: Double
        if (doppler != null) {
            speed = doppler
            floor = STATIONARY_SPEED_MPS
        } else {
            speed = hypot(ax.v, ay.v)
            floor = POS_ONLY_STATIONARY_SPEED_MPS
        }
        if (speed < floor) return 0.0
        val inc = min(speed, maxSpeedMps) * dt
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
    }

    companion object {
        const val SPEC_ID = "kalman_v1"

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

        private fun valid(x: Double): Boolean = x.isFinite()

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
