import Foundation

/// GPS distance estimator, spec v1.3 forward filter — the watchOS port of
/// `scripts/gps_distance/reference.py`. See `docs/features/gps_distance.md`.
/// The watch runs only the causal filter; the spec's smoother is ported where
/// a whole run's saved figure is computed (phone, web, server).
///
/// Every port replays `fixtures/gps_distance_vectors.json` to 1e-3 m, so the
/// arithmetic below follows the reference operation for operation. Do not tune
/// a constant here alone; change the reference and regenerate the vectors.
final class GpsDistanceEstimator {
    static let earthRadiusM = 6371008.8
    static let qAccel = 0.6
    static let minPosSigmaM = 3.0
    static let initVelVar = 25.0
    static let minSpeedSigmaMps = 0.3
    static let defaultSpeedSigmaMps = 0.5
    static let maxSpeedSigmaMps = 1.5
    static let stationarySpeedMps = 0.4
    static let posOnlyStationarySpeedMps = 0.8
    static let gapS = 10.0
    static let freshFixS = 2.0
    static let strideWindowSteps = 50
    static let minStrideM = 0.4
    static let maxStrideM = 2.5
    static let strideEmaAlpha = 0.2
    static let gateChi2 = 13.8155
    static let gateMaxRejects = 5
    static let rScaleAlpha = 0.05
    static let rScaleMin = 1.0
    static let rScaleMax = 9.0
    static let xcheckTauS = 60.0
    static let xcheckMinS = 120.0
    static let xcheckEnterAbsMps = 0.4
    static let xcheckEnterRel = 0.15
    static let xcheckExitAbsMps = 0.2
    static let xcheckExitRel = 0.08
    static let xcheckPersistS = 60.0
    static let xcheckMaxSpanS = 5.0
    static let debiasFullMps = 0.5
    static let debiasZeroMps = 1.0
    static let dscaleTauS = 600.0
    static let dscaleMinS = 60.0
    static let dscaleMin = 0.8
    static let dscaleMax = 1.25
    static let dscaleMinSpeedMps = 1.5
    static let dscaleMaxTurnDeg = 45.0
    static let zuptNoStepS = 6.0
    static let zuptVelSigmaMps = 0.1
    static let zuptDopplerOverrideMps = 1.0
    static let zuptReleaseM = 40.0
    static let specVersion = "1.3"

    /// Every constant by its reference name, so the vector test can hold each
    /// one to the fixture's `constants` block.
    static let constants: [String: Double] = [
        "EARTH_RADIUS_M": earthRadiusM, "Q_ACCEL": qAccel, "MIN_POS_SIGMA_M": minPosSigmaM,
        "INIT_VEL_VAR": initVelVar, "MIN_SPEED_SIGMA_MPS": minSpeedSigmaMps,
        "DEFAULT_SPEED_SIGMA_MPS": defaultSpeedSigmaMps, "MAX_SPEED_SIGMA_MPS": maxSpeedSigmaMps,
        "STATIONARY_SPEED_MPS": stationarySpeedMps, "POS_ONLY_STATIONARY_SPEED_MPS": posOnlyStationarySpeedMps,
        "GAP_S": gapS, "FRESH_FIX_S": freshFixS, "STRIDE_WINDOW_STEPS": Double(strideWindowSteps),
        "MIN_STRIDE_M": minStrideM, "MAX_STRIDE_M": maxStrideM, "STRIDE_EMA_ALPHA": strideEmaAlpha,
        "GATE_CHI2": gateChi2, "GATE_MAX_REJECTS": Double(gateMaxRejects),
        "R_SCALE_ALPHA": rScaleAlpha, "R_SCALE_MIN": rScaleMin, "R_SCALE_MAX": rScaleMax,
        "XCHECK_TAU_S": xcheckTauS, "XCHECK_MIN_S": xcheckMinS,
        "XCHECK_ENTER_ABS_MPS": xcheckEnterAbsMps, "XCHECK_ENTER_REL": xcheckEnterRel,
        "XCHECK_EXIT_ABS_MPS": xcheckExitAbsMps, "XCHECK_EXIT_REL": xcheckExitRel,
        "XCHECK_PERSIST_S": xcheckPersistS, "XCHECK_MAX_SPAN_S": xcheckMaxSpanS,
        "DEBIAS_FULL_MPS": debiasFullMps, "DEBIAS_ZERO_MPS": debiasZeroMps,
        "DSCALE_TAU_S": dscaleTauS, "DSCALE_MIN_S": dscaleMinS, "DSCALE_MIN": dscaleMin, "DSCALE_MAX": dscaleMax,
        "DSCALE_MIN_SPEED_MPS": dscaleMinSpeedMps, "DSCALE_MAX_TURN_DEG": dscaleMaxTurnDeg,
        "ZUPT_NO_STEP_S": zuptNoStepS, "ZUPT_VEL_SIGMA_MPS": zuptVelSigmaMps,
        "ZUPT_DOPPLER_OVERRIDE_MPS": zuptDopplerOverrideMps, "ZUPT_RELEASE_M": zuptReleaseM,
    ]

