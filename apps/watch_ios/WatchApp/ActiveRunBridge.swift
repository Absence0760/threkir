// Lightweight shared-storage handoff between the WatchApp main target
// (which owns the HKWorkoutSession) and the Complication widget
// extension target (which only needs to render numbers).
//
// Lives under WatchApp/ rather than Complications/ because both
// targets need to compile this type. The complication target is added
// in Xcode (see Complications/README.md) with target-membership on
// this file ticked for both WatchApp and the new ComplicationExtension.
//
// The complication can't pull data directly from `WorkoutManager`
// because each widget extension runs in its own process — they don't
// share memory with the host app. The standard fix on watchOS is an
// **App Group** + a shared `UserDefaults`: the host app writes a tiny
// snapshot whenever the workout state changes, and the complication
// reads it on every timeline request.
//
// Why a 5-field snapshot instead of just `workoutManager.something`:
//
//  - Per-tick GPS deltas would burn complication-refresh budget. We
//    only re-snapshot on stage transitions (start, pause, resume,
//    stop) and at half-km / 30 s ticks.
//  - The complication target stays decoupled from HealthKit /
//    CoreLocation — much smaller binary, simpler entitlements.
//  - The same on-disk shape can later be consumed by an iOS Lock
//    Screen widget without dragging the workout types along.

import Foundation

/// The on-wire representation of the active-run state. Five POD
/// fields, JSON-encoded into shared UserDefaults under one key.
public struct ActiveRunSnapshot: Codable {
    public let isActive: Bool
    public let elapsedSeconds: Int
    public let distanceMeters: Double
    public let paceSecPerKm: Double?
    public let lastUpdatedEpoch: Double

    public static let empty = ActiveRunSnapshot(
        isActive: false,
        elapsedSeconds: 0,
        distanceMeters: 0,
        paceSecPerKm: nil,
        lastUpdatedEpoch: 0,
    )
}

/// Today's planned workout as the complication's "today" state draws it
/// while no run is live: the kind and the session's headline distance or
/// duration, raw, so the face formats them in the unit the runner reads at
/// the moment it renders rather than the one in force when the phone pushed.
/// The app writes it from the phone's `todays_workout` push; the extension
/// only reads it.
public struct TodayWorkoutGlance: Codable, Equatable {
    /// The plan day, `yyyy-MM-dd`, as the phone pushed it.
    public let scheduledDate: String
    /// `plan_workouts.kind`, e.g. `tempo`.
    public let workoutKind: String
    public let distanceMetres: Int?
    public let durationSeconds: Int?

    public func isFor(_ date: Date, calendar: Calendar = .current) -> Bool {
        scheduledDate == TodayWorkoutGlance.dayString(date, calendar: calendar)
    }

    /// `date` as a `yyyy-MM-dd` day in `calendar`'s time zone, always in
    /// GREGORIAN reckoning: the phone writes the plan day that way, and a
    /// wrist set to the Buddhist or Japanese calendar would otherwise read
    /// 2026 as 2569 or 8 and never match a day it was sent.
    public static func dayString(_ date: Date, calendar: Calendar = .current) -> String {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        let c = gregorian.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

/// Bridge surface used by both the widget extension (read) and the
/// host app (write). The App Group identifier is centralised here so
/// renaming it later only touches one file.
public enum ActiveRunBridge {
    /// The App Group must be registered on **both** the host app
    /// target and the widget-extension target — see the watchOS
    /// Capabilities pane in Xcode and the README in this directory.
    public static let appGroup = "group.com.threkir.app.activerun"

    /// The widget's `kind`, centralised here for the same reason `appGroup`
    /// is: it was a hand-written literal in two different TARGETS — the host
    /// app's `WidgetCenter.shared.reloadTimelines(ofKind:)` and the widget's
    /// own `let kind` — with nothing able to compare them.
    ///
    /// `reloadTimelines(ofKind:)` with a kind no widget declares is a silent
    /// no-op. It does not throw, does not log, and returns nothing to check.
    /// So a rename on either side leaves the host writing snapshots the
    /// complication never gets told to re-read, and the watch face keeps
    /// showing "ready to run" for up to the platform's own refresh budget
    /// (~30 minutes) after the runner has started — which is the whole
    /// failure this nudge exists to prevent, arrived at from the other
    /// direction. Deriving both sites from one constant is what removes the
    /// possibility rather than guarding against it.
    public static let complicationKind = "ActiveRunComplication"

    private static let key = "active_run_snapshot_v1"

    private static let todayKey = "todays_workout_glance_v1"

    /// The km/mi preference key, read by the run screen and the watch face.
    public static let preferredUnitKey = "preferred_unit"

    /// `UserDefaults.standard` means a DIFFERENT container in the widget
    /// extension than in the host app, so the complication read a suite the
    /// phone never writes and a runner who chose miles saw kilometres on the
    /// watch face while the run screen beside it read miles. The App Group is
    /// the only defaults both targets share; `.standard` stays as the
    /// fallback so the host is still correct before the first mirror write.
    public static func prefersMiles() -> Bool {
        if let shared = defaults?.string(forKey: preferredUnitKey) {
            return shared == "mi"
        }
        return UserDefaults.standard.string(forKey: preferredUnitKey) == "mi"
    }

    /// Mirrors the preference into the App Group so the extension can read
    /// it. Called wherever `preferred_unit` is written.
    public static func mirrorPreferredUnit(_ unit: String) {
        defaults?.set(unit, forKey: preferredUnitKey)
    }

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroup)
    }

    public static func read() -> ActiveRunSnapshot {
        guard
            let data = defaults?.data(forKey: key),
            let snap = try? JSONDecoder().decode(ActiveRunSnapshot.self, from: data)
        else {
            return .empty
        }
        return snap
    }

    /// Called by the host app's `WorkoutManager` whenever workout
    /// state changes meaningfully. After writing, the host should
    /// also call `WidgetCenter.shared.reloadTimelines(ofKind:)` so
    /// the complication picks up the new state on the next bind —
    /// without that nudge the platform may keep the previous timeline
    /// for up to ~30 minutes.
    public static func write(_ snapshot: ActiveRunSnapshot) {
        guard let defaults else { return }
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: key)
        }
    }

    public static func clear() {
        defaults?.removeObject(forKey: key)
    }

    public static func readToday() -> TodayWorkoutGlance? {
        guard let data = defaults?.data(forKey: todayKey) else { return nil }
        return try? JSONDecoder().decode(TodayWorkoutGlance.self, from: data)
    }

    /// Stores `glance`, or clears the slot for nil. Returns whether the slot
    /// changed, so the app can skip a timeline reload for a push that says
    /// what the face already shows — watchOS budgets complication reloads,
    /// and the app republishes the stored push on every launch.
    @discardableResult
    public static func writeToday(_ glance: TodayWorkoutGlance?) -> Bool {
        guard let defaults, readToday() != glance else { return false }
        if let glance, let data = try? JSONEncoder().encode(glance) {
            defaults.set(data, forKey: todayKey)
        } else {
            defaults.removeObject(forKey: todayKey)
        }
        return true
    }
}
