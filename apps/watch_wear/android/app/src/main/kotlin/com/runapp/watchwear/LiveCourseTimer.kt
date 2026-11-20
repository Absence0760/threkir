package com.runapp.watchwear

import kotlin.math.abs
import kotlin.math.max

/// What the live course timer needs of a park course: its catalogue
/// segment's stored length and start and end lines, and the course's ordered
/// checkpoints.
data class CourseTimingSpec(
    val distanceM: Double,
    val startGate: Gate,
    val endGate: Gate,
    val checkpoints: List<GatePoint> = emptyList(),
)

/// Course timing constants: the `segments` pair's
/// `GLOBAL_SEGMENT_BOX_SLACK_M`, `GLOBAL_SEGMENT_FINISH_MAX_GAP_S`, the two
/// `GLOBAL_SEGMENT_GAP_SPEED_*`, the 25 % length guard and the checkpoint
/// match tolerance (decisions § 2589).
const val COURSE_BOX_SLACK_M = 5.0
const val COURSE_FINISH_MAX_GAP_S = 300.0
const val COURSE_GAP_SPEED_MIN = 0.4
const val COURSE_GAP_SPEED_MAX = 1.5
const val COURSE_LENGTH_TOLERANCE = 0.25
const val COURSE_CHECKPOINT_TOLERANCE_M = 35.0

/// What one fix did to the course timing.
sealed interface CourseEvent {
    /// The runner left the start box going forward with no lap being timed:
    /// "Timing started".
    data class Started(val atMs: Double) : CourseEvent

    /// The runner entered the finish box having passed every checkpoint in
    /// order, within the length guard: "Finished! 8:42:10". Every complete
    /// lap finishes; the board keeps the fastest.
    data class Finished(val startMs: Double, val endMs: Double) : CourseEvent {
        val elapsedS: Double get() = (endMs - startMs) / 1000.0
    }
}

/// Times a park course live, fix by fix, by the server matcher's rule
/// (matcher version 4, decisions § 2589): the clock starts when the run
/// leaves the start box going forward and stops when it next enters the
/// finish box, with the covered distance within 25 % of the course and every
/// checkpoint passed in order between the two; 5 m of GPS slack on a
/// recording begun on the line or ended short of the box; a gap of up to
/// 5 minutes across the finish when crossed at the runner's own pace; every
/// lap a candidate. A one-way streaming port of `_scoreByGates` in the
/// `segments` pair (`apps/mobile_android/lib/segments.dart`), held to
/// `fixtures/park_course_runs.json` by `LiveCourseTimerTest`: the fastest lap
/// this timer finishes is the matcher's effort, to the millisecond.
///
/// The watch's cue only; the time on the board is still the server's, from
/// the uploaded track. Not thread-safe: feed it from one place.
class LiveCourseTimer(private val spec: CourseTimingSpec) {
    private val len = spec.distanceM
    private val minCovered = len * (1 - COURSE_LENGTH_TOLERANCE)
    private val maxCovered = len * (1 + COURSE_LENGTH_TOLERANCE)

    val usable: Boolean = len.isFinite() && len > 0.0 &&
        gateUsable(spec.startGate) && gateUsable(spec.endGate)

    private val edges = gateTimingEdges(spec.startGate, spec.endGate)
    private val exit = edges.startExit
    private val entry = edges.finishEntry
    private val startDetector = GateCrossingDetector(exit)
    private val endDetector = GateCrossingDetector(entry)
    private val chained = edges.layout == GateBoxLayout.APART && linesChain(spec.startGate, spec.endGate)

    private class Pending(val crossing: GateCrossing) {
        /// Index of the next checkpoint still to pass.
        var cursor = 0

        /// [cursor] as it stood at the first fix of the stretch the recording
        /// ends in (the finish box and its slack), for [settle].
        var tailCursor: Int? = null
    }

    private class Gap(val fromCoveredM: Double, val fromMs: Double, val gapS: Double, val valid: Boolean)

    private var pending = mutableListOf<Pending>()
    private var accepted = false
    private var prevMs = Double.NEGATIVE_INFINITY
    private var prevCoveredM = 0.0
    private var lastLat = Double.NaN
    private var lastLng = Double.NaN
    private var coveredM = 0.0
    private var anyFix = false

    /// Fixes since the last accepted one (that one first): a start opened at
    /// a fix counts checkpoints from the accepted fix before it.
    private val sinceAccepted = mutableListOf<GatePoint>()

    private var tailOpen = false
    private var tailCoveredM = 0.0
    private var tailMs = Double.NaN
    private var tailGap = Gap(0.0, Double.NaN, 0.0, false)
    private var prevEntry = GateProjection(Double.NaN, Double.NaN)

