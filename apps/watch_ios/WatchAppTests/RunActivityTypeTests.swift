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

    /// The catalog wiring end to end, in the two halves that are separable on
    /// a device whose language nobody chose.
    ///
    /// This half is the wiring: a key with no localization for the running
    /// language renders as the key itself, so a label that is anything else
    /// resolved. It says nothing about the words, and must not — asserting
    /// `"Run"` here is what went red on a Japanese watch (`ランニング`) while
    /// staying green on CI, which pins its destination to one simulator.
    func testLabelsResolveThroughTheStringCatalog() {
        for type in RunActivityType.allCases {
            XCTAssertFalse(type.label.isEmpty, "\(type) has no label at all")
            XCTAssertNotEqual(
                type.label, "activityType.\(type.rawValue)",
                "\(type)'s key rendered as itself — it has no localization for this language")
        }
    }

    /// And this half is the words, read out of the `en` localization by name
    /// rather than out of whichever one the device is running.
    func testTheEnglishCatalogCarriesTheProductsWords() throws {
        XCTAssertEqual(try englishCatalogValue("activityType.run"), "Run")
        XCTAssertEqual(try englishCatalogValue("activityType.walk"), "Walk")
        XCTAssertEqual(try englishCatalogValue("activityType.hike"), "Trail run")
        XCTAssertEqual(try englishCatalogValue("activityType.cycle"), "Cycle")
    }

    private func englishCatalogValue(_ key: String) throws -> String {
        let sentinel = "\u{0}absent"
        let english = Bundle.allBundles.compactMap { bundle -> Bundle? in
            guard let path = bundle.path(forResource: "en", ofType: "lproj") else { return nil }
            return Bundle(path: path)
        }
        return try XCTUnwrap(
            english.map { $0.localizedString(forKey: key, value: sentinel, table: nil) }
                .first { $0 != sentinel },
            "no en.lproj in any loaded bundle carries \(key)")
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
