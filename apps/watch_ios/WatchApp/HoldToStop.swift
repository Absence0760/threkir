import Foundation

/// The Stop control's accidental-press guard.
///
/// Stopping does not destroy the run — `PostRunView` still holds it, its track
/// is still on disk and Sync Run is still offered — so it earns no
/// confirmation dialog (`docs/architecture/conventions.md` § Destructive
/// actions: one guard, never two). What it does end is the RECORDING, and a
/// wrist brushed against a sleeve is the likeliest way for that to happen, so
/// the control is gated on a deliberate press instead. Same 800 ms as Wear
/// OS's `HoldToStopButton`, which has required it since it shipped.
enum HoldToStop {
    /// How long the press must be held before the stop fires.
    static let duration: TimeInterval = 0.8

    /// Ring fill for a press that began `elapsed` seconds ago, 0...1.
    ///
    /// A negative or non-finite reading is 0 rather than clamped upward: the
    /// ring is a promise about how much longer to hold, and an unreadable
    /// clock must not read as nearly done.
    static func progress(elapsed: TimeInterval) -> Double {
        guard elapsed.isFinite, elapsed > 0 else { return 0 }
        return min(elapsed / duration, 1)
    }

    /// Whether a press held for `elapsed` seconds has earned the stop.
    static func isComplete(elapsed: TimeInterval) -> Bool {
        progress(elapsed: elapsed) >= 1
    }
}