    private static let degToRad = Double.pi / 180.0

    private struct Axis {
        var p: Double
        var v: Double = 0
        var a: Double
        var b: Double = 0
        var c: Double = GpsDistanceEstimator.initVelVar

        init(p: Double, posVar: Double) {
            self.p = p
            self.a = posVar
        }

        mutating func predict(_ dt: Double) {
            p += v * dt
            let q = GpsDistanceEstimator.qAccel
            let na = a + 2.0 * dt * b + dt * dt * c + q * pow(dt, 3.0) / 3.0
            let nb = b + dt * c + q * dt * dt / 2.0
            let nc = c + q * dt
            a = na
            b = nb
            c = nc
        }

        mutating func updatePos(_ z: Double, _ r: Double) {
            let s = a + r
            let k0 = a / s
            let k1 = b / s
            let y = z - p
            p += k0 * y
            v += k1 * y
            let oa = a, ob = b, oc = c
            a = (1 - k0) * oa
            b = (1 - k0) * ob
            c = oc - k1 * ob
        }

        mutating func updateVel(_ z: Double, _ r: Double) {
            let s = c + r
            let k0 = b / s
            let k1 = c / s
            let y = z - v
            p += k0 * y
            v += k1 * y
            let oa = a, ob = b, oc = c
            a = oa - k0 * ob
            b = (1 - k1) * ob
            c = (1 - k1) * oc
        }

        /// Gate lock-out re-anchor: position jumps to z, velocity is kept.
        mutating func resetPos(_ z: Double, _ r: Double) {
            p = z
            a = r
            b = 0
        }
    }

    let maxSpeedMps: Double
    let expectedIntervalS: Double
    /// The gap and fresh-fix windows, scaled by the interval the recorder
    /// samples GPS at on purpose.
    let gapWindowS: Double
    let freshFixWindowS: Double
    private(set) var gpsDistanceM: Double = 0
    private(set) var stepDistanceM: Double = 0
    private(set) var strideM: Double?
    private(set) var rScale: Double = 1
    private(set) var rejectedFixes = 0
    private(set) var zuptFixes = 0
    private(set) var dopplerTrusted = true
    private(set) var dopplerScale: Double = 1

    private var lat0: Double?
    private var lng0: Double = 0
    private var x: Axis?
    private var y: Axis?
    private var t: Double?
    private var winSteps = 0
    private var winM: Double = 0
    private var lastSteps: Int?
    private var lastStepT: Double?
    private var pendingStepM: Double = 0
    private var rejectStreak = 0
    private var xcDoppler: Double = 0
    private var xcPos: Double = 0
    private var xcTime: Double = 0
    private var xcPersistS: Double = 0
    private var xcLast = (x: 0.0, y: 0.0, t: 0.0)
    private var dsPos: Double = 0
    private var dsDop: Double = 0
    private var dsTime: Double = 0
    /// The last fix whose position the filter took, with its Doppler speed and bearing.
    private var dsLast: (x: Double, y: Double, t: Double, dop: Double?, bearing: Double?) = (0, 0, 0, nil, nil)
    private var stepsSeen = false
    private var lastStepIncT: Double = 0
    private var zuptReleased = false
    private var zuptAnchor: (x: Double, y: Double)?

