package com.runapp.watchwear

import com.runapp.watchwear.recording.RouteMath

/// Race-mode finish detection, a pure port of the `race_finish` parity pair
/// (Dart side in `apps/mobile_android/lib/`). No Android, no I/O, no clock:
/// every timestamp it handles arrives on a [Fix].
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

    /// One GPS fix with the covered distance the recorder credited by then.
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
    /// [courseDistanceM]. A course without a usable distance never clears it:
    /// there is no fraction of nothing to have covered.
    fun meetsDistanceGate(coveredM: Double, courseDistanceM: Double): Boolean =
        courseDistanceM > 0.0 && coveredM >= MIN_DISTANCE_FRACTION * courseDistanceM

    /// What a "Finish race" press records: a manual finish once the gate is
    /// cleared, a DNF short of it. A race with no course to measure against
    /// has no gate to apply, and is recorded as the manual finish the runner
    /// asked for — the pre-course behaviour.
    fun manualOutcome(coveredM: Double, courseDistanceM: Double?): Outcome =
        when {
            courseDistanceM == null || courseDistanceM <= 0.0 -> Outcome.MANUAL_FINISH
            meetsDistanceGate(coveredM, courseDistanceM) -> Outcome.MANUAL_FINISH
            else -> Outcome.DNF
        }

    enum class Outcome(val finisherStatus: String, val finishMethod: String?) {
        AUTO_FINISH("finished", "auto"),
        MANUAL_FINISH("finished", "manual"),
        DNF("dnf", null),
    }

    /// Gun time: the finish on the SERVER's clock minus `race_sessions
    /// .started_at`, which is server time. [serverOffsetMs] is server minus
    /// device, estimated from the HTTP `Date` header of the race poll
    /// ([clockOffsetMs]); null means no estimate yet, and the device clock is
    /// taken as-is. Null when there is no `started_at` or the result would be
    /// negative — a finish before the gun is a clock fault, not a time.
    fun gunTimeS(finishEpochMs: Long, serverOffsetMs: Long?, startedAtMs: Long?): Int? {
        if (startedAtMs == null) return null
        val ms = finishEpochMs + (serverOffsetMs ?: 0L) - startedAtMs
        if (ms < 0) return null
        return (ms / 1000).toInt()
    }

    /// Chip time: the finish minus the runner's own Start press, both on the
    /// device clock, so no skew enters it. Wall time, pauses included — the
    /// race clock does not stop for a paused watch.
    fun chipTimeS(finishEpochMs: Long, runStartedAtMs: Long): Int =
        ((finishEpochMs - runStartedAtMs).coerceAtLeast(0L) / 1000).toInt()

    /// The leaderboard's `duration_s`: gun time when the session has a gun,
    /// chip time otherwise.
    fun durationS(gunTimeS: Int?, chipTimeS: Int): Int = gunTimeS ?: chipTimeS

    /// Server-minus-device clock offset from one HTTP exchange. The `Date`
    /// header is stamped somewhere between send and receive, so the midpoint
    /// of the round trip is the best device-clock estimate of that instant.
    /// The header has one-second resolution; a half-second bias is far below
    /// what a race result is read at, and far below the skew it corrects.
    fun clockOffsetMs(serverDateMs: Long, sentAtMs: Long, receivedAtMs: Long): Long =
        serverDateMs - (sentAtMs + (receivedAtMs - sentAtMs) / 2)
}

/// Stateful closest-approach tracker for one runner on one course. Feed it
/// every fix while recording; it answers the [RaceFinish.Finish] once and
/// keeps answering it.
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

    fun offer(fix: RaceFinish.Fix): RaceFinish.Finish? {
        finish?.let { return it }
        val d = RouteMath.haversineM(fix.lat, fix.lng, finishLat, finishLng)
        val eligible = d <= RaceFinish.FINISH_RADIUS_M &&
            RaceFinish.meetsDistanceGate(fix.coveredM, courseDistanceM)
        val current = best
        if (current == null) {
            if (eligible) {
                best = fix
                bestDistanceM = d
            }
            return null
        }
        if (!eligible || d > bestDistanceM) return finalise()
        if (d < bestDistanceM) {
            best = fix
            bestDistanceM = d
        }
        return null
    }

    /// Settle a pending closest approach now — the runner pressed "Finish
    /// race" while standing in the zone. Null when there was none.
    fun finaliseNow(): RaceFinish.Finish? = finish ?: if (best != null) finalise() else null

    private fun finalise(): RaceFinish.Finish {
        val b = best!!
        return RaceFinish.Finish(
            epochMs = b.epochMs,
            distanceToFinishM = bestDistanceM,
            coveredM = b.coveredM,
        ).also { finish = it }
    }

    companion object {
        /// Detector for a course polyline, or null when the course cannot be
        /// judged: no points to finish at, or no distance to gate on. A null
        /// detector leaves the race to the manual "Finish race" path.
        fun forCourse(
            waypoints: List<RouteMath.LatLng>,
            courseDistanceM: Double?,
        ): RaceFinishDetector? {
            val end = waypoints.lastOrNull() ?: return null
            val distance = courseDistanceM ?: return null
            if (distance <= 0.0) return null
            return RaceFinishDetector(end.lat, end.lng, distance)
        }
    }
}
