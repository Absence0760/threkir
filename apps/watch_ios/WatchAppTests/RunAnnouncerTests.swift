import XCTest
@testable import WatchApp

/// The spoken cues, pinned on the half a simulator can decide.
///
/// The speech itself cannot be asserted on — `AVSpeechSynthesizer` produces
/// audio, and no test host can hear it — so everything that DECIDES is pure
/// and lives here: which split fires at which distance, how a pace decomposes,
/// which voice tag a locale picks, and whether the preference silences the
/// cue without stalling the tracker behind it. `RunAnnouncer.speak` is the
/// injectable seam that makes that possible, the same shape as
/// `RouteNavigator.playOffRouteHaptic`.
///
/// Phrase assertions are composed from the catalogue's own parts rather than
/// spelled in English, so the suite passes in whatever locale the host runs
/// in. The one assertion about the English WORDS names `en_US` instead, and
/// runs in every language CI tests in rather than skipping itself out of all
/// but one.
final class RunAnnouncerTests: XCTestCase {
    private var savedUnit: String?
    private var savedCues: Any?

    override func setUp() {
        super.setUp()
        savedUnit = UserDefaults.standard.string(forKey: "preferred_unit")
        savedCues = UserDefaults.standard.object(forKey: RunAnnouncer.preferenceKey)
    }

    override func tearDown() {
        if let savedUnit {
            UserDefaults.standard.set(savedUnit, forKey: "preferred_unit")
        } else {
            UserDefaults.standard.removeObject(forKey: "preferred_unit")
        }
        if let savedCues {
            UserDefaults.standard.set(savedCues, forKey: RunAnnouncer.preferenceKey)
        } else {
            UserDefaults.standard.removeObject(forKey: RunAnnouncer.preferenceKey)
        }
        super.tearDown()
    }

    /// An announcer whose speech seam records instead of speaking, with the
    /// unit and the preference pinned so neither reads UserDefaults.
    private func recordingAnnouncer(
        prefersMiles: Bool = false,
        enabled: Bool = true
    ) -> (RunAnnouncer, () -> [String]) {
        let announcer = RunAnnouncer()
        var spoken: [String] = []
        announcer.speak = { text, _ in spoken.append(text) }
        announcer.isEnabled = { enabled }
        announcer.prefersMiles = { prefersMiles }
        return (announcer, { spoken })
    }

    // MARK: - split cadence

    func testSplitIntervalIsTheRunnersOwnUnit() {
        XCTAssertEqual(RunCueMath.splitIntervalMetres(prefersMiles: false), 1000.0)
        XCTAssertEqual(
            RunCueMath.splitIntervalMetres(prefersMiles: true), 1609.344, accuracy: 0.0001
        )
    }

    func testCompletedSplitsFloorsAtTheUnitBoundary() {
        XCTAssertEqual(RunCueMath.completedSplits(distanceMetres: 999.9, prefersMiles: false), 0)
        XCTAssertEqual(RunCueMath.completedSplits(distanceMetres: 1000, prefersMiles: false), 1)
        XCTAssertEqual(RunCueMath.completedSplits(distanceMetres: 4999, prefersMiles: false), 4)
        XCTAssertEqual(RunCueMath.completedSplits(distanceMetres: 1609, prefersMiles: true), 0)
        XCTAssertEqual(RunCueMath.completedSplits(distanceMetres: 1609.5, prefersMiles: true), 1)
        XCTAssertEqual(RunCueMath.completedSplits(distanceMetres: 5000, prefersMiles: true), 3)
    }

    func testCompletedSplitsRefusesNonsenseDistances() {
        XCTAssertEqual(RunCueMath.completedSplits(distanceMetres: 0, prefersMiles: false), 0)
        XCTAssertEqual(RunCueMath.completedSplits(distanceMetres: -5000, prefersMiles: false), 0)
        XCTAssertEqual(
            RunCueMath.completedSplits(distanceMetres: .nan, prefersMiles: false), 0
        )
        XCTAssertEqual(
            RunCueMath.completedSplits(distanceMetres: .infinity, prefersMiles: false), 0
        )
    }

    func testTrackerFiresOncePerUnitAndNeverRepeats() {
        var tracker = SplitTracker()
        XCTAssertNil(tracker.splitDue(distanceMetres: 800, prefersMiles: false))
        XCTAssertEqual(tracker.splitDue(distanceMetres: 1000, prefersMiles: false), 1)
        XCTAssertNil(tracker.splitDue(distanceMetres: 1500, prefersMiles: false))
        XCTAssertNil(tracker.splitDue(distanceMetres: 1999, prefersMiles: false))
        XCTAssertEqual(tracker.splitDue(distanceMetres: 2000, prefersMiles: false), 2)
        XCTAssertEqual(tracker.lastAnnounced, 2)
    }

    func testTrackerJumpsStraightToTheCurrentSplitAfterAGap() {
        // A batch of fixes after a tunnel can add several units at once. The
        // runner hears the split they are actually on, not a countdown of the
        // ones they passed unheard.
        var tracker = SplitTracker()
        XCTAssertEqual(tracker.splitDue(distanceMetres: 5000, prefersMiles: false), 5)
    }

    func testTrackerDoesNotReplayAfterAMidRunUnitSwitch() {
        // 8 km is 8 splits in km mode and 4 in mi mode. The lower count must
        // not re-announce miles 1-4 as though they were new.
        var tracker = SplitTracker()
        XCTAssertEqual(tracker.splitDue(distanceMetres: 8000, prefersMiles: false), 8)
        XCTAssertNil(tracker.splitDue(distanceMetres: 8000, prefersMiles: true))
        XCTAssertEqual(tracker.lastAnnounced, 8)
    }

    func testTrackerResets() {
        var tracker = SplitTracker()
        _ = tracker.splitDue(distanceMetres: 3000, prefersMiles: false)
        tracker.reset()
        XCTAssertEqual(tracker.lastAnnounced, 0)
        XCTAssertEqual(tracker.splitDue(distanceMetres: 1000, prefersMiles: false), 1)
    }

