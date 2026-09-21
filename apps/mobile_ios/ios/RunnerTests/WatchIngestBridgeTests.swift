import XCTest

@testable import Runner

/// Pure-host tests for the two seams of `WatchIngestBridge` that can run
/// without a live `WCSession`: the phone -> watch route payload check, the
/// watch -> phone ingest payload builder, and the in-memory buffer that holds
/// runs arriving before the Flutter engine exists. `WCSession` itself, and
/// `WCSessionFile`, cannot be constructed in a test, so these are the testable
/// seams — same convention as the Kotlin bridge tests on the Android twin.
final class WatchIngestBridgeTests: XCTestCase {

    private func routeArgs(
        points: Int,
        id: String = "route-1",
        name: String = "Canal loop",
        distance: Any = NSNumber(value: 5012.5)
    ) -> [String: Any] {
        [
            "route_id": id,
            "route_name": name,
            "route_distance_m": distance,
            "route_lat": (0..<points).map { 51.5 + Double($0) * 1e-5 },
            "route_lng": (0..<points).map { -0.12 + Double($0) * 1e-5 },
        ]
    }

    // MARK: - Route push cap

    func testMaxRoutePointsMatchesTheDartAndWatchConstants() {
        // Matched only by identical literals in `kMaxAppleWatchRoutePoints`
        // (apple_watch_route_bridge.dart) and `ArmedRoute.maxPoints`
        // (watch_ios). Drift means the phone queues a durable transfer the
        // watch drops whole, and the runner is told the push succeeded.
        XCTAssertEqual(WatchIngestBridge.maxRoutePoints, 512)
    }

    func testAcceptsAPayloadAtTheCap() {
        XCTAssertNotNil(WatchIngestBridge.routeUserInfo(from: routeArgs(points: 512)))
    }

    func testAcceptsAPayloadJustUnderTheCap() {
        XCTAssertNotNil(WatchIngestBridge.routeUserInfo(from: routeArgs(points: 511)))
    }

    func testRejectsAPayloadOnePointOverTheCap() {
        XCTAssertNil(WatchIngestBridge.routeUserInfo(from: routeArgs(points: 513)))
    }

    func testRejectsARouteWithNoLineToFollow() {
        XCTAssertNil(WatchIngestBridge.routeUserInfo(from: routeArgs(points: 0)))
        XCTAssertNil(WatchIngestBridge.routeUserInfo(from: routeArgs(points: 1)))
    }

    func testAcceptsTheShortestUsableRoute() {
        XCTAssertNotNil(WatchIngestBridge.routeUserInfo(from: routeArgs(points: 2)))
    }

    // MARK: - Route push argument decoding

    func testRejectsMismatchedCoordinateCounts() {
        var args = routeArgs(points: 10)
        args["route_lng"] = (0..<9).map { -0.12 + Double($0) * 1e-5 }
        XCTAssertNil(WatchIngestBridge.routeUserInfo(from: args))
    }

    func testRejectsAMissingOrEmptyRouteId() {
        var args = routeArgs(points: 4)
        args.removeValue(forKey: "route_id")
        XCTAssertNil(WatchIngestBridge.routeUserInfo(from: args))
        XCTAssertNil(WatchIngestBridge.routeUserInfo(from: routeArgs(points: 4, id: "")))
    }

    func testRejectsAMissingRouteName() {
        var args = routeArgs(points: 4)
        args.removeValue(forKey: "route_name")
        XCTAssertNil(WatchIngestBridge.routeUserInfo(from: args))
    }

    func testAcceptsAnEmptyRouteName() {
        // An unnamed saved route is still a route worth following.
        XCTAssertNotNil(WatchIngestBridge.routeUserInfo(from: routeArgs(points: 4, name: "")))
    }

    func testRejectsADistanceThatIsNotAFiniteNonNegativeNumber() {
        for bad in [Double.nan, .infinity, -.infinity, -1] {
            XCTAssertNil(
                WatchIngestBridge.routeUserInfo(
                    from: routeArgs(points: 4, distance: NSNumber(value: bad))
                ),
                "expected \(bad) to be rejected"
            )
        }
        var args = routeArgs(points: 4)
        args.removeValue(forKey: "route_distance_m")
        XCTAssertNil(WatchIngestBridge.routeUserInfo(from: args))
        args["route_distance_m"] = "5012.5"
        XCTAssertNil(WatchIngestBridge.routeUserInfo(from: args))
    }

    func testAcceptsAZeroDistance() {
        XCTAssertNotNil(
            WatchIngestBridge.routeUserInfo(
                from: routeArgs(points: 4, distance: NSNumber(value: 0))
            )
        )
    }

    func testRejectsCoordinatesThatAreNotNumberArrays() {
        var args = routeArgs(points: 4)
        args["route_lat"] = "51.5,51.6"
        XCTAssertNil(WatchIngestBridge.routeUserInfo(from: args))

        args = routeArgs(points: 4)
        args.removeValue(forKey: "route_lng")
        XCTAssertNil(WatchIngestBridge.routeUserInfo(from: args))

        args = routeArgs(points: 4)
        args["route_lng"] = ["a", "b", "c", "d"]
        XCTAssertNil(WatchIngestBridge.routeUserInfo(from: args))
    }

