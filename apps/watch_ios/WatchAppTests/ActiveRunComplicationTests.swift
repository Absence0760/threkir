import XCTest
@testable import WatchApp

/// The complication's own coverage.
///
/// `Complications/ActiveRunTimeline.swift` and `WatchApp/RunFormat.swift` are
/// members of BOTH the `WatchAppComplication` extension and the `WatchApp`
/// target, so `@testable import WatchApp` reaches the same source the watch
/// face executes rather than a second copy of it. What it does NOT reach is
/// `ActiveRunComplication.swift` — that file declares the `@main` widget
/// bundle and cannot be a member of the app target, so the views, the
/// `supportedFamilies` list and the widget's `kind` are still compiled-only.
/// Nothing here is evidence that a complication renders on a watch face; see
/// docs/custom_watch/quality_standards.md for the rungs.
final class ActiveRunTimelineTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func snapshot(
        isActive: Bool = true,
        elapsedSeconds: Int = 600,
        distanceMeters: Double = 2000,
        paceSecPerKm: Double? = 300,
        ageSeconds: TimeInterval = 5,
    ) -> ActiveRunSnapshot {
        ActiveRunSnapshot(
            isActive: isActive,
            elapsedSeconds: elapsedSeconds,
            distanceMeters: distanceMeters,
            paceSecPerKm: paceSecPerKm,
            lastUpdatedEpoch: now.timeIntervalSince1970 - ageSeconds,
        )
    }

    // MARK: - entry(from:now:)

    func testEntryCarriesTheSnapshotThrough() {
        let e = ActiveRunTimeline.entry(from: snapshot(), now: now)
        XCTAssertTrue(e.isActive)
        XCTAssertEqual(e.date, now)
        XCTAssertEqual(e.elapsedSeconds, 600)
        XCTAssertEqual(e.distanceMeters, 2000, accuracy: 0.0001)
        XCTAssertEqual(e.paceSecPerKm, 300)
    }

    func testEmptySnapshotIsInactive() {
        let e = ActiveRunTimeline.entry(from: .empty, now: now)
        XCTAssertFalse(e.isActive)
        XCTAssertEqual(e.elapsedSeconds, 0)
        XCTAssertNil(e.paceSecPerKm)
    }

    func testInactiveSnapshotStaysInactiveHoweverFresh() {
        let e = ActiveRunTimeline.entry(from: snapshot(isActive: false, ageSeconds: 0), now: now)
        XCTAssertFalse(e.isActive)
    }

    func testStaleActiveSnapshotReadsInactive() {
        // 25 hours old and still flagged active — the phantom a crashed host
        // app leaves behind.
        let e = ActiveRunTimeline.entry(from: snapshot(ageSeconds: 25 * 3600), now: now)
        XCTAssertFalse(e.isActive)
    }

    func testJustUnderTheCeilingStaysActive() {
        let e = ActiveRunTimeline.entry(
            from: snapshot(ageSeconds: ActiveRunTimeline.staleAfter - 60),
            now: now,
        )
        XCTAssertTrue(e.isActive)
    }

    func testExactlyAtTheCeilingReadsInactive() {
        let e = ActiveRunTimeline.entry(
            from: snapshot(ageSeconds: ActiveRunTimeline.staleAfter),
            now: now,
        )
        XCTAssertFalse(e.isActive, "The ceiling is exclusive: `age < staleAfter`")
    }

    func testZeroEpochNeverReadsActive() {
        let never = ActiveRunSnapshot(
            isActive: true,
            elapsedSeconds: 0,
            distanceMeters: 0,
            paceSecPerKm: nil,
            lastUpdatedEpoch: 0,
        )
        XCTAssertFalse(ActiveRunTimeline.entry(from: never, now: now).isActive)
    }

    func testAFutureStampIsNotRejected() {
        // Clock skew between two processes on one device is possible and a
        // negative age is not staleness. The run must keep showing.
        let e = ActiveRunTimeline.entry(from: snapshot(ageSeconds: -30), now: now)
        XCTAssertTrue(e.isActive)
    }

    // MARK: - entries(from:now:)

    func testIdleTimelineIsOneEntry() {
        let entries = ActiveRunTimeline.entries(from: .empty, now: now)
        XCTAssertEqual(entries.count, 1)
        XCTAssertFalse(entries[0].isActive)
        XCTAssertEqual(entries[0].date, now)
    }

    func testStaleTimelineCollapsesToTheIdleEntry() {
        let entries = ActiveRunTimeline.entries(from: snapshot(ageSeconds: 25 * 3600), now: now)
        XCTAssertEqual(entries.count, 1)
        XCTAssertFalse(entries[0].isActive)
    }

    func testActiveTimelineFillsTheRefreshBudget() {
        let entries = ActiveRunTimeline.entries(from: snapshot(), now: now)
        XCTAssertEqual(entries.count, ActiveRunTimeline.activeEntryCount)
        XCTAssertTrue(entries.allSatisfy(\.isActive))
    }

    func testActiveTimelineAdvancesDateAndElapsedInStep() {
        let entries = ActiveRunTimeline.entries(from: snapshot(elapsedSeconds: 600), now: now)
        for (i, e) in entries.enumerated() {
            let dt = ActiveRunTimeline.activeEntryStride * Double(i)
            XCTAssertEqual(e.date.timeIntervalSince1970, now.timeIntervalSince1970 + dt, accuracy: 0.0001)
            XCTAssertEqual(e.elapsedSeconds, 600 + Int(dt), "entry \(i)")
        }
    }

    func testActiveTimelineHoldsDistanceAndPaceFlat() {
        // Only the clock advances between explicit reloads — inventing
        // distance the runner has not covered would be a lie on the face.
        let entries = ActiveRunTimeline.entries(from: snapshot(), now: now)
        XCTAssertTrue(entries.allSatisfy { $0.distanceMeters == 2000 })
        XCTAssertTrue(entries.allSatisfy { $0.paceSecPerKm == 300 })
    }

    func testTimelineIsNeverEmpty() {
        // `getTimeline` reads `entries.first` to pick its reload policy.
        for snap in [ActiveRunSnapshot.empty, snapshot(), snapshot(isActive: false)] {
            XCTAssertFalse(ActiveRunTimeline.entries(from: snap, now: now).isEmpty)
        }
    }
}

