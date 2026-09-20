import XCTest
import CoreLocation
@testable import WatchApp

/// The recording stack's GPS-resilience pair: the self-heal retry decision and
/// the indoor-vs-lost banner.
///
/// **Host-tested only, and that is the honest ceiling.** A watchOS simulator
/// serves whatever location Xcode is configured to serve; it does not wedge
/// CoreLocation, does not stop delivering mid-run, and does not lose a signal
/// under a canopy. Neither trigger these cases describe can be produced there,
/// so a decision function driven over synthetic uptimes is the only coverage
/// that proves anything. Nothing here is evidence that a real dropout heals on
/// a wrist.
///
/// Mirrors Wear OS's `GpsRetryDecisionTest.kt`, with the two clock inputs
/// separated — see `GpsHealth` for why the banner and the retry read different
/// stamps.
final class GpsHealthTests: XCTestCase {

    private let now: TimeInterval = 10_000

    private func trigger(
        authorized: Bool = true,
        updatesRunning: Bool = true,
        lastDelivery: TimeInterval?,
        lastRetry: TimeInterval? = nil
    ) -> GpsRetryTrigger? {
        GpsHealth.retryTrigger(
            authorized: authorized,
            updatesRunning: updatesRunning,
            lastDeliveryUptime: lastDelivery,
            lastRetryUptime: lastRetry,
            nowUptime: now
        )
    }

    // MARK: - Retry: updates are not running

    func testUpdatesNotRunningIsRestarted() {
        XCTAssertEqual(trigger(updatesRunning: false, lastDelivery: now - 1), .notRunning)
    }

    func testUpdatesNotRunningIsRestartedEvenWithNoDeliveryEver() {
        // The cold-start exemption is about SILENCE, not about being stopped:
        // a run whose updates never started has nothing to wait for.
        XCTAssertEqual(trigger(updatesRunning: false, lastDelivery: nil), .notRunning)
    }

    // MARK: - Retry: an unauthorized manager is never kicked

    func testUnauthorizedNeverRetries() {
        XCTAssertNil(trigger(authorized: false, updatesRunning: false, lastDelivery: nil))
        XCTAssertNil(trigger(authorized: false, updatesRunning: true, lastDelivery: now - 600))
    }

    // MARK: - Retry: mid-run silence

    func testSilenceBeyondTheStallWindowResubscribes() {
        XCTAssertEqual(trigger(lastDelivery: now - GpsHealth.stallSeconds - 0.001), .stalled)
    }

    func testSilenceExactlyAtTheStallWindowDoesNot() {
        // Strict `>`, matching Wear's `(nowMs - lastPointAtMs) > GPS_STALL_MS`.
        XCTAssertNil(trigger(lastDelivery: now - GpsHealth.stallSeconds))
    }

    func testANormalGapBetweenFixesIsNotAStall() {
        XCTAssertNil(trigger(lastDelivery: now - 3))
    }

    // MARK: - Retry: an initial no-fix is indoor mode, not a stall

    func testNoDeliveryEverIsNotAStall() {
        // The whole of a treadmill run lives here. Reading it as a stall would
        // restart CoreLocation every 30 s for an hour and find nothing each
        // time — and the banner, not the retry, is what that runner needs.
        XCTAssertNil(trigger(lastDelivery: nil))
    }

    func testNoDeliveryEverStaysQuietHoursIn() {
        XCTAssertNil(trigger(lastDelivery: nil, lastRetry: now - 7200))
    }

    // MARK: - Retry: the fresh subscription is not thrashed

    func testAFreshRestartIsNotImmediatelyKickedAgain() {
        // The restart landed 5 s ago and the stream has not started emitting
        // yet — which is normal, a re-acquire takes seconds.
        XCTAssertNil(trigger(lastDelivery: now - 120, lastRetry: now - 5))
    }

