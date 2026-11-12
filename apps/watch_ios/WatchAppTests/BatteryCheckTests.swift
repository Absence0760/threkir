import XCTest
@testable import WatchApp

/// The pre-run low-battery advice — Wear OS's `BatteryStatus` on the other
/// wrist. A simulator reports no battery level (it answers -1), so the read
/// itself is device-gated; the rule over the level is pinned here.
final class BatteryCheckTests: XCTestCase {

    func testTheThresholdIsWearOSs() {
        XCTAssertEqual(BatteryCheck.lowThresholdPercent, 40,
                       "Wear's LOW_THRESHOLD_PERCENT — the two wrists give the same advice")
    }

    func testAnUnreportedLevelWarnsOfNothing() {
        XCTAssertNil(BatteryCheck.percent(fromLevel: -1), "monitoring off, or a simulator")
        XCTAssertNil(BatteryCheck.percent(fromLevel: .nan))
        XCTAssertNil(BatteryCheck.percent(fromLevel: 1.5))
        XCTAssertNil(BatteryCheck.warningPercent(fromLevel: -1))
    }

    func testTheLevelIsAWholePercent() {
        XCTAssertEqual(BatteryCheck.percent(fromLevel: 0), 0)
        XCTAssertEqual(BatteryCheck.percent(fromLevel: 0.391), 39)
        XCTAssertEqual(BatteryCheck.percent(fromLevel: 1), 100)
    }

    func testBelowTheThresholdWarns() {
        XCTAssertEqual(BatteryCheck.warningPercent(fromLevel: 0.39), 39)
        XCTAssertEqual(BatteryCheck.warningPercent(fromLevel: 0.05), 5)
    }

    func testAtOrAboveTheThresholdIsQuiet() {
        XCTAssertNil(BatteryCheck.warningPercent(fromLevel: 0.40))
        XCTAssertNil(BatteryCheck.warningPercent(fromLevel: 0.80))
    }
}
