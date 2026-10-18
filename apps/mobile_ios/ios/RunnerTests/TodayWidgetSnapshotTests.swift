import XCTest

@testable import Runner

private let planId = "0b5f3f2e-6a4d-4a8f-9a57-7f0c2c1d9e10"
private let workoutId = "5d1c9a7e-2b3f-4c6d-8e9f-0a1b2c3d4e5f"

/// The Today widget's pure half: decoding Dart's snapshot, choosing what a
/// given local day shows, the tap targets, the midnight schedule, and the
/// bridge's write to the App Group.
///
/// `TodayWidgetSnapshot.swift` is a member of both `Runner` and the
/// `RunActivityExtension`, so `@testable import Runner` reaches the source the
/// widget runs. What it does not reach is `TodayWorkoutWidget.swift` — the
/// views and the provider — which is compiled-only: nothing here is evidence
/// that the widget renders.
final class TodayWidgetSnapshotTests: XCTestCase {

    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    /// 2026-10-18 09:00 UTC.
    private var morning: Date {
        utc.date(from: DateComponents(year: 2026, month: 10, day: 18, hour: 9))!
    }

    private let labels: [String: Any] = [
        "header": "Today",
        "no_plan": "No training plan",
        "no_plan_action": "Pick a plan",
        "nothing_scheduled": "Nothing scheduled",
        "stale": "Open Threkir to update",
        "rest_day": "Rest day",
        "done": "Done",
        "skipped": "Skipped",
    ]

    private func day(
        _ date: String,
        _ state: String,
        title: String = "Tempo run",
        detail: String = "8 km · 4:45 /km",
        workout: String? = nil
    ) -> [String: Any] {
        var d: [String: Any] = ["date": date, "state": state, "title": title, "detail": detail]
        if let workout { d["plan_workout_id"] = workout }
        return d
    }

