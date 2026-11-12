import Foundation
import AVFoundation

/// One thing the watch says out loud during a run. The cue set is Wear OS's
/// (`TtsAnnouncer.kt`): a start confirmation, one split per completed unit of
/// the runner's `preferred_unit`, a pace-drift nudge, and a finish summary.
/// The wording is the phone's (`apps/mobile_android/lib/audio_cues.dart` and
/// the `tts*` keys in `l10n/app_*.arb`), so a runner carrying both devices
/// hears one dialect rather than two.
enum RunCue: Equatable {
    case started
    /// The `index`th completed whole unit — kilometre or mile, per the
    /// runner's preference. `paceSecondsPerKm` is the recorder's figure and is
    /// converted for the read-out; nil drops the pace tail rather than
    /// speaking a "0 minutes 0 seconds".
    case split(index: Int, paceSecondsPerKm: Double?)
    /// True when the runner is SLOWER than target, which is the "pick up the
    /// pace" direction. Same polarity as Wear's `PaceAlertDecision.tooSlow`.
    case paceAlert(tooSlow: Bool)
    case finished(distanceMetres: Double, durationSeconds: Int)
}

/// The numeric half of the cues, kept apart from both the speech engine and
/// the String Catalog so every threshold is testable with no device.
enum RunCueMath {
    /// Metres between spoken splits. A split is a landmark, not a raw
    /// distance: an imperial runner expects to be told when they pass a MILE.
    /// Mirrors Wear's `splitIntervalMetres`.
    static func splitIntervalMetres(prefersMiles: Bool) -> Double {
        prefersMiles ? RunFormat.metresPerMile : 1000.0
    }

    /// Whole splits banked at `distanceMetres`. Floors, so the cue fires as
    /// the unit is completed.
    static func completedSplits(distanceMetres: Double, prefersMiles: Bool) -> Int {
        guard distanceMetres.isFinite, distanceMetres > 0 else { return 0 }
        return Int(distanceMetres / splitIntervalMetres(prefersMiles: prefersMiles))
    }

    /// Integer minutes + seconds for a pace, in the runner's unit. Truncates
    /// rather than rounding, matching Wear's `paceMinSecFor`. Nil when there
    /// is no usable pace, which is what drops the tail from the split cue.
    static func paceMinutesSeconds(
        secondsPerKm: Double?,
        prefersMiles: Bool
    ) -> (minutes: Int, seconds: Int)? {
        guard let secondsPerKm, secondsPerKm.isFinite, secondsPerKm > 0 else { return nil }
        let perUnit = prefersMiles
            ? secondsPerKm * (RunFormat.metresPerMile / 1000.0)
            : secondsPerKm
        return (Int(perUnit / 60), Int(perUnit.truncatingRemainder(dividingBy: 60)))
    }

    /// Whole minutes for the finish summary — no half-minute rounding, so the
    /// watch and the phone report the same figure for the same run.
    static func finishedMinutes(durationSeconds: Int) -> Int {
        max(0, durationSeconds) / 60
    }

    /// The finish summary's distance, in the runner's unit. Always a PERIOD
    /// decimal regardless of locale: a comma is read out as the literal word
    /// "comma" by most speech engines, which is why this one number does not
    /// go through `RunFormat.distance`.
    static func spokenDistance(metres: Double, prefersMiles: Bool) -> String {
        guard metres.isFinite, metres > 0 else { return "0.00" }
        let value = prefersMiles ? metres / RunFormat.metresPerMile : metres / 1000.0
        return String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), value)
    }
}

/// When the watch says something about a runner drifting off their target
/// pace, and how often.
///
/// One-way port of Wear OS's `shouldFirePaceAlert`
/// (`apps/watch_wear/.../recording/PaceAlert.kt`), held to it by
/// `scripts/check_shared_constants.mjs`. The two wrists used to gate this on
/// thresholds nobody had compared — 15 s/km here against Wear's 30 — and
/// while the only effect was a haptic the divergence was invisible. It
/// stopped being invisible the moment the same gate started SPEAKING.
///
/// 30 s/km is the figure on both wrists and on the phone
/// (`run_screen.dart`'s `diff.abs() > 30`), because 15 s/km sits inside the
/// noise floor of the reading it gates: `updatePace` divides a ~200 m
/// look-back by that segment's own time span, so a few metres of position
/// error at either end moves the answer by the better part of ten seconds
/// per kilometre with the runner holding a perfectly even effort. A false
/// haptic costs a wrist tap; a false cue costs a sentence spoken over the
/// runner's music.
enum PaceAlertGate {
    /// Seconds per kilometre of drift, either direction, before the gate
    /// fires. Strictly greater than, matching Wear's `> threshold`.
    static let driftThresholdSecondsPerKm: Double = 30