    /// `initialStrideM` carries a stride learned earlier (e.g. before a
    /// pause); it is ignored outside `minStrideM...maxStrideM`.
    init(maxSpeedMps: Double = 10.0, expectedIntervalS: Double = 1.0, initialStrideM: Double? = nil) {
        self.maxSpeedMps = maxSpeedMps
        self.expectedIntervalS = expectedIntervalS
        let scale = expectedIntervalS.isFinite && expectedIntervalS > 1.0 ? expectedIntervalS : 1.0
        self.gapWindowS = Self.gapS * scale
        self.freshFixWindowS = Self.freshFixS * scale
        if let seed = initialStrideM, seed.isFinite, seed >= Self.minStrideM, seed <= Self.maxStrideM {
            self.strideM = seed
        }
    }

    /// A fresh estimator for the segment after a pause: same configuration,
    /// seeded with this one's stride, which is itself the carried stride when
    /// this segment learned none.
    func nextSegment() -> GpsDistanceEstimator {
        GpsDistanceEstimator(maxSpeedMps: maxSpeedMps, expectedIntervalS: expectedIntervalS, initialStrideM: strideM)
    }

    var distanceM: Double { gpsDistanceM + stepDistanceM }

    /// Wraps a longitude difference (inputs within [-180, 180]) into [-180, 180).
    private static func wrapLng(_ d: Double) -> Double {
        if d >= 180.0 { return d - 360.0 }
        if d < -180.0 { return d + 360.0 }
        return d
    }

    /// Usable, debiased Doppler speed and its sigma, or nil.
    private func dopplerSpeed(_ speedMps: Double?, _ speedAccuracyMps: Double?) -> (s: Double, sa: Double)? {
        guard let speed = speedMps, speed.isFinite, speed >= 0, speed <= maxSpeedMps else { return nil }
        var sa = Self.defaultSpeedSigmaMps
        var reported = false
        if let acc = speedAccuracyMps, acc.isFinite, acc > 0 {
            sa = acc
            reported = true
        }
        if sa > Self.maxSpeedSigmaMps { return nil }
        var s = speed
        if reported && s < Self.debiasZeroMps {
            let w = s <= Self.debiasFullMps ? 1.0 : (Self.debiasZeroMps - s) / (Self.debiasZeroMps - Self.debiasFullMps)
            s = (max(0.0, s * s - w * sa * sa)).squareRoot()
        }
        return (s, sa)
    }

    /// The pedometer says stationary: steps seen this run, none for
    /// `zuptNoStepS`, and trusted Doppler not contradicting it.
    private func zuptDue(_ t: Double, _ dop: Double?) -> Bool {
        if !stepsSeen || zuptReleased || t - lastStepIncT <= Self.zuptNoStepS { return false }
        if let dop, dopplerTrusted, dop >= Self.zuptDopplerOverrideMps { return false }
        return true
    }

