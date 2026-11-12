import XCTest
@testable import WatchApp

/// The press that has to be held before Stop ends the recording.
final class HoldToStopTests: XCTestCase {

    /// One number decides whether a brush against a sleeve ends a run, and it
    /// is the one Wear OS has required since it shipped.
    func testDurationMatchesWearOS() {
        XCTAssertEqual(HoldToStop.duration, 0.8, accuracy: 1e-9)
    }

    func testProgressFillsLinearlyAcrossTheHold() {
        XCTAssertEqual(HoldToStop.progress(elapsed: 0), 0, accuracy: 1e-9)
        XCTAssertEqual(HoldToStop.progress(elapsed: 0.2), 0.25, accuracy: 1e-9)
        XCTAssertEqual(HoldToStop.progress(elapsed: 0.4), 0.5, accuracy: 1e-9)
        XCTAssertEqual(HoldToStop.progress(elapsed: 0.8), 1, accuracy: 1e-9)
    }

    func testProgressClampsAtOne() {
        XCTAssertEqual(HoldToStop.progress(elapsed: 5), 1, accuracy: 1e-9)
    }

    /// A ring drawn from an unreadable clock must read as empty, not as
    /// nearly done: it is the only thing telling the runner how much longer
    /// to hold.
    func testAnUnreadableClockReadsAsNoProgress() {
        XCTAssertEqual(HoldToStop.progress(elapsed: -1), 0, accuracy: 1e-9)
        XCTAssertEqual(HoldToStop.progress(elapsed: .nan), 0, accuracy: 1e-9)
        XCTAssertEqual(HoldToStop.progress(elapsed: .infinity), 0, accuracy: 1e-9)
        XCTAssertEqual(HoldToStop.progress(elapsed: -.infinity), 0, accuracy: 1e-9)
        XCTAssertFalse(HoldToStop.isComplete(elapsed: .infinity))
    }

    func testStopFiresOnlyOnceTheFullDurationIsHeld() {
        XCTAssertFalse(HoldToStop.isComplete(elapsed: 0))
        XCTAssertFalse(HoldToStop.isComplete(elapsed: 0.79))
        XCTAssertTrue(HoldToStop.isComplete(elapsed: 0.8), "the boundary is inclusive")
        XCTAssertTrue(HoldToStop.isComplete(elapsed: 3))
    }

    /// Releasing early is the absence of further progress — the control
    /// cancels its own task and starts the next press from zero, so a
    /// half-finished hold must never count toward the following one.
    func testAReleasedHoldLeavesNothingBanked() {
        XCTAssertFalse(HoldToStop.isComplete(elapsed: 0.6))
        XCTAssertEqual(HoldToStop.progress(elapsed: 0.2), 0.25, accuracy: 1e-9)
    }
}
