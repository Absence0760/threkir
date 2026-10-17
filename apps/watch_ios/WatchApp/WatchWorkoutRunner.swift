import Foundation

/// What one feed of totals produced, in order.
enum WatchWorkoutEvent: Equatable {
    /// A step began. `previous` is -1 for the first one.
    case transition(previous: Int, current: Int)
    /// The end of the current step is close: the last 50 m of a distance
    /// step over 100 m, or the last 10 s of a timed step over 20 s.
    case warning(index: Int)
    /// The runner is well off the step's target pace, rate-limited to one
    /// per `WatchWorkoutRunner.driftCueIntervalSeconds`.
    case paceDrift(index: Int, ahead: Bool, deltaSecondsPerKm: Int)
    case complete
}

/// One step's planned-vs-actual row, `runs.metadata.workout_step_results[]`.
struct WorkoutStepResultRecord: Codable, Equatable {
    let stepIndex: Int
    let kind: String
    let repIndex: Int?
    let repTotal: Int?
    let targetDistanceMetres: Double
    let targetDurationSeconds: Int?
    let actualDistanceMetres: Double
    let targetPaceSecondsPerKm: Int
    let actualPaceSecondsPerKm: Int?
    let toleranceSecondsPerKm: Int
    let durationSeconds: Int
    let status: String

    /// The registry's snake_case names, so the DEBUG direct upload encodes
    /// the row the phone's runner writes.
    enum CodingKeys: String, CodingKey {
        case stepIndex = "step_index"
        case kind
        case repIndex = "rep_index"
        case repTotal = "rep_total"
        case targetDistanceMetres = "target_distance_m"
        case targetDurationSeconds = "target_duration_s"
        case actualDistanceMetres = "actual_distance_m"
        case targetPaceSecondsPerKm = "target_pace_sec_per_km"
        case actualPaceSecondsPerKm = "actual_pace_sec_per_km"
        case toleranceSecondsPerKm = "tolerance_sec_per_km"
        case durationSeconds = "duration_s"
        case status
    }

    /// The shape `WorkoutStepResult.toJson` writes on the phone. Plist-safe,
    /// because it rides `WCSession.transferFile` metadata, where a non-plist
    /// value costs the whole transfer: an unmeasured pace is OMITTED rather
    /// than sent as `NSNull`, and every reader takes absence as null.
    var envelopeValue: [String: Any] {
        var out: [String: Any] = [
            "step_index": stepIndex,
            "kind": kind,
            "target_distance_m": targetDistanceMetres,
            "actual_distance_m": actualDistanceMetres,
            "target_pace_sec_per_km": targetPaceSecondsPerKm,
            "tolerance_sec_per_km": toleranceSecondsPerKm,
            "duration_s": durationSeconds,
            "status": status,
        ]
        if let repIndex { out["rep_index"] = repIndex }
        if let repTotal { out["rep_total"] = repTotal }
        if let targetDurationSeconds { out["target_duration_s"] = targetDurationSeconds }
        if let actualPaceSecondsPerKm { out["actual_pace_sec_per_km"] = actualPaceSecondsPerKm }
        return out
    }
}

/// The review a run started from a pushed workout carries.
struct WorkoutReview: Codable, Equatable {
    let planWorkoutId: String
    let adherence: String
    let steps: [WorkoutStepResultRecord]
}

/// What the running screen shows about the workout.
struct WatchWorkoutView: Equatable {
    /// Nil once the workout is complete.
    let step: PushedStep?
    let index: Int
    let stepCount: Int
    /// Metres left on a distance step, nil on a timed one.
    let remainingMetres: Double?
    /// Seconds left on a timed step, nil on a distance one.
    let remainingSeconds: Int?
}

/// The structured-workout step runner, a port of the phone's
/// `packages/run_recorder/lib/src/workout_runner.dart` (the reference) and a
/// twin of Wear OS's `WorkoutRunner.kt`, held to the same vectors in
/// `fixtures/watch_workout_payload.json` § runner_vectors. Pure: fed the
/// run's totals, it returns what happened, and owns no clock or haptic.
///
/// `onTotals` takes ACTIVE elapsed time, the clock the phone's runner reads,
/// so a timed recovery does not run out while the recording is paused.
///
/// Ported: auto-advance on either axis with the overshoot carried into the
/// next step, the end-of-step warning, the 45 s pace-drift cue on paced
/// steps, manual skip, per-step results and the adherence roll-up. Not
/// ported, for decisions § 354's reasons: rewind, abandon and the halfway cue.
final class WatchWorkoutRunner {
    static let completed = "completed"
    static let skipped = "skipped"
    static let driftCueIntervalSeconds: TimeInterval = 45

