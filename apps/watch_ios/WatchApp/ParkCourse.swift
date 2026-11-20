import Foundation

/// The park course the paired iPhone sent for live timing on this wrist
/// (#1446), and the UserDefaults slot it waits in until a run.
///
/// The phone sends it over `WCSession.transferUserInfo(_:)` under its own key,
/// `park_course`, apart from the armed route's five keys: the route is the
/// line the runner follows (`ArmedRoute`), this is what the server times them
/// by — the course's two lines, its length and its checkpoints, read off the
/// `global_segments` and `park_courses` rows. A course needs no polyline here,
/// because the box rule reads none.
///
/// Wire shape, every number a plist number:
///
/// ```
/// park_course: {
///   course_id: String, course_name: String, course_distance_m: Double,
///   start_gate_lat, start_gate_lng, start_gate_bearing_deg, start_gate_half_width_m,
///   end_gate_lat, end_gate_lng, end_gate_bearing_deg, end_gate_half_width_m,
///   checkpoint_lat: [Double], checkpoint_lng: [Double]   // parallel, at most 50
/// }
/// ```
///
/// An empty dictionary is the phone saying "no course": it clears the wrist.
struct ParkCourse: Codable, Equatable {
    let id: String
    let name: String
    let distanceMetres: Double
    let startGate: Gate
    let endGate: Gate
    let checkpointLatitudes: [Double]
    let checkpointLongitudes: [Double]

    static let payloadKey = "park_course"

    /// `park_courses.checkpoints` holds at most 50.
    static let maxCheckpoints = 50

    var checkpoints: [CourseBox.Point] {
        zip(checkpointLatitudes, checkpointLongitudes).map { CourseBox.Point(lat: $0, lng: $1) }
    }

    /// A fresh timer for one run, or nil when the course cannot be box-timed.
    func makeTimer() -> CourseBoxTimer? {
        CourseBoxTimer(startGate: startGate, endGate: endGate, distanceM: distanceMetres,
                       checkpoints: checkpoints)
    }

    enum Push: Equatable {
        case course(ParkCourse)
        /// The phone cleared the course, or sent one this build refuses.
        /// Either way the course the wrist held has been replaced, so a run
        /// must not be timed against it.
        case clear
    }

    /// What a `WCSession` payload says about the course, or nil when it says
    /// nothing (the key is absent: every other push on this session).
    static func push(in payload: [String: Any]) -> Push? {
        guard let raw = payload[payloadKey] else { return nil }
        guard let dict = raw as? [String: Any], !dict.isEmpty, let course = decode(dict) else {
            return .clear
        }
        return .course(course)
    }

    /// Fail-closed: any field this side would have to guess about refuses the
    /// whole course. A course with one line, a missing checkpoint or a wrong
    /// length would time the runner by a rule the server does not use, and
    /// tell them "Finished!" for a run that gets no time.
    static func decode(_ dict: [String: Any]) -> ParkCourse? {
        guard let id = dict["course_id"] as? String, !id.isEmpty,
              let name = dict["course_name"] as? String,
              let distance = number(dict["course_distance_m"]), distance.isFinite, distance > 0,
              let start = gate(dict, "start_gate"),
              let end = gate(dict, "end_gate"),
              let cpLat = numbers(dict["checkpoint_lat"]),
              let cpLng = numbers(dict["checkpoint_lng"]),
              cpLat.count == cpLng.count, cpLat.count <= maxCheckpoints
        else { return nil }
        for (lat, lng) in zip(cpLat, cpLng) {
            guard lat.isFinite, lng.isFinite, abs(lat) <= 90, abs(lng) <= 180 else { return nil }
        }
        return ParkCourse(id: id, name: name, distanceMetres: distance, startGate: start, endGate: end,
                          checkpointLatitudes: cpLat, checkpointLongitudes: cpLng)
    }

    private static func gate(_ dict: [String: Any], _ prefix: String) -> Gate? {
        guard let lat = number(dict["\(prefix)_lat"]),
              let lng = number(dict["\(prefix)_lng"]),
              let bearing = number(dict["\(prefix)_bearing_deg"]),
              let halfWidth = number(dict["\(prefix)_half_width_m"])
        else { return nil }
        let gate = Gate(lat: lat, lng: lng, bearingDeg: bearing, halfWidthM: halfWidth)
        return gate.isUsable && halfWidth > 0 ? gate : nil
    }

    /// A plist number: the phone's doubles arrive as `Double`, a whole-metre
    /// half-width may arrive as an integer.
    private static func number(_ value: Any?) -> Double? {
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        return nil
    }

    private static func numbers(_ value: Any?) -> [Double]? {
        guard let raw = value as? [Any] else { return nil }
        var out: [Double] = []
        out.reserveCapacity(raw.count)
        for v in raw {
            guard let d = number(v) else { return nil }
            out.append(d)
        }
        return out
    }
}

/// The course's home between a phone push and the run that follows it.
enum ParkCourseStore {
    private static let key = "park_course_v1"

    static func load(defaults: UserDefaults = .standard) -> ParkCourse? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(ParkCourse.self, from: data)
    }

    static func apply(_ push: ParkCourse.Push, defaults: UserDefaults = .standard) {
        switch push {
        case .course(let course):
            guard let data = try? JSONEncoder().encode(course) else { return }
            defaults.set(data, forKey: key)
        case .clear:
            defaults.removeObject(forKey: key)
        }
    }
}

/// What the running screen shows for the course: nothing until the runner
/// leaves the start box, "Timing started" while a lap is timed, and
/// "Finished!" with the time once one counts — kept on screen from then on,
/// so a loop's next lap opening at the same instant never hides the time the
/// runner just ran.
enum CourseTimingDisplay: Equatable {
    case timing
    case finished(seconds: Double)

    /// The display after `events`, from `current`.
    static func next(_ current: CourseTimingDisplay?, after events: [CourseTimingEvent]) -> CourseTimingDisplay? {
        var display = current
        for event in events {
            switch event {
            case .started:
                if case .finished? = display { continue }
                display = .timing
            case let .finished(startMs, endMs):
                display = .finished(seconds: (endMs - startMs) / 1000)
            }
        }
        return display
    }

    /// The buzz for `events`: one per feed, the finish outranking a start,
    /// and no start buzz once a lap has finished (a loop's next lap opens on
    /// the finish itself).
    static func haptic(for events: [CourseTimingEvent], before current: CourseTimingDisplay?) -> CourseTimingHaptic? {
        if events.contains(where: { $0.finishSeconds != nil }) { return .finished }
        if case .finished? = current { return nil }
        if events.contains(where: { if case .started = $0 { return true } else { return false } }) {
            return current == .timing ? nil : .started
        }
        return nil
    }

    /// A course time as the board reads it: whole seconds, rounded to the
    /// nearest, `8:42:11` from an hour and `21:42` under one — the rule of
    /// the web's `formatDuration`, the phone's `formatEffortTime` and Wear's
    /// `formatCourseTime`, so the wrist never reads a second short of them.
    static func clock(seconds: Double) -> String {
        let total = seconds.isFinite ? Int(max(0, seconds).rounded()) : 0
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

enum CourseTimingHaptic: Equatable {
    case started
    case finished
}
