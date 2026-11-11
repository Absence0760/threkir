package com.runapp.watchwear

import java.time.Instant

/// The race-mode transitions `RunViewModel` makes while a race run records,
/// as pure functions: the ViewModel owns the state and the side effects, and
/// these decide what each event means. No Android, no clock — every instant
/// is handed in.

/// What a Stop press means on the run being recorded.
internal enum class RaceStopAction { PAUSE, FINISH_RACE, STOP }

/// In a race, Stop before the finish is a pause, and Stop while paused is
/// "Finish race". A run with no race bound, or whose race outcome is already
/// decided, stops as any run does — including a run the host ended, which is
/// unbound by then.
internal fun raceStopAction(paused: Boolean, raceBound: Boolean, decided: Boolean): RaceStopAction =
    when {
        !raceBound || decided -> RaceStopAction.STOP
        paused -> RaceStopAction.FINISH_RACE
        else -> RaceStopAction.PAUSE
    }

/// "Finish race", or a run that reached `Finished` with no decision: a
/// closest approach still open in the zone ([settled], from
/// [RaceFinishDetector.finaliseNow]) is an automatic finish at that fix;
/// otherwise the 90 % gate makes it a manual finish at [stoppedAtMs] — the
/// instant the runner stopped, not the later press that confirmed it — or a
/// DNF with no finish instant. [lapsMet] is the detector's lap rule at the
/// stop ([RaceLineTimer.lapsMet]): false is a DNF whatever the distance.
/// Mirrors `raceStopOutcome` in `race_finish.dart`.
internal fun raceFinishDecision(
    settled: RaceFinish.Finish?,
    coveredM: Double,
    courseDistanceM: Double?,
    stoppedAtMs: Long,
    lapsMet: Boolean? = null,
): RaceStopDecision {
    if (settled != null) {
        return RaceStopDecision(RaceFinish.Outcome.AUTO_FINISH, settled.epochMs, settled.coveredM, settled)
    }
    val outcome = RaceFinish.manualOutcome(coveredM, courseDistanceM, lapsMet)
    val at = if (outcome == RaceFinish.Outcome.DNF) null else stoppedAtMs
    return RaceStopDecision(outcome, at, coveredM)
}

/// The race a recording binds to, or null. Only an unbound run binds, only to
/// a race that is running, and never the run the host already ended a race
/// under — the next poll would otherwise re-bind it to a race it has left. A
/// self-timed race binds only once the runner tapped "This run is my attempt"
/// (#1306): other runs in the window never bind or ping.
internal fun raceToBind(
    alreadyBound: Boolean,
    runId: String?,
    endedRunId: String?,
    active: ActiveRaceState?,
): ActiveRaceState? {
    if (alreadyBound) return null
    val id = runId ?: return null
    if (id == endedRunId) return null
    return active?.takeIf { it.isRunning && (!it.isSelfTimed || it.attemptArmed) }
}

/// What a polled session status means for this runner.
internal enum class RaceHostEnd {
    /// Not an End, or one that changes nothing: the race is still on, or this
    /// runner's outcome is already decided and owed.
    NONE,

    /// The host ended the race while the runner was still racing: unbind, and
    /// no result is owed.
    END,

    /// The host ended the race after the runner pressed Stop: the race stays
    /// bound so the Finish chosen on the paused screen is still filed, timed
    /// at that Stop. A Resume instead means no result.
    END_AFTER_STOP,
}

/// The host's End for this runner, if [status] is one. A finish already
/// decided is a result already owed, so End racing the service's stop never
/// swallows it; and a Stop pressed before End arrived keeps the runner's own
/// Finish (decisions § 1857).
internal fun raceHostEnd(status: String?, decided: Boolean, stopPending: Boolean): RaceHostEnd =
    when {
        decided || (status != "finished" && status != "cancelled") -> RaceHostEnd.NONE
        stopPending -> RaceHostEnd.END_AFTER_STOP
        else -> RaceHostEnd.END
    }

/// Whether a fix goes to the finish detector: only while recording (a paused
/// watch is not racing toward the line), only before an outcome, and only
/// once per fix — the metrics flow re-emits the same fix on every heart-rate
/// or step update. [fixKey] identifies the fix, it is not a time.
internal fun raceFixOfferable(
    recording: Boolean,
    decided: Boolean,
    fixKey: Long,
    lastFixKey: Long,
): Boolean = recording && !decided && fixKey != lastFixKey