    /// `t` is seconds on a clock monotonic within the run. Returns the metres
    /// this fix credited.
    @discardableResult
    func addFix(
        t: Double,
        lat: Double,
        lng: Double,
        accuracyM: Double? = nil,
        speedMps: Double? = nil,
        speedAccuracyMps: Double? = nil,
        bearingDeg: Double? = nil
    ) -> Double {
        guard t.isFinite, lat.isFinite, lng.isFinite else { return 0 }
        if lat0 == nil {
            lat0 = lat
            lng0 = lng
        }
        let originLat = lat0 ?? lat
        let zx = Self.wrapLng(lng - lng0) * Self.degToRad * Self.earthRadiusM * cos(originLat * Self.degToRad)
        let zy = (lat - originLat) * Self.degToRad * Self.earthRadiusM
        var sigma = Self.minPosSigmaM
        if let acc = accuracyM, acc.isFinite, acc > 0 { sigma = acc }
        let floored = max(sigma, Self.minPosSigmaM)
        let rStated = floored * floored
        let r = max(rStated * rScale, Self.minPosSigmaM * Self.minPosSigmaM)

        if let last = self.t, t <= last { return 0 }
        let doppler = dopplerSpeed(speedMps, speedAccuracyMps)
        let dop = doppler?.s
        guard let last = self.t, t - last <= gapWindowS, var ax = x, var ay = y else {
            // (Re-)anchor. Steps buffered across a real gap are committed now.
            if self.t != nil {
                stepDistanceM += pendingStepM
            }
            pendingStepM = 0
            x = Axis(p: zx, posVar: r)
            y = Axis(p: zy, posVar: r)
            self.t = t
            xcLast = (zx, zy, t)
            dsLast = (zx, zy, t, dop, bearingDeg.flatMap { $0.isFinite ? $0 : nil })
            rejectStreak = 0
            zuptAnchor = nil
            return 0
        }
        // The gap closed inside the gap window, so the filter integrates it: drop the buffer.
        pendingStepM = 0
        let dt = t - last
        self.t = t
        ax.predict(dt)
        ay.predict(dt)

        // 1. Innovation gate on the predicted position.
        let yx = zx - ax.p
        let yy = zy - ay.p
        let pax = ax.a
        let pay = ay.a
        let nis = yx * yx / (pax + r) + yy * yy / (pay + r)
        let accepted = nis <= Self.gateChi2
        if accepted {
            rejectStreak = 0
            ax.updatePos(zx, r)
            ay.updatePos(zy, r)
            // 2. Adaptive R: covariance matching, sample clamped, EMA, bounded.
            let sample = min(max(((yx * yx - pax) + (yy * yy - pay)) / (2.0 * rStated), 0), Self.rScaleMax)
            let ema = (1.0 - Self.rScaleAlpha) * rScale + Self.rScaleAlpha * sample
            rScale = min(max(ema, Self.rScaleMin), Self.rScaleMax)
        } else {
            rejectedFixes += 1
            rejectStreak += 1
            if rejectStreak > Self.gateMaxRejects {
                ax.resetPos(zx, r)
                ay.resetPos(zy, r)
                rejectStreak = 0
                xcLast = (zx, zy, t)
                dsLast = (zx, zy, t, dop, bearingDeg.flatMap { $0.isFinite ? $0 : nil })
            }
        }

        // 3. Pedometer zero-velocity update.
        var zupt = zuptDue(t, dop)
        var chord: Double?
        if zupt {
            if let anchor = zuptAnchor {
                let moved = hypot(ax.p - anchor.x, ay.p - anchor.y)
                if moved > Self.zuptReleaseM {
                    // The pedometer stalled while the runner moved: stop trusting it until it counts again.
                    zuptReleased = true
                    zuptAnchor = nil
                    zupt = false
                    chord = moved
                }
            } else {
                zuptAnchor = (ax.p, ay.p)
            }
        } else {
            zuptAnchor = nil
        }
        if zupt {
            zuptFixes += 1
            let rz = Self.zuptVelSigmaMps * Self.zuptVelSigmaMps
            ax.updateVel(0, rz)
            ay.updateVel(0, rz)
        }

        // 4. Doppler-vs-position cross-check: Doppler speed against the raw
        //    fixes' displacement projected on the Doppler bearing.
        let bearing = bearingDeg.flatMap { $0.isFinite ? $0 : nil }
        if accepted {
            let span = t - xcLast.t
            if let dop, !zupt, let bearing, dop >= Self.posOnlyStationarySpeedMps, span <= Self.xcheckMaxSpanS {
                let b = bearing * Self.degToRad
                let u = ((zx - xcLast.x) * sin(b) + (zy - xcLast.y) * cos(b)) / span
                if xcTime == 0 {
                    xcDoppler = dop
                    xcPos = dop
                } else {
                    let alpha = min(1.0, span / Self.xcheckTauS)
                    xcDoppler += alpha * (dop - xcDoppler)
                    xcPos += alpha * (u - xcPos)
                }
                xcTime += span
                if xcTime >= Self.xcheckMinS {
                    let diff = abs(xcDoppler - xcPos)
                    let ref = abs(xcPos)
                    let flip = dopplerTrusted
                        ? diff > max(Self.xcheckEnterAbsMps, Self.xcheckEnterRel * ref)
                        : diff < max(Self.xcheckExitAbsMps, Self.xcheckExitRel * ref)
                    xcPersistS = flip ? xcPersistS + span : 0
                    if xcPersistS >= Self.xcheckPersistS {
                        dopplerTrusted.toggle()
                        xcPersistS = 0
                    }
                }
            }
            xcLast = (zx, zy, t)

            // 4b. Doppler scale (v1.3): exponentially forgotten integrals of the
            //     fixes' displacement along the span's mean Doppler bearing and of
            //     the trapezoid Doppler distance over the same span.
            let dsSpan = t - dsLast.t
            if !zupt, let dop, let ldop = dsLast.dop, let bearing, let lb = dsLast.bearing,
               dop >= Self.dscaleMinSpeedMps, ldop >= Self.dscaleMinSpeedMps, dsSpan <= Self.xcheckMaxSpanS {
                let turn = abs(bearing - lb).truncatingRemainder(dividingBy: 360.0)
                if min(turn, 360.0 - turn) <= Self.dscaleMaxTurnDeg {
                    let b0 = lb * Self.degToRad
                    let b1 = bearing * Self.degToRad
                    let ux = sin(b0) + sin(b1)
                    let uy = cos(b0) + cos(b1)
                    let n = hypot(ux, uy)
                    let w = exp(-dsSpan / Self.dscaleTauS)
                    dsPos = w * dsPos + ((zx - dsLast.x) * ux + (zy - dsLast.y) * uy) / n
                    dsDop = w * dsDop + 0.5 * (ldop + dop) * dsSpan
                    dsTime += dsSpan
                    if dsTime >= Self.dscaleMinS, dsDop > 0 {
                        dopplerScale = min(max(dsPos / dsDop, Self.dscaleMin), Self.dscaleMax)
                    }
                }
            }
            dsLast = (zx, zy, t, dop, bearing)
        }

        // 5. Doppler velocity update.
        let scale = dopplerScale
        let useDop = dopplerTrusted ? doppler.map { (s: $0.s * scale, sa: $0.sa) } : nil
        if let useDop, !zupt, let bearing, useDop.s >= Self.stationarySpeedMps {
            let flooredSa = max(useDop.sa, Self.minSpeedSigmaMps)
            let rv = flooredSa * flooredSa
            let b = bearing * Self.degToRad
            ax.updateVel(useDop.s * sin(b), rv)
            ay.updateVel(useDop.s * cos(b), rv)
        }
        x = ax
        y = ay

        // 6. Credit.
        let inc: Double
        if let chord {
            inc = chord
        } else if zupt {
            inc = 0
        } else {
            let speed: Double
            let stationaryFloor: Double
            if let useDop {
                speed = useDop.s
                stationaryFloor = Self.stationarySpeedMps
            } else {
                speed = hypot(ax.v, ay.v)
                stationaryFloor = Self.posOnlyStationarySpeedMps
            }
            inc = speed < stationaryFloor ? 0 : min(speed, maxSpeedMps) * dt
        }
        gpsDistanceM += inc
        winM += inc
        return inc
    }

