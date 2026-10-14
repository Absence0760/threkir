package com.runapp.watchwear

import com.runapp.watchwear.recording.RouteMath

/// Race-mode finish detection, a pure port of the `race_finish` parity pair
/// (Dart side in `apps/mobile_android/lib/`). No Android, no I/O, no clock:
/// every timestamp it handles arrives on a [Fix]. Both sides read their cases
/// from `fixtures/race_finish_cases.json` at the repo root, so a rule changes
/// there or nowhere.
///
/// The rule, shared with every client that can record a race:
///
/// - A fix is ELIGIBLE when it is within [FINISH_RADIUS_M] of the course
///   route's last point AND the covered distance is at least
///   [MIN_DISTANCE_FRACTION] of the course distance. The distance gate is
///   what keeps a loop course (start == finish) from finishing at the gun,
///   and an out-and-back or figure-eight from finishing on an early pass by
///   the line.
/// - The finish is the CLOSEST APPROACH among consecutive eligible fixes, not
///   the first one inside the zone: the runner is still closing on the line
///   when the zone is entered.
/// - It is finalised by the first fix that is farther from the line than the
///   best so far, or by the first fix that is no longer eligible (the runner
///   left the zone). GPS jitter that carries a fix back out of the zone
///   therefore finalises at the best fix seen, which was itself inside.
object RaceFinish {
    const val FINISH_RADIUS_M = 30.0
    const val MIN_DISTANCE_FRACTION = 0.9
    const val LATE_START_AFTER_MS = 300_000L
    const val LATE_START_FAR_M = 200.0
    const val EARTH_RADIUS_M = 6_371_000.0

    /// Great-circle distance in metres, on [EARTH_RADIUS_M].
    fun distanceM(lat1: Double, lng1: Double, lat2: Double, lng2: Double): Double =
        RouteMath.haversineM(lat1, lng1, lat2, lng2)

    /// Whether a fix [distanceM] from the finish is inside the zone.
    /// Inclusive; a non-finite distance is not.
    fun inFinishZone(distanceM: Double): Boolean = distanceM <= FINISH_RADIUS_M

    /// One GPS fix with the covered distance the recorder credited by then.
    /// [epochMs] is the fix's instant on the DEVICE clock — the clock the
    /// gun offset and the runner's Start are measured on — not the GPS
    /// time the fix carries ([raceFixDeviceMs]).
    data class Fix(
        val lat: Double,
        val lng: Double,
        val epochMs: Long,
        val coveredM: Double,
    )

    /// The closest-approach fix that decided the finish.
    data class Finish(
        val epochMs: Long,
        val distanceToFinishM: Double,
        val coveredM: Double,
    )

    /// True when [coveredM] clears the 90 % gate for a course of
    /// [courseDistanceM], inclusive. A course distance that is null,
    /// non-finite or <= 0 cannot gate, so it passes: a runner is never marked
    /// DNF for data the course never carried.
    fun meetsDistanceGate(coveredM: Double, courseDistanceM: Double?): Boolean {
        val d = courseDistanceM
        if (d == null || !d.isFinite() || d <= 0.0) return true
        return coveredM >= MIN_DISTANCE_FRACTION * d
    }

    /// What a "Finish race" press records with no open approach: a manual
    /// finish once the gate is cleared, a DNF short of it.
    fun manualOutcome(coveredM: Double, courseDistanceM: Double?): Outcome =
        if (meetsDistanceGate(coveredM, courseDistanceM)) Outcome.MANUAL_FINISH else Outcome.DNF

    /// The late-start flag: recording began strictly more than
    /// [LATE_START_AFTER_MS] after GO, or the first fix was a finite distance
    /// strictly more than [LATE_START_FAR_M] from the course start. Both
    /// instants are on the server clock. An unknown distance does not flag.
    fun startFlagged(gunMs: Long, recordingStartedMs: Long, firstFixFromStartM: Double?): Boolean {
        if (recordingStartedMs - gunMs > LATE_START_AFTER_MS) return true
        val d = firstFixFromStartM
        return d != null && d.isFinite() && d > LATE_START_FAR_M
    }

    enum class Outcome(val finisherStatus: String, val finishMethod: String?) {
        AUTO_FINISH("finished", "auto"),
        MANUAL_FINISH("finished", "manual"),
        DNF("dnf", null),
    }

    /// Gun time: the finish on the SERVER's clock minus `race_sessions
    /// .started_at`, which is server time. [serverOffsetMs] is server minus
    /// device ([ServerClockOffset]); null means no estimate yet, and the
    /// device clock is taken as-is. [finishEpochMs] is on the DEVICE clock,
    /// never a GPS fix's own time. Null when there is no `started_at` or the
    /// result would be negative — a finish before the gun is a clock fault,
    /// not a time.
    fun gunTimeS(finishEpochMs: Long, serverOffsetMs: Long?, startedAtMs: Long?): Int? {
        if (startedAtMs == null) return null
        val ms = finishEpochMs + (serverOffsetMs ?: 0L) - startedAtMs
        if (ms < 0) return null
        return (ms / 1000).toInt()
    }

    /// Chip time: the finish minus the runner's own Start press, both on the
    /// device clock, so no skew enters it. Wall time, pauses included — the
    /// race clock does not stop for a paused watch. Null when negative, as
    /// the gun time is: a finish before the Start press is a clock fault.
    fun chipTimeS(finishEpochMs: Long, runStartedAtMs: Long): Int? {
        val ms = finishEpochMs - runStartedAtMs
        if (ms < 0) return null
        return (ms / 1000).toInt()
    }

