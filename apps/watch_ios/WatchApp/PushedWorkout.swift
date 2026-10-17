import Foundation

/// The kinds of step `expandWorkoutSteps` emits, by their wire token.
enum WorkoutStepKind: String, Codable, CaseIterable {
    case warmup, rep, recovery, walk, steady, cooldown
}

/// One step of today's workout as the phone expanded it. Exactly one of
/// `distanceMetres` and `durationSeconds` is set: the step ends when that
/// axis is covered.
struct PushedStep: Codable, Equatable {
    let kind: WorkoutStepKind
    let repIndex: Int?
    let repTotal: Int?
    let distanceMetres: Int?
    let durationSeconds: Int?
    let paceSecondsPerKm: Int
    let toleranceSecondsPerKm: Int
}

/// Today's planned workout, pushed by the phone (`watch_workout_push.dart`)
/// already expanded into steps. The watch runs it as given and never
/// re-derives a pace. The Swift twin of Wear OS's `PushedWorkout.kt`; both
/// decode `fixtures/watch_workout_payload.json`.
struct PushedWorkout: Codable, Equatable {
    let planWorkoutId: String
    /// The plan day, `yyyy-MM-dd`, in the runner's own calendar.
    let scheduledDate: String
    /// `plan_workouts.kind`. Carried for a later "today" complication.
    let workoutKind: String
    /// A walk-run session: no step is a pace test, so no step grades pace.
    let unpaced: Bool
    let steps: [PushedStep]

    /// Whether this is today's workout on the watch's own calendar, so a
    /// phone left unopened past midnight cannot arm a stale session.
    func isFor(_ date: Date, calendar: Calendar = .current) -> Bool {
        scheduledDate == PushedWorkout.dayString(date, calendar: calendar)
    }

    var totalDistanceMetres: Int? {
        let d = steps.compactMap(\.distanceMetres)
        return d.isEmpty ? nil : d.reduce(0, +)
    }

    var totalDurationSeconds: Int? {
        let d = steps.compactMap(\.durationSeconds)
        return d.isEmpty ? nil : d.reduce(0, +)
    }