    /// Cumulative pedometer count. Learns a stride while GPS is good and
    /// buffers steps x stride while it is not; the buffer is committed only
    /// when the gap turns out to exceed `gapWindowS`.
    func addSteps(t: Double, cumulativeSteps: Int) {
        guard t.isFinite else { return }
        let prev = lastSteps
        let prevT = lastStepT
        lastSteps = cumulativeSteps
        lastStepT = t
        guard let prev, let prevT, cumulativeSteps >= prev, t > prevT else { return }
        let d = cumulativeSteps - prev
        if d > 0 {
            stepsSeen = true
            lastStepIncT = t
            zuptReleased = false
        }
        if let fixT = self.t, t - fixT <= freshFixWindowS {
            winSteps += d
            if winSteps >= Self.strideWindowSteps {
                let stride = winM / Double(winSteps)
                if stride >= Self.minStrideM && stride <= Self.maxStrideM {
                    if let current = strideM {
                        strideM = (1 - Self.strideEmaAlpha) * current + Self.strideEmaAlpha * stride
                    } else {
                        strideM = stride
                    }
                }
                winSteps = 0
                winM = 0
            }
            return
        }
        winSteps = 0
        winM = 0
        guard let stride = strideM else { return }
        pendingStepM += min(Double(d) * stride, maxSpeedMps * (t - prevT))
    }

    /// End of run: commit buffered steps if the trailing gap exceeds `gapWindowS`.
    func finish(t: Double) {
        if let fixT = self.t, t.isFinite, t - fixT > gapWindowS {
            stepDistanceM += pendingStepM
        }
        pendingStepM = 0
    }
}
