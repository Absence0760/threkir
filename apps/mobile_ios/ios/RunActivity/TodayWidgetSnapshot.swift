import Foundation

/// The Today widget's shared half: the App Group, the stored key, the widget
/// kind, the snapshot decoder and the rule that picks what a given day shows.
///
/// Compiled into BOTH the `Runner` app (whose `HomeWidgetBridge` stores the
/// snapshot and reloads the widget) and the `RunActivityExtension` widget
/// extension (which renders it), the way `RunActivityAttributes.swift` is. One
/// file in two targets is what keeps the group, the key and the kind from
/// being spelled twice: `reloadTimelines(ofKind:)` with a kind no widget
/// declares, and a suite name the other process never reads, both fail in
/// silence. It also puts the decoder in reach of `RunnerTests`.
///
/// The snapshot is written by Dart over `run_app/home_widget`, and every
/// string in it is already localized and unit-formatted: like the Live
/// Activity, this side formats nothing and translates nothing. The contract
/// is shared with the Android widget, which reads the same JSON.
enum TodayWidget {
    /// Its own group rather than one of the two the app already holds: the
    /// share extension clears `group.com.threkir.app.share`'s root on every
    /// activation, and `group.com.threkir.app.activerun` is the watch's.
    /// Runner.entitlements and RunActivity.entitlements both carry it, which
    /// `TodayWidgetSnapshotTests` reads off disk.
    static let appGroup = "group.com.threkir.app.widget"
    static let snapshotKey = "today_snapshot_json"
    static let kind = "TodayWorkoutWidget"
    static let snapshotVersion = 1

    /// The snapshot covers the write day and the six after it, so the widget
    /// can roll over at each local midnight for a week without the app.
    static let coveredDays = 7

    static let urlScheme = "com.threkir.app"

    static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroup)
    }

    static func storedJSON(in defaults: UserDefaults? = sharedDefaults) -> String? {
        defaults?.string(forKey: snapshotKey)
    }

    /// `date` as a `yyyy-MM-dd` day in `calendar`'s time zone, always in
    /// GREGORIAN reckoning: Dart writes the plan days that way, and a phone set
    /// to the Buddhist or Japanese calendar would otherwise read 2026 as 2569
    /// or 8 and never match a day it was sent.
    static func dayString(_ date: Date, calendar: Calendar = .current) -> String {
        let c = gregorian(in: calendar).dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// When the widget's timeline holds an entry: now, then every local
    /// midnight the snapshot covers past today. The last of them falls after
    /// the snapshot's final day, so a phone whose app has not run for a week
    /// shows the snapshot's own "open the app" line instead of a stale
    /// workout, and the timeline asks for a reload there.
    static func timelineDates(from now: Date, calendar: Calendar = .current) -> [Date] {
        let cal = gregorian(in: calendar)
        let start = cal.startOfDay(for: now)
        let midnights = (1...coveredDays).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
        return [now] + midnights
    }

    static var plansURL: URL {
        URL(string: "\(urlScheme)://plans")!
    }

    static func planURL(_ planId: String) -> URL? {
        guard isSafeId(planId) else { return nil }
        return URL(string: "\(urlScheme)://plans/\(planId)")
    }

    static func workoutURL(planId: String, workoutId: String) -> URL? {
        guard isSafeId(planId), isSafeId(workoutId) else { return nil }
        return URL(string: "\(urlScheme)://plans/\(planId)/workouts/\(workoutId)")
    }

    /// Ids are uuids. Anything else is refused rather than escaped into a
    /// path segment, so a malformed snapshot can only ever cost the tap its
    /// precision, never point it somewhere else.
    private static func isSafeId(_ id: String) -> Bool {
        !id.isEmpty && id.count <= 64 && id.unicodeScalars.allSatisfy { idCharacters.contains($0) }
    }

    private static let idCharacters = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-"
    )

    private static func gregorian(in calendar: Calendar) -> Calendar {
        var g = Calendar(identifier: .gregorian)
        g.timeZone = calendar.timeZone
        return g
    }
}

/// One decoded snapshot. Fail-closed at the narrowest scope that keeps the
/// widget honest: an unreadable envelope is no snapshot, an unknown version
/// keeps only what the stale line needs, and one unreadable day costs that
/// day alone.
struct TodayWidgetSnapshot: Equatable {
    struct Labels: Decodable, Equatable {
        let header: String
        let noPlan: String
        let noPlanAction: String
        let nothingScheduled: String
        let stale: String
        let restDay: String
        let done: String
        let skipped: String

        enum CodingKeys: String, CodingKey {
            case header
            case noPlan = "no_plan"
            case noPlanAction = "no_plan_action"
            case nothingScheduled = "nothing_scheduled"
            case stale
            case restDay = "rest_day"
            case done
            case skipped
        }
    }

    enum DayState: String {
        case workout, done, skipped, rest, none
    }

    struct Day: Equatable {
        let date: String
        /// Nil for a state this build does not know, which renders as stale
        /// rather than as a guess.
        let state: DayState?
        let title: String
        let detail: String
        let planWorkoutId: String?
    }

    let version: Int
    let planId: String?
    /// Nil only on a snapshot of another version that carries none this
    /// build can read.
    let labels: Labels?
    let days: [Day]