    /// Minimum seconds between two consecutive alerts, in EITHER direction —
    /// one clock for both, not one each. Two clocks let a pace oscillating
    /// across the band speak "slow down" and "pick up the pace" back to back,
    /// each inside the window the other direction's clock had left open.
    static let rateLimitSeconds: TimeInterval = 30

    struct Decision: Equatable {
        let fire: Bool
        /// Meaningful only when `fire`. True when the runner is SLOWER than
        /// target — the same polarity as `RunCue.paceAlert`.
        let tooSlow: Bool

        static let noFire = Decision(fire: false, tooSlow: false)
    }

    /// `secondsSinceLastAlert` is nil when nothing has fired yet this run,
    /// which clears the rate limit.
    static func decide(
        targetSecondsPerKm: Double,
        currentSecondsPerKm: Double,
        secondsSinceLastAlert: TimeInterval?
    ) -> Decision {
        guard targetSecondsPerKm > 0, currentSecondsPerKm.isFinite else { return .noFire }
        let drift = currentSecondsPerKm - targetSecondsPerKm
        guard abs(drift) > driftThresholdSecondsPerKm else { return .noFire }
        if let elapsed = secondsSinceLastAlert, elapsed <= rateLimitSeconds { return .noFire }
        return Decision(fire: true, tooSlow: drift > 0)
    }
}

/// Highest split already spoken this run. Kept as a value type so the
/// fire-once-per-unit contract is testable without a recorder.
struct SplitTracker {
    private(set) var lastAnnounced = 0

    /// The split index to announce for `distanceMetres`, or nil when the
    /// runner has not banked a new one. Switching unit mid-run can lower the
    /// count (8 km is 4 miles); the `>` comparison means the lower figure is
    /// simply not re-announced rather than replayed.
    mutating func splitDue(distanceMetres: Double, prefersMiles: Bool) -> Int? {
        let current = RunCueMath.completedSplits(
            distanceMetres: distanceMetres, prefersMiles: prefersMiles
        )
        guard current > lastAnnounced else { return nil }
        lastAnnounced = current
        return current
    }

    mutating func reset() { lastAnnounced = 0 }
}

/// Which voice reads the cue. An English voice reading a German sentence is a
/// bug, so the tag is derived from the localization the BUNDLE resolved —
/// the language the UI is already rendering in — rather than from the raw
/// device locale, which can name a region the app does not ship.
///
/// One-way port of `ttsLanguageTag` in `apps/mobile_android/lib/audio_cues.dart`.
enum RunCueVoice {
    static func languageTag(for localeTag: String) -> String {
        let lowered = localeTag.lowercased()
        switch lowered {
        case "pt-br", "pt_br": return "pt-BR"
        case "pt-pt", "pt_pt": return "pt-PT"
        default: break
        }
        let base = lowered.split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map(String.init)
        switch base {
        case "en": return "en-US"
        case "de": return "de-DE"
        case "fr": return "fr-FR"
        case "es": return "es-ES"
        case "ja": return "ja-JP"
        // Bare `pt` is the European catalogue on every client in this repo,
        // so speaking Brazilian over it would be the same tag/content
        // disagreement the phone resolved the same way.
        case "pt": return "pt-PT"
        default: return "en-US"
        }
    }

    static var current: String {
        languageTag(for: Bundle.main.preferredLocalizations.first ?? "en")
    }
}

