import XCTest
@testable import WatchApp

/// The wrist route picker's list arrives the same way the armed route does —
/// as an untyped `WCSession` plist from the phone — so these pin what the
/// watch will and will not offer a runner to arm.
///
/// The list's rule differs from the single push's on purpose: one bad element
/// is dropped and the rest of the list stands, because an element is whole or
/// absent on its own and there is no partly-decoded polyline to protect
/// against. What must never happen is a route reaching the picker that
/// `ArmedRoute.decode` would refuse — arming it would then fail at the start
/// of the run, after the runner had chosen it.
final class SavedRoutesTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suiteName = "SavedRoutesTests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    private func route(
        id: Any = "route-1",
        name: Any = "Riverside loop",
        distance: Any = 5120.0,
        points: Int = 3
    ) -> [String: Any] {
        [
            "route_id": id,
            "route_name": name,
            "route_distance_m": distance,
            "route_lat": (0..<points).map { 51.5 + Double($0) * 0.001 },
            "route_lng": (0..<points).map { -0.12 + Double($0) * 0.001 },
        ]
    }

    // MARK: - decodeList

    func testMissingKeyIsNilSoOtherPushesLeaveTheListAlone() {
        XCTAssertNil(SavedRoutes.decodeList(["preferred_unit": "mi"]))
    }

    func testWrongShapeIsNil() {
        XCTAssertNil(SavedRoutes.decodeList(["saved_routes": "riverside,park"]))
        XCTAssertNil(SavedRoutes.decodeList(["saved_routes": ["riverside"]]))
    }

    func testEmptyArrayIsAValueNotAnAbsence() {
        let decoded = SavedRoutes.decodeList(["saved_routes": [[String: Any]]()])
        XCTAssertEqual(decoded?.count, 0)
    }

    func testDecodesEveryFieldInPushOrder() {
        let decoded = SavedRoutes.decodeList([
            "saved_routes": [
                route(id: "a", name: "Riverside loop", distance: 5120.0),
                route(id: "b", name: "Hill repeats", distance: 3000.0),
            ],
        ])
        XCTAssertEqual(decoded?.map(\.id), ["a", "b"])
        XCTAssertEqual(decoded?.first?.name, "Riverside loop")
        XCTAssertEqual(decoded?.first?.distanceMetres, 5120.0)
        XCTAssertEqual(decoded?.first?.latitudes.count, 3)
        XCTAssertEqual(decoded?.last?.distanceMetres, 3000.0)
    }

    func testAMalformedElementIsDroppedAndTheRestStands() {
        var broken = route(id: "b")
        broken.removeValue(forKey: "route_name")
        let decoded = SavedRoutes.decodeList([
            "saved_routes": [route(id: "a"), broken, route(id: "c")],
        ])
        XCTAssertEqual(decoded?.map(\.id), ["a", "c"])
    }

    func testAnElementWithMismatchedCoordinateArraysIsDropped() {
        var lopsided = route(id: "b")
        lopsided["route_lng"] = [-0.12, -0.11]
        let decoded = SavedRoutes.decodeList([
            "saved_routes": [route(id: "a"), lopsided],
        ])
        XCTAssertEqual(decoded?.map(\.id), ["a"])
    }

    func testAnElementWithANonFiniteCoordinateIsDropped() {
        var broken = route(id: "b")
        broken["route_lat"] = [51.5, Double.nan, 51.52]
        let decoded = SavedRoutes.decodeList([
            "saved_routes": [route(id: "a"), broken],
        ])
        XCTAssertEqual(decoded?.map(\.id), ["a"])
    }

    func testAnElementWithNoLineToFollowIsDropped() {
        let decoded = SavedRoutes.decodeList([
            "saved_routes": [route(id: "a"), route(id: "b", points: 1)],
        ])
        XCTAssertEqual(decoded?.map(\.id), ["a"])
    }

    func testAnElementAtThePerRoutePointBudgetIsKept() {
        let decoded = SavedRoutes.decodeList([
            "saved_routes": [route(points: SavedRoutes.maxPointsPerRoute)],
        ])
        XCTAssertEqual(decoded?.first?.latitudes.count, SavedRoutes.maxPointsPerRoute)
    }

    func testAnElementOverThePerRoutePointBudgetIsDropped() {
        let decoded = SavedRoutes.decodeList([
            "saved_routes": [
                route(id: "a"),
                route(id: "b", points: SavedRoutes.maxPointsPerRoute + 1),
            ],
        ])
        XCTAssertEqual(decoded?.map(\.id), ["a"])
    }

    func testTheListIsBoundedToMaxRoutes() {
        let many = (0..<(SavedRoutes.maxRoutes + 5)).map { route(id: "r\($0)") }
        let decoded = SavedRoutes.decodeList(["saved_routes": many])
        XCTAssertEqual(decoded?.count, SavedRoutes.maxRoutes)
        XCTAssertEqual(decoded?.first?.id, "r0")
    }

    /// Twelve routes ride in one `WCSession` user-info payload where one
    /// armed route rides alone, so the list's per-route budget has to be the
    /// tighter of the two. Equal budgets would put the worst-case push over
    /// the transport's ceiling and lose the whole list.
    func testThePerRouteBudgetIsTighterThanASinglePushes() {
        XCTAssertLessThan(SavedRoutes.maxPointsPerRoute, ArmedRoute.maxPoints)
    }

    // MARK: - arming from the list

    /// The picker hands `WorkoutManager.start()` its route through
    /// `ArmedRouteStore`, not through the view, so a decoded list element has
    /// to survive that round trip whole.
    func testAPickedRouteArmsThroughTheStore() throws {
        let picked = try XCTUnwrap(
            SavedRoutes.decodeList(["saved_routes": [route(id: "a")]])?.first
        )

        ArmedRouteStore.save(picked, defaults: defaults)

        XCTAssertEqual(ArmedRouteStore.load(defaults: defaults), picked)
    }

    // MARK: - SavedRoutesStore

    func testStoreRoundTripsTheList() {
        let routes = SavedRoutes.decodeList([
            "saved_routes": [route(id: "a"), route(id: "b")],
        ]) ?? []

        SavedRoutesStore.save(routes, defaults: defaults)

        XCTAssertEqual(SavedRoutesStore.load(defaults: defaults), routes)
    }

    func testStoreIsEmptyBeforeAnyPush() {
        XCTAssertEqual(SavedRoutesStore.load(defaults: defaults), [])
    }

    /// An unreadable cache leaves the runner an empty picker and a working
    /// unguided run, never a crash on the pre-run screen.
    func testStoreReadsAnUnreadableCacheAsEmpty() {
        defaults.set(Data("not json".utf8), forKey: "saved_routes_v1")

        XCTAssertEqual(SavedRoutesStore.load(defaults: defaults), [])
    }

    func testStoreOverwritesRatherThanMerges() {
        SavedRoutesStore.save(
            SavedRoutes.decodeList(["saved_routes": [route(id: "a"), route(id: "b")]]) ?? [],
            defaults: defaults
        )
        SavedRoutesStore.save(
            SavedRoutes.decodeList(["saved_routes": [route(id: "c")]]) ?? [],
            defaults: defaults
        )

        XCTAssertEqual(SavedRoutesStore.load(defaults: defaults).map(\.id), ["c"])
    }

    /// Unstarring the last route empties the picker rather than leaving the
    /// previous list on the wrist to be armed.
    func testAnEmptyPushEmptiesTheStore() {
        SavedRoutesStore.save(
            SavedRoutes.decodeList(["saved_routes": [route(id: "a")]]) ?? [],
            defaults: defaults
        )

        SavedRoutesStore.save(
            SavedRoutes.decodeList(["saved_routes": [[String: Any]]()]) ?? [],
            defaults: defaults
        )

        XCTAssertEqual(SavedRoutesStore.load(defaults: defaults), [])
    }
}
