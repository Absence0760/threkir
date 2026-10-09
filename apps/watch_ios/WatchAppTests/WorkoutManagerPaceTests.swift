import XCTest
import CoreLocation
@testable import WatchApp

/// The rolling pace window: what it measures, and across a pause boundary.
///
/// Pace is the GPS distance estimator's distance gained over the last ~200 m
/// (`PaceWindow`), divided by its time span. A pause puts an unbounded wall-clock
/// gap between two adjacent track points, so a window allowed to straddle it
/// charges the whole aid-station stop to the metres run after it: a 12-minute
/// stop makes the first ~200 m read on the order of an hour per kilometre.
/// That number is published to the complication and fed to `checkPaceAlert`,
/// so the error runs in the direction that fires a false "too slow" haptic.
/// `resume()` must therefore seal the window, not only re-anchor the distance
/// reference (issue #371 fixed the latter alone).
///
/// The state machine is driven directly rather than through `start()`:
/// `pause()` and `resume()` touch only the frozen-checkpoint guard (a no-op
/// without a `CheckpointStore`), the idle `CLLocationManager`, a nil HealthKit
/// session and the App-Group snapshot — none of which need a live run.
final class WorkoutManagerPaceTests: XCTestCase {

    private let legDegrees = 0.0001
    private let legSeconds: TimeInterval = 3.34

    private func loc(_ lat: Double, at timestamp: Date) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: lat, longitude: -0.1),
            altitude: 10,
            horizontalAccuracy: 5,
            verticalAccuracy: 5,
            timestamp: timestamp
        )
    }

    /// `count` fixes marching north one `legDegrees` step per `legSeconds`.
    private func leg(from lat: Double, at start: Date, count: Int) -> [CLLocation] {
        (0..<count).map {
            loc(lat + Double($0) * legDegrees, at: start.addingTimeInterval(Double($0) * legSeconds))
        }
    }

    private func feed(_ wm: WorkoutManager, _ locations: [CLLocation]) {
        wm.locationManager(CLLocationManager(), didUpdateLocations: locations)
    }

    /// Great-circle metres on the estimator's own sphere. Not
    /// `CLLocation.distance(from:)`: the estimator never calls it, it measures
    /// on an ellipsoid, and on the watchOS 26.5 simulator CI runs it returned
    /// NaN, which failed every harness check that leaned on it.
    private func metres(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let rad = Double.pi / 180
        let dLat = (b.latitude - a.latitude) * rad
        let dLng = (b.longitude - a.longitude) * rad
        let h = sin(dLat / 2) * sin(dLat / 2)
            + cos(a.latitude * rad) * cos(b.latitude * rad) * sin(dLng / 2) * sin(dLng / 2)
        return GpsDistanceEstimator.earthRadiusM * 2 * asin(min(1, h.squareRoot()))
    }

    /// Seconds per km implied by one leg — the honest pace of both halves of
    /// the run below, derived from the leg's geometry rather than hardcoded.
    private func expectedPace() -> Double {
        let a = CLLocationCoordinate2D(latitude: 51.5, longitude: -0.1)
        let b = CLLocationCoordinate2D(latitude: 51.5 + legDegrees, longitude: -0.1)
        return (legSeconds / metres(a, b)) * 1000
    }

    func testPaceAfterResumeExcludesThePausedSpan() {
        let wm = WorkoutManager()
        wm.state = .recording
        let expected = expectedPace()
        let base = Date()

        feed(wm, leg(from: 51.5, at: base, count: 8))
        XCTAssertEqual(wm.currentPace ?? 0, expected, accuracy: 15,
                       "harness check: the pre-pause window reads the honest pace")

        wm.pause()
        let bankedBeforeResume = wm.distanceMetres
        wm.resume()

        XCTAssertNil(wm.currentPace,
                     "resume() must drop the pace it can no longer justify, not leave the pre-pause value published")
        XCTAssertEqual(wm.distanceMetres, bankedBeforeResume, accuracy: 0.0001,
                       "sealing the pace window must not cost the run any banked distance")

        // 12 minutes standing at an aid station, then the runner picks up
        // where they stopped and holds the same pace.
        let resumedAt = base.addingTimeInterval(7 * legSeconds + 720)
        feed(wm, leg(from: 51.5 + 8 * legDegrees, at: resumedAt, count: 8))

        XCTAssertEqual(wm.currentPace ?? 0, expected, accuracy: 15,
                       "the post-resume window must time only post-resume metres")
    }

    func testPaceIsWithheldUntilTheResumedWindowRefills() {
        let wm = WorkoutManager()
        wm.state = .recording
        let base = Date()

        feed(wm, leg(from: 51.5, at: base, count: 8))
        wm.pause()
        wm.resume()

        // Four fixes is one short of `updatePace`'s minimum, and with the
        // pre-pause tail still in the window it would have been enough.
        let resumedAt = base.addingTimeInterval(7 * legSeconds + 720)
        feed(wm, leg(from: 51.5 + 8 * legDegrees, at: resumedAt, count: 4))
        XCTAssertNil(wm.currentPace)
    }

    // A steady 5:00/km (10/3 m/s) due north, one fix a second, each fix 1.25 m
    // either side of the true line. Every hop is then 4.17 m for 3.33 m of
    // progress, so a hop-sum reads 4:00/km. scripts/gps_distance/reference.py
    // over the same track gives 300.0 s/km with Doppler and 299.9 s/km from
    // positions alone.
    private let zigZagSpeed = 10.0 / 3.0
    private let zigZagFixes = 121

    private func zigZag(doppler: Bool) -> [CLLocation] {
        let base = Date()
        let degLatPerM = 1 / 111_195.0
        let degLngPerM = degLatPerM / cos(51.5 * .pi / 180)
        return (0..<zigZagFixes).map { i in
            CLLocation(
                coordinate: CLLocationCoordinate2D(
                    latitude: 51.5 + Double(i) * zigZagSpeed * degLatPerM,
                    longitude: -0.1 + (i % 2 == 1 ? 1.25 : -1.25) * degLngPerM
                ),
                altitude: 10,
                horizontalAccuracy: 5,
                verticalAccuracy: 5,
                course: doppler ? 0 : -1,
                courseAccuracy: doppler ? 5 : -1,
                speed: doppler ? zigZagSpeed : -1,
                speedAccuracy: doppler ? 0.5 : -1,
                timestamp: base.addingTimeInterval(Double(i))
            )
        }
    }

    private func hopSumPace(_ fixes: [CLLocation], hops: Int) -> Double {
        let tail = Array(fixes.suffix(hops + 1))
        let summed = zip(tail, tail.dropFirst()).reduce(0.0) { $0 + metres($1.0.coordinate, $1.1.coordinate) }
        return Double(hops) / summed * 1000
    }

    func testZigZagPaceReadsTheEstimatorWithDoppler() {
        let wm = WorkoutManager()
        wm.state = .recording
        let fixes = zigZag(doppler: true)
        XCTAssertEqual(hopSumPace(fixes, hops: 60), 240, accuracy: 3,
                       "harness check: the raw hop-sum reads 4:00/km")
        feed(wm, fixes)
        XCTAssertEqual(wm.currentPace ?? 0, 300, accuracy: 1)
    }

    func testZigZagPaceReadsTheEstimatorFromPositionsAlone() {
        let wm = WorkoutManager()
        wm.state = .recording
        let fixes = zigZag(doppler: false)
        XCTAssertEqual(hopSumPace(fixes, hops: 60), 240, accuracy: 3)
        feed(wm, fixes)
        XCTAssertEqual(wm.currentPace ?? 0, 300, accuracy: 3)
    }
}