/// The words, assembled from the String Catalog. Split out from `RunAnnouncer`
/// so a test can compose the expected phrase from the same parts in whatever
/// locale the host happens to run in.
///
/// `locale` is the seam `RunFormat.distance` and `RouteGuidance.remainingText`
/// carry, widened to the words: production passes nothing and speaks the
/// language the bundle resolved, and a test that asserts particular words
/// names the locale they belong to instead of inheriting whichever one the
/// simulator was left in.
enum RunCuePhrase {
    static func text(for cue: RunCue, prefersMiles: Bool, locale: Locale? = nil) -> String {
        let c = Catalogue(locale)
        switch cue {
        case .started:
            return String(localized: "Run started", bundle: c.bundle, locale: c.locale)
        case let .split(index, paceSecondsPerKm):
            let label = unitLabel(splits: index, prefersMiles: prefersMiles, locale: locale)
            guard let ms = RunCueMath.paceMinutesSeconds(
                secondsPerKm: paceSecondsPerKm, prefersMiles: prefersMiles
            ) else {
                return label
            }
            let tail = paceTail(
                minutes: ms.minutes, seconds: ms.seconds, prefersMiles: prefersMiles,
                locale: locale
            )
            return join(label, tail, locale: locale)
        case let .paceAlert(tooSlow):
            return tooSlow
                ? String(localized: "Pick up the pace", bundle: c.bundle, locale: c.locale)
                : String(localized: "Slow down", bundle: c.bundle, locale: c.locale)
        case let .finished(distanceMetres, durationSeconds):
            let distance = RunCueMath.spokenDistance(
                metres: distanceMetres, prefersMiles: prefersMiles
            )
            let minutes = RunCueMath.finishedMinutes(durationSeconds: durationSeconds)
            return prefersMiles
                ? String(
                    localized: "Run complete. \(distance) miles in \(minutes) minutes.",
                    bundle: c.bundle, locale: c.locale)
                : String(
                    localized: "Run complete. \(distance) kilometres in \(minutes) minutes.",
                    bundle: c.bundle, locale: c.locale)
        }
    }

    static func unitLabel(splits: Int, prefersMiles: Bool, locale: Locale? = nil) -> String {
        let c = Catalogue(locale)
        return prefersMiles
            ? String(localized: "\(splits) miles", bundle: c.bundle, locale: c.locale)
            : String(localized: "\(splits) kilometres", bundle: c.bundle, locale: c.locale)
    }

    static func paceTail(
        minutes: Int, seconds: Int, prefersMiles: Bool, locale: Locale? = nil
    ) -> String {
        let c = Catalogue(locale)
        return prefersMiles
            ? String(
                localized: "Pace, \(minutes) minutes \(seconds) seconds per mile",
                bundle: c.bundle, locale: c.locale)
            : String(
                localized: "Pace, \(minutes) minutes \(seconds) seconds per kilometre",
                bundle: c.bundle, locale: c.locale)
    }

    /// Sentence break between the split's distance and its pace. Localised
    /// rather than hard-coded because the break itself differs — ja joins with
    /// `。` and no space — which is why Wear carries the same `tts_split_phrase`
    /// resource instead of concatenating.
    static func join(_ head: String, _ tail: String, locale: Locale? = nil) -> String {
        let c = Catalogue(locale)
        return String(localized: "\(head). \(tail)", bundle: c.bundle, locale: c.locale)
    }

    /// Where a phrase is looked up. `String(localized:locale:)` formats the
    /// interpolated values in `locale` but still picks the LANGUAGE from the
    /// bundle's own resolution — measured: a `ja` host handed `en_US` answers
    /// in Japanese — so naming a language means naming its `.lproj`. A locale
    /// the app ships no catalogue for falls back to the bundle's resolution
    /// rather than to the development language's keys. `WorkoutCuePhrase`
    /// looks its words up the same way, which is why this is file-wide.
    fileprivate struct Catalogue {
        let bundle: Bundle
        let locale: Locale

        init(_ requested: Locale?) {
            guard let requested else {
                bundle = .main
                locale = .current
                return
            }
            locale = requested
            let candidates: [String?] = [
                requested.language.minimalIdentifier,
                requested.language.languageCode?.identifier,
            ]
            bundle = candidates.lazy
                .compactMap { $0 }
                .compactMap { Bundle.main.path(forResource: $0, ofType: "lproj") }
                .compactMap { Bundle(path: $0) }
                .first ?? .main
        }
    }
}

/// One thing the watch says about a structured workout it is running. The
/// phone's `run_screen.dart` `_onWorkoutEvent` speaks the same four, worded by
/// `formatWorkoutStepUtterance`, `workoutStepProgressUtterance` and
/// `ttsWorkoutComplete` in `apps/mobile_android/lib/audio_cues.dart`.
enum WorkoutSpokenCue: Equatable {
    /// A step began: what it is and what to do. `paced` is false for a
    /// walk-run session, whose steps are effort-led and carry no pace.
    case step(PushedStep, paced: Bool)
    /// The last 10 s of a timed step or the last 50 m of a distance one.
    case stepEnding(timed: Bool)
    case complete
    /// Off the step's pace band, in the direction to correct.
    case paceDrift(tooSlow: Bool)