/// The snapshot-to-view-model half: the one composed string the rectangular
/// and inline families draw, plus the three formatters behind it. These read
/// the km/mi preference through `ActiveRunBridge.prefersMiles()`, which
/// prefers the App Group suite the extension shares with the host and falls
/// back to `UserDefaults.standard`, so both are set and restored here.
final class ActiveRunViewModelTests: XCTestCase {
    private var savedStandard: String?
    private var savedShared: String?

    private func preferUnit(_ unit: String) {
        UserDefaults.standard.set(unit, forKey: ActiveRunBridge.preferredUnitKey)
        ActiveRunBridge.mirrorPreferredUnit(unit)
    }

    override func setUp() {
        super.setUp()
        savedStandard = UserDefaults.standard.string(forKey: ActiveRunBridge.preferredUnitKey)
        savedShared = UserDefaults(suiteName: ActiveRunBridge.appGroup)?
            .string(forKey: ActiveRunBridge.preferredUnitKey)
        preferUnit("km")
    }

    override func tearDown() {
        if let savedStandard {
            UserDefaults.standard.set(savedStandard, forKey: ActiveRunBridge.preferredUnitKey)
        } else {
            UserDefaults.standard.removeObject(forKey: ActiveRunBridge.preferredUnitKey)
        }
        let shared = UserDefaults(suiteName: ActiveRunBridge.appGroup)
        if let savedShared {
            shared?.set(savedShared, forKey: ActiveRunBridge.preferredUnitKey)
        } else {
            shared?.removeObject(forKey: ActiveRunBridge.preferredUnitKey)
        }
        super.tearDown()
    }