    /// The timing columns of a race result row.
    data class ResultTiming(val durationS: Int, val gunTimeS: Int?, val chipTimeS: Int?)

    /// The timing a result row carries. A finish carries the gun time (when
    /// the race had a GO) and the chip time (when the recording's Start is
    /// known), and `duration_s` is the first of gun, chip and [elapsedS] that
    /// exists. The chip time never exceeds the gun time: a recording started
    /// while the race was armed joins it at GO, and the wait on the line is no
    /// part of the race. A DNF, or any outcome with no finish instant, carries neither
    /// time and `duration_s` is [elapsedS] — the recording's own elapsed
    /// seconds, which is what the server writes on a host-filed DNF.
    fun resultTiming(
        finished: Boolean,
        finishAtMs: Long?,
        gunMs: Long?,
        serverOffsetMs: Long?,
        recordingStartedMs: Long?,
        elapsedS: Int,
    ): ResultTiming {
        if (!finished || finishAtMs == null) return ResultTiming(elapsedS, null, null)
        val gun = gunTimeS(finishAtMs, serverOffsetMs, gunMs)
        val fromStart = recordingStartedMs?.let { chipTimeS(finishAtMs, it) }
        val chip = if (gun != null && fromStart != null && fromStart > gun) gun else fromStart
        return ResultTiming(gun ?: chip ?: elapsedS, gun, chip)
    }
}

/// Device-to-server clock offset, estimated from request round trips — the
/// Kotlin half of `ServerClockOffset` in `race_finish.dart`.
///
/// Each sample is a `race_pings` insert sent at `sentAtMs`, answered with the
/// row's server-stamped `at`, received at `receivedAtMs`. The server stamped
/// somewhere inside the round trip, so the midpoint is the best device-side
/// estimate of that instant and the error is at most half the round trip.
/// The sample with the shortest round trip wins; a tie takes the newer one.
class ServerClockOffset {
    /// Server minus device, or null until a sample lands.
    var offsetMs: Long? = null
        private set
    private var bestRttMs: Long? = null

    fun addSample(sentAtMs: Long, receivedAtMs: Long, serverAtMs: Long) {
        val rtt = receivedAtMs - sentAtMs
        if (rtt < 0) return
        val best = bestRttMs
        if (best != null && rtt > best) return
        offsetMs = serverAtMs - (sentAtMs + rtt / 2)
        bestRttMs = rtt
    }
}

/// Stateful closest-approach tracker for one runner on one course. Feed it
/// every fix while recording; it answers the [RaceFinish.Finish] once, and
/// [finish] holds it afterwards.
class RaceFinishDetector(
    private val finishLat: Double,
    private val finishLng: Double,
    private val courseDistanceM: Double,
) {
    private var best: RaceFinish.Fix? = null
    private var bestDistanceM = Double.MAX_VALUE

    var finish: RaceFinish.Finish? = null
        private set

    /// True while the runner is inside the zone past the gate and the
    /// closest approach is still being decided.
    val isCandidate: Boolean get() = finish == null && best != null

    /// The best in-zone fix so far, while the approach is still open.
    val candidate: RaceFinish.Finish?
        get() {
            val b = best ?: return null
            if (finish != null) return null
            return RaceFinish.Finish(b.epochMs, bestDistanceM, b.coveredM)
        }

    /// Feed one fix. Returns the finish on the call that finalises it and
    /// null on every other call, including every call after it. A fix with
    /// a non-finite coordinate or covered distance is ignored, not judged:
    /// read as "outside the zone" it would finalise an open approach.
    fun offer(fix: RaceFinish.Fix): RaceFinish.Finish? {
        if (finish != null) return null
        if (!fix.lat.isFinite() || !fix.lng.isFinite() || !fix.coveredM.isFinite()) return null
        val d = RaceFinish.distanceM(fix.lat, fix.lng, finishLat, finishLng)
        val eligible = RaceFinish.inFinishZone(d) &&
            RaceFinish.meetsDistanceGate(fix.coveredM, courseDistanceM)
        val current = best
        if (current == null) {
            if (eligible) {
                best = fix
                bestDistanceM = d
            }
            return null
        }
        if (!eligible || d > bestDistanceM) return finalise(current)
        if (d < bestDistanceM) {
            best = fix
            bestDistanceM = d
        }
        return null
    }

    /// Settle a pending closest approach now — the runner pressed "Finish
    /// race" while standing in the zone. Null when there was none.
    fun finaliseNow(): RaceFinish.Finish? = finish ?: best?.let { finalise(it) }

    private fun finalise(b: RaceFinish.Fix): RaceFinish.Finish =
        RaceFinish.Finish(
            epochMs = b.epochMs,
            distanceToFinishM = bestDistanceM,
            coveredM = b.coveredM,
        ).also { finish = it }

    companion object {
        /// Detector for a course's finish point, or null when the course
        /// cannot be judged: no finish point (a course with no route), or no
        /// distance to gate on. A null detector leaves the race to the manual
        /// "Finish race" path.
        fun forCourse(
            finishLat: Double?,
            finishLng: Double?,
            courseDistanceM: Double?,
        ): RaceFinishDetector? {
            val lat = finishLat ?: return null
            val lng = finishLng ?: return null
            val distance = courseDistanceM ?: return null
            if (!distance.isFinite() || distance <= 0.0) return null
            return RaceFinishDetector(lat, lng, distance)
        }
    }
}
