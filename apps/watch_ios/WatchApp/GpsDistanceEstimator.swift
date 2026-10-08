import Foundation

/// GPS distance estimator, spec v1 — the watchOS port of
/// `scripts/gps_distance/reference.py`. See `docs/features/gps_distance.md`.
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
    }

    let maxSpeedMps: Double
    private(set) var gpsDistanceM: Double = 0
    private(set) var stepDistanceM: Double = 0
    private(set) var strideM: Double?

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

    init(maxSpeedMps: Double = 10.0) {
        self.maxSpeedMps = maxSpeedMps
    }

    var distanceM: Double { gpsDistanceM + stepDistanceM }

    private static func valid(_ value: Double?) -> Bool {
        guard let value else { return false }
        return value.isFinite
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
        let zx = (lng - lng0) * Self.degToRad * Self.earthRadiusM * cos(originLat * Self.degToRad)
        let zy = (lat - originLat) * Self.degToRad * Self.earthRadiusM
        var sigma = Self.minPosSigmaM
        if let acc = accuracyM, acc.isFinite, acc > 0 { sigma = acc }
        let floored = max(sigma, Self.minPosSigmaM)
        let r = floored * floored

        if let last = self.t, t <= last { return 0 }
        guard let last = self.t, t - last <= Self.gapS, var ax = x, var ay = y else {
            if self.t != nil {
                stepDistanceM += pendingStepM
            }
            pendingStepM = 0
            x = Axis(p: zx, posVar: r)
            y = Axis(p: zy, posVar: r)
            self.t = t
            return 0
        }
        pendingStepM = 0
        let dt = t - last
        self.t = t
        ax.predict(dt)
        ay.predict(dt)
        ax.updatePos(zx, r)
        ay.updatePos(zy, r)

        var doppler: Double?
        if let speed = speedMps, speed.isFinite, speed >= 0, speed <= maxSpeedMps {
            var sa = Self.defaultSpeedSigmaMps
            if let reported = speedAccuracyMps, reported.isFinite, reported > 0 { sa = reported }
            if sa <= Self.maxSpeedSigmaMps {
                doppler = speed
                if Self.valid(bearingDeg), let bearing = bearingDeg, speed >= Self.stationarySpeedMps {
                    let flooredSa = max(sa, Self.minSpeedSigmaMps)
                    let rv = flooredSa * flooredSa
                    let b = bearing * Self.degToRad
                    ax.updateVel(speed * sin(b), rv)
                    ay.updateVel(speed * cos(b), rv)
                }
            }
        }
        x = ax
        y = ay

        let speed: Double
        let stationaryFloor: Double
        if let doppler {
            speed = doppler
            stationaryFloor = Self.stationarySpeedMps
        } else {
            speed = hypot(ax.v, ay.v)
            stationaryFloor = Self.posOnlyStationarySpeedMps
        }
        if speed < stationaryFloor { return 0 }
        let inc = min(speed, maxSpeedMps) * dt
        gpsDistanceM += inc
        winM += inc
        return inc
    }

    /// Cumulative pedometer count. Learns a stride while GPS is good and
    /// buffers steps x stride while it is not; the buffer is committed only
    /// when the gap turns out to exceed `gapS`.
    func addSteps(t: Double, cumulativeSteps: Int) {
        guard t.isFinite else { return }
        let prev = lastSteps
        let prevT = lastStepT
        lastSteps = cumulativeSteps
        lastStepT = t
        guard let prev, let prevT, cumulativeSteps >= prev, t > prevT else { return }
        let d = cumulativeSteps - prev
        if let fixT = self.t, t - fixT <= Self.freshFixS {
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

    /// End of run: commit buffered steps if the trailing gap exceeds `gapS`.
    func finish(t: Double) {
        if let fixT = self.t, t.isFinite, t - fixT > Self.gapS {
            stepDistanceM += pendingStepM
        }
        pendingStepM = 0
    }
}
