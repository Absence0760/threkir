import XCTest
@testable import WatchApp

/// The 3-2-1 window between the Start tap and the run.
///
/// Mirrors Wear OS's countdown, whose digits are asserted nowhere because they
/// live in a composable. The one thing that matters is which tick starts the
/// recording, and that is what these drive.
final class StartCountdownTests: XCTestCase {

    func testStartsAtThreeAndIsNotFinished() {
        let countdown = StartCountdown()
        XCTAssertEqual(countdown.count, 3)
        XCTAssertEqual(StartCountdown.initialCount, 3)
        XCTAssertFalse(countdown.isFinished)
    }

    func testCountsDownThreeTwoOneThenFires() {
        var countdown = StartCountdown()
        XCTAssertFalse(countdown.tick())
        XCTAssertEqual(countdown.count, 2)
        XCTAssertFalse(countdown.tick())
        XCTAssertEqual(countdown.count, 1)
        XCTAssertTrue(countdown.tick(), "the third tick is the one that starts the run")
        XCTAssertEqual(countdown.count, 0)
        XCTAssertTrue(countdown.isFinished)
    }

    /// A duplicated or late timer fire after the count has run out must not
    /// report a second start: the overlay's completion handler calls
    /// `WorkoutManager.start()`, which resets the run id and the track.
    func testTickingPastZeroNeverFiresAgain() {
        var countdown = StartCountdown()
        _ = countdown.tick()
        _ = countdown.tick()
        XCTAssertTrue(countdown.tick())
        for _ in 0..<5 {
            XCTAssertFalse(countdown.tick())
            XCTAssertEqual(countdown.count, 0, "the count must not run negative")
        }
    }

    /// Cancelling is the absence of further ticks, not a state of its own —
    /// the overlay is dropped and a fresh value counts the next attempt from
    /// the top.
    func testANewCountdownStartsFromTheTopAgain() {
        var countdown = StartCountdown()
        _ = countdown.tick()
        XCTAssertEqual(countdown.count, 2)
        countdown = StartCountdown()
        XCTAssertEqual(countdown.count, 3)
        XCTAssertFalse(countdown.isFinished)
    }
}