    private val finishes = mutableListOf<CourseEvent.Finished>()

    /// Every lap finished so far, in order.
    val finished: List<CourseEvent.Finished> get() = finishes.toList()

    /// The fastest lap finished so far: what the matcher will time.
    val best: CourseEvent.Finished? get() = finishes.minByOrNull { it.endMs - it.startMs }

    /// Whether a lap is being timed: a start is open.
    val timing: Boolean get() = pending.isNotEmpty()

    private fun advance(p: Pending, lat: Double, lng: Double) {
        val cps = spec.checkpoints
        while (p.cursor < cps.size &&
            courseHaversineM(lat, lng, cps[p.cursor].lat, cps[p.cursor].lng) <= COURSE_CHECKPOINT_TOLERANCE_M
        ) {
            p.cursor++
        }
    }

    private fun passed(cursor: Int?): Boolean = cursor != null && cursor >= spec.checkpoints.size

    /// Offer one fix: [tMs] epoch milliseconds. Returns what it did, in
    /// order (a chained loop's finish can open the next lap on the same fix,
    /// which is not announced as a start).
    fun offer(lat: Double, lng: Double, tMs: Double): List<CourseEvent> {
        if (!usable || !lat.isFinite() || !lng.isFinite() || !tMs.isFinite()) return emptyList()
        if (anyFix) coveredM += courseHaversineM(lastLat, lastLng, lat, lng)
        anyFix = true
        lastLat = lat
        lastLng = lng
        for (p in pending) advance(p, lat, lng)
        sinceAccepted.add(GatePoint(lat, lng))
        if (tMs <= prevMs) return emptyList()

        val wasTiming = pending.isNotEmpty()
        val events = mutableListOf<CourseEvent>()
        val fix = GateFix(lat = lat, lng = lng, tMs = tMs, coveredM = coveredM)
        val endCrossing = endDetector.offer(fix)
        val startCrossing = startDetector.offer(fix)

        val gap = Gap(prevCoveredM, prevMs, (tMs - prevMs) / 1000.0, accepted)
        val inFinish = gateProjection(entry, lat, lng)
        if (inFinish.s >= -COURSE_BOX_SLACK_M && inFinish.s <= edges.depthM && abs(inFinish.u) <= entry.halfWidthM) {
            if (!tailOpen) {
                tailOpen = true
                tailCoveredM = coveredM
                tailMs = tMs
                tailGap = gap
                for (p in pending) p.tailCursor = p.cursor
            }
        } else {
            tailOpen = false
        }

        val entered: GateCrossing? = when {
            endCrossing != null && endCrossing.direction == GateDirection.FORWARD -> endCrossing
            gap.gapS > GATE_REJECT_GAP_S && gap.gapS <= COURSE_FINISH_MAX_GAP_S ->
                enteredAcrossGap(prevEntry, inFinish, fix, pending.lastOrNull())
            else -> null
        }
        prevEntry = inFinish

        var closedBy: GateCrossing? = null
        if (entered != null) {
            val chosen = pick(entered.coveredM, entered.tMs, gap, coveredM) { it.cursor }
            if (chosen != null) {
                val done = CourseEvent.Finished(chosen.crossing.tMs, entered.tMs)
                finishes.add(done)
                events.add(done)
                pending = mutableListOf()
                closedBy = entered
            }
        }
        if (closedBy != null && chained) pending.add(open(closedBy))
        if (startCrossing != null && startCrossing.direction == GateDirection.FORWARD &&
            (closedBy == null || startCrossing.tMs >= closedBy.tMs)
        ) {
            pending.add(open(startCrossing))
        } else if (!accepted) {
            val atStart = gateProjection(exit, lat, lng)
            if (atStart.s >= 0.0 && atStart.s <= COURSE_BOX_SLACK_M && abs(atStart.u) <= exit.halfWidthM) {
                val p = Pending(
                    GateCrossing(
                        direction = GateDirection.FORWARD,
                        fraction = 0.0,
                        tMs = tMs,
                        coveredM = coveredM,
                        offsetM = atStart.u,
                        gapped = false,
                    ),
                )
                advance(p, lat, lng)
                pending.add(p)
            }
        }
        if (closedBy == null && !wasTiming && pending.isNotEmpty()) {
            events.add(CourseEvent.Started(pending.first().crossing.tMs))
        }

        accepted = true
        prevMs = tMs
        prevCoveredM = coveredM
        sinceAccepted.clear()
        sinceAccepted.add(GatePoint(lat, lng))
        return events
    }

