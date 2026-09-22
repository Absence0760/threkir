import ActivityKit
import Foundation

/// The in-progress run as the lock screen and the Dynamic Island see it.
///
/// Compiled into BOTH the `Runner` app (which requests and updates the
/// activity) and the `RunActivityExtension` widget extension (which renders
/// it) — ActivityKit matches the two ends by this type, so one file in two
/// targets is the only shape that works.
///
/// It has no static attributes on purpose. Everything the widget draws can
/// change during a run, including the header, which carries the paused state
/// in words; a static copy of the activity label beside it would be a second
/// string saying the same thing, localized in the same place, able to drift.
///
/// Every field is a finished, already-localized, already-unit-formatted
/// string. The extension formats nothing and translates nothing: Dart owns
/// both, from the same `AppLocalizations` and the same `UnitFormat` the run
/// screen reads, so the lock screen cannot disagree with the screen behind it
/// and the extension ships with no String Catalog of its own. The one
/// exception is `timerStart`, which is a date rather than a string precisely
/// so the widget can tick the clock itself between updates.
@available(iOS 16.2, *)
struct RunActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// Lock-screen header, e.g. "Run" or "Run • paused".
        var title: String
        var paused: Bool
        /// What the run's elapsed clock counts up from: `now - elapsed` at
        /// the moment the frame was built, so `Text(_:style:.timer)` renders
        /// a live clock with no further updates. Meaningless while `paused`,
        /// where `elapsedText` is shown instead.
        var timerStart: Date
        /// The frozen clock shown while `paused`.
        var elapsedText: String
        var timeLabel: String
        var distanceLabel: String
        var distanceText: String
        var paceLabel: String
        var paceText: String
    }
}

@available(iOS 16.2, *)
extension RunActivityAttributes.ContentState {
    /// Build a frame from the method channel's argument map.
    ///
    /// Returns nil rather than substituting defaults when anything is
    /// missing: a lock screen showing an empty distance beside a live clock
    /// reads as a broken run, and dropping the update leaves the last good
    /// frame standing, which is the honest degradation for an L4 effect.
    init?(arguments: [String: Any]) {
        guard let title = arguments["title"] as? String,
              let elapsedText = arguments["elapsed_text"] as? String,
              let timeLabel = arguments["time_label"] as? String,
              let distanceLabel = arguments["distance_label"] as? String,
              let distanceText = arguments["distance_text"] as? String,
              let paceLabel = arguments["pace_label"] as? String,
              let paceText = arguments["pace_text"] as? String,
              let startMs = arguments["timer_start_epoch_ms"] as? NSNumber
        else { return nil }
        self.init(
            title: title,
            paused: (arguments["paused"] as? NSNumber)?.boolValue ?? false,
            timerStart: Date(timeIntervalSince1970: startMs.doubleValue / 1000),
            elapsedText: elapsedText,
            timeLabel: timeLabel,
            distanceLabel: distanceLabel,
            distanceText: distanceText,
            paceLabel: paceLabel,
            paceText: paceText
        )
    }
}
