import HealthKit
import XCTest
@testable import WatchApp

/// The pre-run activity picker's own behaviour: what it cycles through, what
/// it stores, and what it opens the HealthKit session with.
///
/// The vocabulary's agreement with the phone, the web and the CHECK
/// constraint is a separate concern and lives in
/// `ActivityTypeVocabularyTests`.
final class RunActivityTypeTests: XCTestCase {

    func testCyclesRunWalkHikeCycleAndWraps() {
        XCTAssertEqual(RunActivityType.run.next, .walk)
        XCTAssertEqual(RunActivityType.walk.next, .hike)
        XCTAssertEqual(RunActivityType.hike.next, .cycle)
        XCTAssertEqual(RunActivityType.cycle.next, .run, "the cycle wraps")
        XCTAssertEqual(RunActivityType.allCases, [.run, .walk, .hike, .cycle])
    }

    /// The token is what `runs.activity_type` stores, so it is not free to
    /// follow a Swift rename.
    func testRawValuesAreTheStoredTokens() {
        XCTAssertEqual(RunActivityType.run.rawValue, "run")
        XCTAssertEqual(RunActivityType.walk.rawValue, "walk")
        XCTAssertEqual(RunActivityType.hike.rawValue, "hike")
        XCTAssertEqual(RunActivityType.cycle.rawValue, "cycle")
    }

    /// The reason this is worth more than a metadata stamp: HealthKit scores
    /// energy and heart rate by the configuration's activity type.
    func testEachChoiceConfiguresTheMatchingHealthKitWorkout() {
        XCTAssertEqual(RunActivityType.run.healthKitActivityType, .running)
        XCTAssertEqual(RunActivityType.walk.healthKitActivityType, .walking)
        XCTAssertEqual(RunActivityType.cycle.healthKitActivityType, .cycling)
    }

    /// `hike` is shown as "Trail run" everywhere in the product, so someone
    /// who picks it is running. Filing it in Health as a hike would report a
    /// runner's energy expenditure as a walker's.
    func testTrailRunIsScoredAsRunningNotHiking() {
        XCTAssertEqual(RunActivityType.hike.healthKitActivityType, .running)
    }

    /// The catalog wiring end to end: the namespaced key resolves through the
    /// String Catalog's explicit `en` entry rather than falling back to the
    /// key itself, which is what a missing `en` localization would render.
    func testLabelsResolveThroughTheStringCatalog() {
        XCTAssertEqual(RunActivityType.run.label, "Run")
        XCTAssertEqual(RunActivityType.walk.label, "Walk")
        XCTAssertEqual(RunActivityType.hike.label, "Trail run")
        XCTAssertEqual(RunActivityType.cycle.label, "Cycle")
    }

    /// An unknown token means this build is older than whatever wrote it. A
    /// recovered run is worth more than its classification, so the parse
    /// falls back to the column's own default rather than dropping the run.
    func testAnUnknownTokenParsesAsRunRatherThanFailing() {
        XCTAssertEqual(RunActivityType.parse("cycle"), .cycle)
        XCTAssertEqual(RunActivityType.parse("stroller"), .run)
        XCTAssertEqual(RunActivityType.parse(""), .run)
        XCTAssertEqual(RunActivityType.parse(nil), .run)
    }

    /// A checkpoint written before the picker existed carries no token, and
    /// the recovered run must be a run rather than nothing.
    func testACheckpointWithoutTheFieldRecoversAsARun() throws {
        let legacy = Data("""
        {"version":1,"id":"abc","startedAt":0,"distanceMetres":120.5,
         "activeDurationSeconds":60,"pausedIntervalSeconds":0,"trackPointCount":9}
        """.utf8)
        let decoded = try JSONDecoder().decode(RunCheckpoint.self, from: legacy)
        XCTAssertEqual(decoded.activityType, "run")
        XCTAssertEqual(RunActivityType.parse(decoded.activityType), .run)
    }

    func testACheckpointRoundTripsTheChosenActivity() throws {
        let cp = RunCheckpoint(
            id: "abc",
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            distanceMetres: 5000,
            activeDurationSeconds: 1800,
            pausedIntervalSeconds: 0,
            trackPointCount: 1800,
            cacheFileURL: URL(fileURLWithPath: "/tmp/abc.ndjson"),
            averageBPM: nil,
            hrCoverage: nil,
            steps: nil,
            laps: nil,
            activityType: RunActivityType.cycle.rawValue
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(RunCheckpoint.self, from: encoder.encode(cp))
        XCTAssertEqual(RunActivityType.parse(decoded.activityType), .cycle)
    }
}
