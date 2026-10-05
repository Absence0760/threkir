import Foundation
import CoreLocation
import WatchKit

/// One position's projection onto the route polyline. Swift port of the
/// web `route_geometry.ts` `progressAlongRoute` matcher (also ported by
/// Wear's `RouteMath.kt` and the phone recorder): the nearest perpendicular
/// foot per segment in a local planar frame, along-distance accumulated over
/// haversine segment lengths, and — given the previous match — a search
/// windowed around where the runner can plausibly be, so a loop's start is
/// not its finish and an out-and-back's return leg is not its outbound one.
struct RouteProjection: Equatable {
    let deviationMetres: Double
    let alongRouteMetres: Double
    let remainingMetres: Double
}

enum RouteGeometry {
    private static let earthRadiusMetres = 6_371_000.0
    private static let degToRad = Double.pi / 180.0
    private static let metresPerDegree = earthRadiusMetres * degToRad

    // Matcher tuning — the values web `route_geometry.ts` uses.
    private static let lookaheadMetres = 200.0
    private static let backtrackMetres = 50.0
    /// The off-route alert threshold: a windowed match further off the line
    /// than this sends the matcher looking further along the route.
    private static let reacquireMetres = OffRouteLatch.thresholdMetres
    private static let forwardBiasPerMetre = 0.05
    private static let backwardBiasPerMetre = 0.5
    private static let maxBiasMetres = 20.0
    private static let continuityPerMetre = 1e-6

    static func totalLengthMetres(_ points: [CLLocationCoordinate2D]) -> Double {
        var total = 0.0
        for i in 1..<max(points.count, 1) {
            total += haversineMetres(points[i - 1], points[i])
        }
        return total
    }

    /// Nil when there is no line to project onto (< 2 points, a
    /// non-finite fix, or any non-finite route vertex) — never a bogus
    /// zero, matching `progressAlongRoute`'s null contract.
    ///
    /// Only the stretch from `backtrackMetres` behind `previousAlongMetres`
    /// to `lookaheadMetres` past `previousAlongMetres + travelledMetres` is
    /// searched (the start of the route when there is no previous match), and
    /// within it a tie between overlapping legs goes to forward progress, with
    /// a bias capped at `maxBiasMetres` so it never outweighs real distance off
    /// the line. When nothing in that window is within `reacquireMetres`, or
    /// the runner projects past its far end, the rest of the route ahead is
    /// searched, so a runner who skips ahead or
    /// returns after a signal gap is re-acquired; a runner still off the line
    /// keeps the windowed match, unless there is no previous match to keep.
    ///
    /// `deviationMetres` is the distance to the nearest point on the WHOLE
    /// line: a runner standing on the route is not off it, whichever lap or
    /// leg the matcher has them on.
    static func project(
        _ position: CLLocationCoordinate2D,
        onto points: [CLLocationCoordinate2D],
        totalLengthMetres total: Double,
        previousAlongMetres: Double? = nil,
        travelledMetres: Double = 0
    ) -> RouteProjection? {
        guard points.count >= 2 else { return nil }
        guard position.latitude.isFinite, position.longitude.isFinite else { return nil }

        let n = points.count - 1
        var segStart = [Double](repeating: 0, count: n)
        var segLen = [Double](repeating: 0, count: n)
        var tFree = [Double](repeating: 0, count: n)
        var seen = 0.0
        var bestPerp = Double.infinity
        for i in 0..<n {
            let a = points[i]
            let b = points[i + 1]
            guard a.latitude.isFinite, a.longitude.isFinite,
                  b.latitude.isFinite, b.longitude.isFinite else { return nil }
            segStart[i] = seen
            segLen[i] = haversineMetres(a, b)
            seen += segLen[i]
            let projected = frame(position, a, b, t: nil)
            tFree[i] = projected.t
            bestPerp = min(bestPerp, projected.perp)
        }
        guard bestPerp.isFinite, seen.isFinite else { return nil }

        let hasPrevious = previousAlongMetres?.isFinite ?? false
        let previous = hasPrevious ? min(seen, max(0, previousAlongMetres!)) : 0
        let travelled = travelledMetres.isFinite && travelledMetres > 0 ? travelledMetres : 0
        let anchor = min(seen, previous + travelled)
        let lo = hasPrevious ? max(0, previous - backtrackMetres) : 0

        // `pastEnd` marks a match pinned to `toM` while the runner projects
        // beyond it.
        func best(
            from fromM: Double, to toM: Double
        ) -> (along: Double, perp: Double, pastEnd: Bool)? {
            var found: (along: Double, perp: Double, pastEnd: Bool)?
            var bestCost = Double.infinity
            for i in 0..<n {
                let s = segStart[i]
                let len = segLen[i]
                if s > toM || s + len < fromM { continue }
                let tLo = len > 0 ? max(0, (fromM - s) / len) : 0
                let tHi = len > 0 ? min(1, (toM - s) / len) : 0
                let t = min(tHi, max(tLo, tFree[i]))
                let perp = frame(position, points[i], points[i + 1], t: t).perp
                let along = s + t * len
                let gap = along - anchor
                let bias = min(
                    maxBiasMetres,
                    gap >= 0 ? gap * forwardBiasPerMetre : -gap * backwardBiasPerMetre
                )
                let cost = perp + bias + abs(gap) * continuityPerMetre
                if cost < bestCost {
                    bestCost = cost
                    found = (along, perp, tFree[i] > t)
                }
            }
            return found
        }

        var match = best(from: lo, to: anchor + lookaheadMetres)
        if match == nil || match!.perp > reacquireMetres || match!.pastEnd {
            if let ahead = best(from: lo, to: seen),
               match == nil
                || (ahead.perp < match!.perp
                    && (!hasPrevious || ahead.perp <= reacquireMetres)) {
                match = ahead
            }
        }
        guard let match else { return nil }
        let along = min(seen, max(0, match.along))
        return RouteProjection(
            deviationMetres: bestPerp,
            alongRouteMetres: along,
            remainingMetres: max(0, total - along)
        )
    }