    // MARK: - pace decomposition

    func testPaceDecomposesToWholeMinutesAndSeconds() {
        let ms = RunCueMath.paceMinutesSeconds(secondsPerKm: 330, prefersMiles: false)
        XCTAssertEqual(ms?.minutes, 5)
        XCTAssertEqual(ms?.seconds, 30)
    }

    func testPaceTruncatesRatherThanRounding() {
        // 329.9 s/km is 5:29.9 — spoken as 5:29, matching Wear's paceMinSec.
        let ms = RunCueMath.paceMinutesSeconds(secondsPerKm: 329.9, prefersMiles: false)
        XCTAssertEqual(ms?.minutes, 5)
        XCTAssertEqual(ms?.seconds, 29)
    }

    func testPaceScalesToTheMileBeforeSpeaking() {
        // 5:00/km is 8:02/mi (300 x 1.609344 = 482.8 s).
        let ms = RunCueMath.paceMinutesSeconds(secondsPerKm: 300, prefersMiles: true)
        XCTAssertEqual(ms?.minutes, 8)
        XCTAssertEqual(ms?.seconds, 2)
    }

    func testPaceIsNilWhenThereIsNothingToSay() {
        XCTAssertNil(RunCueMath.paceMinutesSeconds(secondsPerKm: nil, prefersMiles: false))
        XCTAssertNil(RunCueMath.paceMinutesSeconds(secondsPerKm: 0, prefersMiles: false))
        XCTAssertNil(RunCueMath.paceMinutesSeconds(secondsPerKm: -10, prefersMiles: false))
        XCTAssertNil(RunCueMath.paceMinutesSeconds(secondsPerKm: .nan, prefersMiles: false))
    }

    // MARK: - finish summary

    func testFinishedMinutesFloors() {
        XCTAssertEqual(RunCueMath.finishedMinutes(durationSeconds: 1659), 27)
        XCTAssertEqual(RunCueMath.finishedMinutes(durationSeconds: 59), 0)
        XCTAssertEqual(RunCueMath.finishedMinutes(durationSeconds: -5), 0)
    }

    func testSpokenDistanceAlwaysUsesAPeriodDecimal() {
        // A comma is read out as the literal word "comma" by most engines, so
        // this one number does not follow the locale the way RunFormat does.
        let km = RunCueMath.spokenDistance(metres: 5123, prefersMiles: false)
        XCTAssertEqual(km, "5.12")
        let mi = RunCueMath.spokenDistance(metres: 5123, prefersMiles: true)
        XCTAssertEqual(mi, "3.18")
        XCTAssertEqual(RunCueMath.spokenDistance(metres: 0, prefersMiles: false), "0.00")
        XCTAssertEqual(RunCueMath.spokenDistance(metres: .nan, prefersMiles: false), "0.00")
    }

    // MARK: - voice language

    func testVoiceTagForEveryShippedLocale() {
        XCTAssertEqual(RunCueVoice.languageTag(for: "en"), "en-US")
        XCTAssertEqual(RunCueVoice.languageTag(for: "de"), "de-DE")
        XCTAssertEqual(RunCueVoice.languageTag(for: "fr"), "fr-FR")
        XCTAssertEqual(RunCueVoice.languageTag(for: "es"), "es-ES")
        XCTAssertEqual(RunCueVoice.languageTag(for: "ja"), "ja-JP")
        XCTAssertEqual(RunCueVoice.languageTag(for: "pt-BR"), "pt-BR")
        XCTAssertEqual(RunCueVoice.languageTag(for: "pt-PT"), "pt-PT")
    }

    func testVoiceTagToleratesRegionsAndUnderscoresAndCase() {
        XCTAssertEqual(RunCueVoice.languageTag(for: "de_DE"), "de-DE")
        XCTAssertEqual(RunCueVoice.languageTag(for: "PT_br"), "pt-BR")
        XCTAssertEqual(RunCueVoice.languageTag(for: "fr-CA"), "fr-FR")
        // Bare `pt` is the European catalogue on every client in this repo.
        XCTAssertEqual(RunCueVoice.languageTag(for: "pt"), "pt-PT")
    }

    func testVoiceTagFallsBackRatherThanReturningNothing() {
        XCTAssertEqual(RunCueVoice.languageTag(for: "sv-SE"), "en-US")
        XCTAssertEqual(RunCueVoice.languageTag(for: ""), "en-US")
    }

    func testVoiceTagForTheRunningBundleIsOneWeShip() {
        let shipped = ["en-US", "de-DE", "fr-FR", "es-ES", "ja-JP", "pt-BR", "pt-PT"]
        XCTAssertTrue(shipped.contains(RunCueVoice.current), "Got: \(RunCueVoice.current)")
    }

    // MARK: - phrases

    func testSplitPhraseJoinsTheDistanceAndThePace() {
        let text = RunCuePhrase.text(
            for: .split(index: 3, paceSecondsPerKm: 330), prefersMiles: false
        )
        let label = RunCuePhrase.unitLabel(splits: 3, prefersMiles: false)
        let tail = RunCuePhrase.paceTail(minutes: 5, seconds: 30, prefersMiles: false)
        XCTAssertEqual(text, RunCuePhrase.join(label, tail))
        XCTAssertTrue(text.contains(label), "Got: \(text)")
        XCTAssertTrue(text.contains(tail), "Got: \(text)")
    }

    func testSplitPhraseDropsTheTailWhenThereIsNoPace() {
        // Not "0 minutes 0 seconds", and not silence: the distance alone.
        let text = RunCuePhrase.text(
            for: .split(index: 1, paceSecondsPerKm: nil), prefersMiles: false
        )
        XCTAssertEqual(text, RunCuePhrase.unitLabel(splits: 1, prefersMiles: false))
    }