    /// The cue for one feed of runner events, or nil. Unlike the haptic
    /// (`WatchWorkoutCue.cue`), the FIRST step is announced: the phone speaks
    /// it too, and the runner who has just pressed Start needs to hear what
    /// they are starting. Several transitions in one feed (a burst of skips,
    /// or a run of short steps covered between two feeds) speak only the step
    /// the runner is now on; a transition replaces the warning and the drift
    /// of the step it left; completion replaces everything.
    static func cue(for events: [WatchWorkoutEvent], workout: PushedWorkout) -> WorkoutSpokenCue? {
        if events.contains(.complete) { return .complete }
        for event in events.reversed() {
            if case .transition(_, let current) = event, workout.steps.indices.contains(current) {
                return .step(workout.steps[current], paced: !workout.unpaced)
            }
        }
        for event in events.reversed() {
            if case .warning(let index) = event, workout.steps.indices.contains(index) {
                return .stepEnding(timed: workout.steps[index].durationSeconds != nil)
            }
        }
        for event in events.reversed() {
            if case .paceDrift(_, let ahead, _) = event { return .paceDrift(tooSlow: !ahead) }
        }
        return nil
    }

    /// The phone's minimal voice mode drops these two — its "chatty in-rep
    /// progress + pace-drift" — and keeps step changes and completion.
    var isChatty: Bool {
        switch self {
        case .stepEnding, .paceDrift: return true
        case .step, .complete: return false
        }
    }

    /// A step cue goes ahead of anything still waiting to be said, and
    /// replaces an older step cue that has not been said yet. The drift
    /// nudge waits its turn like a split, so it can never displace the step
    /// change it would otherwise have pushed out of the queue.
    var priority: RunCuePriority {
        switch self {
        case .step, .stepEnding, .complete: return .step
        case .paceDrift: return .normal
        }
    }
}

/// Whether a workout cue is spoken, exactly as the phone's `_onWorkoutEvent`
/// gates it: `audio_cues` off speaks nothing, the `workout_steps` voice cue
/// off silences the workout's cues alone, and `minimal` verbosity keeps the
/// step changes and the completion while dropping the end-of-step warning and
/// the pace nudge. The haptics answer to none of this.
enum WorkoutVoiceGate {
    static func speaks(
        _ cue: WorkoutSpokenCue,
        audioCues: Bool,
        workoutStepCues: Bool,
        verbose: Bool
    ) -> Bool {
        guard audioCues, workoutStepCues else { return false }
        return verbose || !cue.isChatty
    }
}

/// The numbers a step announcement reads out, apart from their words.
enum WorkoutCueMath {
    /// A step's distance as it is spoken: metres or kilometres for a metric
    /// runner, yards or miles for an imperial one.
    enum SpokenDistance: Equatable {
        case metres(Int)
        case kilometres(Int)
        /// One decimal, always a period — see `RunCueMath.spokenDistance`.
        case kilometresDecimal(String)
        case yards(Int)
        case miles(Int)
        case milesDecimal(String)
    }

    /// The phone's `formatSpokenDistance`, with one difference: the value is
    /// rounded to a tenth BEFORE deciding whole-vs-decimal and mile-vs-yard,
    /// as the phone's own `splitCueDistance` does. The push carries whole
    /// metres, so a one-mile step arrives as 1609 m, which the phone's exact
    /// comparison would read out as "1760 yards".
    static func spokenDistance(metres: Int, prefersMiles: Bool) -> SpokenDistance {
        let m = Double(max(0, metres))
        if prefersMiles {
            let tenths = (m / RunFormat.metresPerMile * 10).rounded()
            guard tenths >= 10 else { return .yards(Int((m * 1.09361).rounded())) }
            return tenths.truncatingRemainder(dividingBy: 10) == 0
                ? .miles(Int(tenths / 10))
                : .milesDecimal(oneDecimal(tenths / 10))
        }
        guard m >= 1000 else { return .metres(Int(m)) }
        let tenths = (m / 1000 * 10).rounded()
        return tenths.truncatingRemainder(dividingBy: 10) == 0
            ? .kilometres(Int(tenths / 10))
            : .kilometresDecimal(oneDecimal(tenths / 10))
    }

    /// A step's target pace in the runner's unit, ROUNDED to the second as
    /// the phone's step announcement rounds it (the split cue truncates).
    static func stepPace(secondsPerKm: Int, prefersMiles: Bool) -> (minutes: Int, seconds: Int) {
        let perUnit = prefersMiles
            ? Int((Double(secondsPerKm) * (RunFormat.metresPerMile / 1000.0)).rounded())
            : secondsPerKm
        let clamped = max(0, perUnit)
        return (clamped / 60, clamped % 60)
    }

