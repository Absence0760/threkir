import XCTest

@testable import Runner

/// Host tests for the one seam of the Live Activity bridge that can run
/// without ActivityKit: the decode from the method channel's argument map
/// into `RunActivityAttributes.ContentState`.
///
/// `Activity.request` cannot be exercised here — it needs a real device or
/// simulator session with Live Activities enabled and a widget extension
/// loaded — so what is pinned is the boundary that decides whether an update
/// reaches the lock screen at all, and its fail-closed contract: a frame
/// missing a field is dropped whole rather than rendered with a blank in it.
@available(iOS 16.2, *)
final class LiveActivityBridgeTests: XCTestCase {

    private func args(
        omitting missing: String? = nil,
        overriding overrides: [String: Any] = [:]
    ) -> [String: Any] {
        var out: [String: Any] = [
            "title": "Run",
            "paused": NSNumber(value: false),
            "timer_start_epoch_ms": NSNumber(value: 1_700_000_000_000 as Int64),
            "elapsed_text": "00:42",
            "time_label": "Time",
            "distance_label": "Distance",
            "distance_text": "1.20 km",
            "pace_label": "Pace",
            "pace_text": "5:30 /km",
        ]
        if let missing { out.removeValue(forKey: missing) }
        out.merge(overrides) { _, new in new }
        return out
    }

    func testDecodesEveryRenderedField() throws {
        let state = try XCTUnwrap(RunActivityAttributes.ContentState(arguments: args()))
        XCTAssertEqual(state.title, "Run")
        XCTAssertFalse(state.paused)
        XCTAssertEqual(state.elapsedText, "00:42")
        XCTAssertEqual(state.timeLabel, "Time")
        XCTAssertEqual(state.distanceLabel, "Distance")
        XCTAssertEqual(state.distanceText, "1.20 km")
        XCTAssertEqual(state.paceLabel, "Pace")
        XCTAssertEqual(state.paceText, "5:30 /km")
    }

    /// The anchor crosses the channel in milliseconds because that is what
    /// `DateTime.millisecondsSinceEpoch` is, and it is past the 32-bit range:
    /// reading it as an `Int` rather than an `NSNumber` would truncate on the
    /// way in and put the run's clock decades out.
    func testTimerAnchorSurvivesMillisecondPrecision() throws {
        let state = try XCTUnwrap(RunActivityAttributes.ContentState(arguments: args()))
        XCTAssertEqual(state.timerStart.timeIntervalSince1970, 1_700_000_000, accuracy: 0.001)
    }

    func testPausedFlagDecodes() throws {
        let state = try XCTUnwrap(
            RunActivityAttributes.ContentState(
                arguments: args(overriding: ["paused": NSNumber(value: true)])
            )
        )
        XCTAssertTrue(state.paused)
    }

    /// Absent rather than false is what a hand-rolled or older payload looks
    /// like; a missing pause flag must read as running, not crash the decode.
    func testAbsentPausedFlagReadsAsRunning() throws {
        let state = try XCTUnwrap(
            RunActivityAttributes.ContentState(arguments: args(omitting: "paused"))
        )
        XCTAssertFalse(state.paused)
    }

    func testAnyMissingRenderedFieldDropsTheWholeFrame() {
        for key in [
            "title",
            "timer_start_epoch_ms",
            "elapsed_text",
            "time_label",
            "distance_label",
            "distance_text",
            "pace_label",
            "pace_text",
        ] {
            XCTAssertNil(
                RunActivityAttributes.ContentState(arguments: args(omitting: key)),
                "a frame missing \(key) must be dropped, not rendered with a gap"
            )
        }
    }

    func testAWronglyTypedFieldDropsTheFrame() {
        XCTAssertNil(
            RunActivityAttributes.ContentState(
                arguments: args(overriding: ["distance_text": NSNumber(value: 1200)])
            )
        )
        XCTAssertNil(
            RunActivityAttributes.ContentState(
                arguments: args(overriding: ["timer_start_epoch_ms": "1700000000000"])
            )
        )
    }

    func testDecodesAWorkoutStep() throws {
        let state = try XCTUnwrap(
            RunActivityAttributes.ContentState(
                arguments: args(overriding: [
                    "step_title": "Rep 3 of 6",
                    "step_remaining_text": "400 m to go",
                    "step_target": "@ 4:00 /km",
                    "step_end_epoch_ms": NSNumber(value: 1_700_000_090_000 as Int64),
                ])
            )
        )
        XCTAssertEqual(state.stepTitle, "Rep 3 of 6")
        XCTAssertEqual(state.stepRemainingText, "400 m to go")
        XCTAssertEqual(state.stepTarget, "@ 4:00 /km")
        let end = try XCTUnwrap(state.stepEnd)
        XCTAssertEqual(end.timeIntervalSince1970, 1_700_000_090, accuracy: 0.001)
    }

    /// A free run sends no step keys at all, and neither did any frame built
    /// before the step line existed: both must still decode, with no step.
    func testAFrameWithoutAStepStillDecodes() throws {
        let state = try XCTUnwrap(RunActivityAttributes.ContentState(arguments: args()))
        XCTAssertNil(state.stepTitle)
        XCTAssertNil(state.stepRemainingText)
        XCTAssertNil(state.stepTarget)
        XCTAssertNil(state.stepEnd)
    }

    /// The step line is the optional part of the frame: a wrongly typed step
    /// field loses that field, not the run stats.
    func testAWronglyTypedStepFieldDropsOnlyThatField() throws {
        let state = try XCTUnwrap(
            RunActivityAttributes.ContentState(
                arguments: args(overriding: [
                    "step_title": "Walk",
                    "step_end_epoch_ms": "1700000090000",
                ])
            )
        )
        XCTAssertEqual(state.stepTitle, "Walk")
        XCTAssertNil(state.stepEnd)
        XCTAssertEqual(state.distanceText, "1.20 km")
    }

    /// ActivityKit persists the content state as JSON; one encoded before the
    /// step fields existed must decode into the current shape.
    func testContentStateEncodedWithoutStepFieldsDecodes() throws {
        let legacy = """
        {"title":"Run","paused":false,"timerStart":0,"elapsedText":"00:42",
         "timeLabel":"Time","distanceLabel":"Distance","distanceText":"1.20 km",
         "paceLabel":"Pace","paceText":"5:30 /km"}
        """
        let state = try JSONDecoder().decode(
            RunActivityAttributes.ContentState.self,
            from: Data(legacy.utf8)
        )
        XCTAssertEqual(state.paceText, "5:30 /km")
        XCTAssertNil(state.stepTitle)
    }
}