    /// Project `p` onto segment a→b in a local planar frame anchored at `a`.
    /// Returns the free (clamped) projection parameter and the perpendicular
    /// distance at `t` — or at the free parameter when `t` is nil.
    private static func frame(
        _ p: CLLocationCoordinate2D,
        _ a: CLLocationCoordinate2D,
        _ b: CLLocationCoordinate2D,
        t: Double?
    ) -> (t: Double, perp: Double) {
        let cosLat = cos(a.latitude * degToRad)
        let bx = (b.longitude - a.longitude) * cosLat * metresPerDegree
        let by = (b.latitude - a.latitude) * metresPerDegree
        let px = (p.longitude - a.longitude) * cosLat * metresPerDegree
        let py = (p.latitude - a.latitude) * metresPerDegree
        let lenSq = bx * bx + by * by
        let tFree = lenSq <= 0 ? 0 : min(1, max(0, (px * bx + py * by) / lenSq))
        let tt = t ?? tFree
        let dx = px - bx * tt
        let dy = py - by * tt
        return (tFree, (dx * dx + dy * dy).squareRoot())
    }

    private static func haversineMetres(
        _ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D
    ) -> Double {
        let dLat = (b.latitude - a.latitude) * degToRad
        let dLng = (b.longitude - a.longitude) * degToRad
        let h = sin(dLat / 2) * sin(dLat / 2)
            + cos(a.latitude * degToRad) * cos(b.latitude * degToRad)
                * sin(dLng / 2) * sin(dLng / 2)
        return earthRadiusMetres * 2 * asin(min(1, h.squareRoot()))
    }
}

/// The cross-platform off-route hysteresis: alert past 40 m, re-arm only
/// once back within 20 m, so hovering at the boundary can't flap the
/// alert on GPS jitter. Same constants + edges as the mobile run
/// screen's `_offRouteThresholdMetres` block, Wear's banner, and the
/// custom watch's `OffCourseAlert`.
struct OffRouteLatch {
    static let thresholdMetres = 40.0
    static let rearmMetres = thresholdMetres / 2

    private(set) var isOffRoute = false