    static func minutesSeconds(_ seconds: Int) -> (minutes: Int, seconds: Int) {
        let clamped = max(0, seconds)
        return (clamped / 60, clamped % 60)
    }

    private static func oneDecimal(_ value: Double) -> String {
        String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), value)
    }
}

/// The words of a workout cue, from the String Catalog. The wording is the
/// phone's `tts*` ARB keys, so a runner who has heard a session from the phone
/// hears the same sentences from the wrist. `locale` is `RunCuePhrase`'s seam.
enum WorkoutCuePhrase {
    static func text(for cue: WorkoutSpokenCue, prefersMiles: Bool, locale: Locale? = nil) -> String {
        let c = RunCuePhrase.Catalogue(locale)
        switch cue {
        case let .step(step, paced):
            return stepAnnouncement(step, paced: paced, prefersMiles: prefersMiles, locale: locale)
        case let .stepEnding(timed):
            if timed {
                return String(localized: "Ten seconds to go", bundle: c.bundle, locale: c.locale)
            }
            // The window is 50 m either way; an imperial runner hears it in
            // their unit, as on the phone.
            return prefersMiles
                ? String(localized: "Fifty yards to go", bundle: c.bundle, locale: c.locale)
                : String(localized: "Fifty metres to go", bundle: c.bundle, locale: c.locale)
        case .complete:
            return String(localized: "Workout complete. Nice work.", bundle: c.bundle, locale: c.locale)
        case let .paceDrift(tooSlow):
            return RunCuePhrase.text(
                for: .paceAlert(tooSlow: tooSlow), prefersMiles: prefersMiles, locale: locale
            )
        }
    }

    /// "Rep 3 of 6. 400 metres at 4 minutes per kilometre." A timed step says
    /// how long instead ("Walk 2 of 5. 1 minute 30 seconds."), and an
    /// effort-led distance step says how far and nothing about pace.
    static func stepAnnouncement(
        _ step: PushedStep, paced: Bool, prefersMiles: Bool, locale: Locale? = nil
    ) -> String {
        let c = RunCuePhrase.Catalogue(locale)
        let intro = stepName(step, paced: paced, locale: locale)
        if let seconds = step.durationSeconds {
            let duration = spokenDuration(seconds: seconds, locale: locale)
            return String(localized: "\(intro). \(duration).", bundle: c.bundle, locale: c.locale)
        }
        let distance = spokenDistance(
            WorkoutCueMath.spokenDistance(metres: step.distanceMetres ?? 0, prefersMiles: prefersMiles),
            locale: locale
        )
        guard paced else {
            return String(localized: "\(intro). \(distance).", bundle: c.bundle, locale: c.locale)
        }
        let pace = stepPace(
            secondsPerKm: step.paceSecondsPerKm, prefersMiles: prefersMiles, locale: locale
        )
        return String(localized: "\(intro). \(distance) at \(pace).", bundle: c.bundle, locale: c.locale)
    }

    /// The phone's `workoutStepName`. A rep with a duration is a walk-run
    /// "Run" interval, one with a distance an interval "Rep"; an unpaced
    /// warm-up or cool-down is the walking one, said as such so a beginner
    /// does not hear "Warmup" and start running. The bare words are
    /// namespaced keys because "Rep", "Run" and "Walk" are already the
    /// running screen's own, differently translated, labels.
    static func stepName(_ step: PushedStep, paced: Bool, locale: Locale? = nil) -> String {
        let c = RunCuePhrase.Catalogue(locale)
        let timed = step.durationSeconds != nil
        let index = step.repIndex
        let total = step.repTotal
        switch step.kind {
        case .warmup:
            return paced
                ? String(localized: "tts.step.warmup", bundle: c.bundle, locale: c.locale)
                : String(localized: "tts.step.warmupWalk", bundle: c.bundle, locale: c.locale)
        case .rep:
            if let index, let total {
                return timed
                    ? String(localized: "Run \(index) of \(total)", bundle: c.bundle, locale: c.locale)
                    : String(localized: "Rep \(index) of \(total)", bundle: c.bundle, locale: c.locale)
            }
            return timed
                ? String(localized: "tts.step.run", bundle: c.bundle, locale: c.locale)
                : String(localized: "tts.step.rep", bundle: c.bundle, locale: c.locale)
        case .recovery:
            return String(localized: "tts.step.recovery", bundle: c.bundle, locale: c.locale)
        case .walk:
            if let index, let total {
                return String(localized: "Walk \(index) of \(total)", bundle: c.bundle, locale: c.locale)
            }
            return String(localized: "tts.step.walk", bundle: c.bundle, locale: c.locale)
        case .steady:
            return String(localized: "tts.step.steady", bundle: c.bundle, locale: c.locale)
        case .cooldown:
            return paced
                ? String(localized: "tts.step.cooldown", bundle: c.bundle, locale: c.locale)
                : String(localized: "tts.step.cooldownWalk", bundle: c.bundle, locale: c.locale)
        }
    }