    private func entry(distanceMeters: Double, paceSecPerKm: Double?) -> ActiveRunEntry {
        ActiveRunEntry(
            date: Date(timeIntervalSince1970: 1_700_000_000),
            isActive: true,
            elapsedSeconds: 600,
            distanceMeters: distanceMeters,
            paceSecPerKm: paceSecPerKm,
        )
    }

    // MARK: - statLine

    func testStatLineJoinsDistanceAndPace() {
        let s = ActiveRunTimeline.statLine(entry(distanceMeters: 5120, paceSecPerKm: 330))
        XCTAssertTrue(s.contains("5.12") || s.contains("5,12"), "Got: \(s)")
        XCTAssertTrue(s.lowercased().contains("km"), "Got: \(s)")
        XCTAssertTrue(s.contains("5:30/km"), "Got: \(s)")
        XCTAssertTrue(s.contains(" · "), "The two halves are joined by a spaced middle dot: \(s)")
    }

    func testStatLineBeforeThereIsAPace() {
        let s = ActiveRunTimeline.statLine(entry(distanceMeters: 0, paceSecPerKm: nil))
        XCTAssertTrue(s.hasPrefix("0"), "Got: \(s)")
        XCTAssertTrue(s.hasSuffix("—:—/km"), "Got: \(s)")
    }

    func testStatLineFollowsTheMilesPreference() {
        preferUnit("mi")
        let s = ActiveRunTimeline.statLine(entry(distanceMeters: 1609.344, paceSecPerKm: 300))
        XCTAssertTrue(s.contains("1.00") || s.contains("1,00"), "Got: \(s)")
        XCTAssertTrue(s.lowercased().contains("mi"), "Got: \(s)")
        XCTAssertTrue(s.contains("8:03/mi"), "Got: \(s)")
    }

    // MARK: - formatElapsed

    func testElapsedUnderOneHourIsMMSS() {
        XCTAssertEqual(formatElapsed(0), "00:00")
        XCTAssertEqual(formatElapsed(42), "00:42")
        XCTAssertEqual(formatElapsed(12 * 60 + 34), "12:34")
        XCTAssertEqual(formatElapsed(59 * 60 + 59), "59:59")
    }

    func testElapsedAtAndOverOneHourIsHMMSS() {
        XCTAssertEqual(formatElapsed(3600), "1:00:00")
        XCTAssertEqual(formatElapsed(1 * 3600 + 23 * 60 + 45), "1:23:45")
        XCTAssertEqual(formatElapsed(9 * 3600 + 59 * 60 + 59), "9:59:59")
    }

    func testElapsedUltraLength() {
        // 27h 03m 07s — well past any watch battery, but the formatter
        // must not overflow or wrap.
        XCTAssertEqual(formatElapsed(27 * 3600 + 3 * 60 + 7), "27:03:07")
    }

    func testElapsedClampsNegativeToZero() {
        XCTAssertEqual(formatElapsed(-5), "00:00")
    }

    // MARK: - formatPaceSecPerKm

    func testPaceKm() {
        XCTAssertEqual(formatPaceSecPerKm(330.0), "5:30/km")
        XCTAssertEqual(formatPaceSecPerKm(240.0), "4:00/km")
        XCTAssertEqual(formatPaceSecPerKm(754.0), "12:34/km")
    }

    func testPaceGuardsNilNonPositiveNonFinite() {
        XCTAssertEqual(formatPaceSecPerKm(nil), "—:—/km")
        XCTAssertEqual(formatPaceSecPerKm(0.0), "—:—/km")
        XCTAssertEqual(formatPaceSecPerKm(-30.0), "—:—/km")
        XCTAssertEqual(formatPaceSecPerKm(Double.nan), "—:—/km")
        XCTAssertEqual(formatPaceSecPerKm(Double.infinity), "—:—/km")
    }