    /// Nil for no snapshot at all: nothing stored, not JSON, or no integer
    /// `v`. A v1 snapshot without its labels is nil too, because every state
    /// the widget can draw takes its words from them.
    static func decode(_ json: String?) -> TodayWidgetSnapshot? {
        guard let data = json?.data(using: .utf8),
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data)
        else { return nil }
        let planId = envelope.planId.flatMap { $0.isEmpty ? nil : $0 }
        guard envelope.v == TodayWidget.snapshotVersion else {
            return TodayWidgetSnapshot(version: envelope.v, planId: planId, labels: envelope.labels, days: [])
        }
        guard let labels = envelope.labels else { return nil }
        return TodayWidgetSnapshot(
            version: envelope.v,
            planId: planId,
            labels: labels,
            days: envelope.days.compactMap(\.day)
        )
    }

    /// What the widget shows on `date`'s local day.
    func content(on date: Date, calendar: Calendar = .current) -> TodayWidgetContent {
        guard let labels else { return .empty }
        let planURL = planId.flatMap(TodayWidget.planURL) ?? TodayWidget.plansURL
        let stale = TodayWidgetContent(
            kind: .stale, header: labels.header, title: labels.stale, detail: "", badge: nil, url: planURL
        )
        guard version == TodayWidget.snapshotVersion else { return stale }
        guard let planId else {
            return TodayWidgetContent(
                kind: .noPlan,
                header: labels.header,
                title: labels.noPlan,
                detail: labels.noPlanAction,
                badge: nil,
                url: TodayWidget.plansURL
            )
        }
        let today = TodayWidget.dayString(date, calendar: calendar)
        guard let day = days.first(where: { $0.date == today }), let state = day.state else { return stale }
        let workoutURL = day.planWorkoutId
            .flatMap { TodayWidget.workoutURL(planId: planId, workoutId: $0) } ?? planURL
        switch state {
        case .workout:
            return TodayWidgetContent(
                kind: .workout, header: labels.header, title: day.title, detail: day.detail,
                badge: nil, url: workoutURL
            )
        case .done:
            return TodayWidgetContent(
                kind: .done, header: labels.header, title: day.title, detail: day.detail,
                badge: labels.done, url: workoutURL
            )
        case .skipped:
            return TodayWidgetContent(
                kind: .skipped, header: labels.header, title: day.title, detail: day.detail,
                badge: labels.skipped, url: workoutURL
            )
        case .rest:
            return TodayWidgetContent(
                kind: .rest, header: labels.header,
                title: day.title.isEmpty ? labels.restDay : day.title, detail: day.detail,
                badge: nil, url: planURL
            )
        case .none:
            return TodayWidgetContent(
                kind: .nothingScheduled, header: labels.header, title: labels.nothingScheduled,
                detail: "", badge: nil, url: planURL
            )
        }
    }

    private struct Envelope: Decodable {
        let v: Int
        let planId: String?
        let labels: Labels?
        let days: [LossyDay]

        enum CodingKeys: String, CodingKey {
            case v
            case planId = "plan_id"
            case labels
            case days
        }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            v = try c.decode(Int.self, forKey: .v)
            planId = try? c.decodeIfPresent(String.self, forKey: .planId)
            labels = try? c.decodeIfPresent(Labels.self, forKey: .labels)
            days = (try? c.decodeIfPresent([LossyDay].self, forKey: .days)) ?? []
        }
    }

    /// One `days` element, or nil when it is not one: without this, a single
    /// malformed day would fail the array and blank the whole week.
    private struct LossyDay: Decodable {
        let day: Day?

        enum CodingKeys: String, CodingKey {
            case date, state, title, detail
            case planWorkoutId = "plan_workout_id"
        }

        init(from decoder: any Decoder) {
            guard let c = try? decoder.container(keyedBy: CodingKeys.self),
                  let date = try? c.decode(String.self, forKey: .date),
                  let state = try? c.decode(String.self, forKey: .state)
            else {
                day = nil
                return
            }
            let title: String? = try? c.decodeIfPresent(String.self, forKey: .title)
            let detail: String? = try? c.decodeIfPresent(String.self, forKey: .detail)
            let workoutId: String? = try? c.decodeIfPresent(String.self, forKey: .planWorkoutId)
            day = Day(
                date: date,
                state: DayState(rawValue: state),
                title: title ?? "",
                detail: detail ?? "",
                planWorkoutId: workoutId.flatMap { $0.isEmpty ? nil : $0 }
            )
        }
    }
}

/// What one family view draws for one moment: already-localized strings
/// from the snapshot, plus where a tap goes. `empty` has no words at all —
/// nothing stored, or nothing this build can read — and the views draw the
/// app's mark for it rather than inventing English.
struct TodayWidgetContent: Equatable {
    enum Kind: Equatable {
        case empty, noPlan, stale, workout, done, skipped, rest, nothingScheduled
    }

    let kind: Kind
    let header: String
    let title: String
    let detail: String
    /// "Done" / "Skipped" beside a workout that is no longer to do.
    let badge: String?
    /// Nil only for `empty`, where a tap simply opens the app.
    let url: URL?

    static let empty = TodayWidgetContent(
        kind: .empty, header: "", title: "", detail: "", badge: nil, url: nil
    )

    /// `snapshot`'s content on `date`, or `empty` when there is none.
    static func of(
        _ snapshot: TodayWidgetSnapshot?,
        on date: Date,
        calendar: Calendar = .current
    ) -> TodayWidgetContent {
        snapshot?.content(on: date, calendar: calendar) ?? .empty
    }

    /// The one-line form the inline lock-screen family has room for.
    var line: String {
        [title, badge ?? detail].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}