    let workout: PushedWorkout
    var steps: [PushedStep] { workout.steps }

    private var idx = 0
    private var stepStartDistance = 0.0
    private var stepStartElapsed = 0.0
    private var lastDistance = 0.0
    private var lastElapsed = 0.0
    private var hasTotals = false
    private var emittedFirst = false
    private var firedWarning = false
    private var lastDriftAt: TimeInterval?
    private var results: [WorkoutStepResultRecord] = []

    init(workout: PushedWorkout) {
        self.workout = workout
    }

    var currentIndex: Int { idx }
    var isComplete: Bool { idx >= steps.count }

    /// While true the step owns the run's pace cues, and the run's general
    /// target-pace alert stands down (decisions § 2076).
    var ownsPaceCues: Bool { !isComplete }

    private var stepDistance: Double {
        hasTotals ? max(0, lastDistance - stepStartDistance) : 0
    }

    private var stepElapsed: Double {
        hasTotals ? max(0, lastElapsed - stepStartElapsed) : 0
    }

    /// Whole seconds, as the phone's `Duration.inSeconds` reads them.
    private var stepSecs: Int { Int(stepElapsed.rounded(.down)) }

    func view() -> WatchWorkoutView {
        let step = idx < steps.count ? steps[idx] : nil
        return WatchWorkoutView(
            step: step,
            index: idx,
            stepCount: steps.count,
            remainingMetres: step?.distanceMetres.map { max(0, Double($0) - stepDistance) },
            remainingSeconds: step?.durationSeconds.map { max(0, $0 - stepSecs) }
        )
    }

    /// `now` is any monotonic clock in seconds; it only spaces the drift cue.
    func onTotals(distanceMetres: Double, elapsedSeconds: Double, now: TimeInterval) -> [WatchWorkoutEvent] {
        guard !steps.isEmpty, !isComplete else { return [] }
        var out: [WatchWorkoutEvent] = []
        lastDistance = distanceMetres
        lastElapsed = elapsedSeconds
        hasTotals = true

        if !emittedFirst {
            emittedFirst = true
            stepStartDistance = distanceMetres
            stepStartElapsed = elapsedSeconds
            out.append(.transition(previous: -1, current: 0))
        }

        let step = steps[idx]
        let warningHit: Bool
        if let duration = step.durationSeconds {
            warningHit = duration - stepSecs <= 10 && duration > 20
        } else {
            let target = Double(step.distanceMetres ?? 0)
            warningHit = target - stepDistance <= 50 && target > 100
        }
        if !firedWarning, warningHit {
            firedWarning = true
            out.append(.warning(index: idx))
        }

        if let drift = paceDrift(step) {
            if lastDriftAt == nil || now - lastDriftAt! >= Self.driftCueIntervalSeconds {
                lastDriftAt = now
                out.append(.paceDrift(index: idx, ahead: drift < 0, deltaSecondsPerKm: abs(drift)))
            }
        }

        while !isComplete {
            let cur = steps[idx]
            let hit: Bool
            if let duration = cur.durationSeconds {
                hit = stepSecs >= duration
            } else {
                hit = stepDistance >= Double(cur.distanceMetres ?? 0)
            }
            guard hit else { break }
            out.append(advance(status: Self.completed, carryOvershoot: true))
        }
        return out
    }

    /// Skip the current step: what it covered is its actual, status skipped,
    /// and the next step starts from the latest totals.
    func skipStep() -> [WatchWorkoutEvent] {
        guard !isComplete, hasTotals else { return [] }
        return [advance(status: Self.skipped, carryOvershoot: false)]
    }

    /// Results so far, the step in progress included as `skipped`: the
    /// crash-recovery shape the phone writes on every in-progress save.
    func snapshotResults() -> [WorkoutStepResultRecord] {
        var out = results
        if !isComplete, hasTotals {
            out.append(result(idx, steps[idx], stepDistance, stepElapsed, Self.skipped))
        }
        return out
    }