    static func dayString(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

/// What one push says.
enum WorkoutPush: Equatable {
    /// A workout to offer.
    case workout(PushedWorkout)
    /// The phone's explicit "nothing today": drop whatever the watch holds.
    case none
    /// Not a payload this build can trust. Also drops what the watch holds,
    /// because keeping a workout the phone has since replaced would offer a
    /// session the plan no longer has.
    case rejected

    /// The payload version this build decodes; must equal
    /// `kWatchWorkoutPayloadVersion` in `watch_workout_push.dart`.
    static let payloadVersion = 1

    /// The custom watch's `WKT1` caps, which the phone applies before it
    /// pushes, restated so a payload that bypassed the phone gate still
    /// cannot reach the runner. Same values as Wear OS's `PushedWorkout.kt`.
    static let maxSteps = 64
    static let paceRange = 120...5940
    static let distanceRange = 1...1_000_000
    static let durationRange = 1...0xFFFF
    static let toleranceRange = 0...0xFF

    /// Decode one push, fail-closed. A payload with no (or an empty)
    /// `plan_workout_id` is `.none`; anything that is not exactly the shape
    /// the phone writes is `.rejected` whole, because a half-decoded session
    /// is a different session. `JSONDecoder` is what keeps a number out of a
    /// Bool, a fraction out of an Int and a number out of a String.
    static func decode(_ json: String?) -> WorkoutPush {
        guard let data = json?.data(using: .utf8),
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              envelope.v == payloadVersion
        else { return .rejected }
        guard let id = envelope.planWorkoutId, !id.isEmpty else { return .none }
        guard let raw = try? JSONDecoder().decode(RawWorkout.self, from: data),
              PushedWorkout.isDay(raw.scheduledDate),
              !raw.steps.isEmpty, raw.steps.count <= maxSteps
        else { return .rejected }
        var steps: [PushedStep] = []
        for s in raw.steps {
            guard let step = s.validated() else { return .rejected }
            steps.append(step)
        }
        return .workout(PushedWorkout(
            planWorkoutId: id,
            scheduledDate: raw.scheduledDate,
            workoutKind: raw.workoutKind,
            unpaced: raw.unpaced,
            steps: steps
        ))
    }

    /// The workout the pre-run screen offers, or nil: only one scheduled
    /// for `today` on the watch's own calendar.
    static func offered(_ push: WorkoutPush?, today: Date, calendar: Calendar = .current) -> PushedWorkout? {
        guard case .workout(let w)? = push, w.isFor(today, calendar: calendar) else { return nil }
        return w
    }

    private struct Envelope: Decodable {
        let v: Int
        let planWorkoutId: String?

        enum CodingKeys: String, CodingKey {
            case v
            case planWorkoutId = "plan_workout_id"
        }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            v = try c.decode(Int.self, forKey: .v)
            // A non-string id is "no id", as on Wear OS: nothing to offer.
            planWorkoutId = try? c.decodeIfPresent(String.self, forKey: .planWorkoutId)
        }
    }

    private struct RawWorkout: Decodable {
        let scheduledDate: String
        let workoutKind: String
        let unpaced: Bool
        let steps: [RawStep]

        enum CodingKeys: String, CodingKey {
            case scheduledDate = "scheduled_date"
            case workoutKind = "workout_kind"
            case unpaced, steps
        }
    }

    private struct RawStep: Decodable {
        let kind: String
        let repIndex: Int?
        let repTotal: Int?
        let distance: Int?
        let duration: Int?
        let hasDistance: Bool
        let hasDuration: Bool
        let pace: Int
        let tolerance: Int

        enum CodingKeys: String, CodingKey {
            case kind
            case repIndex = "rep_index"
            case repTotal = "rep_total"
            case distance = "distance_m"
            case duration = "duration_s"
            case pace = "pace_s_per_km"
            case tolerance = "tolerance_s_per_km"
        }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            kind = try c.decode(String.self, forKey: .kind)
            repIndex = try c.decodeIfPresent(Int.self, forKey: .repIndex)
            repTotal = try c.decodeIfPresent(Int.self, forKey: .repTotal)
            hasDistance = c.contains(.distance)
            hasDuration = c.contains(.duration)
            distance = try c.decodeIfPresent(Int.self, forKey: .distance)
            duration = try c.decodeIfPresent(Int.self, forKey: .duration)
            pace = try c.decode(Int.self, forKey: .pace)
            tolerance = try c.decode(Int.self, forKey: .tolerance)
        }

        func validated() -> PushedStep? {
            guard let kind = WorkoutStepKind(rawValue: kind),
                  hasDistance != hasDuration,
                  WorkoutPush.paceRange.contains(pace),
                  WorkoutPush.toleranceRange.contains(tolerance)
            else { return nil }
            if hasDistance {
                guard let d = distance, WorkoutPush.distanceRange.contains(d) else { return nil }
            } else {
                guard let d = duration, WorkoutPush.durationRange.contains(d) else { return nil }
            }
            return PushedStep(
                kind: kind,
                repIndex: repIndex,
                repTotal: repTotal,
                distanceMetres: distance,
                durationSeconds: duration,
                paceSecondsPerKm: pace,
                toleranceSecondsPerKm: tolerance
            )
        }
    }
}

extension PushedWorkout {
    /// A real calendar day in `yyyy-MM-dd`, so `2026-13-40` is refused rather
    /// than rolled over into a different date.
    static func isDay(_ s: String) -> Bool {
        let parts = s.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
              (1...12).contains(m), d >= 1
        else { return false }
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = TimeZone(identifier: "UTC")!
        guard let first = gregorian.date(from: DateComponents(year: y, month: m, day: 1)),
              let days = gregorian.range(of: .day, in: .month, for: first)
        else { return false }
        return days.contains(d)
    }
}

/// Today's workout between the phone's push and the run that follows it.
/// The JSON text is what is kept, so the recorder decodes the same bytes the
/// receiver did rather than a re-encoding of them.
enum PushedWorkoutStore {
    private static let key = "todays_workout_v1"

    static func load(defaults: UserDefaults = .standard) -> WorkoutPush? {
        guard let json = defaults.string(forKey: key) else { return nil }
        return WorkoutPush.decode(json)
    }

    static func save(json: String, defaults: UserDefaults = .standard) {
        defaults.set(json, forKey: key)
    }

    static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
    }
}
