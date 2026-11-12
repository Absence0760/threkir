import Foundation
import CoreLocation

/// A route the paired iPhone pushed for this watch to follow, and the
/// UserDefaults slot it survives in.
///
/// The phone sends it over `WCSession.transferUserInfo(_:)` — queued and
/// durable rather than immediate, because the runner picks a route on the
/// phone long before the watch app is on screen (see
/// `WatchConnectivityManager.session(_:didReceiveUserInfo:)`). A delivery
/// can therefore land while the app is backgrounded or freshly woken, so the
/// route is written to disk on arrival and read back at `WorkoutManager.start()`
/// rather than held only in memory.
///
/// The wire shape is five flat plist values — `route_id`, `route_name`,
/// `route_distance_m`, and two parallel `[Double]` coordinate arrays. Flat
/// arrays rather than an array of dictionaries: a per-point dictionary costs
/// more in the plist than the two doubles it carries, and this frame rides a
/// transport with a hard payload ceiling.
struct ArmedRoute: Codable, Equatable {
    let id: String
    let name: String
    let distanceMetres: Double
    let latitudes: [Double]
    let longitudes: [Double]

    /// Positions a `WCSession` push may carry. The phone thins a denser route
    /// to this budget before sending (`appleWatchRouteFromWaypoints` in
    /// `apple_watch_route_bridge.dart`); anything over it is a payload this
    /// side never agreed to and is dropped whole. 512 keeps the frame around
    /// 8 KB of coordinate data — far inside the transport's ceiling — while
    /// leaving the per-fix projection in `RouteGeometry.project` (linear in
    /// the point count, run at ~1 Hz) inconsequential on a watch CPU.
    static let maxPoints = 512

    var coordinates: [CLLocationCoordinate2D] {
        zip(latitudes, longitudes).map { lat, lng in
            CLLocationCoordinate2D(latitude: lat, longitude: lng)
        }
    }

    var locations: [CLLocation] {
        zip(latitudes, longitudes).map { lat, lng in
            CLLocation(latitude: lat, longitude: lng)
        }
    }

    /// Read a route out of a `WCSession` payload, or nil when the payload
    /// carries no route or one this watch will not follow.
    ///
    /// Every rejection drops the whole push. A truncated or partly-decoded
    /// polyline is worse than none: the runner would be measured off-route
    /// against a line the route does not have, and told they had arrived while
    /// the real course kept going.
    static func decode(_ payload: [String: Any]) -> ArmedRoute? {
        guard let id = payload["route_id"] as? String, !id.isEmpty,
              let name = payload["route_name"] as? String,
              let distance = payload["route_distance_m"] as? Double,
              distance.isFinite, distance >= 0,
              let latitudes = payload["route_lat"] as? [Double],
              let longitudes = payload["route_lng"] as? [Double],
              latitudes.count == longitudes.count,
              latitudes.count >= 2, latitudes.count <= maxPoints
        else { return nil }

        for (lat, lng) in zip(latitudes, longitudes) {
            guard lat.isFinite, lng.isFinite,
                  lat >= -90, lat <= 90, lng >= -180, lng <= 180
            else { return nil }
        }

        return ArmedRoute(
            id: id,
            name: name,
            distanceMetres: distance,
            latitudes: latitudes,
            longitudes: longitudes
        )
    }
}

/// The armed route's home between a phone push and the run that follows it.
enum ArmedRouteStore {
    private static let key = "armed_route_v1"

    static func load(defaults: UserDefaults = .standard) -> ArmedRoute? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(ArmedRoute.self, from: data)
    }

    static func save(_ route: ArmedRoute, defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(route) else { return }
        defaults.set(data, forKey: key)
    }

    static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
    }
}

/// The starred routes the paired iPhone pushed for the wrist's route picker.
///
/// Same session and same envelope as the single armed route above, under a
/// different key: `saved_routes` carries an array of exactly the dictionaries
/// a single push carries, so arming one from the wrist is an
/// `ArmedRouteStore.save` of an already-validated `ArmedRoute` rather than a
/// second decode path with a second set of rules.
///
/// Why the list rides the phone rather than the watch querying Supabase for
/// `is_starred=eq.true`, which is how Wear OS's picker fills: the watch is not
/// where the Supabase surface grows (`apps/watch_ios/CLAUDE.md`), and a list
/// delivered over `WCSession.transferUserInfo(_:)` is already on the wrist
/// when the runner reaches a trailhead with the phone in the car and no
/// signal at all.
enum SavedRoutes {
    /// Routes one push may offer, and the cap the phone's push must apply
    /// too. It bounds the UserDefaults slot the list is cached in and the
    /// list a runner thumbs through on a 1.9-inch screen, and together with
    /// `maxPointsPerRoute` keeps the worst-case payload near 29 KB against
    /// `WCSession`'s 65,536-byte user-info ceiling: 12 routes of 128
    /// positions, two 8-byte plist doubles each, plus a small per-route
    /// header.
    static let maxRoutes = 12

    /// Positions one route in the LIST may carry — a quarter of the 512 a
    /// single armed push may, because twelve of them ride in one payload.
    /// The phone thins to this budget with the same priority
    /// Douglas-Peucker pass it already uses for the single push, so a thinned
    /// route keeps its shape and both its endpoints. At 128 positions a 10 km
    /// route holds a vertex every ~78 m, which leaves the 40 m off-route
    /// threshold alone: `RouteNavigator` measures perpendicular to a segment,
    /// not to the nearest vertex.
    static let maxPointsPerRoute = 128

    /// Read the picker's list out of a `WCSession` payload.
    ///
    /// Nil when the payload carries no list at all, which leaves whatever the
    /// watch already cached alone — every other key on this envelope arrives
    /// without one. An EMPTY array is a value rather than an absence: it is
    /// what lands when the runner unstars their last route, and it must empty
    /// the picker.
    ///
    /// A single element that fails `ArmedRoute.decode`, or that overruns
    /// `maxPointsPerRoute`, is dropped and the rest of the list stands. That
    /// is deliberately weaker than the single push's drop-the-whole-thing
    /// rule, whose reason does not reach here: there a rejection would leave
    /// a PARTLY decoded polyline, measuring the runner against a line their
    /// route does not have. Here each element is whole or absent on its own,
    /// and one the watch could not follow is one it must not offer — arming
    /// it would fail at the start of the run instead.
    static func decodeList(_ payload: [String: Any]) -> [ArmedRoute]? {
        guard let raw = payload["saved_routes"] as? [[String: Any]] else { return nil }

        var routes: [ArmedRoute] = []
        routes.reserveCapacity(min(raw.count, maxRoutes))
        for element in raw {
            guard let route = ArmedRoute.decode(element),
                  route.latitudes.count <= maxPointsPerRoute
            else { continue }
            routes.append(route)
            if routes.count == maxRoutes { break }
        }
        return routes
    }
}

/// The picker's list between phone pushes, so a watch waking with no phone in
/// range still has one to offer.
enum SavedRoutesStore {
    private static let key = "saved_routes_v1"

    /// An unreadable cache is an empty picker, never a crash: the list is an
    /// auxiliary surface and the runner can still start an unguided run.
    static func load(defaults: UserDefaults = .standard) -> [ArmedRoute] {
        guard let data = defaults.data(forKey: key),
              let routes = try? JSONDecoder().decode([ArmedRoute].self, from: data)
        else { return [] }
        return routes
    }

    static func save(_ routes: [ArmedRoute], defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(routes) else { return }
        defaults.set(data, forKey: key)
    }
}