    static func spokenDistance(_ distance: WorkoutCueMath.SpokenDistance, locale: Locale? = nil) -> String {
        let c = RunCuePhrase.Catalogue(locale)
        switch distance {
        case let .metres(n):
            return String(localized: "\(n) metres", bundle: c.bundle, locale: c.locale)
        case let .kilometres(n):
            return String(localized: "\(n) kilometres", bundle: c.bundle, locale: c.locale)
        case let .kilometresDecimal(value):
            return String(localized: "\(value) kilometres", bundle: c.bundle, locale: c.locale)
        case let .yards(n):
            return String(localized: "\(n) yards", bundle: c.bundle, locale: c.locale)
        case let .miles(n):
            return String(localized: "\(n) miles", bundle: c.bundle, locale: c.locale)
        case let .milesDecimal(value):
            return String(localized: "\(value) miles", bundle: c.bundle, locale: c.locale)
        }
    }

    /// "90 s" is "1 minute 30 seconds", "60 s" is "1 minute", "45 s" is
    /// "45 seconds" — the phone's `_spokenDuration`.
    static func spokenDuration(seconds: Int, locale: Locale? = nil) -> String {
        let c = RunCuePhrase.Catalogue(locale)
        let ms = WorkoutCueMath.minutesSeconds(seconds)
        if ms.minutes == 0 {
            return String(localized: "\(ms.seconds) seconds", bundle: c.bundle, locale: c.locale)
        }
        let minutes = String(localized: "\(ms.minutes) minutes", bundle: c.bundle, locale: c.locale)
        if ms.seconds == 0 { return minutes }
        return String(localized: "\(minutes) \(ms.seconds) seconds", bundle: c.bundle, locale: c.locale)
    }

    /// A whole-minute pace drops its "0 seconds", as on the phone.
    static func stepPace(secondsPerKm: Int, prefersMiles: Bool, locale: Locale? = nil) -> String {
        let c = RunCuePhrase.Catalogue(locale)
        let p = WorkoutCueMath.stepPace(secondsPerKm: secondsPerKm, prefersMiles: prefersMiles)
        if prefersMiles {
            return p.seconds == 0
                ? String(localized: "\(p.minutes) minutes per mile", bundle: c.bundle, locale: c.locale)
                : String(
                    localized: "\(p.minutes) minutes \(p.seconds) seconds per mile",
                    bundle: c.bundle, locale: c.locale)
        }
        return p.seconds == 0
            ? String(localized: "\(p.minutes) minutes per kilometre", bundle: c.bundle, locale: c.locale)
            : String(
                localized: "\(p.minutes) minutes \(p.seconds) seconds per kilometre",
                bundle: c.bundle, locale: c.locale)
    }
}

/// Which cue gets the speaker first.
enum RunCuePriority: Equatable {
    /// Splits, pace alerts, start and finish: said in the order they arrive.
    case normal
    /// A structured workout's step change, end-of-step warning and
    /// completion: said before anything still waiting, because a step change
    /// heard late is an instruction the runner has already missed.
    case step
}

/// What `RunSpeech` has yet to say. Nothing here interrupts a sentence in
/// progress — a cue cut off mid-word is worse than one a few seconds late —
/// so priority only decides the order of the cues still WAITING, and a step
/// cue replaces an older one nobody has heard yet rather than queueing behind
/// it: the runner who skipped two steps in a second wants the step they are
/// on, not a recital of the ones they passed.
struct SpeechQueue {
    struct Entry: Equatable {
        let text: String
        let priority: RunCuePriority
    }

    private(set) var pending: [Entry] = []

    var isEmpty: Bool { pending.isEmpty }

    mutating func enqueue(_ text: String, priority: RunCuePriority) {
        guard !text.isEmpty else { return }
        switch priority {
        case .normal:
            pending.append(Entry(text: text, priority: .normal))
        case .step:
            pending.removeAll { $0.priority == .step }
            pending.insert(Entry(text: text, priority: .step), at: 0)
        }
    }

    mutating func next() -> String? {
        pending.isEmpty ? nil : pending.removeFirst().text
    }
}