    func testSplitPhraseSpeaksMilesInMilesMode() {
        let km = RunCuePhrase.unitLabel(splits: 2, prefersMiles: false)
        let mi = RunCuePhrase.unitLabel(splits: 2, prefersMiles: true)
        XCTAssertNotEqual(km, mi, "The two units must not share one spoken word")
        XCTAssertTrue(mi.contains("2"), "Got: \(mi)")
    }

    func testPaceAlertPhrasesAreDistinctInBothDirections() {
        let slow = RunCuePhrase.text(for: .paceAlert(tooSlow: true), prefersMiles: false)
        let fast = RunCuePhrase.text(for: .paceAlert(tooSlow: false), prefersMiles: false)
        XCTAssertFalse(slow.isEmpty)
        XCTAssertFalse(fast.isEmpty)
        XCTAssertNotEqual(slow, fast)
    }

    func testFinishPhraseCarriesTheDistanceAndTheMinutes() {
        let text = RunCuePhrase.text(
            for: .finished(distanceMetres: 5123, durationSeconds: 1659), prefersMiles: false
        )
        XCTAssertTrue(text.contains("5.12"), "Got: \(text)")
        XCTAssertTrue(text.contains("27"), "Got: \(text)")
    }

    func testNoCuePhraseIsEmpty() {
        let cues: [RunCue] = [
            .started,
            .split(index: 1, paceSecondsPerKm: 300),
            .split(index: 1, paceSecondsPerKm: nil),
            .paceAlert(tooSlow: true),
            .paceAlert(tooSlow: false),
            .finished(distanceMetres: 5000, durationSeconds: 1500),
        ]
        for miles in [false, true] {
            for cue in cues {
                XCTAssertFalse(
                    RunCuePhrase.text(for: cue, prefersMiles: miles).isEmpty,
                    "Empty phrase for \(cue), miles=\(miles)"
                )
            }
        }
    }

    func testEnglishWordingMatchesThePhone() {
        let en = Locale(identifier: "en_US")
        XCTAssertEqual(
            RunCuePhrase.text(for: .started, prefersMiles: false, locale: en), "Run started"
        )
        XCTAssertEqual(
            RunCuePhrase.text(for: .paceAlert(tooSlow: true), prefersMiles: false, locale: en),
            "Pick up the pace"
        )
        XCTAssertEqual(
            RunCuePhrase.text(for: .paceAlert(tooSlow: false), prefersMiles: false, locale: en),
            "Slow down"
        )
        XCTAssertEqual(
            RunCuePhrase.unitLabel(splits: 1, prefersMiles: false, locale: en), "1 kilometre"
        )
        XCTAssertEqual(
            RunCuePhrase.unitLabel(splits: 2, prefersMiles: false, locale: en), "2 kilometres"
        )
        XCTAssertEqual(RunCuePhrase.unitLabel(splits: 1, prefersMiles: true, locale: en), "1 mile")
        XCTAssertEqual(RunCuePhrase.unitLabel(splits: 5, prefersMiles: true, locale: en), "5 miles")
        XCTAssertEqual(
            RunCuePhrase.text(
                for: .split(index: 1, paceSecondsPerKm: 330), prefersMiles: false, locale: en
            ),
            "1 kilometre. Pace, 5 minutes 30 seconds per kilometre"
        )
        XCTAssertEqual(
            RunCuePhrase.text(
                for: .finished(distanceMetres: 5123, durationSeconds: 1659),
                prefersMiles: false,
                locale: en
            ),
            "Run complete. 5.12 kilometres in 27 minutes."
        )
    }

    // MARK: - announcer

    func testAnnouncerSpeaksOneCuePerSplit() {
        let (announcer, spoken) = recordingAnnouncer()
        announcer.announceSplitIfDue(distanceMetres: 900, paceSecondsPerKm: 300)
        XCTAssertEqual(spoken().count, 0)
        announcer.announceSplitIfDue(distanceMetres: 1010, paceSecondsPerKm: 300)
        announcer.announceSplitIfDue(distanceMetres: 1500, paceSecondsPerKm: 300)
        announcer.announceSplitIfDue(distanceMetres: 2100, paceSecondsPerKm: 300)
        XCTAssertEqual(spoken().count, 2)
        XCTAssertEqual(
            spoken()[0],
            RunCuePhrase.text(for: .split(index: 1, paceSecondsPerKm: 300), prefersMiles: false)
        )
        XCTAssertEqual(
            spoken()[1],
            RunCuePhrase.text(for: .split(index: 2, paceSecondsPerKm: 300), prefersMiles: false)
        )
    }

    func testAnnouncerSpeaksStartPaceAlertAndFinish() {
        let (announcer, spoken) = recordingAnnouncer()
        announcer.announceStart()
        announcer.announcePaceAlert(tooSlow: true)
        announcer.announceFinish(distanceMetres: 5000, durationSeconds: 1500)
        XCTAssertEqual(spoken().count, 3)
        XCTAssertEqual(spoken()[0], RunCuePhrase.text(for: .started, prefersMiles: false))
        XCTAssertEqual(
            spoken()[1], RunCuePhrase.text(for: .paceAlert(tooSlow: true), prefersMiles: false)
        )
    }

    func testDisabledPreferenceSilencesTheCueButNotTheTracker() {
        // Turning cues back on mid-run must not dump every split banked while
        // they were off, so the tracker advances either way.
        let (announcer, spoken) = recordingAnnouncer(enabled: false)
        announcer.announceSplitIfDue(distanceMetres: 3000, paceSecondsPerKm: 300)
        announcer.announceStart()
        announcer.announcePaceAlert(tooSlow: false)
        XCTAssertEqual(spoken().count, 0)
        XCTAssertEqual(announcer.announcedSplits, 3)
    }

    func testAnnouncerResetsWithTheRun() {
        let (announcer, spoken) = recordingAnnouncer()
        announcer.announceSplitIfDue(distanceMetres: 4000, paceSecondsPerKm: 300)
        announcer.reset()
        XCTAssertEqual(announcer.announcedSplits, 0)
        announcer.announceSplitIfDue(distanceMetres: 1000, paceSecondsPerKm: 300)
        XCTAssertEqual(spoken().count, 2)
        XCTAssertEqual(
            spoken()[1],
            RunCuePhrase.text(for: .split(index: 1, paceSecondsPerKm: 300), prefersMiles: false)
        )
    }

