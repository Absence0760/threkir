import XCTest
@testable import WatchApp

/// Replays `fixtures/gps_distance_vectors.json` — the golden vectors every
/// port of the spec-v1 estimator is held to (`docs/features/gps_distance.md`).
/// The distance is asserted after every event, not only at the end, so a port
/// that reaches the right total by a different path still fails.
final class GpsDistanceEstimatorTests: XCTestCase {

    private struct Vectors: Decodable {
        let tolerance_m: Double
        let scenarios: [Scenario]
    }

    private struct Scenario: Decodable {
        let name: String
        let maxSpeedMps: Double
        let events: [Event]
        let expected: Expected
    }

    private struct Event: Decodable {
        let type: String
        let t: Double
        let lat: Double?
        let lng: Double?
        let acc: Double?
        let speed: Double?
        let speedAcc: Double?
        let bearing: Double?
        let count: Int?
    }

    private struct Expected: Decodable {
        let distanceAfterEachEventM: [Double]
        let gpsDistanceM: Double
        let stepDistanceM: Double
        let strideM: Double?
    }

    private func loadVectors(file: StaticString = #filePath) throws -> Vectors {
        let here = URL(fileURLWithPath: "\(file)")
        let fixtureURL = here
            .deletingLastPathComponent() // WatchAppTests
            .deletingLastPathComponent() // watch_ios
            .deletingLastPathComponent() // apps
            .deletingLastPathComponent() // repo root
            .appendingPathComponent("fixtures/gps_distance_vectors.json")
        let data = try Data(contentsOf: fixtureURL)
        return try JSONDecoder().decode(Vectors.self, from: data)
    }

    func testFixtureCarriesScenarios() throws {
        let vectors = try loadVectors()
        XCTAssertFalse(vectors.scenarios.isEmpty)
    }

    func testEveryScenarioReplaysWithinTolerance() throws {
        let vectors = try loadVectors()
        let tol = vectors.tolerance_m
        for scenario in vectors.scenarios {
            XCTAssertEqual(scenario.events.count, scenario.expected.distanceAfterEachEventM.count,
                           "\(scenario.name): one expected distance per event")
            let estimator = GpsDistanceEstimator(maxSpeedMps: scenario.maxSpeedMps)
            for (i, event) in scenario.events.enumerated() {
                switch event.type {
                case "fix":
                    estimator.addFix(
                        t: event.t,
                        lat: event.lat ?? .nan,
                        lng: event.lng ?? .nan,
                        accuracyM: event.acc,
                        speedMps: event.speed,
                        speedAccuracyMps: event.speedAcc,
                        bearingDeg: event.bearing
                    )
                case "steps":
                    if let count = event.count {
                        estimator.addSteps(t: event.t, cumulativeSteps: count)
                    }
                case "finish":
                    estimator.finish(t: event.t)
                default:
                    XCTFail("\(scenario.name): unknown event type \(event.type)")
                }
                XCTAssertEqual(estimator.distanceM, scenario.expected.distanceAfterEachEventM[i],
                               accuracy: tol, "\(scenario.name): distance after event \(i)")
            }
            XCTAssertEqual(estimator.gpsDistanceM, scenario.expected.gpsDistanceM, accuracy: tol,
                           "\(scenario.name): gpsDistanceM")
            XCTAssertEqual(estimator.stepDistanceM, scenario.expected.stepDistanceM, accuracy: tol,
                           "\(scenario.name): stepDistanceM")
            if let stride = scenario.expected.strideM {
                XCTAssertEqual(estimator.strideM ?? -1, stride, accuracy: tol, "\(scenario.name): strideM")
            } else {
                XCTAssertNil(estimator.strideM, "\(scenario.name): strideM")
            }
        }
    }

    func testFirstFixCreditsNothing() {
        let estimator = GpsDistanceEstimator()
        XCTAssertEqual(estimator.addFix(t: 0, lat: 40, lng: -75, accuracyM: 4, speedMps: 3, speedAccuracyMps: 0.3, bearingDeg: 0), 0)
        XCTAssertEqual(estimator.distanceM, 0)
    }

    func testDopplerFixCreditsSpeedTimesInterval() {
        let estimator = GpsDistanceEstimator()
        estimator.addFix(t: 0, lat: 40, lng: -75, accuracyM: 4, speedMps: 3, speedAccuracyMps: 0.3, bearingDeg: 0)
        let credited = estimator.addFix(t: 2, lat: 40.00005, lng: -75, accuracyM: 4, speedMps: 3, speedAccuracyMps: 0.3, bearingDeg: 0)
        XCTAssertEqual(credited, 6, accuracy: 1e-9)
    }

    func testGapOverTenSecondsReanchorsWithoutCredit() {
        let estimator = GpsDistanceEstimator()
        estimator.addFix(t: 0, lat: 40, lng: -75, accuracyM: 4, speedMps: 3, speedAccuracyMps: 0.3, bearingDeg: 0)
        XCTAssertEqual(estimator.addFix(t: 30, lat: 40.001, lng: -75, accuracyM: 4, speedMps: 3, speedAccuracyMps: 0.3, bearingDeg: 0), 0)
    }
}
