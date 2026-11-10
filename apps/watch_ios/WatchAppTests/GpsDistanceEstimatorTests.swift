import XCTest
@testable import WatchApp

/// Replays `fixtures/gps_distance_vectors.json` — the golden vectors every
/// port of the spec-v1.7 estimator is held to (`docs/features/gps_distance.md`).
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
        let learnStride: Bool
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
        let stepOverChordM: Double
        let strideM: Double?
        let rejectedFixes: Int
        let zuptFixes: Int
        let rScale: Double
        let dopplerTrusted: Bool
        let dopplerScale: Double
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

    func testFixtureIsSpecOneFourAndEveryConstantMatches() throws {
        let vectors = try loadVectors()
        XCTAssertFalse(vectors.scenarios.isEmpty)
        XCTAssertEqual(vectors.spec, "gps-distance-estimator v1.7")
        XCTAssertEqual(GpsDistanceEstimator.specVersion, "1.7")
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
                initialStrideM: scenario.initialStrideM,
                learnStride: scenario.learnStride
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
            XCTAssertEqual(estimator.stepOverChordM, scenario.expected.stepOverChordM, accuracy: tol,
                           "\(scenario.name): stepOverChordM")
            if let stride = scenario.expected.strideM {
                XCTAssertEqual(estimator.strideM ?? -1, stride, accuracy: tol, "\(scenario.name): strideM")
            } else {
                XCTAssertNil(estimator.strideM, "\(scenario.name): strideM")
            }
            XCTAssertEqual(estimator.rejectedFixes, scenario.expected.rejectedFixes, "\(scenario.name): rejectedFixes")
            XCTAssertEqual(estimator.zuptFixes, scenario.expected.zuptFixes, "\(scenario.name): zuptFixes")
            XCTAssertEqual(estimator.rScale, scenario.expected.rScale, accuracy: 1e-6, "\(scenario.name): rScale")
            XCTAssertEqual(estimator.dopplerScale, scenario.expected.dopplerScale, accuracy: 1e-6, "\(scenario.name): dopplerScale")
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

    func testGapOverTenSecondsReanchorsCreditingItsChordLowerBound() {
        let estimator = GpsDistanceEstimator()
        estimator.addFix(t: 0, lat: 40, lng: -75, accuracyM: 4, speedMps: 3, speedAccuracyMps: 0.3, bearingDeg: 0)
        // 111.195 m north, less sqrt(16 + 16 + 2 * 16) = 8 m of uncertainty.
        let chord = 0.001 * Double.pi / 180 * 6371008.8 - 8
        let credited = estimator.addFix(t: 30, lat: 40.001, lng: -75, accuracyM: 4, speedMps: 3, speedAccuracyMps: 0.3, bearingDeg: 0)
        XCTAssertEqual(credited, chord, accuracy: 1e-6)
    }

    func testFixWorseThanFiftyMetresIsIgnored() {
        let estimator = GpsDistanceEstimator()
        XCTAssertEqual(estimator.addFix(t: 0, lat: 40, lng: -75, accuracyM: 51), 0)
        estimator.addFix(t: 1, lat: 40, lng: -75, accuracyM: 50)
        estimator.addFix(t: 2, lat: 40.00003, lng: -75, accuracyM: 51, speedMps: 3, speedAccuracyMps: 0.3, bearingDeg: 0)
        XCTAssertEqual(estimator.distanceM, 0)
    }

    func testNoStrideLearningKeepsTheSeed() {
        let estimator = GpsDistanceEstimator(initialStrideM: 0.95, learnStride: false)
        learnStride(estimator)
        XCTAssertEqual(estimator.strideM, 0.95)
        XCTAssertFalse(estimator.nextSegment().learnStride)
    }

    private let eastMPerDeg = 111195 * cos(40 * Double.pi / 180)

    private func eastward() -> GpsDistanceEstimator {
        let estimator = GpsDistanceEstimator(initialStrideM: 0.5, learnStride: false)
        for i in 0...25 {
            estimator.addFix(t: Double(i), lat: 40, lng: -75 + 4 * Double(i) / eastMPerDeg, accuracyM: 3, speedMps: 4, speedAccuracyMps: 0.3, bearingDeg: 90)
            estimator.addSteps(t: Double(i) + 0.5, cumulativeSteps: 4 * i + 2)
        }
        return estimator
    }

    func testLateStepBatchTopsAGapUpWithoutCountingItsChordTwice() {
        // Steps at 0.5 m credit 2 m/s, so the straight 30 s gap's 116 m chord
        // lower bound wins. The batch after the resuming fix moves 10 m of
        // that credit from the chord to the steps and adds nothing (v1.6).
        let estimator = eastward()
        estimator.addSteps(t: 50, cumulativeSteps: 202)
        estimator.addFix(t: 55, lat: 40, lng: -75 + 220 / eastMPerDeg, accuracyM: 3, speedMps: 4, speedAccuracyMps: 0.3, bearingDeg: 90)
        let before = estimator.distanceM
        let steps = estimator.stepDistanceM
        estimator.addSteps(t: 56.5, cumulativeSteps: 228)
        XCTAssertEqual(estimator.distanceM, before, accuracy: 1e-9)
        XCTAssertEqual(estimator.stepDistanceM - steps, 10, accuracy: 1e-9)
    }

    func testLateSampleStampedInsideAGapSharesOnlyItsOwnInterval() {
        // 2 steps over (50, 51] at a 0.5 m stride credit 1 m; sharing the rest
        // of the gap, which the fix at 55 closed before the sample arrived, at
        // the sample's rate would credit 5 m (v1.6).
        let estimator = eastward()
        estimator.addSteps(t: 50, cumulativeSteps: 202)
        estimator.addFix(t: 55, lat: 40, lng: -75 + 110 / eastMPerDeg, accuracyM: 3, speedMps: 4, speedAccuracyMps: 0.3, bearingDeg: 90)
        let before = estimator.distanceM
        let steps = estimator.stepDistanceM
        estimator.addSteps(t: 51, cumulativeSteps: 204)
        XCTAssertEqual(estimator.distanceM - before, 1, accuracy: 1e-9)
        XCTAssertEqual(estimator.stepDistanceM - steps, 1, accuracy: 1e-9)
    }

    func testFixBridgingAShortStallTeachesNoStrideFromItsCredit() {
        // 4 m/s at 4 steps/s is a 1 m stride. The fix at 36 bridges a 7 s stall
        // whose samples emptied the window; feeding its 28 m to the window
        // learns 1.092 m, and letting the sample at 36.5 refill it 0.985 m (v1.6).
        let estimator = GpsDistanceEstimator()
        for i in 0...60 {
            if i < 30 || i >= 36 {
                estimator.addFix(t: Double(i), lat: 40, lng: -75 + 4 * Double(i) / eastMPerDeg, accuracyM: 3, speedMps: 4, speedAccuracyMps: 0.3, bearingDeg: 90)
            }
            estimator.addSteps(t: Double(i) + 0.5, cumulativeSteps: 4 * i + 2)
        }
        XCTAssertEqual(estimator.strideM ?? 0, 1, accuracy: 1e-9)
    }

    /// 4 m/s at 4 steps/s is a 1 m stride. The first sample, at 15.5, only sets
    /// the baseline; counting the window's metres from the first fix put 30 s of
    /// metres against 15 s of steps and learned 2.0 m, then 1.64 m by 60.5.
    func testFirstStepSampleOfAStretchStartsTheStrideWindow() {
        let estimator = GpsDistanceEstimator()
        for i in 0...60 {
            estimator.addFix(t: Double(i), lat: 40, lng: -75 + 4 * Double(i) / eastMPerDeg, accuracyM: 3, speedMps: 4, speedAccuracyMps: 0.3, bearingDeg: 90)
            if i > 0 && i % 15 == 0 {
                estimator.addSteps(t: Double(i) + 0.5, cumulativeSteps: 4 * i + 2)
            }
        }
        XCTAssertEqual(estimator.strideM ?? 0, 1, accuracy: 1e-6)
    }

    /// 4 m/s at 4 steps/s is a 1 m stride. The first sample, at 14.5, lands
    /// inside a 7 s stall the fix at 18 bridges, so it is stale as well as the
    /// baseline; the bridging fix must empty the window rather than feed it 28
    /// m, which learned 1.171 m.
    func testStaleFirstStepSampleKeepsABridgedStallOutOfTheStrideWindow() {
        let estimator = GpsDistanceEstimator()
        for i in 0...60 {
            if i < 11 || i > 17 {
                estimator.addFix(t: Double(i), lat: 40, lng: -75 + 4 * Double(i) / eastMPerDeg, accuracyM: 3, speedMps: 4, speedAccuracyMps: 0.3, bearingDeg: 90)
            }
            if i % 15 == 14 {
                estimator.addSteps(t: Double(i) + 0.5, cumulativeSteps: 4 * i + 2)
            }
        }
        XCTAssertEqual(estimator.strideM ?? 0, 1, accuracy: 1e-6)
    }

    /// The first sample, at 0.5, and the second, at 15.5, come before the
    /// first fix at 20; the first fix starts the window, so the sample at
    /// 30.5, whose interval began before it, empties the window rather than
    /// pairing 15 s of steps with 10 s of metres, which learned 0.787 m.
    func testFirstFixOfAStretchStartsTheStrideWindow() {
        let estimator = GpsDistanceEstimator()
        for i in 0...60 {
            if i >= 20 {
                estimator.addFix(t: Double(i), lat: 40, lng: -75 + 4 * Double(i) / eastMPerDeg, accuracyM: 3, speedMps: 4, speedAccuracyMps: 0.3, bearingDeg: 90)
            }
            if i % 15 == 0 {
                estimator.addSteps(t: Double(i) + 0.5, cumulativeSteps: 4 * i + 2)
            }
        }
        XCTAssertEqual(estimator.strideM ?? 0, 1, accuracy: 1e-6)
    }

    /// The baseline, stamped 15.5, arrives after the fix at 18, so the window's
    /// metres start at 18; the sample at 30.5, whose steps start at 15.5, must
    /// empty the window rather than pair 15 s of steps with 12 s of metres,
    /// which learned 0.8 m (v1.7).
    func testStepBaselineDeliveredAfterALaterFixKeepsItsStepsOutOfTheStrideWindow() {
        let estimator = GpsDistanceEstimator()
        for i in 0...60 {
            estimator.addFix(t: Double(i), lat: 40, lng: -75 + 4 * Double(i) / eastMPerDeg, accuracyM: 3, speedMps: 4, speedAccuracyMps: 0.3, bearingDeg: 90)
            if i == 18 { estimator.addSteps(t: 15.5, cumulativeSteps: 62) }
            if i > 15 && i % 15 == 0 {
                estimator.addSteps(t: Double(i) + 0.5, cumulativeSteps: 4 * i + 2)
            }
        }
        XCTAssertEqual(estimator.strideM ?? 0, 1, accuracy: 1e-6)
    }

    /// A seeded 1 m stride, 4 m/s and 4 steps/s, then a 26 s fix gap whose 104 m
    /// of steps the resuming fix puts beside no chord (the runner looped back),
    /// a 55.39 m one, and one longer than the steps (v1.7).
    func testStepOverChordCountsOnlyTheStepsAGapCreditedBeyondItsChord() {
        for (eastM, want) in [(24.0, 104.0), (80.0, 48.612667), (160.0, 0.0)] {
            let estimator = GpsDistanceEstimator(initialStrideM: 1.0, learnStride: false)
            for i in 0...30 {
                if i <= 5 {
                    estimator.addFix(t: Double(i), lat: 40, lng: -75 + 4 * Double(i) / eastMPerDeg, accuracyM: 3, speedMps: 4, speedAccuracyMps: 0.3, bearingDeg: 90)
                }
                estimator.addSteps(t: Double(i) + 0.5, cumulativeSteps: 4 * i + 2)
            }
            estimator.addFix(t: 31, lat: 40, lng: -75 + eastM / eastMPerDeg, accuracyM: 3, speedMps: 4, speedAccuracyMps: 0.3, bearingDeg: 90)
            estimator.addSteps(t: 31.5, cumulativeSteps: 126)
            XCTAssertEqual(estimator.stepDistanceM, 104, accuracy: 1e-9)
            XCTAssertEqual(estimator.stepOverChordM, want, accuracy: 1e-6, "resume \(eastM) m")
        }
    }

    func testStretchCreditsNoStepsTakenBeforeItsFirstFix() {
        let estimator = GpsDistanceEstimator(initialStrideM: 1.0, learnStride: false)
        for i in 0..<30 { estimator.addSteps(t: Double(i) + 0.5, cumulativeSteps: 4 * i) }
        estimator.addFix(t: 30, lat: 40, lng: -75, accuracyM: 3)
        estimator.finish(t: 31)
        XCTAssertEqual(estimator.distanceM, 0)
    }
}