    /// The recording stopped. One that ends in the finish box, or 5 m short
    /// of it, without having entered finishes where its last stretch there
    /// began. Returns that finish, if any; nothing is offered after.
    fun settle(): CourseEvent.Finished? {
        if (!usable || !tailOpen || pending.isEmpty()) return null
        val chosen = pick(tailCoveredM, tailMs, tailGap, tailCoveredM) { it.tailCursor } ?: return null
        val done = CourseEvent.Finished(chosen.crossing.tMs, tailMs)
        finishes.add(done)
        tailOpen = false
        pending = mutableListOf()
        return done
    }

    /// A start at the current fix: checkpoints count from the accepted fix
    /// before it.
    private fun open(crossing: GateCrossing): Pending {
        val p = Pending(crossing)
        for (pt in sinceAccepted) advance(p, pt.lat, pt.lng)
        return p
    }

    private fun pick(
        endCoveredM: Double,
        endMs: Double,
        gap: Gap,
        toCoveredM: Double,
        cursorOf: (Pending) -> Int?,
    ): Pending? {
        pending = pending.filter { endCoveredM - it.crossing.coveredM <= maxCovered }.toMutableList()
        var picked: Pending? = null
        for (s in pending) {
            if (endCoveredM - s.crossing.coveredM < minCovered) continue
            if (!(endMs > s.crossing.tMs)) continue
            if (gap.gapS > GATE_REJECT_GAP_S && !plausibleGap(s, gap, toCoveredM)) continue
            if (!passed(cursorOf(s))) continue
            picked = s
        }
        return picked
    }

    private fun plausibleGap(start: Pending, gap: Gap, toCoveredM: Double): Boolean {
        if (gap.gapS > COURSE_FINISH_MAX_GAP_S || !gap.valid) return false
        val soFarS = (gap.fromMs - start.crossing.tMs) / 1000.0
        val soFarM = gap.fromCoveredM - start.crossing.coveredM
        if (!(soFarS > 0.0) || !(soFarM > 0.0)) return false
        val avg = soFarM / soFarS
        val across = (toCoveredM - gap.fromCoveredM) / gap.gapS
        return across >= COURSE_GAP_SPEED_MIN * avg && across <= COURSE_GAP_SPEED_MAX * avg
    }

    private fun enteredAcrossGap(
        prev: GateProjection,
        cur: GateProjection,
        fix: GateFix,
        since: Pending?,
    ): GateCrossing? {
        if (since == null ||
            !(prev.s < 0.0 || abs(prev.u) > entry.halfWidthM) ||
            cur.s < 0.0 ||
            abs(cur.u) > entry.halfWidthM
        ) {
            return null
        }
        val paceS = (prevMs - since.crossing.tMs) / 1000.0
        val paceM = prevCoveredM - since.crossing.coveredM
        if (!(paceS > 0.0) || !(paceM > 0.0)) return null
        val backS = cur.s / (paceM / paceS)
        val tMs = max(prevMs, fix.tMs - backS * 1000.0)
        return GateCrossing(
            direction = GateDirection.FORWARD,
            fraction = (tMs - prevMs) / (fix.tMs - prevMs),
            tMs = tMs,
            coveredM = max(prevCoveredM, fix.coveredM - cur.s),
            offsetM = cur.u,
            gapped = true,
        )
    }
}

/// A course time as the runner reads it: whole seconds, "8:42:10" from an
/// hour, "16:05" under one.
fun formatCourseTime(elapsedS: Double): String {
    val total = Math.round(elapsedS.coerceAtLeast(0.0))
    val h = total / 3600
    val m = (total % 3600) / 60
    val sec = total % 60
    return if (h > 0) {
        String.format(java.util.Locale.ROOT, "%d:%02d:%02d", h, m, sec)
    } else {
        String.format(java.util.Locale.ROOT, "%d:%02d", m, sec)
    }
}

/// What the running screen says about the course: "Timing started" while a
/// lap is timed and none has finished since, else "Finished!" with the last
/// lap's time. Null before the first start.
data class CourseCueView(val finishedS: Double?)

/// The cue after [events], from [current]: the last event wins.
fun courseCueAfter(current: CourseCueView?, events: List<CourseEvent>): CourseCueView? =
    when (val last = events.lastOrNull()) {
        null -> current
        is CourseEvent.Started -> CourseCueView(finishedS = null)
        is CourseEvent.Finished -> CourseCueView(finishedS = last.elapsedS)
    }

/// The timer for a run on [route]: the course it is, when it is one of
/// [courses] and the timer can time it; null for a saved route, a course no
/// longer offered, or one without a usable pair of lines or a length.
fun courseTimerFor(route: SavedRoute?, courses: List<ParkCourse>): LiveCourseTimer? {
    val id = route?.courseId ?: return null
    val course = courses.firstOrNull { it.id == id } ?: return null
    return LiveCourseTimer(course.timing).takeIf { it.usable }
}
