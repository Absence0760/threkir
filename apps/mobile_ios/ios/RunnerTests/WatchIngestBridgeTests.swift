import Flutter
import WatchConnectivity
import XCTest

@testable import Runner

/// Pure-host tests for the seams of `WatchIngestBridge` that can run without a
/// live `WCSession`: the phone -> watch route payload check, the watch -> phone
/// ingest payload builder, and the serialised in-memory buffer that holds runs
/// arriving before the Flutter engine exists or refused once it is up. `WCSession` itself, and
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
            "steps": NSNumber(value: 7_412),
            "laps": "[{\"n\":1}]",
            "is_public": true,
        ]
    }

    func testIngestPayloadForwardsEveryKnownKeyPlusTheTrack() {
        let payload = WatchIngestBridge.ingestPayload(metadata: fullMetadata, track: "[]")
        XCTAssertEqual(Set(payload.keys), Set(fullMetadata.keys).union(["track"]))
        XCTAssertEqual(payload["id"] as? String, "run-7")
        XCTAssertEqual(payload["source"] as? String, "apple_watch")
        XCTAssertEqual(payload["avg_bpm"] as? Int, 148)
        XCTAssertEqual(payload["steps"] as? Int, 7_412)
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

    func testIngestPayloadCarriesTheVisibilityTheWristStamped() {
        let payload = WatchIngestBridge.ingestPayload(metadata: fullMetadata, track: "[]")
        XCTAssertEqual(payload["is_public"] as? Bool, true)
    }

    // MARK: - Preference push

    private let requiredPrefs: [String: Any] = ["preferred_unit": "km", "audio_cues": true]

    func testPrefsContextCarriesTheThreeSettingsTheWatchApplies() throws {
        var args = requiredPrefs
        args["default_activity_type"] = "hike"
        args["privacy_default"] = "public"
        args["hr_zone_cutoffs"] = [114, 133, 152, 171, 190]
        let context = try XCTUnwrap(WatchIngestBridge.prefsContext(from: args))
        XCTAssertEqual(context["default_activity_type"] as? String, "hike")
        XCTAssertEqual(context["privacy_default"] as? String, "public")
        XCTAssertEqual(context["hr_zone_cutoffs"] as? [Int], [114, 133, 152, 171, 190])
    }

    func testPrefsContextKeepsAnEmptyLadderBecauseThatIsHowZonesAreCleared() throws {
        var args = requiredPrefs
        args["hr_zone_cutoffs"] = [Int]()
        let context = try XCTUnwrap(WatchIngestBridge.prefsContext(from: args))
        XCTAssertEqual(context["hr_zone_cutoffs"] as? [Int], [])
    }

    func testARogueOptionalIsDroppedAloneAndTheRequiredPairStillShips() throws {
        var args = requiredPrefs
        args["default_activity_type"] = "stroller"
        args["privacy_default"] = "everyone"
        args["hr_zone_cutoffs"] = [150, 140, 130, 120, 110]
        let context = try XCTUnwrap(WatchIngestBridge.prefsContext(from: args))
        XCTAssertEqual(Set(context.keys), ["preferred_unit", "audio_cues"])
    }

    func testTheZoneLadderGateMatchesTheWatchDecoder() {
        XCTAssertTrue(WatchIngestBridge.isZoneLadder([]))
        XCTAssertTrue(WatchIngestBridge.isZoneLadder([40, 100, 150, 200, 240]))
        XCTAssertFalse(WatchIngestBridge.isZoneLadder([39, 100, 150, 200, 240]))
        XCTAssertFalse(WatchIngestBridge.isZoneLadder([40, 100, 150, 200, 241]))
        XCTAssertFalse(WatchIngestBridge.isZoneLadder([100, 100, 150, 200, 240]))
        XCTAssertFalse(WatchIngestBridge.isZoneLadder([100, 150, 200, 240]))
    }

    func testIngestPayloadKeepsTheTrackVerbatim() {
        let track = #"[{"lat":51.5,"lng":-0.12,"t":0}]"#
        let payload = WatchIngestBridge.ingestPayload(metadata: fullMetadata, track: track)
        XCTAssertEqual(payload["track"] as? String, track)
    }

    // MARK: - Pending buffer

    /// Stands in for the real dispatch, which needs a live method channel.
    /// The refusal path calls `requeueRefused` exactly as production does, so
    /// the retry ceiling is exercised rather than modelled.
    private final class RecordingBridge: WatchIngestBridge {
        var dispatched: [[String: Any]] = []
        var refuse: [String] = []

        override func dispatch(_ payload: [String: Any]) {
            dispatched.append(payload)
            if let id = payload["id"] as? String, refuse.contains(id) {
                requeueRefused(payload)
            }
        }
    }

    /// A `FlutterBinaryMessenger` that answers nothing, so `attach` can build
    /// its channels without an engine.
    private final class SilentMessenger: NSObject, FlutterBinaryMessenger {
        func send(onChannel channel: String, message: Data?) {}

        func send(onChannel channel: String, message: Data?, binaryReply: FlutterBinaryReply?) {}

        func setMessageHandlerOnChannel(
            _ channel: String,
            binaryMessageHandler handler: FlutterBinaryMessageHandler?
        ) -> FlutterBinaryMessengerConnection {
            0
        }

        func cleanUpConnection(_ connection: FlutterBinaryMessengerConnection) {}
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
        bridge.refuse = ["b"]
        bridge.pending = [payload("a"), payload("b")]
        bridge.flushPending()
        XCTAssertEqual(bridge.pending.compactMap { $0["id"] as? String }, ["b"])
    }

    func testFlushOnAnEmptyBufferDispatchesNothing() {
        let bridge = RecordingBridge()
        bridge.flushPending()
        XCTAssertTrue(bridge.dispatched.isEmpty)
    }

    // MARK: - Retrying a refused run

    func testActivationCompletingRetriesTheBuffer() {
        // The whole point of the re-queue: watch contact, not an engine
        // re-attach, is what gives a refused run its next go.
        let bridge = RecordingBridge()
        bridge.pending = [payload("a")]
        bridge.session(WCSession.default, activationDidCompleteWith: .activated, error: nil)
        XCTAssertEqual(bridge.dispatched.compactMap { $0["id"] as? String }, ["a"])
    }

    func testAFailedActivationDoesNotRetry() {
        let bridge = RecordingBridge()
        bridge.pending = [payload("a")]
        bridge.session(WCSession.default, activationDidCompleteWith: .notActivated, error: nil)
        XCTAssertTrue(bridge.dispatched.isEmpty)
        XCTAssertEqual(bridge.pending.count, 1)
    }

    func testRetriesStopOnceTheRefusalCeilingIsReached() {
        let bridge = RecordingBridge()
        bridge.refuse = ["a"]
        bridge.pending = [payload("a")]
        for _ in 0..<(WatchIngestBridge.maxRefusedRetries + 10) {
            bridge.flushPending()
        }
        XCTAssertEqual(bridge.dispatched.count, WatchIngestBridge.maxRefusedRetries)
    }

    func testARunAtTheRefusalCeilingStaysBufferedRatherThanBeingDropped() {
        let bridge = RecordingBridge()
        bridge.refuse = ["a"]
        bridge.pending = [payload("a")]
        for _ in 0..<(WatchIngestBridge.maxRefusedRetries + 10) {
            bridge.flushPending()
        }
        XCTAssertEqual(bridge.pending.compactMap { $0["id"] as? String }, ["a"])
    }

    func testAttachResetsTheRefusalCeilingAndRetries() {
        let bridge = RecordingBridge()
        bridge.refuse = ["a"]
        bridge.pending = [payload("a")]
        for _ in 0..<(WatchIngestBridge.maxRefusedRetries + 10) {
            bridge.flushPending()
        }
        bridge.attach(binaryMessenger: SilentMessenger())
        XCTAssertEqual(bridge.dispatched.count, WatchIngestBridge.maxRefusedRetries + 1)
    }

    func testAFlushBeforeTheEngineIsUpReBuffersRatherThanDropping() {
        // `flushPending` now runs on watch contact, which can precede `attach`.
        // Without the channel check in `dispatch` the snapshot would be cleared
        // and the runs would go nowhere.
        let bridge = WatchIngestBridge()
        bridge.pending = [payload("a"), payload("b")]
        bridge.flushPending()
        XCTAssertTrue(bridge.pending.isEmpty)

        // FIFO on the main queue: the dispatches were enqueued first, so by the
        // time this one runs they have all re-buffered.
        let drained = expectation(description: "main queue drained")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 5)

        XCTAssertEqual(bridge.pending.compactMap { $0["id"] as? String }, ["a", "b"])
    }

    // MARK: - Buffer serialisation

    func testConcurrentRequeuesDoNotLoseARun() {
        // The buffer is written from the WCSession delegate queue, the main
        // queue and the channel reply callback. Unserialised this corrupts.
        let bridge = WatchIngestBridge()
        let runs = 400
        DispatchQueue.concurrentPerform(iterations: runs) { i in
            bridge.requeueRefused(self.payload("run-\(i)"))
        }
        XCTAssertEqual(bridge.pending.count, runs)
        XCTAssertEqual(Set(bridge.pending.compactMap { $0["id"] as? String }).count, runs)
    }
}