    func testPaceMilesSuffixAndPlaceholder() {
        preferUnit("mi")
        // 300 s/km -> 8:03/mi.
        XCTAssertEqual(formatPaceSecPerKm(300.0), "8:03/mi")
        XCTAssertEqual(formatPaceSecPerKm(nil), "—:—/mi")
    }

    // MARK: - formatDistanceKm

    func testDistanceTwoDecimalsUnderTen() {
        let s = formatDistanceKm(5120)
        XCTAssertTrue(s.contains("5.12") || s.contains("5,12"), "Got: \(s)")
        XCTAssertTrue(s.lowercased().contains("km"), "Got: \(s)")
    }

    func testDistanceOneDecimalAtOrBeyondTen() {
        // The complication uses 2 decimals under 10 km, 1 at/over — the
        // second decimal is noise on a tiny face at marathon distances.
        let s = formatDistanceKm(21_100)
        XCTAssertTrue(s.contains("21.1") || s.contains("21,1"), "Got: \(s)")
        XCTAssertFalse(s.contains("21.10"), "At >=10 km must drop the second decimal: \(s)")
    }

    func testDistanceTenKmBoundaryUsesOneDecimal() {
        // Exactly 10.0 km is the cutoff — `value >= 10.0` selects 1 digit.
        let s = formatDistanceKm(10_000)
        XCTAssertTrue(s.contains("10.0") || s.contains("10,0"), "Got: \(s)")
        XCTAssertFalse(s.contains("10.00"), "Got: \(s)")
    }

    func testDistanceZero() {
        let s = formatDistanceKm(0)
        XCTAssertTrue(s.hasPrefix("0"), "Got: \(s)")
    }

    /// Asserts the CONVERSION, not the rendering. `contains("mi")` read as a
    /// unit abbreviation and passed on `1.00 miles`; it fails outright on a
    /// Japanese wrist, where the same value renders `1.00 マイル`. Holding the
    /// complication's output to `RunFormat`'s is exact in every language, and
    /// it is the thing that actually matters now that one file serves both.
    func testDistanceMilesConverts() {
        preferUnit("mi")
        XCTAssertEqual(
            formatDistanceKm(1609.344),
            RunFormat.distance(metres: 1609.344, fractionDigits: 2)
        )
        XCTAssertNotEqual(
            formatDistanceKm(1609.344),
            RunFormat.distance(metres: 1609.344, fractionDigits: 1)
        )
    }
}

/// The complication's "today" state: today's planned workout on an idle face,
/// only on its own day, rolling back to idle at the next local midnight with
/// no app running. Same reach as the suites above — `ActiveRunTimeline.swift`
/// and `ActiveRunBridge.swift` are members of both targets — and the same
/// limit: none of this is evidence the face renders it.
final class TodayComplicationTests: XCTestCase {
    private var utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    /// 2026-10-16 09:00 UTC.
    private var morning: Date {
        utc.date(from: DateComponents(year: 2026, month: 10, day: 16, hour: 9))!
    }

    private func glance(
        date: String = "2026-10-16",
        kind: String = "tempo",
        distance: Int? = 8000,
        duration: Int? = nil
    ) -> TodayWorkoutGlance {
        TodayWorkoutGlance(
            scheduledDate: date,
            workoutKind: kind,
            distanceMetres: distance,
            durationSeconds: duration
        )
    }

    private func live(at now: Date) -> ActiveRunSnapshot {
        ActiveRunSnapshot(
            isActive: true,
            elapsedSeconds: 60,
            distanceMeters: 200,
            paceSecPerKm: 300,
            lastUpdatedEpoch: now.timeIntervalSince1970 - 5,
        )
    }

    // MARK: - entry

    func testIdleFaceShowsTodaysWorkoutOnItsDay() {
        let e = ActiveRunTimeline.entry(from: .empty, today: glance(), now: morning, calendar: utc)
        XCTAssertFalse(e.isActive)
        XCTAssertEqual(e.today, glance())
    }

