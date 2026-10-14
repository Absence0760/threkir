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
/// otherwise the 90 % gate makes it a manual finish at [stoppedAtMs] — the
/// instant the runner stopped, not the later press that confirmed it — or a
/// DNF with no finish instant. Mirrors `raceStopOutcome` in
/// `race_finish.dart`.
internal fun raceFinishDecision(
    settled: RaceFinish.Finish?,
    coveredM: Double,
    courseDistanceM: Double?,
    stoppedAtMs: Long,
): RaceStopDecision {
    if (settled != null) {
        return RaceStopDecision(RaceFinish.Outcome.AUTO_FINISH, settled.epochMs, settled.coveredM)
    }
    val outcome = RaceFinish.manualOutcome(coveredM, courseDistanceM)
    val at = if (outcome == RaceFinish.Outcome.DNF) null else stoppedAtMs
    return RaceStopDecision(outcome, at, coveredM)
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
