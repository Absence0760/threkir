import Foundation

/// How a run picks up again after the app was terminated in the middle of it.
///
/// Until this existed the only thing a crash checkpoint could become was a
/// FINISHED run: "Recover unsaved run?" saved the run as it stood at the last
/// 15 s checkpoint. On a 5K that is the right answer. On an ultra it is not —
/// a process killed at hour eight ended the recording at hour eight, and the
/// remaining hours had to be started as a second run, so the race reached the
/// phone as two activities with the gap between them uncounted. Wear OS
/// survives the same moment through its foreground service; watchOS keeps the
/// `HKWorkoutSession` alive instead and relaunches the app into
/// `handleActiveWorkoutRecovery()`, which nothing here implemented
/// (decisions § 1793).
///
/// Pure: every decision about the clock is made here from the checkpoint and
/// a `now` the caller passes, so the arithmetic is exercised in the test host
/// and a wrist is needed only for the relaunch itself.
struct RunResumePlan: Equatable {
    /// What `WorkoutManager.totalPausedInterval` resumes at.
    let totalPausedInterval: TimeInterval
    /// Non-nil when the run was paused at the checkpoint; it resumes paused,
    /// and the pause goes on accruing from the moment it began.
    let pausedAt: Date?
    /// The active clock the run resumes at.
    let elapsedSeconds: TimeInterval
    /// Seconds between the last checkpoint and the relaunch, never negative.
    /// No fix was recorded across it, so it carries no distance either way.
    let gapSeconds: TimeInterval

    var resumesPaused: Bool { pausedAt != nil }

    /// Beyond this a run is no longer continued — only saved or discarded.
    ///
    /// Twelve hours, because the case this exists for is a runner who plugs
    /// a dead watch in at an aid station or a sleep stop and wants the same
    /// run back on the wrist; a checkpoint older than a night's sleep is a run
    /// that ended, and continuing it would fold a second day's outing into the
    /// first one's row.
    static let maxContinueGapSeconds: TimeInterval = 12 * 3600

    /// When the checkpoint describes. A paused checkpoint is written at the
    /// pause, so it is the pause's start; a recording one is written on the
    /// active clock, which runs `startedAt + active + paused`.
    static func checkpointedAt(_ cp: RunCheckpoint) -> Date {
        cp.pausedAt ?? cp.startedAt.addingTimeInterval(cp.activeDurationSeconds + cp.pausedIntervalSeconds)
    }

    /// Whether this checkpoint may be continued rather than only saved.
    ///
    /// A checkpoint written by a clock ahead of `now` (the wrist's time was
    /// corrected between the crash and the relaunch) is continued: the gap is
    /// read as zero, not as a reason to lose the run.
    static func canContinue(_ cp: RunCheckpoint, now: Date) -> Bool {
        guard !cp.id.isEmpty,
              cp.activeDurationSeconds.isFinite,
              cp.pausedIntervalSeconds.isFinite else { return false }
        let gap = now.timeIntervalSince(checkpointedAt(cp))
        return gap.isFinite && gap <= maxContinueGapSeconds
    }

    /// The clock the run resumes on.
    ///
    /// `workoutSessionSurvived` is the one fact that decides what the gap
    /// was. When watchOS kept the `HKWorkoutSession` running and relaunched
    /// the app into it, the workout never stopped — the runner was moving —
    /// so the gap is active time, exactly as Health already counts it. When
    /// nothing survived (the watch died, or was restarted, and the runner
    /// chose to continue), nothing knows what the gap was, and it is carried
    /// as paused: a pace computed against time nobody can show was spent
    /// running would be a slower pace than the runner ran.
    ///
    /// A negative gap is clock skew, and is absorbed into the paused interval
    /// in both cases so the active clock resumes where the checkpoint left it
    /// rather than running backwards.
    static func make(checkpoint cp: RunCheckpoint, now: Date, workoutSessionSurvived: Bool) -> RunResumePlan {
        let raw = now.timeIntervalSince(checkpointedAt(cp))
        let rawGap = raw.isFinite ? raw : 0
        let gap = max(rawGap, 0)
        if let pausedAt = cp.pausedAt {
            return RunResumePlan(
                totalPausedInterval: cp.pausedIntervalSeconds,
                pausedAt: pausedAt,
                elapsedSeconds: cp.activeDurationSeconds,
                gapSeconds: gap
            )
        }
        if workoutSessionSurvived {
            return RunResumePlan(
                totalPausedInterval: cp.pausedIntervalSeconds + min(rawGap, 0),
                pausedAt: nil,
                elapsedSeconds: cp.activeDurationSeconds + gap,
                gapSeconds: gap
            )
        }
        return RunResumePlan(
            totalPausedInterval: cp.pausedIntervalSeconds + rawGap,
            pausedAt: nil,
            elapsedSeconds: cp.activeDurationSeconds,
            gapSeconds: gap
        )
    }

    /// The heart-rate state the checkpoint carried, in the shape
    /// `HealthKitManager` resumes from. Falls back to the graded pair a
    /// checkpoint from a build predating the raw fields carries: the graded
    /// mean is nil below half coverage, so such a run resumes with no prior
    /// mean, which costs the pre-crash average and never invents one.
    static func heartRatePrior(_ cp: RunCheckpoint, resumingAt activeSeconds: TimeInterval) -> HeartRatePrior {
        let covered = cp.hrCoveredSeconds
            ?? cp.hrCoverage.map { $0 * cp.activeDurationSeconds }
            ?? 0
        return HeartRatePrior(
            mean: cp.hrMeanUngraded ?? cp.averageBPM,
            coveredSeconds: covered.isFinite ? max(covered, 0) : 0,
            atActiveSeconds: activeSeconds
        )
    }
}

/// The heart-rate measurement a resumed run carries over from before the
/// termination.
struct HeartRatePrior: Equatable {
    /// The ungraded mean of the samples before the termination, or nil.
    let mean: Double?
    /// Active seconds the sensor was credited with before the termination.
    let coveredSeconds: TimeInterval
    /// The active clock the run resumes at — where coverage picks up, so the
    /// gap across the termination is never credited.
    let atActiveSeconds: TimeInterval
}

/// A value that may arrive before or after the one thing that wants it.
///
/// watchOS calls `handleActiveWorkoutRecovery()` on the application delegate
/// at launch, and `recoverActiveWorkoutSession` answers on its own queue —
/// either side of `ContentView` constructing the `WorkoutManager` that has to
/// take the session. Whichever comes second completes the handoff, and a
/// value is handed over exactly once. Main-queue only, which is where both
/// callers already are.
final class PendingHandoff<Value> {
    private var pending: Value?
    private var receiver: ((Value) -> Void)?

    func deliver(_ value: Value) {
        if let receiver {
            receiver(value)
        } else {
            pending = value
        }
    }

    func register(_ receiver: @escaping (Value) -> Void) {
        self.receiver = receiver
        if let value = pending {
            pending = nil
            receiver(value)
        }
    }
}
