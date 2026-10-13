package com.runapp.watchwear

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
/// otherwise the 90 % gate makes it a manual finish or a DNF at
/// [nowDeviceMs]. Mirrors `raceStopOutcome` in `race_finish.dart`.
internal fun raceFinishDecision(
    settled: RaceFinish.Finish?,
    coveredM: Double,
    courseDistanceM: Double?,
    nowDeviceMs: Long,
): RaceStopDecision =
    if (settled != null) {
        RaceStopDecision(RaceFinish.Outcome.AUTO_FINISH, settled.epochMs, settled.coveredM)
    } else {
        RaceStopDecision(RaceFinish.manualOutcome(coveredM, courseDistanceM), nowDeviceMs, coveredM)
    }

/// The race a recording binds to, or null. Only an unbound run binds, only to
/// a race that is running, and never the run the host already ended a race
/// under — the next poll would otherwise re-bind it to a race it has left.
internal fun raceToBind(
    alreadyBound: Boolean,
    runId: String?,
    endedRunId: String?,
    active: ActiveRaceState?,
): ActiveRaceState? {
    if (alreadyBound) return null
    val id = runId ?: return null
    if (id == endedRunId) return null
    return active?.takeIf { it.isRunning }
}

/// Whether a polled session status is the host's End for this runner. A
/// finish already decided is a result already owed, so End racing the
/// service's stop never swallows it.
internal fun hostEndsRace(status: String?, decided: Boolean): Boolean =
    !decided && (status == "finished" || status == "cancelled")

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

/// The gun on the device clock, for the running screen's race clock.
internal fun gunStartDeviceMs(startedAtMs: Long?, serverOffsetMs: Long?): Long? =
    startedAtMs?.let { it - (serverOffsetMs ?: 0L) }

/// The queued results a session may send: never another account's.
internal fun raceResultsToReplay(pending: List<PendingRaceResult>, userId: String): List<PendingRaceResult> =
    pending.filter { it.userId == userId }