    func testALiveRunWinsTheFace() {
        let e = ActiveRunTimeline.entry(from: live(at: morning), today: glance(), now: morning, calendar: utc)
        XCTAssertTrue(e.isActive)
        XCTAssertNil(e.today)
    }

    func testAWorkoutForAnotherDayIsNotShown() {
        for date in ["2026-10-15", "2026-10-17"] {
            let e = ActiveRunTimeline.entry(from: .empty, today: glance(date: date), now: morning, calendar: utc)
            XCTAssertNil(e.today, date)
        }
    }

    func testTheDayIsTheWatchesOwnZone() {
        // 23:30 UTC on the 15th is already the 16th in Auckland.
        var auckland = utc
        auckland.timeZone = TimeZone(identifier: "Pacific/Auckland")!
        let lateUTC = utc.date(from: DateComponents(year: 2026, month: 10, day: 15, hour: 23, minute: 30))!
        XCTAssertNil(ActiveRunTimeline.entry(from: .empty, today: glance(), now: lateUTC, calendar: utc).today)
        XCTAssertEqual(
            ActiveRunTimeline.entry(from: .empty, today: glance(), now: lateUTC, calendar: auckland).today,
            glance()
        )
    }

    func testANonGregorianWristStillMatchesTheDay() {
        // The phone writes Gregorian days; a Buddhist-calendar watch would
        // otherwise read the year as 2569 and never match one.
        var buddhist = Calendar(identifier: .buddhist)
        buddhist.timeZone = utc.timeZone
        XCTAssertEqual(TodayWorkoutGlance.dayString(morning, calendar: buddhist), "2026-10-16")
        XCTAssertEqual(PushedWorkout.dayString(morning, calendar: buddhist), "2026-10-16")
        XCTAssertEqual(
            ActiveRunTimeline.entry(from: .empty, today: glance(), now: morning, calendar: buddhist).today,
            glance()
        )
    }

    // MARK: - entries + reload policy

