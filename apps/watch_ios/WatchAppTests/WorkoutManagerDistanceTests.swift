import XCTest
import CoreLocation
@testable import WatchApp

/// How the watchOS recorder turns fixes into distance: every accepted fix goes
/// through the spec-v1 `GpsDistanceEstimator` (docs/features/gps_distance.md),
/// whose own arithmetic `GpsDistanceEstimatorTests` pins against the shared
/// vectors. These tests pin the wiring — the clock it is fed, the CoreLocation
/// sentinels it is spared, and the pause boundary (issue #371) that must credit
/// neither the paused span nor the wander across it.
///
/// Constructing `WorkoutManager` is side-effect-free until `start()`, and
/// `didUpdateLocations`, `pause()` and `resume()` touch no live
/// `CLLocationManager`, HealthKit session or timer that needs a real run.
final class WorkoutManagerDistanceTests: XCTestCase {

    private let base = Date()

    private func loc(
        _ lat: Double,
        at seconds: TimeInterval,
        speed: Double = 2.8,
        speedAccuracy: Double = 0.3,
        course: Double = 0,
        accuracy: Double = 5
    ) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: lat, longitude: -0.1),
            altitude: 10,
            horizontalAccuracy: accuracy,
            verticalAccuracy: 5,
            course: course,
            courseAccuracy: course >= 0 ? 5 : -1,
            speed: speed,
            speedAccuracy: speedAccuracy,
            timestamp: base.addingTimeInterval(seconds)
        )
    }

    private func feed(_ wm: WorkoutManager, _ locations: [CLLocation]) {
        wm.locationManager(CLLocationManager(), didUpdateLocations: locations)
    }

    /// One fix per second heading north at the Doppler speed's pace.
    private func run(from lat: Double, at start: TimeInterval, seconds: Int, speed: Double = 2.8) -> [CLLocation] {
        let degPerSecond = speed / 111_195
        return (0...seconds).map {
            loc(lat + Double($0) * degPerSecond, at: start + Double($0), speed: speed)
        }
    }

    func testFirstFixEverAddsNoPhantomDistance() {
        let wm = WorkoutManager()
        feed(wm, [loc(51.5, at: 0)])
        XCTAssertEqual(wm.distanceMetres, 0)
    }

    func testDopplerRunCreditsSpeedTimesElapsed() {
        let wm = WorkoutManager()
        feed(wm, run(from: 51.5, at: 0, seconds: 60))
        XCTAssertEqual(wm.distanceMetres, 2.8 * 60, accuracy: 0.01)
    }

    func testBatchedDeliveryKeepsEachFixsOwnSpacing() {
        // CoreLocation can hand over several fixes in one call. They share a
        // delivery instant, so the estimator's clock has to come from each
        // fix's timestamp or every fix but the first would be ignored.
        let wm = WorkoutManager()
        let fixes = run(from: 51.5, at: 0, seconds: 10)
        feed(wm, Array(fixes.prefix(1)))
        feed(wm, Array(fixes.dropFirst()))
        XCTAssertEqual(wm.distanceMetres, 2.8 * 10, accuracy: 0.01)
    }

    func testStandingStillWithDopplerCreditsNothing() {
        // The red-light case: position wanders a few metres, the chip's own
        // speed says ~0, and the old hop-sum banked every wobble.
        let wm = WorkoutManager()
        let wobble = [0.0, 0.00002, -0.00001, 0.00003, 0.0, -0.00002, 0.00001]
        feed(wm, wobble.enumerated().map { loc(51.5 + $0.element, at: Double($0.offset), speed: 0.1) })
        XCTAssertEqual(wm.distanceMetres, 0)
    }

    func testUnknownSpeedFallsBackToThePositionOnlyPath() {
        // `speed == -1` is CoreLocation's "unknown". Passed through it would
        // fail the estimator's `>= 0` test anyway, but a negative course with
        // a real speed must not be read as a bearing either.
        let wm = WorkoutManager()
        let degPerSecond = 2.8 / 111_195
        feed(wm, (0...60).map {
            loc(51.5 + Double($0) * degPerSecond, at: Double($0), speed: -1, speedAccuracy: -1, course: -1)
        })
        XCTAssertGreaterThan(wm.distanceMetres, 2.8 * 60 * 0.8)
        XCTAssertLessThan(wm.distanceMetres, 2.8 * 60 * 1.2)
    }

    func testGapOverTenSecondsCreditsNothingForTheGap() {
        let wm = WorkoutManager()
        feed(wm, run(from: 51.5, at: 0, seconds: 20))
        let before = wm.distanceMetres
        // 60 s later and ~170 m north: the estimator re-anchors and the
        // un-sampled span is not invented.
        feed(wm, [loc(51.5 + 0.0015, at: 80)])
        XCTAssertEqual(wm.distanceMetres, before, accuracy: 0.0001)
        feed(wm, [loc(51.5 + 0.0015 + 2.8 / 111_195, at: 81)])
        XCTAssertEqual(wm.distanceMetres, before + 2.8, accuracy: 0.01)
    }

    func testBadAccuracyFixIsIgnored() {
        let wm = WorkoutManager()
        feed(wm, run(from: 51.5, at: 0, seconds: 5))
        let banked = wm.distanceMetres
        feed(wm, [loc(51.6, at: 6, accuracy: 50)])
        XCTAssertEqual(wm.distanceMetres, banked, accuracy: 0.0001)
    }

    // MARK: - The pause boundary (#371)

    func testWanderWhilePausedAddsNoDistanceOnResume() {
        let wm = WorkoutManager()
        wm.state = .recording
        feed(wm, run(from: 51.5, at: 0, seconds: 30))
        let bankedBeforePause = wm.distanceMetres
        XCTAssertGreaterThan(bankedBeforePause, 0)

        wm.pause()
        XCTAssertEqual(wm.distanceMetres, bankedBeforePause, accuracy: 0.0001,
                       "pausing banks the segment, it does not change it")
        wm.resume()

        // Five seconds later and ~44 m away: short enough that one continuous
        // filter would integrate it, which is why a pause starts a new segment.
        let resumeLat = 51.5 + 30 * 2.8 / 111_195 + 0.0004
        feed(wm, [loc(resumeLat, at: 35)])
        XCTAssertEqual(wm.distanceMetres, bankedBeforePause, accuracy: 0.0001,
                       "first fix after resume must anchor a fresh segment, not bank the pause wander")

        feed(wm, run(from: resumeLat, at: 35, seconds: 10).dropFirst().map { $0 })
        XCTAssertEqual(wm.distanceMetres, bankedBeforePause + 2.8 * 10, accuracy: 0.01)
    }

    func testStopKeepsTheBankedFigure() {
        let wm = WorkoutManager()
        wm.state = .recording
        feed(wm, run(from: 51.5, at: 0, seconds: 30))
        let live = wm.distanceMetres
        wm.stop()
        XCTAssertEqual(wm.finishedRun?.distanceMetres ?? -1, live, accuracy: 0.0001)
        XCTAssertEqual(wm.finishedRun?.distanceEstimator, WorkoutManager.distanceEstimatorTag)
        XCTAssertEqual(wm.finishedRun?.distanceStepFilledMetres ?? -1, 0)
    }

    func testCyclingRaisesTheSpeedCap() {
        XCTAssertEqual(WorkoutManager.maxSpeedMps(for: .run), 10)
        XCTAssertEqual(WorkoutManager.maxSpeedMps(for: .cycle), 25)
    }
}
