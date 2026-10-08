import XCTest
@testable import WatchApp

/// Replays `fixtures/gps_distance_vectors.json` — the golden vectors every
/// port of the spec-v1.2 estimator is held to (`docs/features/gps_distance.md`).
/// The distance is asserted after every event, not only at the end, so a port
/// that reaches the right total by a different path still fails. The scenario
/// list comes from the fixture, so a new scenario is replayed without a code
/// change.
final class GpsDistanceEstimatorTests: XCTestCase {

    private struct Vectors: Decodable {
        let spec: String
        let constants: [String: Double]
        let tolerance_m: Double
        let scenarios: [Scenario]
    }

    private struct Scenario: Decodable {
        let name: String
        let maxSpeedMps: Double
        let expectedIntervalS: Double
        let initialStrideM: Double?
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
        let rejectedFixes: Int
        let zuptFixes: Int
        let rScale: Double
        let dopplerTrusted: Bool
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

    func testFixtureIsSpecOneTwoAndEveryConstantMatches() throws {
        let vectors = try loadVectors()
        XCTAssertFalse(vectors.scenarios.isEmpty)
        XCTAssertEqual(vectors.spec, "gps-distance-estimator v1.2")
        XCTAssertEqual(GpsDistanceEstimator.specVersion, "1.2")
        XCTAssertFalse(GpsDistanceEstimator.constants.isEmpty)
        for (name, value) in GpsDistanceEstimator.constants {
            XCTAssertEqual(vectors.constants[name], value, "\(name)")
        }
    }

    private func learnStride(_ estimator: GpsDistanceEstimator) {
        let degPerM = 180.0 / (Double.pi * 6371008.8)
        estimator.addFix(t: 0, lat: 45, lng: 7, accuracyM: 5, speedMps: 0, speedAccuracyMps: 0.5, bearingDeg: 0)
        estimator.addSteps(t: 0.5, cumulativeSteps: 0)
        for i in 1...20 {
            estimator.addFix(t: Double(i), lat: 45 + 3.0 * Double(i) * degPerM, lng: 7, accuracyM: 5,
                             speedMps: 3, speedAccuracyMps: 0.5, bearingDeg: 0)
            estimator.addSteps(t: Double(i) + 0.5, cumulativeSteps: 3 * i)
        }
    }

    func testNextSegmentCarriesLearnedStrideAndConfiguration() {
        let first = GpsDistanceEstimator(maxSpeedMps: 6, expectedIntervalS: 15)
        learnStride(first)
        XCTAssertEqual(first.strideM ?? -1, 1.0, accuracy: 1e-9)
        let next = first.nextSegment()
        XCTAssertEqual(next.strideM ?? -1, 1.0, accuracy: 1e-9)
        XCTAssertEqual(next.maxSpeedMps, 6)
        XCTAssertEqual(next.expectedIntervalS, 15)
        XCTAssertEqual(next.gapWindowS, 150)
        XCTAssertEqual(next.distanceM, 0)
    }

    func testSegmentThatLearnedNothingPassesOnItsSeed() {
        XCTAssertEqual(GpsDistanceEstimator(initialStrideM: 0.95).nextSegment().nextSegment().strideM, 0.95)
        XCTAssertNil(GpsDistanceEstimator().nextSegment().strideM)
        XCTAssertNil(GpsDistanceEstimator(initialStrideM: 3.0).strideM)
    }

    func testCarriedStrideBlendsWithTheNextLearnedOne() {
        let estimator = GpsDistanceEstimator(initialStrideM: 0.95)
        learnStride(estimator)
        XCTAssertEqual(estimator.strideM ?? -1, 0.96, accuracy: 1e-9)
    }

    func testEveryScenarioReplaysWithinTolerance() throws {
        let vectors = try loadVectors()
        let tol = vectors.tolerance_m
        for scenario in vectors.scenarios {
            XCTAssertEqual(scenario.events.count, scenario.expected.distanceAfterEachEventM.count,
                           "\(scenario.name): one expected distance per event")
            let estimator = GpsDistanceEstimator(
                maxSpeedMps: scenario.maxSpeedMps,
                expectedIntervalS: scenario.expectedIntervalS,
                initialStrideM: scenario.initialStrideM
            )
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
            XCTAssertEqual(estimator.rejectedFixes, scenario.expected.rejectedFixes, "\(scenario.name): rejectedFixes")
            XCTAssertEqual(estimator.zuptFixes, scenario.expected.zuptFixes, "\(scenario.name): zuptFixes")
            XCTAssertEqual(estimator.rScale, scenario.expected.rScale, accuracy: 1e-6, "\(scenario.name): rScale")
            XCTAssertEqual(estimator.dopplerTrusted, scenario.expected.dopplerTrusted, "\(scenario.name): dopplerTrusted")
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
