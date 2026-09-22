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

    static func entry(from snapshot: ActiveRunSnapshot, now: Date) -> ActiveRunEntry {
        let age = now.timeIntervalSince1970 - snapshot.lastUpdatedEpoch
        let isActive = snapshot.isActive && snapshot.lastUpdatedEpoch > 0 && age < staleAfter
        return ActiveRunEntry(
            date: now,
            isActive: isActive,
            elapsedSeconds: snapshot.elapsedSeconds,
            distanceMeters: snapshot.distanceMeters,
            paceSecPerKm: snapshot.paceSecPerKm,
        )
    }

    static func entries(from snapshot: ActiveRunSnapshot, now: Date) -> [ActiveRunEntry] {
        let head = entry(from: snapshot, now: now)
        guard head.isActive else { return [head] }
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