    func testAnnouncerFollowsTheMilesPreference() {
        let (announcer, spoken) = recordingAnnouncer(prefersMiles: true)
        // 1700 m is past the first mile but only one kilometre-and-a-bit: a
        // mi-mode runner must be told at the MILE.
        announcer.announceSplitIfDue(distanceMetres: 1700, paceSecondsPerKm: 300)
        XCTAssertEqual(spoken().count, 1)
        XCTAssertEqual(
            spoken()[0],
            RunCuePhrase.text(for: .split(index: 1, paceSecondsPerKm: 300), prefersMiles: true)
        )
    }

    // MARK: - preference

    func testCuesDefaultOnWhenThePhoneHasNeverPushedThePreference() {
        UserDefaults.standard.removeObject(forKey: RunAnnouncer.preferenceKey)
        XCTAssertTrue(RunAnnouncer.isEnabledByPreference)
    }

    func testPreferenceKeyIsHonouredInBothDirections() {
        UserDefaults.standard.set(false, forKey: RunAnnouncer.preferenceKey)
        XCTAssertFalse(RunAnnouncer.isEnabledByPreference)
        UserDefaults.standard.set(true, forKey: RunAnnouncer.preferenceKey)
        XCTAssertTrue(RunAnnouncer.isEnabledByPreference)
    }

    func testPreferenceKeyMatchesThePhonesOwn() {
        // `apps/mobile_android/lib/preferences.dart` `_kAudioCues`. A rename on
        // one side is a preference the runner sets that the wrist never reads.
        XCTAssertEqual(RunAnnouncer.preferenceKey, "audio_cues")
    }

    // MARK: - layering

    func testTheSeamIsTheOnlyRouteToTheEngine() {
        // A default `RunAnnouncer` reaches `RunSpeech`; one with the seam
        // replaced reaches nothing else. That substitution is what makes every
        // test above runnable with no audio hardware, and it is the same
        // property that keeps a speech failure off the recording path: the
        // announcer neither inspects the seam's result nor waits on it, so the
        // tracker advances identically whatever the engine does.
        let announcer = RunAnnouncer()
        var attempts = 0
        announcer.isEnabled = { true }
        announcer.prefersMiles = { false }
        announcer.speak = { _, _ in attempts += 1 }
        announcer.announceSplitIfDue(distanceMetres: 1000, paceSecondsPerKm: nil)
        announcer.announceSplitIfDue(distanceMetres: 2000, paceSecondsPerKm: nil)
        XCTAssertEqual(attempts, 2)
        XCTAssertEqual(announcer.announcedSplits, 2)
    }
}

/// The pace-drift gate, held to Wear OS's `shouldFirePaceAlert` case for
/// case. Both wrists now speak through this decision, so every boundary
/// asserted in `PaceAlertTest.kt` is asserted here too — a divergence that
/// survives both suites is one `scripts/check_shared_constants.mjs` is left
/// to catch alone.
final class PaceAlertGateTests: XCTestCase {

    private func decide(
        target: Double = 300,
        current: Double,
        since: TimeInterval? = nil
    ) -> PaceAlertGate.Decision {
        PaceAlertGate.decide(
            targetSecondsPerKm: target,
            currentSecondsPerKm: current,
            secondsSinceLastAlert: since
        )
    }

    // MARK: - the threshold

    func testTheThresholdIsWearsThirtySecondsPerKilometre() {
        // Not an arbitrary pin: this is the whole point of the change. 15 s/km
        // was the watchOS figure while Wear and the phone both used 30, and
        // the three only ever buzzed, so nothing read the disagreement out.
        XCTAssertEqual(PaceAlertGate.driftThresholdSecondsPerKm, 30)
        XCTAssertEqual(PaceAlertGate.rateLimitSeconds, 30)
    }

    func testOnPaceDoesNotFire() {
        XCTAssertFalse(decide(current: 300).fire)
    }

    func testTheOldFifteenSecondDriftIsNowSilent() {
        // The regression this change is FOR: a runner holding 5:00/km whose
        // 200 m window reads 5:16 is inside GPS noise, and used to be told so
        // out loud.
        XCTAssertFalse(decide(current: 316).fire)
        XCTAssertFalse(decide(current: 284).fire)
    }

    func testExactlyThirtySecondsDoesNotFire() {
        // Strictly greater than, matching Wear's `> threshold`.
        XCTAssertFalse(decide(current: 330).fire)
        XCTAssertFalse(decide(current: 270).fire)
    }

    func testThirtyOneSecondsSlowerFires() {
        let d = decide(current: 331)
        XCTAssertTrue(d.fire)
        XCTAssertTrue(d.tooSlow, "positive drift is the runner being slower than target")
    }

    func testThirtyOneSecondsFasterFires() {
        let d = decide(current: 269)
        XCTAssertTrue(d.fire)
        XCTAssertFalse(d.tooSlow)
    }

    func testDirectionFollowsTheSignOfTheDrift() {
        for current in [331.0, 350.0, 400.0, 600.0] {
            XCTAssertTrue(decide(current: current).tooSlow, "\(current) is slower than 300")
        }
        for current in [269.0, 250.0, 200.0, 100.0] {
            XCTAssertFalse(decide(current: current).tooSlow, "\(current) is faster than 300")
        }
    }

    // MARK: - the rate limit

    func testTheFirstAlertOfARunIsNotRateLimited() {
        XCTAssertTrue(decide(current: 400, since: nil).fire)
    }

    func testAnAlertInsideTheWindowIsSuppressed() {
        XCTAssertFalse(decide(current: 400, since: 5).fire)
    }

    func testExactlyThirtySecondsSinceTheLastAlertStillSuppresses() {
        XCTAssertFalse(decide(current: 400, since: 30).fire)
    }

