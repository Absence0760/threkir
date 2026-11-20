import Foundation

/// Timing-line ("gate") crossing detection, spec `gate_crossing v1` (issue
/// #1304, decisions § 2377). A one-way Swift port of the phone's
/// `apps/mobile_android/lib/gate_crossing.dart`, held to the same case table,
/// `fixtures/gate_crossing_cases.json` (`GateCrossingTests`). The park course
/// box timer (`CourseBoxTiming.swift`) is what reads it on this wrist.
///
/// Pure Foundation: no clock, no CoreLocation, no I/O.
enum GateConstants {
    static let earthRadiusM = 6371008.8
    static let maxGapS = 10.0
    static let maxHopM = 50.0
    static let rejectGapS = 60.0
    static let halfWidthRaceM = 15.0
    static let halfWidthSegmentM = 15.0
}

/// A line through (`lat`, `lng`), perpendicular to the direction of travel
/// `bearingDeg` (clockwise from north), reaching `halfWidthM` either side.
struct Gate: Codable, Equatable {
    let lat: Double
    let lng: Double
    let bearingDeg: Double
    let halfWidthM: Double

    /// Whether the line can report crossings at all; an unusable one reports
    /// none.
    var isUsable: Bool {
        lat.isFinite && lng.isFinite && bearingDeg.isFinite && halfWidthM.isFinite
            && halfWidthM >= 0 && abs(lat) < 90 && abs(lng) <= 180
    }
}

/// One distinct, trusted fix, timed at its own fix instant (`tMs`, epoch
/// milliseconds), with the distance the recording had covered by then.
struct GateFix: Equatable {
    let lat: Double
    let lng: Double
    let tMs: Double
    let coveredM: Double
}

enum GateDirection: String, Equatable {
    case forward
    case backward
}

struct GateCrossing: Equatable {
    let direction: GateDirection
    /// Where between the two fixes the line was crossed, 0...1.
    let fraction: Double
    let tMs: Double
    let coveredM: Double
    /// Lateral offset from the centre, positive to the right of travel.
    let offsetM: Double
    /// The pair was more than `maxGapS` apart or hopped more than `maxHopM`.
    let gapped: Bool
}

struct GateCrossingOptions: Equatable {
    var maxGapS = GateConstants.maxGapS
    var maxHopM = GateConstants.maxHopM
    var rejectGapS = GateConstants.rejectGapS
}

/// `s`: signed distance past the line along travel. `u`: lateral offset.
struct GateProjection: Equatable {
    let s: Double
    let u: Double
}

enum GateMath {
    static func rad(_ deg: Double) -> Double { deg * .pi / 180 }
    static func deg(_ r: Double) -> Double { r * 180 / .pi }

    static func wrapLng(_ d: Double) -> Double {
        if d >= 180 { return d - 360 }
        if d < -180 { return d + 360 }
        return d
    }

    /// Dart's `%` on doubles: the remainder carried non-negative. The phone's
    /// bearing arithmetic is written in it, and a port that rounded
    /// differently at 360 would face a line a hair the other way.
    static func dartMod(_ a: Double, _ b: Double) -> Double {
        let r = a.truncatingRemainder(dividingBy: b)
        return r < 0 ? r + abs(b) : r
    }

    /// The phone's `haversineMetres` (`run_stats.dart`), the distance the
    /// matcher's covered-distance index is built from: R = 6,371,000 m and the
    /// arc clamped, exactly as there.
    static func haversineMetres(_ lat1: Double, _ lng1: Double, _ lat2: Double, _ lng2: Double) -> Double {
        let r = 6371000.0
        let dLat = (lat2 - lat1) * .pi / 180
        let dLng = (lng2 - lng1) * .pi / 180
        let sinLat = sin(dLat / 2)
        let sinLng = sin(dLng / 2)
        let a = sinLat * sinLat + cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180) * sinLng * sinLng
        let clamped = a > 1 ? 1.0 : (a < 0 ? 0.0 : a)
        return r * 2 * asin(clamped.squareRoot())
    }
}

/// (`lat`, `lng`) on the tangent plane at the gate centre, on the gate's axes.
func gateProjection(_ gate: Gate, _ lat: Double, _ lng: Double) -> GateProjection {
    let x = GateMath.rad(GateMath.wrapLng(lng - gate.lng)) * GateConstants.earthRadiusM
        * cos(GateMath.rad(gate.lat))
    let y = GateMath.rad(lat - gate.lat) * GateConstants.earthRadiusM
    let sinB = sin(GateMath.rad(gate.bearingDeg))
    let cosB = cos(GateMath.rad(gate.bearingDeg))
    return GateProjection(s: x * sinB + y * cosB, u: x * cosB - y * sinB)
}

/// Streaming form: `offer` each fix as it arrives; the call that completes a
/// crossing returns it. `settle` ends the stream and returns every crossing.
final class GateCrossingDetector {
    let gate: Gate
    let options: GateCrossingOptions
    private let usable: Bool
    private var prev: (fix: GateFix, s: Double, u: Double)?
    private var found: [GateCrossing] = []
    private var settled = false

    init(_ gate: Gate, options: GateCrossingOptions = GateCrossingOptions()) {
        self.gate = gate
        self.options = options
        self.usable = gate.isUsable
    }

    var crossings: [GateCrossing] { found }

    func offer(_ fix: GateFix) -> GateCrossing? {
        if settled || !usable { return nil }
        guard fix.lat.isFinite, fix.lng.isFinite, fix.tMs.isFinite, fix.coveredM.isFinite
        else { return nil }
        let before = prev
        if let before, fix.tMs <= before.fix.tMs { return nil }

        let p = gateProjection(gate, fix.lat, fix.lng)
        let cur = (fix: fix, s: p.s, u: p.u)
        prev = cur
        guard let before else { return nil }

        let crossing = cross(before, cur)
        if let crossing { found.append(crossing) }
        return crossing
    }

    func settle() -> [GateCrossing] {
        settled = true
        return found
    }

    private func cross(
        _ a: (fix: GateFix, s: Double, u: Double),
        _ b: (fix: GateFix, s: Double, u: Double)
    ) -> GateCrossing? {
        let direction: GateDirection
        if a.s < 0 && b.s >= 0 {
            direction = .forward
        } else if a.s >= 0 && b.s < 0 {
            direction = .backward
        } else {
            return nil
        }

        let dtS = (b.fix.tMs - a.fix.tMs) / 1000
        if dtS > options.rejectGapS { return nil }

        let f = -a.s / (b.s - a.s)
        let offsetM = a.u + f * (b.u - a.u)
        if abs(offsetM) > gate.halfWidthM { return nil }

        let ds = b.s - a.s
        let du = b.u - a.u
        let hopM = (ds * ds + du * du).squareRoot()
        return GateCrossing(
            direction: direction,
            fraction: f,
            tMs: a.fix.tMs + f * (b.fix.tMs - a.fix.tMs),
            coveredM: a.fix.coveredM + f * (b.fix.coveredM - a.fix.coveredM),
            offsetM: offsetM,
            gapped: dtS > options.maxGapS || hopM > options.maxHopM
        )
    }
}

/// Batch form: every crossing of `track` through `gate`, in order.
func crossingsOf(
    _ track: [GateFix], _ gate: Gate, options: GateCrossingOptions = GateCrossingOptions()
) -> [GateCrossing] {
    let detector = GateCrossingDetector(gate, options: options)
    for fix in track { _ = detector.offer(fix) }
    return detector.settle()
}