    private func json(_ object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object)
        return try XCTUnwrap(String(data: data, encoding: .utf8))
    }

    private func snapshot(
        v: Any = 1,
        plan: String? = planId,
        labels: [String: Any]? = nil,
        days: [[String: Any]]
    ) throws -> String {
        var o: [String: Any] = ["v": v, "written_at_ms": 1_760_000_000_000, "days": days]
        if let plan { o["plan_id"] = plan }
        o["labels"] = labels ?? self.labels
        return try json(o)
    }

    private func content(_ json: String?, on date: Date? = nil) -> TodayWidgetContent {
        TodayWidgetContent.of(TodayWidgetSnapshot.decode(json), on: date ?? morning, calendar: utc)
    }

    // MARK: - The day's state

    func testTodaysWorkoutShowsItsWordsAndOpensTheWorkout() throws {
        let c = content(try snapshot(days: [day("2026-10-18", "workout", workout: workoutId)]))
        XCTAssertEqual(c.kind, .workout)
        XCTAssertEqual(c.header, "Today")
        XCTAssertEqual(c.title, "Tempo run")
        XCTAssertEqual(c.detail, "8 km · 4:45 /km")
        XCTAssertNil(c.badge)
        XCTAssertEqual(c.url?.absoluteString, "com.threkir.app://plans/\(planId)/workouts/\(workoutId)")
    }

    func testDoneAndSkippedCarryTheirBadgeAndStillOpenTheWorkout() throws {
        let done = content(try snapshot(days: [day("2026-10-18", "done", workout: workoutId)]))
        XCTAssertEqual(done.kind, .done)
        XCTAssertEqual(done.badge, "Done")
        XCTAssertEqual(done.url?.absoluteString, "com.threkir.app://plans/\(planId)/workouts/\(workoutId)")

        let skipped = content(try snapshot(days: [day("2026-10-18", "skipped", workout: workoutId)]))
        XCTAssertEqual(skipped.kind, .skipped)
        XCTAssertEqual(skipped.badge, "Skipped")
    }

    func testRestDayFallsBackToItsLabelAndOpensThePlan() throws {
        let c = content(try snapshot(days: [day("2026-10-18", "rest", title: "", detail: "")]))
        XCTAssertEqual(c.kind, .rest)
        XCTAssertEqual(c.title, "Rest day")
        XCTAssertEqual(c.url?.absoluteString, "com.threkir.app://plans/\(planId)")
    }

    func testARestDayWithItsOwnTitleKeepsIt() throws {
        let c = content(try snapshot(days: [day("2026-10-18", "rest", title: "Recovery day")]))
        XCTAssertEqual(c.title, "Recovery day")
    }

    func testAnUncoveredDaySaysNothingScheduled() throws {
        let c = content(try snapshot(days: [day("2026-10-18", "none", title: "", detail: "")]))
        XCTAssertEqual(c.kind, .nothingScheduled)
        XCTAssertEqual(c.title, "Nothing scheduled")
        XCTAssertEqual(c.url?.absoluteString, "com.threkir.app://plans/\(planId)")
    }

    func testNoPlanSaysSoAndOpensThePlansList() throws {
        let c = content(try snapshot(plan: nil, days: []))
        XCTAssertEqual(c.kind, .noPlan)
        XCTAssertEqual(c.title, "No training plan")
        XCTAssertEqual(c.detail, "Pick a plan")
        XCTAssertEqual(c.url?.absoluteString, "com.threkir.app://plans")
    }

    func testAnEmptyPlanIdIsNoPlan() throws {
        XCTAssertEqual(content(try snapshot(plan: "", days: [])).kind, .noPlan)
    }

    // MARK: - Picking the day

    func testTheEntryForTheLocalDayIsChosen() throws {
        let week = [
            day("2026-10-18", "rest", title: ""),
            day("2026-10-19", "workout", title: "Intervals", workout: workoutId),
        ]
        XCTAssertEqual(content(try snapshot(days: week)).kind, .rest)
        let tomorrow = morning.addingTimeInterval(86_400)
        XCTAssertEqual(content(try snapshot(days: week), on: tomorrow).title, "Intervals")
    }

    func testTheDayIsTheDevicesOwnZone() throws {
        // 23:30 UTC on the 17th is already the 18th in Auckland.
        let late = utc.date(from: DateComponents(year: 2026, month: 10, day: 17, hour: 23, minute: 30))!
        var auckland = utc
        auckland.timeZone = TimeZone(identifier: "Pacific/Auckland")!
        let s = TodayWidgetSnapshot.decode(try snapshot(days: [day("2026-10-18", "workout", workout: workoutId)]))
        XCTAssertEqual(TodayWidgetContent.of(s, on: late, calendar: utc).kind, .stale)
        XCTAssertEqual(TodayWidgetContent.of(s, on: late, calendar: auckland).kind, .workout)
    }

    func testANonGregorianPhoneStillMatchesTheDay() {
        var buddhist = Calendar(identifier: .buddhist)
        buddhist.timeZone = utc.timeZone
        XCTAssertEqual(TodayWidget.dayString(morning, calendar: buddhist), "2026-10-18")
    }

    func testAPlanWithNoEntryForTodayIsStale() throws {
        let c = content(try snapshot(days: [day("2026-10-11", "workout", workout: workoutId)]))
        XCTAssertEqual(c.kind, .stale)
        XCTAssertEqual(c.title, "Open Threkir to update")
        XCTAssertEqual(c.url?.absoluteString, "com.threkir.app://plans/\(planId)")
    }

    func testAnUnknownStateIsStaleForThatDayOnly() throws {
        let week = [
            day("2026-10-18", "moved"),
            day("2026-10-19", "workout", workout: workoutId),
        ]
        XCTAssertEqual(content(try snapshot(days: week)).kind, .stale)
        XCTAssertEqual(content(try snapshot(days: week), on: morning.addingTimeInterval(86_400)).kind, .workout)
    }

    func testAMalformedDayCostsOnlyThatDay() throws {
        let week: [[String: Any]] = [
            ["date": 20261018, "state": "workout"],
            day("2026-10-19", "workout", workout: workoutId),
        ]
        XCTAssertEqual(content(try snapshot(days: week), on: morning.addingTimeInterval(86_400)).kind, .workout)
    }

    // MARK: - Versions and unreadable snapshots

    func testAnotherVersionIsStaleNeverAGuess() throws {
        let c = content(try snapshot(v: 2, days: [day("2026-10-18", "workout", workout: workoutId)]))
        XCTAssertEqual(c.kind, .stale)
        XCTAssertEqual(c.title, "Open Threkir to update")
    }

    func testAnotherVersionWithNoReadableLabelsIsEmpty() throws {
        let c = content(try snapshot(v: 2, labels: ["stale": 7], days: []))
        XCTAssertEqual(c, .empty)
    }

    func testNothingStoredOrUnreadableIsEmpty() throws {
        XCTAssertEqual(content(nil), .empty)
        XCTAssertEqual(content("not json"), .empty)
        XCTAssertEqual(content("{}"), .empty)
        XCTAssertNil(content(nil).url, "the empty state's tap just opens the app")
    }

    func testABooleanVersionIsNotOne() throws {
        // JSONSerialization would read `true` as 1; the decoder must not.
        XCTAssertEqual(content(try snapshot(v: true, days: [])), .empty)
    }

    func testAVersionOneSnapshotWithoutLabelsIsEmpty() throws {
        var o: [String: Any] = ["v": 1, "plan_id": planId, "days": [day("2026-10-18", "workout")]]
        o["labels"] = ["header": "Today"]
        XCTAssertEqual(content(try json(o)), .empty)
    }

    // MARK: - Tap targets

    func testAnIdThatIsNotAUuidShapeFallsBackRatherThanEscaping() throws {
        let c = content(try snapshot(days: [day("2026-10-18", "workout", workout: "../../settings")]))
        XCTAssertEqual(c.url?.absoluteString, "com.threkir.app://plans/\(planId)")
        let noPlanURL = content(try snapshot(plan: "a b", days: [day("2026-10-18", "rest")]))
        XCTAssertEqual(noPlanURL.url?.absoluteString, "com.threkir.app://plans")
    }

    func testAWorkoutWithNoIdOpensThePlan() throws {
        let c = content(try snapshot(days: [day("2026-10-18", "workout")]))
        XCTAssertEqual(c.url?.absoluteString, "com.threkir.app://plans/\(planId)")
    }

    func testTheSchemeIsOneTheAppRegisters() throws {
        let types = try XCTUnwrap(try plist("Runner/Info.plist")["CFBundleURLTypes"] as? [[String: Any]])
        let schemes = types.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
        XCTAssertTrue(schemes.contains(TodayWidget.urlScheme), "registered: \(schemes)")
    }

    // MARK: - The inline line

    func testInlineLinePrefersTheBadgeOverTheDetail() throws {
        let done = content(try snapshot(days: [day("2026-10-18", "done", workout: workoutId)]))
        XCTAssertEqual(done.line, "Tempo run · Done")
        let rest = content(try snapshot(days: [day("2026-10-18", "rest", title: "", detail: "")]))
        XCTAssertEqual(rest.line, "Rest day")
    }

    // MARK: - Timeline

    func testTimelineIsNowThenSevenLocalMidnights() {
        let dates = TodayWidget.timelineDates(from: morning, calendar: utc)
        XCTAssertEqual(dates.count, 1 + TodayWidget.coveredDays)
        XCTAssertEqual(dates.first, morning)
        for (i, d) in dates.dropFirst().enumerated() {
            let want = utc.date(from: DateComponents(year: 2026, month: 10, day: 19 + i))!
            XCTAssertEqual(d, want, "midnight \(i + 1)")
        }
    }

    func testMidnightsFollowTheZoneAcrossADaylightSavingChange() {
        // Europe/London leaves summer time at 02:00 on 2026-10-25, so the
        // week from the 22nd holds one 25-hour day.
        var london = utc
        london.timeZone = TimeZone(identifier: "Europe/London")!
        let start = london.date(from: DateComponents(year: 2026, month: 10, day: 22, hour: 9))!
        let dates = TodayWidget.timelineDates(from: start, calendar: london)
        XCTAssertEqual(dates.count, 1 + TodayWidget.coveredDays)
        for d in dates.dropFirst() {
            let c = london.dateComponents([.hour, .minute], from: d)
            XCTAssertEqual(c.hour, 0)
            XCTAssertEqual(c.minute, 0)
        }
    }

    func testTheLastEntryOfAWeekOldSnapshotIsStale() throws {
        let week = (0..<7).map { day(String(format: "2026-10-%02d", 18 + $0), "workout", workout: workoutId) }
        let s = TodayWidgetSnapshot.decode(try snapshot(days: week))
        let dates = TodayWidget.timelineDates(from: morning, calendar: utc)
        let kinds = dates.map { TodayWidgetContent.of(s, on: $0, calendar: utc).kind }
        XCTAssertEqual(Array(kinds.dropLast()), Array(repeating: .workout, count: 7))
        XCTAssertEqual(kinds.last, .stale)
    }

    // MARK: - The bridge's write

    func testStoreWritesAndClearsTheSnapshot() throws {
        let suite = "TodayWidgetSnapshotTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertTrue(HomeWidgetBridge.shared.store("{\"v\":1}", in: defaults))
        XCTAssertEqual(TodayWidget.storedJSON(in: defaults), "{\"v\":1}")
        XCTAssertTrue(HomeWidgetBridge.shared.store(nil, in: defaults))
        XCTAssertNil(TodayWidget.storedJSON(in: defaults))
    }

    func testStoreReportsAnUnavailableGroup() {
        XCTAssertFalse(HomeWidgetBridge.shared.store("{}", in: nil))
    }

    // MARK: - The App Group, spelled in three places

    /// `<repo>/apps/mobile_ios/ios`.
    private static let iosRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    /// Read off disk, as `ShareExtensionHandoffTests` does: entitlements never
    /// appear in a bundle.
    private func plist(_ relativePath: String) throws -> [String: Any] {
        let data = try Data(contentsOf: Self.iosRoot.appendingPathComponent(relativePath))
        let parsed = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        return try XCTUnwrap(parsed as? [String: Any], "\(relativePath) is not a dictionary")
    }

    private func appGroups(inEntitlements relativePath: String) throws -> [String] {
        try XCTUnwrap(
            try plist(relativePath)["com.apple.security.application-groups"] as? [String],
            "\(relativePath) declares no com.apple.security.application-groups array"
        )
    }

    func testBothEntitlementsCarryTheWidgetGroup() throws {
        XCTAssertTrue(try appGroups(inEntitlements: "Runner/Runner.entitlements").contains(TodayWidget.appGroup))
        XCTAssertEqual(try appGroups(inEntitlements: "RunActivity/RunActivity.entitlements"), [TodayWidget.appGroup])
    }
}