/// Decides which cue fires when, and hands the words to an injectable speech
/// seam. Everything audible is L4 by the layering contract
/// (`docs/features/run_recording.md` § Layering): `WorkoutManager` calls these
/// methods LAST, after every core value is committed, and they return Void —
/// nothing here can cancel a state update, and nothing here is awaited.
final class RunAnnouncer {
    /// The phone's `audio_cues` preference (`apps/mobile_android/lib/preferences.dart`),
    /// carried over `WCSession` in the same envelope as `preferred_unit`.
    /// Absent means ON, which is the phone's default.
    static let preferenceKey = "audio_cues"

    static var isEnabledByPreference: Bool {
        UserDefaults.standard.object(forKey: preferenceKey) as? Bool ?? true
    }

    /// The phone's `voice_feedback_verbosity`, carried in the same envelope.
    /// Anything but `minimal` — absence included — is `full`, the phone's
    /// default.
    static let verbosityKey = "voice_feedback_verbosity"

    /// The phone's `workout_steps` voice cue (`VoiceCue.workoutSteps` in
    /// `preferences.dart`), carried in the same envelope. Absent means ON,
    /// as an absent id does on the phone.
    static let workoutStepCuesKey = "voice_cue_workout_steps"

    static var isVerboseByPreference: Bool {
        UserDefaults.standard.string(forKey: verbosityKey) != "minimal"
    }

    static var workoutStepCuesByPreference: Bool {
        UserDefaults.standard.object(forKey: workoutStepCuesKey) as? Bool ?? true
    }

    /// Auxiliary effect seam, same shape as `RouteNavigator.playOffRouteHaptic`:
    /// the only route from this type to AVFoundation, replaced wholesale by
    /// tests so the decision half runs with no audio hardware at all.
    var speak: (String, RunCuePriority) -> Void = { RunSpeech.shared.speak($0, priority: $1) }
    var isEnabled: () -> Bool = { RunAnnouncer.isEnabledByPreference }
    var isVerbose: () -> Bool = { RunAnnouncer.isVerboseByPreference }
    var workoutStepCuesEnabled: () -> Bool = { RunAnnouncer.workoutStepCuesByPreference }
    var prefersMiles: () -> Bool = { RunFormat.prefersMiles }

    private var splits = SplitTracker()

    /// Splits spoken so far this run — the recorded half of the tracker, for
    /// the tests and for anything that wants to know without re-deriving it.
    var announcedSplits: Int { splits.lastAnnounced }

    func reset() { splits.reset() }

    /// Mark every split a continued run already banked as heard, silently.
    /// Without it the first fix after a relaunch at 80 km announces "80
    /// kilometres" as though the runner had just reached it.
    func primeSplits(distanceMetres: Double) {
        _ = splits.splitDue(distanceMetres: distanceMetres, prefersMiles: prefersMiles())
    }

    func announceStart() { emit(.started) }

    /// Fed the run's cumulative distance on every fix. The tracker advances
    /// whether or not cues are audible, so a runner who turns them on at 8 km
    /// hears the ninth split rather than the first eight back to back.
    func announceSplitIfDue(distanceMetres: Double, paceSecondsPerKm: Double?) {
        guard let index = splits.splitDue(
            distanceMetres: distanceMetres, prefersMiles: prefersMiles()
        ) else { return }
        emit(.split(index: index, paceSecondsPerKm: paceSecondsPerKm))
    }

    func announcePaceAlert(tooSlow: Bool) { emit(.paceAlert(tooSlow: tooSlow)) }

    func announceFinish(distanceMetres: Double, durationSeconds: Int) {
        emit(.finished(distanceMetres: distanceMetres, durationSeconds: durationSeconds))
    }

    /// A structured workout's cue, gated the way the phone gates it (see
    /// `WorkoutVoiceGate`). Called by `WorkoutManager` after the step it
    /// describes is already on screen, like every cue here.
    func announceWorkout(_ cue: WorkoutSpokenCue) {
        guard WorkoutVoiceGate.speaks(
            cue,
            audioCues: isEnabled(),
            workoutStepCues: workoutStepCuesEnabled(),
            verbose: isVerbose()
        ) else { return }
        speak(WorkoutCuePhrase.text(for: cue, prefersMiles: prefersMiles()), cue.priority)
    }

    private func emit(_ cue: RunCue) {
        guard isEnabled() else { return }
        speak(RunCuePhrase.text(for: cue, prefersMiles: prefersMiles()), .normal)
    }
}

