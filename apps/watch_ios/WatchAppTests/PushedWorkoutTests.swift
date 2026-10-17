import XCTest
@testable import WatchApp

/// The phone -> watch today's-workout payload, read off the fixture the
/// phone's encoder writes (`apps/mobile_android/test/watch_workout_push_test.dart`)
/// and Wear OS decodes too (`WorkoutPushFixtureTest.kt`). A payload the phone
/// writes must decode here to the same steps; every rejected shape must be
/// refused whole, never partly loaded.
final class PushedWorkoutTests: XCTestCase {

    static func fixture(file: StaticString = #filePath) throws -> [String: Any] {
        let url = URL(fileURLWithPath: "\(file)")
            .deletingLastPathComponent() // WatchAppTests
            .deletingLastPathComponent() // watch_ios
            .deletingLastPathComponent() // apps
            .deletingLastPathComponent() // repo root
            .appendingPathComponent("fixtures/watch_workout_payload.json")
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func text(_ object: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object)
        return try XCTUnwrap(String(data: data, encoding: .utf8))
    }

    func testEveryPayloadThePhoneWritesDecodesToItsSteps() throws {
        let cases = try XCTUnwrap(Self.fixture()["cases"] as? [[String: Any]])
        XCTAssertFalse(cases.isEmpty)
        for c in cases {
            let name = c["name"] as? String ?? "?"
            let payload = try XCTUnwrap(c["payload"] as? [String: Any])
            guard case .workout(let w) = WorkoutPush.decode(try text(payload)) else {
                return XCTFail("\(name) did not decode")
            }
            XCTAssertEqual(w.planWorkoutId, payload["plan_workout_id"] as? String, name)
            XCTAssertEqual(w.scheduledDate, payload["scheduled_date"] as? String, name)
            XCTAssertEqual(w.workoutKind, payload["workout_kind"] as? String, name)
            XCTAssertEqual(w.unpaced, payload["unpaced"] as? Bool, name)
            let want = try XCTUnwrap(payload["steps"] as? [[String: Any]])
            XCTAssertEqual(want.count, w.steps.count, name)
            for (i, s) in want.enumerated() {
                let got = w.steps[i]
                XCTAssertEqual(got.kind.rawValue, s["kind"] as? String, "\(name) \(i)")
                XCTAssertEqual(got.repIndex, s["rep_index"] as? Int, "\(name) \(i)")
                XCTAssertEqual(got.repTotal, s["rep_total"] as? Int, "\(name) \(i)")
                XCTAssertEqual(got.distanceMetres, s["distance_m"] as? Int, "\(name) \(i)")
                XCTAssertEqual(got.durationSeconds, s["duration_s"] as? Int, "\(name) \(i)")
                XCTAssertEqual(got.paceSecondsPerKm, s["pace_s_per_km"] as? Int, "\(name) \(i)")
                XCTAssertEqual(got.toleranceSecondsPerKm, s["tolerance_s_per_km"] as? Int, "\(name) \(i)")
            }
        }
    }

    func testTheNothingTodayPayloadsClearRatherThanReject() throws {
        let nones = try XCTUnwrap(Self.fixture()["none_payloads"] as? [[String: Any]])
        XCTAssertFalse(nones.isEmpty)
        for p in nones {
            XCTAssertEqual(WorkoutPush.decode(try text(p)), WorkoutPush.none, "\(p)")
        }
    }

    func testEveryRejectedShapeIsRefusedWhole() throws {
        let rejected = try XCTUnwrap(Self.fixture()["rejected_payloads"] as? [[String: Any]])
        XCTAssertFalse(rejected.isEmpty)
        for r in rejected {
            let payload = try XCTUnwrap(r["payload"])
            XCTAssertEqual(WorkoutPush.decode(try text(payload)), .rejected, r["why"] as? String ?? "?")
        }
    }

    func testTextThatIsNotAJsonObjectIsRejected() {
        for raw in [nil, "", "not json", "[1,2]", "1"] as [String?] {
            XCTAssertEqual(WorkoutPush.decode(raw), .rejected, "\(raw ?? "nil")")
        }
    }

    func testMoreStepsThanTheCapIsRejectedRatherThanTruncated() throws {
        func payload(_ n: Int) throws -> String {
            let step: [String: Any] = ["kind": "rep", "distance_m": 200, "pace_s_per_km": 240, "tolerance_s_per_km": 10]
            return try text([
                "v": 1, "plan_workout_id": "x", "scheduled_date": "2026-10-16",
                "workout_kind": "interval", "unpaced": false,
                "steps": Array(repeating: step, count: n),
            ] as [String: Any])
        }
        guard case .workout = WorkoutPush.decode(try payload(WorkoutPush.maxSteps)) else {
            return XCTFail("the cap itself must decode")
        }
        XCTAssertEqual(WorkoutPush.decode(try payload(WorkoutPush.maxSteps + 1)), .rejected)
    }

    func testOnlyAWorkoutForTodayIsOffered() throws {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let cases = try XCTUnwrap(Self.fixture()["cases"] as? [[String: Any]])
        let push = WorkoutPush.decode(try text(try XCTUnwrap(cases.first?["payload"])))
        guard case .workout(let w) = push else { return XCTFail("fixture case did not decode") }
        let day = try XCTUnwrap(utc.date(from: DateComponents(year: 2026, month: 10, day: 16, hour: 9)))
        XCTAssertEqual(w.scheduledDate, "2026-10-16")
        XCTAssertEqual(WorkoutPush.offered(push, today: day, calendar: utc), w)
        XCTAssertNil(WorkoutPush.offered(push, today: day.addingTimeInterval(86_400), calendar: utc))
        XCTAssertNil(WorkoutPush.offered(WorkoutPush.none, today: day, calendar: utc))
        XCTAssertNil(WorkoutPush.offered(.rejected, today: day, calendar: utc))
        XCTAssertNil(WorkoutPush.offered(nil, today: day, calendar: utc))
    }

    func testThePayloadVersionMatchesThePhoneWriter(file: StaticString = #filePath) throws {
        let src = URL(fileURLWithPath: "\(file)")
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("apps/mobile_android/lib/watch_workout_push.dart")
        let dart = try String(contentsOf: src, encoding: .utf8)
        XCTAssertTrue(dart.contains("const int kWatchWorkoutPayloadVersion = \(WorkoutPush.payloadVersion);"))
    }

    func testTheStoreKeepsTheTextAndDecodesItBack() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "PushedWorkoutTests"))
        defaults.removePersistentDomain(forName: "PushedWorkoutTests")
        XCTAssertNil(PushedWorkoutStore.load(defaults: defaults))
        let cases = try XCTUnwrap(Self.fixture()["cases"] as? [[String: Any]])
        let json = try text(try XCTUnwrap(cases.first?["payload"]))
        PushedWorkoutStore.save(json: json, defaults: defaults)
        XCTAssertEqual(PushedWorkoutStore.load(defaults: defaults), WorkoutPush.decode(json))
        PushedWorkoutStore.clear(defaults: defaults)
        XCTAssertNil(PushedWorkoutStore.load(defaults: defaults))
    }
}