/// A fix's instant on the DEVICE wall clock. The fix's own GPS `time` is a
/// different clock from the one the runner's Start and the server offset are
/// measured on, so it is never used; the fix's `elapsedRealtime` stamp is
/// carried onto the wall clock instead, which also keeps a batched delivery
/// from stamping every fix at its arrival. Without a stamp (or with one from
/// the future, which only a clock fault produces) the fix is taken as now —
/// the phone's `offerFix(at: DateTime.now())`.
internal fun raceFixDeviceMs(
    fixElapsedRealtimeMs: Long?,
    nowWallMs: Long,
    nowElapsedRealtimeMs: Long,
): Long {
    val fixAt = fixElapsedRealtimeMs ?: return nowWallMs
    val ageMs = nowElapsedRealtimeMs - fixAt
    return if (ageMs < 0) nowWallMs else nowWallMs - ageMs
}

/// `metadata.race_undone_finish_at` for a recording whose line finish was
/// taken back at [undoneFinishMs] (device clock): that instant on the server
/// clock, as a result's `finish_at` is written, or null when none was.
internal fun raceUndoneFinishAtIso(undoneFinishMs: Long?, serverOffsetMs: Long?): String? =
    undoneFinishMs?.let { Instant.ofEpochMilli(it + (serverOffsetMs ?: 0L)).toString() }

/// The gun on the device clock, for the running screen's race clock.
internal fun gunStartDeviceMs(startedAtMs: Long?, serverOffsetMs: Long?): Long? =
    startedAtMs?.let { it - (serverOffsetMs ?: 0L) }

/// The queued results a session may send: never another account's.
internal fun raceResultsToReplay(pending: List<PendingRaceResult>, userId: String): List<PendingRaceResult> =
    pending.filter { it.userId == userId }

/// The late-start flag for a bound race run, asked on its first finite fix and
/// again when the course lands after it. Mirrors the phone's
/// `_evaluateLateStart`: the Start is carried onto the server clock with the
/// offset known so far, and the far-from-start arm is measured only against
/// the course row's own start point, never the route (decisions § 1845), so a
/// course with none checks the time arm alone. Unknown inputs never flag.
internal fun raceLateStart(
    gunMs: Long?,
    recordingStartedDeviceMs: Long?,
    serverOffsetMs: Long?,
    firstFixLat: Double?,
    firstFixLng: Double?,
    course: RaceSessionClient.RaceCourse?,
): Boolean {
    val gun = gunMs ?: return false
    val began = recordingStartedDeviceMs ?: return false
    val lat = firstFixLat?.takeIf { it.isFinite() } ?: return false
    val lng = firstFixLng?.takeIf { it.isFinite() } ?: return false
    val fromStart = course?.takeIf { it.hasStart }?.let {
        RaceFinish.distanceM(lat, lng, it.startLat!!, it.startLng!!)
    }
    return RaceFinish.startFlagged(gun, began + (serverOffsetMs ?: 0L), fromStart)
}

/// A race session's status at [nowMs]: a scheduled or self-timed race is
/// live once its instant passes and finished once its window closes, without
/// waiting for the server to write either. Host GO is what the row says.
/// Mirrors `effectiveRaceStatus` in `race_start_modes.dart`.
internal fun raceEffectiveStatus(
    status: String,
    startMode: String,
    startInstantMs: Long?,
    windowClosesAtMs: Long?,
    nowMs: Long,
): String {
    if (status == "finished" || status == "cancelled") return status
    if (startMode == "host_go") return status
    val startPassed = startInstantMs != null && startInstantMs <= nowMs
    if (windowClosesAtMs != null && windowClosesAtMs <= nowMs && (status == "running" || startPassed)) {
        return "finished"
    }
    if (status == "armed" && startPassed) return "running"
    return status
}

data class ActiveRaceState(
    val eventId: String,
    val instanceStart: String,
    val status: String,
    val startedAtMs: Long?,
    val eventTitle: String?,
    /// The course the runner picked at RSVP. Null when they picked none or it
    /// could not be read; the race then finishes only by "Finish race".
    val course: RaceSessionClient.RaceCourse? = null,
    /// `host_go` | `scheduled` | `self_timed` (#1306).
    val startMode: String = "host_go",
    /// When the clock starts, server epoch ms: the scheduled GO or the
    /// window's opening. Null for Host GO.
    val startInstantMs: Long? = null,
    /// A self-timed race binds a recording only after the runner taps
    /// "This run is my attempt" on the watch (owner decision 4a).
    val attemptArmed: Boolean = false,
    /// When a scheduled or self-timed race's window closes, server epoch ms.
    /// Null for Host GO.
    val windowClosesAtMs: Long? = null,
) {
    val isSelfTimed: Boolean get() = startMode == "self_timed"
    val isArmed: Boolean get() = effectiveStatusAt(System.currentTimeMillis()) == "armed"
    val isRunning: Boolean get() = effectiveStatusAt(System.currentTimeMillis()) == "running"

    /// A scheduled or self-timed race whose instant has passed is live, and
    /// one whose window has closed is over, before the next poll says so; the
    /// server judges it the same way.
    fun effectiveStatusAt(nowMs: Long): String =
        raceEffectiveStatus(status, startMode, startInstantMs, windowClosesAtMs, nowMs)

    /// GO on the server clock: the stamped start, or the instant itself.
    val goAtMs: Long? get() = startedAtMs ?: startInstantMs.takeIf { startMode != "host_go" }
}