    /// Feed the latest deviation; true exactly on the off-route rising edge.
    mutating func update(deviationMetres: Double) -> Bool {
        if deviationMetres > Self.thresholdMetres {
            if !isOffRoute {
                isOffRoute = true
                return true
            }
        } else if deviationMetres < Self.rearmMetres {
            isOffRoute = false
        }
        return false
    }
}

/// Detects off-route deviation and provides distance-remaining feedback.
class RouteNavigator: ObservableObject {
    @Published var isOffRoute = false
    @Published var deviationMetres: Double?
    @Published var remainingMetres: Double?

    private let coordinates: [CLLocationCoordinate2D]
    private let totalLengthMetres: Double
    private var latch = OffRouteLatch()
    /// The last match and the fix it was made from: the next fix is searched
    /// for around it, so progress follows the runner rather than snapping to
    /// whichever pass of the line happens to be nearest.
    private var matchedAlongMetres: Double?
    private var matchedFrom: CLLocation?

    /// Auxiliary effect seam: fired once per off-route transition, after
    /// every published value is already set, so nothing it does can
    /// disturb the core update (layered-resilience contract).
    var playOffRouteHaptic: () -> Void = {
        WKInterfaceDevice.current().play(.notification)
    }

    init(routePoints: [CLLocation]) {
        coordinates = routePoints.map(\.coordinate)
        totalLengthMetres = RouteGeometry.totalLengthMetres(coordinates)
    }

    func update(currentLocation: CLLocation) {
        let travelled = matchedFrom.map { currentLocation.distance(from: $0) } ?? 0
        guard let projection = RouteGeometry.project(
            currentLocation.coordinate,
            onto: coordinates,
            totalLengthMetres: totalLengthMetres,
            previousAlongMetres: matchedAlongMetres,
            travelledMetres: travelled
        ) else {
            // No line, or a non-finite fix: publish honest nils. The
            // latch is left alone so one bad fix can't clear a real
            // off-route state and re-fire the haptic on the next good one.
            deviationMetres = nil
            remainingMetres = nil
            if coordinates.count < 2 { isOffRoute = false }
            return
        }
        matchedAlongMetres = projection.alongRouteMetres
        matchedFrom = currentLocation
        deviationMetres = projection.deviationMetres
        remainingMetres = projection.remainingMetres
        let fired = latch.update(deviationMetres: projection.deviationMetres)
        isOffRoute = latch.isOffRoute
        if fired { playOffRouteHaptic() }
    }
}

// MARK: - Display shaping

/// Turns the navigator's published values into what the run screen renders.
/// Pure and unit-tested separately from the SwiftUI view.
enum RouteGuidance {
    enum Status: Equatable {
        case onRoute
        case offRoute
        /// No projection is available — a degenerate route, or a fix the
        /// geometry refused. Distinct from `onRoute` on purpose: a runner
        /// shown nothing cannot tell "you are on the line" from "the watch
        /// has lost track of the line".
        case unknown
    }

    /// A latched off-route state outranks a missing deviation, so one bad fix
    /// cannot downgrade a live alert to "unknown" and back.
    static func status(isOffRoute: Bool, deviationMetres: Double?) -> Status {
        if isOffRoute { return .offRoute }
        return deviationMetres == nil ? .unknown : .onRoute
    }

    /// Distance still to run, in the user's preferred unit. Nil when the
    /// navigator has no projection to report.
    static func remainingText(metres: Double?, locale: Locale = .current) -> String? {
        guard let metres, metres.isFinite, metres >= 0 else { return nil }
        return RunFormat.distance(metres: metres, fractionDigits: 2, locale: locale)
    }

    /// How far off the line the runner is, always in metres — a deviation
    /// rendered in miles (`0.04 mi`) tells a runner nothing they can act on,
    /// so this one readout stays metric in both unit modes, matching Wear OS.
    static func deviationText(metres: Double?) -> String? {
        guard let metres, metres.isFinite, metres >= 0 else { return nil }
        let formatter = MeasurementFormatter()
        formatter.locale = Locale.current
        formatter.unitOptions = .providedUnit
        formatter.numberFormatter.maximumFractionDigits = 0
        return formatter.string(
            from: Measurement(value: metres.rounded(), unit: UnitLength.meters)
        )
    }
}
