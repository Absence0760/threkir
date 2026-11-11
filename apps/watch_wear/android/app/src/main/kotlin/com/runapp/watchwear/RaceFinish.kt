package com.runapp.watchwear

import com.runapp.watchwear.recording.RouteMath
import kotlin.math.abs

/// Race-mode finish detection, a pure port of the `race_finish` parity pair
/// (Dart side `apps/mobile_android/lib/race_finish.dart`, web side
/// `apps/web/src/lib/races/race_finish.ts`), spec `race_finish v3` (decisions
/// § 2378, § 2472). No Android, no I/O, no clock: every timestamp it handles arrives
/// on a [Fix]. All three read their cases from `fixtures/race_finish_cases.json`
/// at the repo root, so a rule changes there or nowhere.
///
/// The v1 rule, which a course with no usable line still follows in a gun
/// mode (the start and finish lines are [RaceFinishDetector]'s):
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

    /// Share of the course distance a LINE finish needs when coverage runs
    /// from a committed start. Provisional until the #1304 calibration
    /// session: #1303 gives 50-60 %, and this takes the cautious end.
    const val MIN_COVERAGE_WITH_START = 0.6

    /// Covered distance a forward start-line crossing after GO must be
    /// followed by, with no backward crossing, before it is the runner's
    /// start. Provisional until the #1304 calibration session.
    const val START_COMMIT_M = 50.0
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

    /// Host GO and Scheduled GO are both [GUN]: the server's GO exists.
    /// [SELF_TIMED] has none; each runner's start-line crossing starts
    /// their clock.
    enum class StartMode { GUN, SELF_TIMED }

    /// A forward start-line crossing, or GO itself for a runner already past
    /// the line at GO. Both are `start_detection = 'gate'`; no [Start] at
    /// all is `'device'` (the runner's own Start press).
    enum class StartKind { LINE, GO }

    /// The committed start a finish is measured from.
    data class Start(
        val epochMs: Long,
        val coveredM: Double,
        val kind: StartKind,
        val gapped: Boolean = false,
    )

    enum class FinishDetection(val wire: String) { ZONE("zone"), GATE("gate") }

    /// The closest-approach fix in the zone, or the interpolated finish-line
    /// crossing. For a line finish [distanceToFinishM] is the crossing's
    /// lateral offset from the line's centre; [start] is null when coverage
    /// ran from the Start press.
    data class Finish(
        val epochMs: Long,
        val distanceToFinishM: Double,
        val coveredM: Double,
        val detection: FinishDetection = FinishDetection.ZONE,
        val start: Start? = null,
        val gapped: Boolean = false,
    )

    /// A line a race can be timed by: one `gate_crossing` can use, with a
    /// positive half-width. Anything else is no line.
    fun lineUsable(gate: Gate?): Boolean = gate != null && gateUsable(gate) && gate.halfWidthM > 0.0

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
    /// finish once the gate is cleared and, on a lap course, the laps run
    /// ([lapsMet], the detector's [RaceFinishDetector.lapsMet]: false is a
    /// DNF whatever the distance, null leaves the distance to decide); a DNF
    /// otherwise.
    fun manualOutcome(coveredM: Double, courseDistanceM: Double?, lapsMet: Boolean? = null): Outcome =
        if (meetsDistanceGate(coveredM, courseDistanceM) && lapsMet != false) Outcome.MANUAL_FINISH else Outcome.DNF

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
    /// part of the race. With a committed start ([startAtMs], device clock: a
    /// start-line crossing, or GO for a runner already past the line) the
    /// chip time runs from it instead of the Start press, under the same cap.
    /// A DNF, or any outcome with no finish instant, carries neither
    /// time and `duration_s` is [elapsedS] — the recording's own elapsed
    /// seconds, which is what the server writes on a host-filed DNF.
    fun resultTiming(
        finished: Boolean,
        finishAtMs: Long?,
        gunMs: Long?,
        serverOffsetMs: Long?,
        recordingStartedMs: Long?,
        elapsedS: Int,
        startAtMs: Long? = null,
    ): ResultTiming {
        if (!finished || finishAtMs == null) return ResultTiming(elapsedS, null, null)
        val gun = gunTimeS(finishAtMs, serverOffsetMs, gunMs)
        val fromStart = (startAtMs ?: recordingStartedMs)?.let { chipTimeS(finishAtMs, it) }
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

/// Finish detection for one runner on one course, spec `race_finish v3`.
/// Feed it every fix while recording; it answers the [RaceFinish.Finish]
/// once, and [finish] holds it afterwards.
///
/// Without a usable line, in a gun mode, it is v1's closest approach (the
/// rule on [RaceFinish]). With lines (the Dart twin's class comment carries
/// the rules in full, decisions § 2378):
/// - Start, gun mode with a start line: the runner's side of the line at GO
///   decides. On or past it, the start is GO; behind it, the first forward
///   crossing after GO followed by [RaceFinish.START_COMMIT_M] of covered
///   distance with no backward crossing. Until GO is known every fix is held
///   and [setGo] replays them; a race whose GO never comes finishes nothing
///   automatically.
/// - Start, self-timed: a forward crossing commits as in a gun race, with no
///   GO. Once committed a later forward crossing (the next lap) changes
///   nothing and a backward one (an out-and-back coming home) re-arms it
///   without clearing it, until a new forward crossing commits and replaces
///   it, though once the runner has passed the finish line forward since the
///   start, or covered [RaceFinish.MIN_DISTANCE_FRACTION] of the course from
///   it, a backward crossing is ignored (a GPS wobble at a lap pass must not
///   restart the clock). No committed start, no finish. No start line in a
///   gun mode: the Start press.
/// - Coverage runs from the start; a gun runner with no committed start is
///   measured from GO, and one whose crossing is still committing cannot
///   finish.
/// - The finish is the first forward finish-line crossing that clears
///   [RaceFinish.MIN_COVERAGE_WITH_START] from a committed start or
///   [RaceFinish.MIN_DISTANCE_FRACTION] without one, timed at its
///   interpolated instant rounded to the millisecond; once GO is known
///   nothing before it finishes. On a tie between a start and a finish
///   crossing a gun race takes the start first, a self-timed one the
///   finish. With a finish line the zone decides only on [finaliseNow], for
///   a runner inside it then.
/// - A lap pass is a forward finish crossing from a committed start at least
///   the lines' separation plus [RaceFinish.START_COMMIT_M] past it, and
///   [RaceFinish.START_COMMIT_M] past the previous pass. With the lap count
///   the race froze ([lapCount]) the line finish is the pass that brings the
///   count to it, the share kept as a floor; with none, from the second pass
///   on the share's floor rises to the course distance less half the lap just
///   run. [lapsMet] applies the same rule to a stop and to the zone
///   (decisions § 2472).
class RaceFinishDetector(
    private val finishLat: Double,
    private val finishLng: Double,
    private val courseDistanceM: Double,
    startGate: Gate? = null,
    finishGate: Gate? = null,
    val mode: RaceFinish.StartMode = RaceFinish.StartMode.GUN,
    goAtMs: Long? = null,
    lapCount: Int? = null,
) {
    private enum class StartState { PRE_GO, SEEKING, PENDING, COMMITTED }

    private class Sampled(val fix: RaceFinish.Fix, val s: Double)

    private class Base(val fromM: Double, val start: RaceFinish.Start?)

    /// The start line, or null when none was given or it is unusable.
    val startGate: Gate? = startGate?.takeIf { RaceFinish.lineUsable(it) }

    /// The finish line, or null when none was given or it is unusable.
    val finishGate: Gate? = finishGate?.takeIf { RaceFinish.lineUsable(it) }

    /// Metres between the two lines' centres; 0 without both.
    private val sepM: Double = this.startGate.let { s ->
        val f = this.finishGate
        if (s != null && f != null) RaceFinish.distanceM(s.lat, s.lng, f.lat, f.lng) else 0.0
    }

    private val startLine = this.startGate?.let { GateCrossingDetector(it) }
    private val finishLine = this.finishGate?.let { GateCrossingDetector(it) }

    /// The course's lap count, or null when the race froze none.
    val lapCount: Int? = lapCount?.takeIf { it >= 2 && this.finishGate != null }

    private var best: RaceFinish.Fix? = null
    private var bestDistanceM = Double.MAX_VALUE
    private var bestStart: RaceFinish.Start? = null

    private var goMs: Long? = null
    private val held = mutableListOf<RaceFinish.Fix>()
    private var closed = false
    private var prev: Sampled? = null
    private var state =
        if (mode == RaceFinish.StartMode.SELF_TIMED) StartState.SEEKING else StartState.PRE_GO
    private var pending: GateCrossing? = null
    private var committed: RaceFinish.Start? = null
    private var goCoveredM = 0.0
    private var passes = 0
    private var lastPassM: Double? = null
    private var lapM: Double? = null
    private var finishSeen = false

    var finish: RaceFinish.Finish? = null
        private set

    init {
        if (goAtMs != null) setGo(goAtMs)
    }

    private val v1: Boolean
        get() = mode == RaceFinish.StartMode.GUN && startGate == null && finishGate == null

    private val awaitingGo: Boolean
        get() = mode == RaceFinish.StartMode.GUN && startGate != null && goMs == null

    /// True while the runner is inside the zone past the gate and the
    /// closest approach is still being decided.
    val isCandidate: Boolean get() = candidate != null

    /// The best in-zone fix so far, while the approach is still open.
    val candidate: RaceFinish.Finish?
        get() {
            val b = best ?: return null
            if (finish != null || closed) return null
            return zoneFinish(b)
        }

    /// The start a finish would be measured from right now: the committed
    /// start. A self-timed start a backward crossing has re-armed stays it
    /// until a new forward crossing commits. Null for the Start press, and
    /// while the first crossing is still committing.
    val start: RaceFinish.Start?
        get() = committed

    /// Feed one fix. Returns the finish on the call that finalises it and
    /// null on every other call, including every call after it. A fix with
    /// a non-finite coordinate or covered distance is ignored, not judged:
    /// read as "outside the zone" it would finalise an open approach.
    fun offer(fix: RaceFinish.Fix): RaceFinish.Finish? {
        if (v1) return offerV1(fix)
        if (finish != null || closed) return null
        if (awaitingGo) {
            held.add(fix)
            return null
        }
        return process(fix)
    }

    /// GO, on the device clock the fixes are timed on. Fixed once set. With a
    /// start line in a gun mode the fixes held until now are replayed, and
    /// the call returns the finish when that replay finalises one.
    fun setGo(atMs: Long): RaceFinish.Finish? {
        if (goMs != null) return null
        goMs = atMs
        if (held.isEmpty()) return null
        val replay = held.toList()
        held.clear()
        if (finish != null || closed) return null
        for (fix in replay) {
            val r = process(fix)
            if (r != null) return r
        }
        return null
    }

    /// Settle a pending closest approach now — the runner pressed "Finish
    /// race" while standing in the zone. Null when there was none. With lines
    /// the stream is closed either way.
    fun finaliseNow(): RaceFinish.Finish? {
        finish?.let { return it }
        if (!v1) {
            closed = true
            held.clear()
        }
        return best?.let { finalise(it) }
    }

    private fun offerV1(fix: RaceFinish.Fix): RaceFinish.Finish? {
        if (finish != null) return null
        if (!fix.lat.isFinite() || !fix.lng.isFinite() || !fix.coveredM.isFinite()) return null
        val d = RaceFinish.distanceM(fix.lat, fix.lng, finishLat, finishLng)
        val eligible = RaceFinish.inFinishZone(d) &&
            covers(0.0, fix.coveredM, RaceFinish.MIN_DISTANCE_FRACTION)
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

    private fun process(fix: RaceFinish.Fix): RaceFinish.Finish? {
        if (!fix.lat.isFinite() || !fix.lng.isFinite() || !fix.coveredM.isFinite()) return null
        val before = prev
        if (before != null && fix.epochMs <= before.fix.epochMs) return null
        val sg = startGate
        val cur = Sampled(fix, if (sg == null) 0.0 else gateProjection(sg, fix.lat, fix.lng).s)
        prev = cur

        val go = goMs
        if (mode == RaceFinish.StartMode.GUN && sg != null && state == StartState.PRE_GO &&
            go != null && fix.epochMs >= go
        ) {
            resolveGo(before, cur, go)
        }

        val gf = GateFix(fix.lat, fix.lng, fix.epochMs.toDouble(), fix.coveredM)
        val sc = startLine?.offer(gf)
        val fc = finishLine?.offer(gf)
        if (sc != null && fc != null &&
            (sc.tMs < fc.tMs || (sc.tMs == fc.tMs && mode == RaceFinish.StartMode.GUN))
        ) {
            onStartCrossing(sc)
            onFinishCrossing(fc)
        } else {
            if (fc != null) onFinishCrossing(fc)
            if (finish == null && sc != null) onStartCrossing(sc)
        }
        finish?.let { return it }

        advanceCommit(fix.coveredM)
        zone(fix)
        return finish
    }

    private fun resolveGo(before: Sampled?, cur: Sampled, go: Long) {
        var sGo = cur.s
        var cGo = cur.fix.coveredM
        if (before != null && before.fix.epochMs < go) {
            val f = (go - before.fix.epochMs).toDouble() / (cur.fix.epochMs - before.fix.epochMs).toDouble()
            sGo = before.s + f * (cur.s - before.s)
            cGo = before.fix.coveredM + f * (cur.fix.coveredM - before.fix.coveredM)
        }
        if (sGo >= 0.0) {
            committed = RaceFinish.Start(go, cGo, RaceFinish.StartKind.GO)
            state = StartState.COMMITTED
        } else {
            goCoveredM = cGo
            state = StartState.SEEKING
        }
    }

    private fun advanceCommit(coveredM: Double) {
        val p = pending ?: return
        if (state != StartState.PENDING) return
        if (coveredM >= p.coveredM + RaceFinish.START_COMMIT_M) {
            if (committed != null) forgetLaps()
            committed = lineStart(p)
            pending = null
            state = StartState.COMMITTED
        }
    }

    private fun onStartCrossing(x: GateCrossing) {
        advanceCommit(x.coveredM)
        if (mode == RaceFinish.StartMode.SELF_TIMED) {
            if (x.direction == GateDirection.FORWARD) {
                if (state == StartState.COMMITTED) return
                pending = x
                state = StartState.PENDING
            } else {
                if (startHeld(x.coveredM)) return
                pending = null
                state = StartState.SEEKING
            }
            return
        }
        if (state != StartState.SEEKING && state != StartState.PENDING) return
        if (x.direction == GateDirection.FORWARD) {
            pending = x
            state = StartState.PENDING
        } else {
            pending = null
            state = StartState.SEEKING
        }
    }

    private fun onFinishCrossing(x: GateCrossing) {
        if (x.direction != GateDirection.FORWARD) return
        advanceCommit(x.coveredM)
        val base = base(x.tMs) ?: return
        if (base.start != null) finishSeen = true
        val pass = countPass(base, x.coveredM)
        val k = lapCount
        if (k != null && base.start != null && (!pass || passes < k)) return
        val share = if (base.start != null) RaceFinish.MIN_COVERAGE_WITH_START else RaceFinish.MIN_DISTANCE_FRACTION
        if (!covers(base.fromM, x.coveredM, share)) return
        finish = RaceFinish.Finish(
            epochMs = Math.round(x.tMs),
            distanceToFinishM = abs(x.offsetM),
            coveredM = x.coveredM,
            detection = RaceFinish.FinishDetection.GATE,
            start = base.start,
            gapped = x.gapped,
        )
    }

    private fun zone(fix: RaceFinish.Fix) {
        val d = RaceFinish.distanceM(fix.lat, fix.lng, finishLat, finishLng)
        val base = base(fix.epochMs.toDouble())
        val qualifies = RaceFinish.inFinishZone(d) && base != null &&
            covers(base.fromM, fix.coveredM, RaceFinish.MIN_DISTANCE_FRACTION) &&
            lapsMet(fix.coveredM) != false
        val current = best
        if (finishGate != null) {
            if (!qualifies) {
                best = null
                bestDistanceM = Double.MAX_VALUE
                bestStart = null
            } else if (current == null || d < bestDistanceM) {
                best = fix
                bestDistanceM = d
                bestStart = base!!.start
            }
            return
        }
        if (current != null && (!qualifies || d > bestDistanceM)) {
            finalise(current)
            return
        }
        if (qualifies && (current == null || d < bestDistanceM)) {
            best = fix
            bestDistanceM = d
            bestStart = base!!.start
        }
    }

    /// Where coverage counts from at [tMs], and its start; null when no
    /// finish can count then.
    private fun base(tMs: Double): Base? {
        if (mode == RaceFinish.StartMode.SELF_TIMED) {
            val c = committed ?: return null
            return Base(c.coveredM, c)
        }
        val go = goMs
        if (go != null && tMs < go.toDouble()) return null
        if (startGate == null) return Base(0.0, null)
        if (go == null) return null
        return when (state) {
            StartState.COMMITTED -> committed?.let { Base(it.coveredM, it) }
            StartState.SEEKING -> Base(goCoveredM, null)
            StartState.PRE_GO, StartState.PENDING -> null
        }
    }

    /// A self-timed start a backward crossing may no longer re-arm: the
    /// runner has passed the finish line forward since it, or covered the
    /// no-start share of the course, so they are on a later lap or coming home.
    private fun startHeld(coveredM: Double): Boolean {
        val c = committed ?: return false
        if (finishSeen) return true
        val d = courseDistanceM
        return d.isFinite() && d > 0.0 && coveredM - c.coveredM >= d * RaceFinish.MIN_DISTANCE_FRACTION
    }

    /// Whether a forward finish crossing at [coveredM] is a lap pass: from a
    /// committed start, at least the lines' separation plus
    /// [RaceFinish.START_COMMIT_M] past it (so the start's own pass is not
    /// one), and [RaceFinish.START_COMMIT_M] past the last pass (so a wobble
    /// across the line is one pass). Records it.
    private fun countPass(base: Base, coveredM: Double): Boolean {
        if (base.start == null) return false
        if (coveredM - base.fromM < sepM + RaceFinish.START_COMMIT_M) return false
        val last = lastPassM
        if (last != null && coveredM - last < RaceFinish.START_COMMIT_M) return false
        lapM = if (last == null) coveredM - base.fromM - sepM else coveredM - last
        lastPassM = coveredM
        passes += 1
        return true
    }

    private fun forgetLaps() {
        passes = 0
        lastPassM = null
        lapM = null
        finishSeen = false
    }

    /// Whether [coveredM] completes the laps, for a stop or a zone finish:
    /// with a lap count, every pass but the last made and half a lap since it
    /// (the lap measured as the runner's own mean), or every pass made; with
    /// none, from the second pass on, the coverage rule scaled by the lap just
    /// run. Null when no lap rule applies (no lap known, or no committed start
    /// to count from).
    fun lapsMet(coveredM: Double): Boolean? {
        val b = base(Double.POSITIVE_INFINITY) ?: return null
        val k = lapCount
        if (k != null) {
            if (b.start == null) return null
            if (passes >= k) return true
            val last = lastPassM
            if (passes == k - 1 && last != null) {
                val mean = (last - b.fromM - sepM) / passes
                return coveredM - last >= mean / 2
            }
            return false
        }
        if (passes >= 2) return covers(b.fromM, coveredM, RaceFinish.MIN_DISTANCE_FRACTION)
        return null
    }

    /// Covered distance from the base a finish needs at [share]; null when
    /// nothing can gate. With no lap count frozen, from the second pass on,
    /// the lap just run raises it to the course less half that lap. A first
    /// pass needs no floor: on a course of two or more laps it is at most half
    /// the course, under the share, and a single loop keeps the share's margin.
    private fun required(share: Double): Double? {
        val d = courseDistanceM
        if (!d.isFinite() || d <= 0.0) return null
        val lap = if (lapCount == null && passes >= 2) lapM else null
        val need = d * share
        return if (lap == null) need else maxOf(need, d - lap / 2)
    }

    private fun covers(fromM: Double, coveredM: Double, share: Double): Boolean {
        val need = required(share) ?: return true
        return coveredM - fromM >= need
    }

    private fun lineStart(x: GateCrossing) =
        RaceFinish.Start(Math.round(x.tMs), x.coveredM, RaceFinish.StartKind.LINE, x.gapped)

    private fun zoneFinish(b: RaceFinish.Fix) = RaceFinish.Finish(
        epochMs = b.epochMs,
        distanceToFinishM = bestDistanceM,
        coveredM = b.coveredM,
        start = bestStart,
    )

    private fun finalise(b: RaceFinish.Fix): RaceFinish.Finish = zoneFinish(b).also { finish = it }

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