/// The one place in the watch app that touches AVFoundation.
///
/// Audio session: the cue rides the app's shared session configured exactly
/// the way the phone configures its own (`ttsDuckingStrategyFor` →
/// `IosTextToSpeechAudioCategory.playback` with `mixWithOthers` + `duckOthers`,
/// mode `.voicePrompt`). `mixWithOthers` is the load-bearing option — without
/// it a cue takes the route outright and the runner's music stops for good
/// rather than dipping. The session is activated per utterance and released,
/// with `.notifyOthersOnDeactivation`, only once nothing is left to say, so a
/// split landing on top of a pace alert cannot hand the route back mid-word;
/// that is Wear's audio-focus shape. Nothing else in the app configures a
/// session, and nothing else is deactivated here.
///
/// The synthesizer is handed ONE utterance at a time out of a `SpeechQueue`,
/// rather than everything at once to queue internally, because its own queue
/// has no notion of priority: a step change arriving behind two splits would
/// be said third. A step cue goes to the front of what is still waiting; the
/// sentence in progress is never cut off.
///
/// Every fallible step is caught and logged where it happens rather than
/// widened into one outer catch: a session that will not configure must still
/// let the utterance be attempted, a voice the device has no data for must
/// still be spoken in the default voice, and neither may reach the caller —
/// `speak` returns Void and throws nothing, which is what keeps the recording
/// stack (L0–L3) unable to observe any of it.
final class RunSpeech: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = RunSpeech()

    private let synthesizer = AVSpeechSynthesizer()
    private var configured = false
    private var queue = SpeechQueue()
    /// Utterances handed to the synthesizer and not yet finished or
    /// cancelled. One in the normal course; more only after the backstop
    /// below has fired.
    private var handed = 0
    private var lastHandedAt: TimeInterval = 0
    /// How long an unanswered utterance may hold the queue while the
    /// synthesizer reports itself silent. Longer than the gap between a
    /// `speak` call and `isSpeaking` turning true, so a second cue arriving in
    /// the same instant waits its turn rather than being handed straight over.
    private static let staleAfterSeconds: TimeInterval = 5

    override private init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String, priority: RunCuePriority = .normal) {
        guard !text.isEmpty else { return }
        queue.enqueue(text, priority: priority)
        startNextIfIdle()
    }

    /// The backstop is for a delegate callback that never comes: without it
    /// one lost `didFinish` would hold every later cue forever. An utterance
    /// handed over long enough ago, beside a synthesizer that says it is
    /// silent, is taken as done.
    private func startNextIfIdle() {
        if handed > 0 {
            let waited = ProcessInfo.processInfo.systemUptime - lastHandedAt
            guard !synthesizer.isSpeaking, waited > Self.staleAfterSeconds else { return }
            debugPrint("RunSpeech: no callback for the last utterance, moving on")
            handed = 0
        }
        guard let text = queue.next() else { return }
        configureSessionIfNeeded()

        let utterance = AVSpeechUtterance(string: text)
        let tag = RunCueVoice.current
        if let voice = AVSpeechSynthesisVoice(language: tag) {
            utterance.voice = voice
        } else {
            // Best-effort, not silence: the cue is still spoken in whatever
            // voice the device defaults to, which beats saying nothing.
            debugPrint("RunSpeech: no voice for \(tag), using the system default")
        }

        handed += 1
        lastHandedAt = ProcessInfo.processInfo.systemUptime
        activateSession()
        synthesizer.speak(utterance)
    }

    private func configureSessionIfNeeded() {
        guard !configured else { return }
        configured = true
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playback,
                mode: .voicePrompt,
                options: [.mixWithOthers, .duckOthers]
            )
        } catch {
            debugPrint("RunSpeech: audio category refused: \(error)")
        }
    }

    private func activateSession() {
        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            debugPrint("RunSpeech: audio session would not activate: \(error)")
        }
    }

    /// One utterance ended: say the next, or hand the route back when there
    /// is nothing left.
    private func utteranceEnded() {
        handed = max(0, handed - 1)
        guard handed == 0 else { return }
        guard queue.isEmpty else {
            startNextIfIdle()
            return
        }
        do {
            try AVAudioSession.sharedInstance().setActive(
                false, options: .notifyOthersOnDeactivation
            )
        } catch {
            debugPrint("RunSpeech: audio session would not deactivate: \(error)")
        }
    }

    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance
    ) {
        DispatchQueue.main.async { self.utteranceEnded() }
    }

    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance
    ) {
        DispatchQueue.main.async { self.utteranceEnded() }
    }
}
