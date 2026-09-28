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
    /// rather than to the development language's keys.
    private struct Catalogue {
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

    /// Auxiliary effect seam, same shape as `RouteNavigator.playOffRouteHaptic`:
    /// the only route from this type to AVFoundation, replaced wholesale by
    /// tests so the decision half runs with no audio hardware at all.
    var speak: (String) -> Void = { RunSpeech.shared.speak($0) }
    var isEnabled: () -> Bool = { RunAnnouncer.isEnabledByPreference }
    var prefersMiles: () -> Bool = { RunFormat.prefersMiles }

    private var splits = SplitTracker()

    /// Splits spoken so far this run — the recorded half of the tracker, for
    /// the tests and for anything that wants to know without re-deriving it.
    var announcedSplits: Int { splits.lastAnnounced }

    func reset() { splits.reset() }

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

    private func emit(_ cue: RunCue) {
        guard isEnabled() else { return }
        speak(RunCuePhrase.text(for: cue, prefersMiles: prefersMiles()))
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
/// with `.notifyOthersOnDeactivation`, only once the LAST one finishes, so a
/// split landing on top of a pace alert cannot hand the route back mid-word;
/// that ref-count is Wear's audio-focus shape. Nothing else in the app
/// configures a session, and nothing else is deactivated here.
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
    private var pendingUtterances = 0

    override private init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String) {
        guard !text.isEmpty else { return }
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

        pendingUtterances += 1
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

    private func releaseSessionIfIdle() {
        pendingUtterances = max(0, pendingUtterances - 1)
        guard pendingUtterances == 0 else { return }
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
        DispatchQueue.main.async { self.releaseSessionIfIdle() }
    }

    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance
    ) {
        DispatchQueue.main.async { self.releaseSessionIfIdle() }
    }
}