    func testJustPastTheWindowFires() {
        XCTAssertTrue(decide(current: 400, since: 30.001).fire)
    }

    func testOneClockCoversBothDirections() {
        // The watchOS-only half of the change. Two clocks — one per direction
        // — let a pace crossing the band speak twice in consecutive fixes,
        // which is two SENTENCES back to back now that the gate talks.
        XCTAssertTrue(decide(current: 400, since: nil).fire)
        XCTAssertFalse(
            decide(current: 200, since: 1).fire,
            "the opposite direction must ride the same rate limit"
        )
    }

    // MARK: - refusals

    func testNoTargetPaceNeverFires() {
        XCTAssertFalse(decide(target: 0, current: 400).fire)
        XCTAssertFalse(decide(target: -1, current: 400).fire)
    }

    func testANonFinitePaceNeverFires() {
        // `updatePace` divides by a measured segment; a degenerate window can
        // hand this a non-number, and `abs(nan) > 30` is false anyway — pinned
        // so a later rewrite of the comparison cannot start speaking at it.
        XCTAssertFalse(decide(current: .nan).fire)
        XCTAssertFalse(decide(current: .infinity).fire)
    }
}

/// The spoken half of a structured workout: which cue a feed of runner events
/// speaks, whether the phone's voice switches let it, what it says, and in
/// what order the speaker takes it. Phrase assertions about the WORDS name
/// `en_US`, as `testEnglishWordingMatchesThePhone` does; the rest compose from
/// the catalogue's own parts so they hold in any host language.
final class WorkoutSpokenCueTests: XCTestCase {
    private let en = Locale(identifier: "en_US")
    private var saved: [String: Any] = [:]
    private let keys = [
        RunAnnouncer.preferenceKey, RunAnnouncer.verbosityKey, RunAnnouncer.workoutStepCuesKey,
    ]