    /// `completed` when every step ran to at least 80 % of its target on its
    /// own axis, `partial` otherwise; `abandoned` only for a workout that
    /// never started.
    func adherence() -> String {
        let rs = snapshotResults()
        if rs.isEmpty { return "abandoned" }
        var short = rs.count < steps.count
        for r in rs {
            if r.status == Self.skipped {
                short = true
                continue
            }
            if let target = r.targetDurationSeconds {
                if Double(r.durationSeconds) < Double(target) * 0.8 { short = true }
            } else if r.actualDistanceMetres < r.targetDistanceMetres * 0.8 {
                short = true
            }
        }
        return short ? "partial" : "completed"
    }

    func review() -> WorkoutReview {
        WorkoutReview(planWorkoutId: workout.planWorkoutId, adherence: adherence(), steps: snapshotResults())
    }

    /// Signed drift in s/km (positive = slower) when the step is paced and
    /// the runner is past twice its tolerance, else nil.
    private func paceDrift(_ step: PushedStep) -> Int? {
        if workout.unpaced { return nil }
        let d = stepDistance
        let secs = stepSecs
        if d < 5 || secs < 1 { return nil }
        let actual = Int((Double(secs) / (d / 1000)).rounded())
        let diff = actual - step.paceSecondsPerKm
        return abs(diff) > step.toleranceSecondsPerKm * 2 ? diff : nil
    }

    private func advance(status: String, carryOvershoot: Bool) -> WatchWorkoutEvent {
        let step = steps[idx]
        let coveredDist = stepDistance
        let coveredElapsed = stepElapsed
        var consumedDist = coveredDist
        var consumedElapsed = coveredElapsed
        if carryOvershoot {
            if let duration = step.durationSeconds {
                consumedElapsed = Double(duration)
                let ratio = coveredElapsed > 0 ? min(max(consumedElapsed / coveredElapsed, 0), 1) : 1
                consumedDist = coveredDist * ratio
            } else {
                consumedDist = Double(step.distanceMetres ?? 0)
                let ratio = coveredDist > 0 ? min(max(consumedDist / coveredDist, 0), 1) : 1
                consumedElapsed = coveredElapsed * ratio
            }
        }
        results.append(result(idx, step, consumedDist, consumedElapsed, status))

        let prev = idx
        idx += 1
        if carryOvershoot {
            stepStartDistance += consumedDist
            stepStartElapsed += consumedElapsed
        } else {
            stepStartDistance = lastDistance
            stepStartElapsed = lastElapsed
        }
        firedWarning = false
        lastDriftAt = nil
        return isComplete ? .complete : .transition(previous: prev, current: idx)
    }

    private func result(
        _ index: Int,
        _ step: PushedStep,
        _ distance: Double,
        _ elapsed: Double,
        _ status: String
    ) -> WorkoutStepResultRecord {
        let secs = Int(elapsed.rounded(.down))
        let pace = distance >= 5 && secs >= 1 ? Int((Double(secs) / (distance / 1000)).rounded()) : nil
        return WorkoutStepResultRecord(
            stepIndex: index,
            kind: step.kind.rawValue,
            repIndex: step.repIndex,
            repTotal: step.repTotal,
            targetDistanceMetres: Double(step.distanceMetres ?? 0),
            targetDurationSeconds: step.durationSeconds,
            actualDistanceMetres: distance,
            targetPaceSecondsPerKm: step.paceSecondsPerKm,
            actualPaceSecondsPerKm: pace,
            toleranceSecondsPerKm: step.toleranceSecondsPerKm,
            durationSeconds: secs,
            status: status
        )
    }
}

/// What the wrist does for a feed of events: the Swift twin of Wear OS's
/// `workoutCue`, one cue per feed, most important first.
enum WatchWorkoutCue: Equatable {
    /// A new step began.
    case step
    /// The step ends in the next 50 m or 10 s.
    case stepEnding
    /// The last step ended.
    case complete
    /// Off the step's pace band: the pace alert, in the direction to correct.
    case paceAlert(tooSlow: Bool)

    /// The session's first transition is silent (the runner has just pressed
    /// Start); a transition replaces the warning and the drift of the step
    /// being left; several transitions in one feed buzz once.
    static func cue(for events: [WatchWorkoutEvent]) -> WatchWorkoutCue? {
        if events.contains(.complete) { return .complete }
        if events.contains(where: { if case .transition(let p, _) = $0 { return p >= 0 }; return false }) {
            return .step
        }
        if events.contains(where: { if case .warning = $0 { return true }; return false }) {
            return .stepEnding
        }
        for e in events.reversed() {
            if case .paceDrift(_, let ahead, _) = e { return .paceAlert(tooSlow: !ahead) }
        }
        return nil
    }
}
