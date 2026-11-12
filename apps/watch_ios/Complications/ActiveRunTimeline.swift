// The active-run complication's pure layer: the timeline entry, the
// snapshot -> entry shaping, and the one composed string the views draw.
//
// Split out of `ActiveRunComplication.swift` so it can be a member of BOTH
// the `WatchAppComplication` extension and the `WatchApp` app target, the
// way `ActiveRunBridge.swift` is. `ActiveRunComplication.swift` itself
// cannot be: it declares the `@main` widget bundle, and a module may hold
// only one. With this file in the app target, `WatchAppTests` reaches the
// same source the extension compiles, which is the only way anything in
// this repo tests the code the watch face runs — the extension has no test
// host of its own.

import Foundation
import WidgetKit

struct ActiveRunEntry: TimelineEntry {
    let date: Date
    let isActive: Bool
    let elapsedSeconds: Int
    let distanceMeters: Double
    let paceSecPerKm: Double?
    /// Today's planned workout, set only on an idle entry whose own date is
    /// the workout's day.
    var today: TodayWorkoutGlance? = nil
}

enum ActiveRunTimeline {
    /// The writer stamps `lastUpdatedEpoch` on every state transition so the
    /// reader can tell a live run from a stale snapshot. If the host app is
    /// killed mid-run without a clean stop/reset, `isActive` stays true and
    /// the watch face would show a phantom run until the next launch clears
    /// it. A snapshot older than this ceiling reads as inactive. The ceiling
    /// sits far beyond any realistic Apple-Watch run (battery dies long
    /// before a day), so a genuine long run is never wrongly hidden.
    static let staleAfter: TimeInterval = 24 * 60 * 60

    /// While a run is live the timeline carries `activeEntryCount` entries
    /// `activeEntryStride` apart, so the elapsed-time *display* advances
    /// without the complication consuming a real refresh per tick — the
    /// platform throttles complication refreshes to ~50/day per app. The
    /// host app reloads the timeline on stage transitions (start, pause,
    /// resume, stop), which overwrites this schedule with fresher data.
    static let activeEntryCount = 10
    static let activeEntryStride: TimeInterval = 30

    /// A live run always wins the face. Today's workout shows only when no
    /// run is, and only on its own day by the watch's calendar — the rule
    /// `WorkoutPush.offered` applies to the pre-run screen, so the face never
    /// names a session the Start button would not follow.
    static func entry(
        from snapshot: ActiveRunSnapshot,
        today glance: TodayWorkoutGlance? = nil,
        now: Date,
        calendar: Calendar = .current
    ) -> ActiveRunEntry {
        let age = now.timeIntervalSince1970 - snapshot.lastUpdatedEpoch
        let isActive = snapshot.isActive && snapshot.lastUpdatedEpoch > 0 && age < staleAfter
        let shown = isActive ? nil : glance.flatMap { $0.isFor(now, calendar: calendar) ? $0 : nil }
        return ActiveRunEntry(
            date: now,
            isActive: isActive,
            elapsedSeconds: snapshot.elapsedSeconds,
            distanceMeters: snapshot.distanceMeters,
            paceSecPerKm: snapshot.paceSecPerKm,
            today: shown
        )
    }

    /// An idle face holding today's workout carries a second entry at the
    /// next local midnight, where the workout's day ends and the face drops
    /// back to idle with no app running to tell it. The same entry is what
    /// shows a workout dated tomorrow when the phone's day is ahead of the
    /// wrist's.
    static func entries(
        from snapshot: ActiveRunSnapshot,
        today glance: TodayWorkoutGlance? = nil,
        now: Date,
        calendar: Calendar = .current
    ) -> [ActiveRunEntry] {
        let head = entry(from: snapshot, today: glance, now: now, calendar: calendar)
        guard head.isActive else {
            guard let glance,
                  let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)),
                  head.today != nil || glance.isFor(midnight, calendar: calendar)
            else { return [head] }
            return [head, entry(from: snapshot, today: glance, now: midnight, calendar: calendar)]
        }
        return (0..<activeEntryCount).map { i in
            let dt = activeEntryStride * Double(i)
            return ActiveRunEntry(
                date: now.addingTimeInterval(dt),
                isActive: true,
                elapsedSeconds: head.elapsedSeconds + Int(dt),
                distanceMeters: head.distanceMeters,
                paceSecPerKm: head.paceSecPerKm,
            )
        }
    }

    /// Whether the system should ask for a fresh timeline once this one has
    /// run out: a live run's schedule is ten entries deep, and an idle one
    /// with a midnight rollover needs the next day's reading. A plain idle
    /// face waits for the app's next reload instead of spending budget.
    static func reloadsAtEnd(_ entries: [ActiveRunEntry]) -> Bool {
        entries.first?.isActive == true || entries.count > 1
    }

    /// The plan's word for a workout kind, the phone's and the web's
    /// verbatim. A kind this build does not know reads as the generic
    /// heading rather than a raw token. `rest` is absent because the phone
    /// never pushes a rest day: it has no steps to follow.
    static func kindLabel(_ kind: String) -> String {
        switch kind {
        case "easy": return String(localized: "workoutKind.easy")
        case "long": return String(localized: "workoutKind.long")
        case "recovery": return String(localized: "workoutKind.recovery")
        case "tempo": return String(localized: "workoutKind.tempo")
        case "interval": return String(localized: "workoutKind.interval")
        case "marathon_pace": return String(localized: "workoutKind.marathon_pace")
        case "walk_run": return String(localized: "workoutKind.walk_run")
        case "race": return String(localized: "workoutKind.race")
        default: return String(localized: "Today's workout")
        }
    }

    /// The session's headline: its distance when any step is measured in
    /// distance, else its time, else nothing. The pre-run screen's summary
    /// shows both for a mixed session; a face has room for one.
    static func todayHeadline(_ glance: TodayWorkoutGlance) -> String? {
        if let d = glance.distanceMetres {
            return RunFormat.distance(metres: Double(d), fractionDigits: 1)
        }
        if let t = glance.durationSeconds { return formatElapsed(t) }
        return nil
    }

    /// Kind and headline on one line, a `String` for the reason `statLine`
    /// is one.
    static func todayLine(_ glance: TodayWorkoutGlance) -> String {
        [kindLabel(glance.workoutKind), todayHeadline(glance)]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    /// Distance and pace on one line, assembled OUTSIDE any `Text` / `Label`
    /// literal. Both halves are already formatted and already localized, so a
    /// literal carrying the interpolations would be a `LocalizedStringKey`
    /// lookup for a key with nothing in it to translate — and Xcode's next
    /// string extraction would add that key to `Localizable.xcstrings`, where
    /// the locale-parity guard would then demand six translations of a middle
    /// dot. Passing a `String` selects the non-localizing overload instead.
    static func statLine(_ entry: ActiveRunEntry) -> String {
        "\(formatDistanceKm(entry.distanceMeters)) · \(formatPaceSecPerKm(entry.paceSecPerKm))"
    }
}