    func testPayloadCarriesTheFiveWireKeysAndNothingElse() throws {
        var args = routeArgs(points: 3)
        args["route_colour"] = "teal"
        let payload = try XCTUnwrap(WatchIngestBridge.routeUserInfo(from: args))
        XCTAssertEqual(
            Set(payload.keys),
            ["route_id", "route_name", "route_distance_m", "route_lat", "route_lng"]
        )
    }

    func testPayloadPreservesCoordinateOrder() throws {
        let latitudes = [51.5, 51.6, 51.7]
        let longitudes = [-0.12, -0.13, -0.14]
        let payload = try XCTUnwrap(
            WatchIngestBridge.routeUserInfo(from: [
                "route_id": "route-1",
                "route_name": "Canal loop",
                "route_distance_m": NSNumber(value: 1200.0),
                "route_lat": latitudes,
                "route_lng": longitudes,
            ])
        )
        XCTAssertEqual(payload["route_lat"] as? [Double], latitudes)
        XCTAssertEqual(payload["route_lng"] as? [Double], longitudes)
    }

    // MARK: - Ingest payload

    private var fullMetadata: [String: Any] {
        [
            "id": "run-7",
            "started_at": "2026-09-20T06:30:00Z",
            "source": "apple_watch",
            "activity_type": "run",
            "last_modified_at": "2026-09-20T07:35:00Z",
            "duration_s": NSNumber(value: 3_902),
            "distance_m": NSNumber(value: 12_040.5),
            "avg_bpm": NSNumber(value: 148),
            "hr_coverage": NSNumber(value: 0.93),
        ]
    }

    func testIngestPayloadForwardsEveryKnownKeyPlusTheTrack() {
        let payload = WatchIngestBridge.ingestPayload(metadata: fullMetadata, track: "[]")
        XCTAssertEqual(Set(payload.keys), Set(fullMetadata.keys).union(["track"]))
        XCTAssertEqual(payload["id"] as? String, "run-7")
        XCTAssertEqual(payload["source"] as? String, "apple_watch")
        XCTAssertEqual(payload["avg_bpm"] as? Int, 148)
    }

    func testIngestPayloadDropsMetadataTheDartSideDoesNotRead() {
        var metadata = fullMetadata
        metadata["device_name"] = "Apple Watch Ultra"
        metadata["schema"] = NSNumber(value: 2)
        let payload = WatchIngestBridge.ingestPayload(metadata: metadata, track: "[]")
        XCTAssertNil(payload["device_name"])
        XCTAssertNil(payload["schema"])
    }

    func testIngestPayloadOmitsRatherThanNullsAbsentKeys() {
        // An absent optional must stay absent: a key present with NSNull would
        // cross the channel as a Dart null and overwrite a real value.
        let payload = WatchIngestBridge.ingestPayload(
            metadata: ["id": "run-7", "started_at": "2026-09-20T06:30:00Z"],
            track: "[]"
        )
        XCTAssertEqual(Set(payload.keys), ["id", "started_at", "track"])
    }

    func testIngestPayloadKeepsTheTrackVerbatim() {
        let track = #"[{"lat":51.5,"lng":-0.12,"t":0}]"#
        let payload = WatchIngestBridge.ingestPayload(metadata: fullMetadata, track: track)
        XCTAssertEqual(payload["track"] as? String, track)
    }

    // MARK: - Pending buffer

    private final class RecordingBridge: WatchIngestBridge {
        var dispatched: [[String: Any]] = []
        var requeue: [String] = []

        override func dispatch(_ payload: [String: Any]) {
            dispatched.append(payload)
            if let id = payload["id"] as? String, requeue.contains(id) {
                pending.append(payload)
            }
        }
    }

    private func payload(_ id: String) -> [String: Any] {
        ["id": id, "track": "[]"]
    }

    func testFlushDispatchesInArrivalOrder() {
        let bridge = RecordingBridge()
        bridge.pending = [payload("a"), payload("b"), payload("c")]
        bridge.flushPending()
        XCTAssertEqual(bridge.dispatched.compactMap { $0["id"] as? String }, ["a", "b", "c"])
        XCTAssertTrue(bridge.pending.isEmpty)
    }

    func testFlushClearsTheBufferBeforeDispatchingSoARequeueSurvives() {
        // `dispatch` re-queues a run Dart could not write. Clearing the buffer
        // after the loop instead of before it would throw that run away.
        let bridge = RecordingBridge()
        bridge.requeue = ["b"]
        bridge.pending = [payload("a"), payload("b")]
        bridge.flushPending()
        XCTAssertEqual(bridge.pending.compactMap { $0["id"] as? String }, ["b"])
    }

    func testFlushOnAnEmptyBufferDispatchesNothing() {
        let bridge = RecordingBridge()
        bridge.flushPending()
        XCTAssertTrue(bridge.dispatched.isEmpty)
    }
}