    func testARestartThatNeverTookIsKickedAgainAfterTheStallWindow() {
        XCTAssertEqual(
            trigger(lastDelivery: now - 120, lastRetry: now - GpsHealth.stallSeconds),
            .stalled
        )
    }

    func testTheThrashGuardDoesNotDelayARestartOfStoppedUpdates() {
        // `.notRunning` is not silence — nothing is registered to emit, so
        // waiting out the stall window would be waiting for nothing.
        XCTAssertEqual(
            trigger(updatesRunning: false, lastDelivery: now - 120, lastRetry: now - 1),
            .notRunning
        )
    }

    // MARK: - Banner

    func testNoFixEverReadsAsIndoor() {
        XCTAssertEqual(GpsHealth.banner(lastAcceptedFixAge: nil), .noFixYet)
    }

    func testAFreshFixShowsNothing() {
        XCTAssertEqual(GpsHealth.banner(lastAcceptedFixAge: 0), .healthy)
        XCTAssertEqual(GpsHealth.banner(lastAcceptedFixAge: 3), .healthy)
    }

    func testAFixExactlyAtTheThresholdIsStillHealthy() {
        XCTAssertEqual(GpsHealth.banner(lastAcceptedFixAge: GpsHealth.lostSeconds), .healthy)
    }

    func testAnAgedFixReadsAsLost() {
        XCTAssertEqual(
            GpsHealth.banner(lastAcceptedFixAge: GpsHealth.lostSeconds + 0.001),
            .lost
        )
        XCTAssertEqual(GpsHealth.banner(lastAcceptedFixAge: 600), .lost)
    }

    // MARK: - The banner and the retry are told apart by which clock they read

    func testAStreamOfUnusableFixesStallsTheBannerButNotTheRetry() {
        // CoreLocation delivering only low-accuracy fixes: the subsystem is
        // alive (nothing for the retry to heal — a restart cannot clear a tree
        // canopy) while the runner's distance is frozen and the banner must
        // say so. Two clocks, one situation.
        XCTAssertNil(trigger(lastDelivery: now - 1))
        XCTAssertEqual(GpsHealth.banner(lastAcceptedFixAge: 120), .lost)
    }

    func testAWedgedSubsystemHealsAndSaysLostAtTheSameTime() {
        XCTAssertEqual(trigger(lastDelivery: now - 120), .stalled)
        XCTAssertEqual(GpsHealth.banner(lastAcceptedFixAge: 120), .lost)
    }

    // MARK: - Wiring: the recorder stamps the banner's clock from real fixes

    func testRecorderStartsIndoorAndClearsOnTheFirstAcceptedFix() {
        // `WorkoutManager` is side-effect-free until `start()`, and
        // `didUpdateLocations` touches no live CLLocationManager, HealthKit or
        // timer — the same seam `WorkoutManagerDistanceTests` drives.
        let wm = WorkoutManager()
        wm.refreshGpsBanner()
        XCTAssertEqual(wm.gpsBanner, .noFixYet)

        wm.locationManager(CLLocationManager(), didUpdateLocations: [fix(accuracy: 5)])
        wm.refreshGpsBanner()
        XCTAssertEqual(wm.gpsBanner, .healthy)
    }

    func testARejectedFixDoesNotClearTheIndoorBanner() {
        // A 50 m fix is dropped by the accuracy gate, so it banks no distance
        // — telling the runner GPS is fine while the distance sits at zero
        // would be the lie the banner exists to prevent.
        let wm = WorkoutManager()
        wm.locationManager(CLLocationManager(), didUpdateLocations: [fix(accuracy: 50)])
        wm.refreshGpsBanner()
        XCTAssertEqual(wm.gpsBanner, .noFixYet)
    }

    private func fix(accuracy: Double) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 51.5, longitude: -0.1),
            altitude: 10,
            horizontalAccuracy: accuracy,
            verticalAccuracy: 5,
            timestamp: Date()
        )
    }
}
