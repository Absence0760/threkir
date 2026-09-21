import EventKit
import XCTest

@testable import Runner

/// Pins `CalendarBridge.recurrenceRule(from:)` against the RRULE grammar
/// `lib/calendar_intent.dart`'s `buildRrule` emits, and against decisions § 692:
/// a value outside that subset must yield NO rule rather than a different one.
/// Nothing downstream can catch a wrong-but-plausible parse — the system editor
/// would simply state a series the club page never agreed to — so the negative
/// cases below carry as much weight as the positive ones.
final class CalendarBridgeRruleTests: XCTestCase {

    private func rule(
        _ value: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> EKRecurrenceRule {
        try XCTUnwrap(
            CalendarBridge.recurrenceRule(from: value),
            "expected a rule for \(value)",
            file: file,
            line: line
        )
    }

    private func assertNoRule(
        _ value: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertNil(
            CalendarBridge.recurrenceRule(from: value),
            "expected no rule for \(value)",
            file: file,
            line: line
        )
    }

    private func weekdays(_ rule: EKRecurrenceRule) -> [EKWeekday] {
        (rule.daysOfTheWeek ?? []).map { $0.dayOfTheWeek }
    }

    // MARK: - The subset buildRrule emits

    func testPlainWeekly() throws {
        let r = try rule("FREQ=WEEKLY")
        XCTAssertEqual(r.frequency, .weekly)
        XCTAssertEqual(r.interval, 1)
        XCTAssertTrue(weekdays(r).isEmpty)
        XCTAssertTrue(r.daysOfTheMonth?.isEmpty ?? true)
        XCTAssertNil(r.recurrenceEnd)
    }

    func testWeeklyByDayKeepsTheEmittedOrder() throws {
        let r = try rule("FREQ=WEEKLY;BYDAY=MO,WE,FR")
        XCTAssertEqual(r.frequency, .weekly)
        XCTAssertEqual(weekdays(r), [.monday, .wednesday, .friday])
    }

    func testEveryWeekdayCodeMaps() throws {
        let r = try rule("FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR,SA,SU")
        XCTAssertEqual(
            weekdays(r),
            [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday]
        )
    }

    func testBiweeklyIsIntervalTwo() throws {
        let r = try rule("FREQ=WEEKLY;INTERVAL=2;BYDAY=SA")
        XCTAssertEqual(r.frequency, .weekly)
        XCTAssertEqual(r.interval, 2)
        XCTAssertEqual(weekdays(r), [.saturday])
    }

    func testWeeklyCountBecomesOccurrenceCount() throws {
        let r = try rule("FREQ=WEEKLY;COUNT=8;BYDAY=MO")
        XCTAssertEqual(r.recurrenceEnd?.occurrenceCount, 8)
        XCTAssertNil(r.recurrenceEnd?.endDate)
    }

    func testWeeklyUntilIsReadAsUtc() throws {
        let r = try rule("FREQ=WEEKLY;UNTIL=20261231T090000Z;BYDAY=WE")
        let end = try XCTUnwrap(r.recurrenceEnd?.endDate)
        var components = DateComponents()
        components.year = 2026
        components.month = 12
        components.day = 31
        components.hour = 9
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let expected = try XCTUnwrap(calendar.date(from: components))
        XCTAssertEqual(end.timeIntervalSince1970, expected.timeIntervalSince1970, accuracy: 1)
    }

    func testMonthlyByMonthDay() throws {
        let r = try rule("FREQ=MONTHLY;BYMONTHDAY=15")
        XCTAssertEqual(r.frequency, .monthly)
        XCTAssertEqual(r.interval, 1)
        XCTAssertEqual(r.daysOfTheMonth, [15])
        XCTAssertTrue(weekdays(r).isEmpty)
    }

    func testMonthlyWithCount() throws {
        let r = try rule("FREQ=MONTHLY;COUNT=3;BYMONTHDAY=1")
        XCTAssertEqual(r.daysOfTheMonth, [1])
        XCTAssertEqual(r.recurrenceEnd?.occurrenceCount, 3)
    }

    func testLowercaseIsTolerated() throws {
        let r = try rule("freq=weekly;interval=2;byday=tu,th")
        XCTAssertEqual(r.frequency, .weekly)
        XCTAssertEqual(r.interval, 2)
        XCTAssertEqual(weekdays(r), [.tuesday, .thursday])
    }

    func testMonthlyPastTheTwentyEighthParsesFaithfully() throws {
        // `buildRrule` refuses to EMIT this shape — BYMONTHDAY has no clamp, so
        // a 31st series skips February outright. The refusal belongs there, not
        // here: this parser's job is to restate an RRULE exactly or not at all.
        let r = try rule("FREQ=MONTHLY;BYMONTHDAY=31")
        XCTAssertEqual(r.daysOfTheMonth, [31])
    }

    // MARK: - Outside the subset: no rule, never a different one

    func testFrequenciesBuildRruleNeverEmitsYieldNoRule() {
        assertNoRule("FREQ=DAILY")
        assertNoRule("FREQ=YEARLY")
        assertNoRule("FREQ=HOURLY;INTERVAL=6")
        assertNoRule("FREQ=WEEKLYISH")
    }

    func testMissingFreqYieldsNoRule() {
        assertNoRule("")
        assertNoRule("BYDAY=MO")
        assertNoRule("INTERVAL=2;COUNT=4")
    }

    func testRrulePrefixYieldsNoRule() {
        // The Dart side sends the VALUE, with no `RRULE:` prefix. A prefixed
        // string parses its first field as `RRULE:FREQ`, leaving FREQ unset —
        // pinned so the two sides can never drift into a silent one-off.
        assertNoRule("RRULE:FREQ=WEEKLY;BYDAY=MO")
    }

    func testMonthlyWithoutAUsableMonthDayYieldsNoRule() {
        assertNoRule("FREQ=MONTHLY")
        assertNoRule("FREQ=MONTHLY;BYMONTHDAY=0")
        assertNoRule("FREQ=MONTHLY;BYMONTHDAY=32")
        assertNoRule("FREQ=MONTHLY;BYMONTHDAY=-1")
        assertNoRule("FREQ=MONTHLY;BYMONTHDAY=LAST")
        assertNoRule("FREQ=MONTHLY;BYDAY=2MO")
    }

    func testUnknownWeekdayCodeYieldsNoRule() {
        // Dropping the unknown code and keeping the rest would state a narrower
        // series than the string does — the exact failure § 692 forbids.
        assertNoRule("FREQ=WEEKLY;BYDAY=XX")
        assertNoRule("FREQ=WEEKLY;BYDAY=MO,XX")
        assertNoRule("FREQ=WEEKLY;BYDAY=MON")
        assertNoRule("FREQ=WEEKLY;BYDAY=1MO")
    }

    func testUnusableCountYieldsNoRule() {
        assertNoRule("FREQ=WEEKLY;COUNT=0;BYDAY=MO")
        assertNoRule("FREQ=WEEKLY;COUNT=-2;BYDAY=MO")
        assertNoRule("FREQ=WEEKLY;COUNT=many;BYDAY=MO")
        assertNoRule("FREQ=WEEKLY;COUNT=3.5;BYDAY=MO")
    }

    func testUnusableIntervalYieldsNoRule() {
        assertNoRule("FREQ=WEEKLY;INTERVAL=0;BYDAY=MO")
        assertNoRule("FREQ=WEEKLY;INTERVAL=-1;BYDAY=MO")
        // A non-integer INTERVAL must not fall through to 1: that turns an
        // unreadable series into a confident weekly one.
        assertNoRule("FREQ=WEEKLY;INTERVAL=two;BYDAY=MO")
        assertNoRule("FREQ=WEEKLY;INTERVAL=1.5;BYDAY=MO")
    }

    func testUnparseableUntilYieldsNoRule() {
        assertNoRule("FREQ=WEEKLY;UNTIL=2026-12-31T09:00:00Z;BYDAY=MO")
        assertNoRule("FREQ=WEEKLY;UNTIL=20261231;BYDAY=MO")
        assertNoRule("FREQ=WEEKLY;UNTIL=20261331T090000Z;BYDAY=MO")
    }

    func testCountWinsWhenBothEndsArePresent() throws {
        // RFC 5545 § 3.3.10 forbids both and `buildRrule` never emits both, so
        // this only pins that the outcome is deterministic rather than a rule
        // carrying two contradictory ends.
        let r = try rule("FREQ=WEEKLY;COUNT=4;UNTIL=20261231T090000Z;BYDAY=MO")
        XCTAssertEqual(r.recurrenceEnd?.occurrenceCount, 4)
        XCTAssertNil(r.recurrenceEnd?.endDate)
    }
}