    func testTodayRollsOverAtTheNextLocalMidnight() {
        let entries = ActiveRunTimeline.entries(from: .empty, today: glance(), now: morning, calendar: utc)
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].today, glance())
        let midnight = utc.date(from: DateComponents(year: 2026, month: 10, day: 17))!
        XCTAssertEqual(entries[1].date, midnight)
        XCTAssertNil(entries[1].today)
        XCTAssertFalse(entries[1].isActive)
        XCTAssertTrue(ActiveRunTimeline.reloadsAtEnd(entries))
    }

    func testAWorkoutDatedTomorrowAppearsAtMidnight() {
        let entries = ActiveRunTimeline.entries(
            from: .empty, today: glance(date: "2026-10-17"), now: morning, calendar: utc
        )
        XCTAssertEqual(entries.count, 2)
        XCTAssertNil(entries[0].today)
        XCTAssertEqual(entries[1].today, glance(date: "2026-10-17"))
    }

    func testAStaleWorkoutIsOneIdleEntryThatWaits() {
        let entries = ActiveRunTimeline.entries(
            from: .empty, today: glance(date: "2026-10-14"), now: morning, calendar: utc
        )
        XCTAssertEqual(entries.count, 1)
        XCTAssertNil(entries[0].today)
        XCTAssertFalse(ActiveRunTimeline.reloadsAtEnd(entries))
    }

    func testNoWorkoutKeepsTheIdleFaceWaiting() {
        let entries = ActiveRunTimeline.entries(from: .empty, now: morning, calendar: utc)
        XCTAssertEqual(entries.count, 1)
        XCTAssertFalse(ActiveRunTimeline.reloadsAtEnd(entries))
    }

    func testALiveRunTimelineIgnoresToday() {
        let entries = ActiveRunTimeline.entries(from: live(at: morning), today: glance(), now: morning, calendar: utc)
        XCTAssertEqual(entries.count, ActiveRunTimeline.activeEntryCount)
        XCTAssertTrue(entries.allSatisfy { $0.isActive && $0.today == nil })
        XCTAssertTrue(ActiveRunTimeline.reloadsAtEnd(entries))
    }

    // MARK: - the words on the face

    func testEveryPushedKindHasACatalogLabel() {
        for kind in ["easy", "long", "recovery", "tempo", "interval", "marathon_pace", "walk_run", "race"] {
            let label = ActiveRunTimeline.kindLabel(kind)
            XCTAssertFalse(label.isEmpty, kind)
            XCTAssertFalse(label.hasPrefix("workoutKind."), "\(kind) has no catalog entry: \(label)")
        }
    }

    func testAnUnknownKindReadsAsTheGenericHeading() {
        XCTAssertEqual(ActiveRunTimeline.kindLabel("fartlek"), String(localized: "Today's workout"))
    }

    func testHeadlinePrefersDistanceThenTime() {
        XCTAssertEqual(
            ActiveRunTimeline.todayHeadline(glance(distance: 8000, duration: 1800)),
            RunFormat.distance(metres: 8000, fractionDigits: 1)
        )
        XCTAssertEqual(ActiveRunTimeline.todayHeadline(glance(distance: nil, duration: 1800)), "30:00")
        XCTAssertNil(ActiveRunTimeline.todayHeadline(glance(distance: nil, duration: nil)))
    }

    func testTodayLineJoinsKindAndHeadline() {
        let g = glance(distance: nil, duration: 1800)
        XCTAssertEqual(ActiveRunTimeline.todayLine(g), "\(ActiveRunTimeline.kindLabel("tempo")) · 30:00")
        XCTAssertEqual(
            ActiveRunTimeline.todayLine(glance(distance: nil, duration: nil)),
            ActiveRunTimeline.kindLabel("tempo")
        )
    }

    // MARK: - the push -> glance -> App Group path

    func testAPushedWorkoutBecomesItsGlance() throws {
        let cases = try XCTUnwrap(PushedWorkoutTests.fixture()["cases"] as? [[String: Any]])
        let payload = try XCTUnwrap(cases.first?["payload"])
        let json = try XCTUnwrap(String(data: try JSONSerialization.data(withJSONObject: payload), encoding: .utf8))
        let push = WorkoutPush.decode(json)
        guard case .workout(let w) = push else { return XCTFail("fixture case did not decode") }
        let g = try XCTUnwrap(TodayWorkoutGlance(push))
        XCTAssertEqual(g.scheduledDate, w.scheduledDate)
        XCTAssertEqual(g.workoutKind, w.workoutKind)
        XCTAssertEqual(g.distanceMetres, w.totalDistanceMetres)
        XCTAssertEqual(g.durationSeconds, w.totalDurationSeconds)
    }

    func testNothingTodayARefusalOrNoPushIsNoGlance() {
        XCTAssertNil(TodayWorkoutGlance(WorkoutPush.none))
        XCTAssertNil(TodayWorkoutGlance(.rejected))
        XCTAssertNil(TodayWorkoutGlance(nil))
    }

    func testTheAppGroupSlotReportsOnlyARealChange() {
        let saved = ActiveRunBridge.readToday()
        defer { ActiveRunBridge.writeToday(saved) }
        ActiveRunBridge.writeToday(nil)

        XCTAssertFalse(ActiveRunBridge.writeToday(nil), "clearing an empty slot is no change")
        XCTAssertTrue(ActiveRunBridge.writeToday(glance()))
        XCTAssertEqual(ActiveRunBridge.readToday(), glance())
        XCTAssertFalse(ActiveRunBridge.writeToday(glance()), "the same glance again is no change")
        XCTAssertTrue(ActiveRunBridge.writeToday(glance(kind: "easy")))
        XCTAssertTrue(ActiveRunBridge.writeToday(nil))
        XCTAssertNil(ActiveRunBridge.readToday())
    }
}