    override func setUp() {
        super.setUp()
        saved = [:]
        for key in keys {
            if let value = UserDefaults.standard.object(forKey: key) { saved[key] = value }
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    override func tearDown() {
        for key in keys {
            if let value = saved[key] {
                UserDefaults.standard.set(value, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        super.tearDown()
    }

    private func step(
        _ kind: WorkoutStepKind,
        rep: (Int, Int)? = nil,
        metres: Int? = nil,
        seconds: Int? = nil,
        pace: Int = 300
    ) -> PushedStep {
        PushedStep(
            kind: kind,
            repIndex: rep?.0,
            repTotal: rep?.1,
            distanceMetres: metres,
            durationSeconds: seconds,
            paceSecondsPerKm: pace,
            toleranceSecondsPerKm: 10
        )
    }

    private func workout(_ steps: [PushedStep], unpaced: Bool = false) -> PushedWorkout {
        PushedWorkout(
            planWorkoutId: "pw-1", scheduledDate: "2026-10-18", workoutKind: "interval",
            unpaced: unpaced, steps: steps
        )
    }

    private func say(_ cue: WorkoutSpokenCue, miles: Bool = false) -> String {
        WorkoutCuePhrase.text(for: cue, prefersMiles: miles, locale: en)
    }

    private func announcer(
        audio: Bool = true, stepCues: Bool = true, verbose: Bool = true, miles: Bool = false
    ) -> (RunAnnouncer, () -> [(String, RunCuePriority)]) {
        let announcer = RunAnnouncer()
        var spoken: [(String, RunCuePriority)] = []
        announcer.speak = { spoken.append(($0, $1)) }
        announcer.isEnabled = { audio }
        announcer.workoutStepCuesEnabled = { stepCues }
        announcer.isVerbose = { verbose }
        announcer.prefersMiles = { miles }
        return (announcer, { spoken })
    }

    // MARK: - which cue a feed speaks

    func testTheFirstStepIsAnnouncedThoughItDoesNotBuzz() {
        let w = workout([step(.warmup, metres: 1000), step(.rep, metres: 400)])
        let events: [WatchWorkoutEvent] = [.transition(previous: -1, current: 0)]
        XCTAssertNil(WatchWorkoutCue.cue(for: events), "the haptic stays silent on Start")
        XCTAssertEqual(WorkoutSpokenCue.cue(for: events, workout: w), .step(w.steps[0], paced: true))
    }

    func testSeveralTransitionsInOneFeedSpeakOnlyTheStepTheRunnerIsOn() {
        let w = workout([step(.rep, metres: 400), step(.recovery, seconds: 60), step(.rep, metres: 400)])
        let events: [WatchWorkoutEvent] = [
            .transition(previous: 0, current: 1), .transition(previous: 1, current: 2),
        ]
        XCTAssertEqual(WorkoutSpokenCue.cue(for: events, workout: w), .step(w.steps[2], paced: true))
    }

    func testATransitionReplacesTheWarningAndTheDriftOfTheStepItLeft() {
        let w = workout([step(.rep, metres: 400), step(.recovery, seconds: 60)])
        let events: [WatchWorkoutEvent] = [
            .warning(index: 0),
            .paceDrift(index: 0, ahead: false, deltaSecondsPerKm: 40),
            .transition(previous: 0, current: 1),
        ]
        XCTAssertEqual(WorkoutSpokenCue.cue(for: events, workout: w), .step(w.steps[1], paced: true))
    }

    func testCompletionReplacesEverything() {
        let w = workout([step(.rep, metres: 400)])
        let events: [WatchWorkoutEvent] = [.transition(previous: -1, current: 0), .warning(index: 0), .complete]
        XCTAssertEqual(WorkoutSpokenCue.cue(for: events, workout: w), .complete)
    }

    func testTheWarningSaysWhichAxisTheStepEndsOn() {
        let w = workout([step(.recovery, seconds: 90), step(.rep, metres: 800)])
        XCTAssertEqual(
            WorkoutSpokenCue.cue(for: [.warning(index: 0)], workout: w), .stepEnding(timed: true)
        )
        XCTAssertEqual(
            WorkoutSpokenCue.cue(for: [.warning(index: 1)], workout: w), .stepEnding(timed: false)
        )
    }

    func testTheDriftNudgeIsSpokenInTheDirectionToCorrect() {
        let w = workout([step(.rep, metres: 800)])
        XCTAssertEqual(
            WorkoutSpokenCue.cue(
                for: [.paceDrift(index: 0, ahead: true, deltaSecondsPerKm: 30)], workout: w
            ),
            .paceDrift(tooSlow: false)
        )
        XCTAssertEqual(
            WorkoutSpokenCue.cue(
                for: [.paceDrift(index: 0, ahead: false, deltaSecondsPerKm: 30)], workout: w
            ),
            .paceDrift(tooSlow: true)
        )
    }

    func testAFeedWithNothingInItSaysNothing() {
        XCTAssertNil(WorkoutSpokenCue.cue(for: [], workout: workout([step(.steady, metres: 5000)])))
    }

    func testAnUnpacedSessionsStepsAreAnnouncedUnpaced() {
        let w = workout([step(.walk, rep: (1, 5), seconds: 90)], unpaced: true)
        XCTAssertEqual(
            WorkoutSpokenCue.cue(for: [.transition(previous: -1, current: 0)], workout: w),
            .step(w.steps[0], paced: false)
        )
    }

    func testAnIndexPastTheWorkoutIsNotSpoken() {
        let w = workout([step(.rep, metres: 400)])
        XCTAssertNil(WorkoutSpokenCue.cue(for: [.transition(previous: 0, current: 5)], workout: w))
        XCTAssertNil(WorkoutSpokenCue.cue(for: [.warning(index: 5)], workout: w))
    }

    // MARK: - the phone's voice switches

    func testFullModeSpeaksAllFour() {
        let cues: [WorkoutSpokenCue] = [
            .step(step(.rep, metres: 400), paced: true), .stepEnding(timed: true),
            .complete, .paceDrift(tooSlow: true),
        ]
        for cue in cues {
            XCTAssertTrue(
                WorkoutVoiceGate.speaks(cue, audioCues: true, workoutStepCues: true, verbose: true),
                "\(cue)"
            )
        }
    }

    func testMinimalModeKeepsStepChangesAndCompletionOnly() {
        func minimal(_ cue: WorkoutSpokenCue) -> Bool {
            WorkoutVoiceGate.speaks(cue, audioCues: true, workoutStepCues: true, verbose: false)
        }
        XCTAssertTrue(minimal(.step(step(.rep, metres: 400), paced: true)))
        XCTAssertTrue(minimal(.complete))
        XCTAssertFalse(minimal(.stepEnding(timed: true)))
        XCTAssertFalse(minimal(.stepEnding(timed: false)))
        XCTAssertFalse(minimal(.paceDrift(tooSlow: true)))
        XCTAssertFalse(minimal(.paceDrift(tooSlow: false)))
    }

    func testAudioOffSpeaksNothingInEitherMode() {
        let cues: [WorkoutSpokenCue] = [
            .step(step(.rep, metres: 400), paced: true), .stepEnding(timed: false),
            .complete, .paceDrift(tooSlow: false),
        ]
        for cue in cues {
            for verbose in [true, false] {
                XCTAssertFalse(
                    WorkoutVoiceGate.speaks(cue, audioCues: false, workoutStepCues: true, verbose: verbose)
                )
            }
        }
    }

    func testTheWorkoutStepsVoiceCueSilencesTheWorkoutAlone() {
        XCTAssertFalse(
            WorkoutVoiceGate.speaks(.complete, audioCues: true, workoutStepCues: false, verbose: true)
        )
        XCTAssertFalse(
            WorkoutVoiceGate.speaks(
                .step(step(.steady, metres: 5000), paced: true),
                audioCues: true, workoutStepCues: false, verbose: true
            )
        )
    }

    func testThePreferencesDefaultToFullAndOn() {
        XCTAssertTrue(RunAnnouncer.isVerboseByPreference)
        XCTAssertTrue(RunAnnouncer.workoutStepCuesByPreference)
        UserDefaults.standard.set("minimal", forKey: RunAnnouncer.verbosityKey)
        XCTAssertFalse(RunAnnouncer.isVerboseByPreference)
        UserDefaults.standard.set("full", forKey: RunAnnouncer.verbosityKey)
        XCTAssertTrue(RunAnnouncer.isVerboseByPreference)
        UserDefaults.standard.set(false, forKey: RunAnnouncer.workoutStepCuesKey)
        XCTAssertFalse(RunAnnouncer.workoutStepCuesByPreference)
    }

    func testThePreferenceKeysAreTheWireKeys() {
        // `apple_watch_prefs_bridge.dart` sends these; a rename on one side is
        // a switch the runner flips that the wrist never reads.
        XCTAssertEqual(RunAnnouncer.verbosityKey, "voice_feedback_verbosity")
        XCTAssertEqual(RunAnnouncer.workoutStepCuesKey, "voice_cue_workout_steps")
    }

    // MARK: - the announcer

    func testTheAnnouncerSpeaksAStepChangeAtStepPriority() {
        let (a, spoken) = announcer()
        let rep = step(.rep, rep: (3, 6), metres: 400, pace: 240)
        a.announceWorkout(.step(rep, paced: true))
        XCTAssertEqual(spoken().count, 1)
        XCTAssertEqual(
            spoken().first?.0,
            WorkoutCuePhrase.text(for: .step(rep, paced: true), prefersMiles: false)
        )
        XCTAssertEqual(spoken().first?.1, RunCuePriority.step)
    }

    func testTheAnnouncerHonoursMinimalAndOff() {
        let (minimal, minimalSpoken) = announcer(verbose: false)
        minimal.announceWorkout(.stepEnding(timed: true))
        minimal.announceWorkout(.paceDrift(tooSlow: true))
        minimal.announceWorkout(.complete)
        XCTAssertEqual(
            minimalSpoken().map { $0.0 },
            [WorkoutCuePhrase.text(for: .complete, prefersMiles: false)]
        )

        let (off, offSpoken) = announcer(audio: false)
        off.announceWorkout(.complete)
        off.announceWorkout(.step(step(.steady, metres: 5000), paced: true))
        XCTAssertTrue(offSpoken().isEmpty)
    }

    func testTheDriftNudgeWaitsItsTurnLikeAPaceAlert() {
        let (a, spoken) = announcer()
        a.announceWorkout(.paceDrift(tooSlow: true))
        XCTAssertEqual(spoken().first?.1, RunCuePriority.normal)
        XCTAssertEqual(
            spoken().first?.0,
            RunCuePhrase.text(for: .paceAlert(tooSlow: true), prefersMiles: false)
        )
    }

    func testTheAnnouncerSpeaksInTheRunnersUnit() {
        let (a, spoken) = announcer(miles: true)
        a.announceWorkout(.stepEnding(timed: false))
        XCTAssertEqual(
            spoken().first?.0, WorkoutCuePhrase.text(for: .stepEnding(timed: false), prefersMiles: true)
        )
    }

    // MARK: - the numbers

    func testMetricDistancesSpeakMetresUnderAKilometre() {
        XCTAssertEqual(WorkoutCueMath.spokenDistance(metres: 400, prefersMiles: false), .metres(400))
        XCTAssertEqual(WorkoutCueMath.spokenDistance(metres: 999, prefersMiles: false), .metres(999))
        XCTAssertEqual(WorkoutCueMath.spokenDistance(metres: 1000, prefersMiles: false), .kilometres(1))
        XCTAssertEqual(WorkoutCueMath.spokenDistance(metres: 5000, prefersMiles: false), .kilometres(5))
        XCTAssertEqual(
            WorkoutCueMath.spokenDistance(metres: 1500, prefersMiles: false), .kilometresDecimal("1.5")
        )
    }

    func testImperialDistancesSpeakYardsUnderAMile() {
        // 400 m is 437.4 yd.
        XCTAssertEqual(WorkoutCueMath.spokenDistance(metres: 400, prefersMiles: true), .yards(437))
        // 2000 m is 1.243 mi.
        XCTAssertEqual(
            WorkoutCueMath.spokenDistance(metres: 2000, prefersMiles: true), .milesDecimal("1.2")
        )
    }

    func testAOneMileStepIsOneMileThoughThePushCarriesWholeMetres() {
        // The phone rounds 1609.344 m to 1609 before it pushes. An exact
        // whole-mile test would call that 0.9998 mi and say "1760 yards".
        XCTAssertEqual(WorkoutCueMath.spokenDistance(metres: 1609, prefersMiles: true), .miles(1))
        XCTAssertEqual(WorkoutCueMath.spokenDistance(metres: 3219, prefersMiles: true), .miles(2))
    }

    func testTheStepPaceRoundsToTheSecondAsThePhoneDoes() {
        let km = WorkoutCueMath.stepPace(secondsPerKm: 330, prefersMiles: false)
        XCTAssertEqual(km.minutes, 5)
        XCTAssertEqual(km.seconds, 30)
        // 330 s/km x 1.609344 = 531.08 s/mi, 8:51.
        let mi = WorkoutCueMath.stepPace(secondsPerKm: 330, prefersMiles: true)
        XCTAssertEqual(mi.minutes, 8)
        XCTAssertEqual(mi.seconds, 51)
        // 240 s/km x 1.609344 = 386.24 s/mi, 6:26.
        let rep = WorkoutCueMath.stepPace(secondsPerKm: 240, prefersMiles: true)
        XCTAssertEqual(rep.minutes, 6)
        XCTAssertEqual(rep.seconds, 26)
    }

    func testDurationsSplitIntoMinutesAndSeconds() {
        let walk = WorkoutCueMath.minutesSeconds(90)
        XCTAssertEqual(walk.minutes, 1)
        XCTAssertEqual(walk.seconds, 30)
        let recovery = WorkoutCueMath.minutesSeconds(45)
        XCTAssertEqual(recovery.minutes, 0)
        XCTAssertEqual(recovery.seconds, 45)
        let nonsense = WorkoutCueMath.minutesSeconds(-3)
        XCTAssertEqual(nonsense.minutes, 0)
        XCTAssertEqual(nonsense.seconds, 0)
    }

    // MARK: - the words

    func testEveryStepKindInEnglishMatchesThePhone() {
        XCTAssertEqual(
            say(.step(step(.rep, rep: (3, 6), metres: 400, pace: 240), paced: true)),
            "Rep 3 of 6. 400 metres at 4 minutes per kilometre."
        )
        XCTAssertEqual(
            say(.step(step(.rep, metres: 1000, pace: 240), paced: true)),
            "Rep. 1 kilometre at 4 minutes per kilometre."
        )
        XCTAssertEqual(
            say(.step(step(.rep, rep: (1, 5), seconds: 60), paced: false)),
            "Run 1 of 5. 1 minute."
        )
        XCTAssertEqual(say(.step(step(.rep, seconds: 120), paced: false)), "Run. 2 minutes.")
        XCTAssertEqual(
            say(.step(step(.warmup, metres: 2000, pace: 330), paced: true)),
            "Warmup. 2 kilometres at 5 minutes 30 seconds per kilometre."
        )
        XCTAssertEqual(say(.step(step(.warmup, seconds: 300), paced: false)), "Warm-up walk. 5 minutes.")
        XCTAssertEqual(say(.step(step(.recovery, seconds: 45), paced: true)), "Recovery. 45 seconds.")
        XCTAssertEqual(
            say(.step(step(.walk, rep: (2, 5), seconds: 90), paced: false)),
            "Walk 2 of 5. 1 minute 30 seconds."
        )
        XCTAssertEqual(
            say(.step(step(.steady, metres: 5000, pace: 300), paced: true)),
            "Steady. 5 kilometres at 5 minutes per kilometre."
        )
        XCTAssertEqual(
            say(.step(step(.cooldown, metres: 1500, pace: 360), paced: true)),
            "Cooldown. 1.5 kilometres at 6 minutes per kilometre."
        )
        XCTAssertEqual(
            say(.step(step(.cooldown, seconds: 300), paced: false)), "Cool-down walk. 5 minutes."
        )
    }

    func testMilesModeSpeaksYardsMilesAndPacePerMile() {
        XCTAssertEqual(
            say(.step(step(.rep, rep: (3, 6), metres: 400, pace: 240), paced: true), miles: true),
            "Rep 3 of 6. 437 yards at 6 minutes 26 seconds per mile."
        )
        XCTAssertEqual(
            say(.step(step(.warmup, metres: 2000, pace: 330), paced: true), miles: true),
            "Warmup. 1.2 miles at 8 minutes 51 seconds per mile."
        )
        XCTAssertEqual(
            say(.step(step(.steady, metres: 1609, pace: 373), paced: true), miles: true),
            "Steady. 1 mile at 10 minutes per mile."
        )
    }

    func testATimedStepSpeaksTheSameInEitherUnit() {
        let walk = WorkoutSpokenCue.step(step(.walk, rep: (2, 5), seconds: 90), paced: false)
        XCTAssertEqual(say(walk, miles: false), say(walk, miles: true))
    }

    func testAnEffortLedDistanceStepCarriesNoPace() {
        XCTAssertEqual(say(.step(step(.walk, metres: 800), paced: false)), "Walk. 800 metres.")
        XCTAssertEqual(
            say(.step(step(.walk, metres: 800), paced: false), miles: true), "Walk. 875 yards."
        )
    }

    func testTheWarningCompletionAndNudgeInEnglish() {
        XCTAssertEqual(say(.stepEnding(timed: true)), "Ten seconds to go")
        XCTAssertEqual(say(.stepEnding(timed: true), miles: true), "Ten seconds to go")
        XCTAssertEqual(say(.stepEnding(timed: false)), "Fifty metres to go")
        XCTAssertEqual(say(.stepEnding(timed: false), miles: true), "Fifty yards to go")
        XCTAssertEqual(say(.complete), "Workout complete. Nice work.")
        XCTAssertEqual(say(.paceDrift(tooSlow: true)), "Pick up the pace")
        XCTAssertEqual(say(.paceDrift(tooSlow: false)), "Slow down")
    }

    func testTheAnnouncementIsComposedFromItsParts() {
        // Locale-free: whatever the host speaks, the sentence carries the
        // step's name and its distance.
        let rep = step(.rep, rep: (3, 6), metres: 400, pace: 240)
        let text = WorkoutCuePhrase.text(for: .step(rep, paced: true), prefersMiles: false)
        XCTAssertTrue(text.contains(WorkoutCuePhrase.stepName(rep, paced: true)), "Got: \(text)")
        XCTAssertTrue(
            text.contains(WorkoutCuePhrase.spokenDistance(.metres(400))), "Got: \(text)"
        )
        XCTAssertTrue(
            text.contains(WorkoutCuePhrase.stepPace(secondsPerKm: 240, prefersMiles: false)),
            "Got: \(text)"
        )
    }

    func testNoWorkoutPhraseIsEmptyInAnyShippedLanguage() {
        let steps: [PushedStep] = WorkoutStepKind.allCases.flatMap { kind in
            [
                step(kind, metres: 400), step(kind, metres: 1609), step(kind, metres: 2500),
                step(kind, seconds: 1), step(kind, seconds: 60), step(kind, seconds: 95),
                step(kind, rep: (2, 4), metres: 800), step(kind, rep: (2, 4), seconds: 120),
            ]
        }
        var cues: [WorkoutSpokenCue] = [
            .stepEnding(timed: true), .stepEnding(timed: false), .complete,
            .paceDrift(tooSlow: true), .paceDrift(tooSlow: false),
        ]
        for s in steps { cues += [.step(s, paced: true), .step(s, paced: false)] }
        for id in ["en_US", "de_DE", "fr_FR", "es_ES", "ja_JP", "pt_BR", "pt_PT"] {
            let locale = Locale(identifier: id)
            for miles in [false, true] {
                for cue in cues {
                    let text = WorkoutCuePhrase.text(for: cue, prefersMiles: miles, locale: locale)
                    XCTAssertFalse(text.isEmpty, "\(id) \(cue)")
                    XCTAssertFalse(text.contains("tts.step."), "an untranslated key in \(id): \(text)")
                }
            }
        }
    }
}

/// The order `RunSpeech` says things in, apart from the engine.
final class SpeechQueueTests: XCTestCase {
    func testNormalCuesAreSaidInTheOrderTheyArrive() {
        var q = SpeechQueue()
        q.enqueue("1 kilometre", priority: .normal)
        q.enqueue("Pick up the pace", priority: .normal)
        XCTAssertEqual(q.next(), "1 kilometre")
        XCTAssertEqual(q.next(), "Pick up the pace")
        XCTAssertNil(q.next())
        XCTAssertTrue(q.isEmpty)
    }

    func testAStepCueGoesAheadOfEverythingStillWaiting() {
        var q = SpeechQueue()
        q.enqueue("Run started", priority: .normal)
        q.enqueue("1 kilometre", priority: .normal)
        q.enqueue("Rep 1 of 6", priority: .step)
        XCTAssertEqual(q.next(), "Rep 1 of 6")
        XCTAssertEqual(q.next(), "Run started")
        XCTAssertEqual(q.next(), "1 kilometre")
    }

    func testANewerStepCueReplacesAnUnsaidOlderOne() {
        var q = SpeechQueue()
        q.enqueue("2 kilometres", priority: .normal)
        q.enqueue("Rep 1 of 6", priority: .step)
        q.enqueue("Recovery", priority: .step)
        XCTAssertEqual(q.pending.map(\.text), ["Recovery", "2 kilometres"])
    }

    func testAnEmptyCueIsNeverQueued() {
        var q = SpeechQueue()
        q.enqueue("", priority: .step)
        q.enqueue("", priority: .normal)
        XCTAssertTrue(q.isEmpty)
    }
}
