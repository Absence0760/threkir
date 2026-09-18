import XCTest
@testable import WatchApp

/// The recording stack's GPS self-heal retry decision.
///
/// **Host-tested only, and that is the honest ceiling.** A watchOS simulator
/// serves whatever location Xcode is configured to serve; it does not wedge
/// CoreLocation and does not stop delivering mid-run. Neither trigger these
/// cases describe can be produced there, so a decision function driven over
/// synthetic uptimes is the only coverage that proves anything. Nothing here is
/// evidence that a real dropout heals on a wrist.
///
/// Mirrors Wear OS's `GpsRetryDecisionTest.kt`.
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
        // restart CoreLocation every 30 s for an hour and find nothing each time.
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
}