/// How a race run is being stopped, decided before the service is told to
/// stop so `handleFinishedRun` builds the result from the finish, not from
/// whenever the service got round to publishing `Finished`.
internal data class RaceStopDecision(
    val outcome: RaceFinish.Outcome,
    /// The finish on the device clock; null for a DNF, which has none.
    val finishEpochMs: Long?,
    val coveredM: Double,
    /// The detector's finish behind an automatic outcome: how it was
    /// detected and the start it was measured from.
    val finish: RaceFinish.Finish? = null,
)

/// The `event_results` row a race run owes. Pure, so the gun / chip / DNF
/// arithmetic is pinned without a ViewModel; the timing columns follow
/// [RaceFinish.resultTiming], the fixture's `resultTiming` rule.
///
/// The crossings (#1307) go on the server clock — the device instant plus
/// [serverOffsetMs], which the server re-derives the gun and chip time from.
/// A committed start ([start]: a start-line crossing, or GO for a runner past
/// the line) is `gate`; without one the start is the runner's own Start
/// press, `device`. A start at GO is GO itself, re-expressed under the offset
/// at filing so its chip time equals its gun time. A DNF carries no crossing.
/// Mirrors the phone's `_resultFor`. [runId] is null for a finish filed at
/// the line, before the run row exists.
internal fun buildRaceResult(
    race: ActiveRaceState,
    decision: RaceStopDecision,
    userId: String,
    runId: String?,
    runStartedAtMs: Long,
    elapsedS: Int,
    serverOffsetMs: Long?,
    start: RaceFinish.Start? = null,
): PendingRaceResult {
    val finished = decision.outcome.finisherStatus == "finished"
    val auto = decision.outcome == RaceFinish.Outcome.AUTO_FINISH
    val offset = serverOffsetMs ?: 0L
    val gun = race.goAtMs
    val committed = if (finished) decision.finish?.start ?: start else null
    val startDevice = when {
        !finished -> null
        committed != null && committed.kind == RaceFinish.StartKind.GO && gun != null -> gun - offset
        else -> committed?.epochMs ?: runStartedAtMs.takeIf { it > 0L }
    }
    val finishDevice = if (finished) decision.finishEpochMs else null
    val timing = RaceFinish.resultTiming(
        finished = finished,
        finishAtMs = decision.finishEpochMs,
        gunMs = gun,
        serverOffsetMs = serverOffsetMs,
        recordingStartedMs = runStartedAtMs,
        elapsedS = elapsedS,
        startAtMs = if (committed == null) null else startDevice,
    )
    return PendingRaceResult(
        userId = userId,
        eventId = race.eventId,
        instanceStart = race.instanceStart,
        runId = runId,
        durationS = timing.durationS,
        distanceM = decision.coveredM,
        finisherStatus = decision.outcome.finisherStatus,
        finishMethod = decision.outcome.finishMethod,
        courseId = race.course?.id,
        gunTimeS = timing.gunTimeS,
        chipTimeS = timing.chipTimeS,
        startAt = startDevice?.let { Instant.ofEpochMilli(it + offset).toString() },
        finishAt = finishDevice?.let { Instant.ofEpochMilli(it + offset).toString() },
        startDetection = startDevice?.let {
            (if (committed != null) RaceStartDetection.GATE else RaceStartDetection.DEVICE).wire
        },
        finishDetection = if (auto && finishDevice != null) {
            (decision.finish?.detection ?: RaceFinish.FinishDetection.ZONE).wire
        } else {
            null
        },
        clockOffsetMs = serverOffsetMs,
    )
}

/// What the running screen shows about the race before and around a
/// recording binds: the race the timer follows and the course it times by.
/// The bound race wins; otherwise the armed or live race while a recording
/// runs, a self-timed one only once "This run is my attempt" is on, and GO
/// only once the race is live. Mirrors the phone's `_detectionRace`.
internal fun raceTargetFor(
    bound: ActiveRaceState?,
    active: ActiveRaceState?,
    recording: Boolean,
): RaceTarget? {
    if (bound != null) {
        return RaceTarget(
            bound.eventId,
            bound.instanceStart,
            bound.isSelfTimed,
            bound.goAtMs.takeIf { !bound.isSelfTimed },
        )
    }
    if (!recording || active == null) return null
    if (!active.isArmed && !active.isRunning) return null
    if (active.isSelfTimed && !active.attemptArmed) return null
    return RaceTarget(
        active.eventId,
        active.instanceStart,
        active.isSelfTimed,
        active.goAtMs.takeIf { active.isRunning && !active.isSelfTimed },
    )
}
