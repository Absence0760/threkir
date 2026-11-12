package com.runapp.watchwear

import kotlin.math.abs

/// The race a recording is being timed for right now: the race it is bound
/// to, else the runner's armed or live race while a recording runs (a
/// self-timed one only once "This run is my attempt" is on). [goServerMs] is
/// GO on the server clock, null until it is known and always for a
/// self-timed race, which has none.
internal data class RaceTarget(
    val eventId: String,
    val instanceStart: String,
    val selfTimed: Boolean,
    val goServerMs: Long?,
) {
    val key: String get() = "$eventId|$instanceStart"
}

/// Fixes a recording keeps from its Start for the detector to replay when the
/// race or its course is known only later: twelve hours at one a second, as
/// the phone's `kRaceFixLogMax`. Past it the oldest go first.
internal const val RACE_FIX_LOG_MAX = 43_200

/// How long "Not finished? Resume" is offered after a line finish (#1307
/// m11), the phone's `kRaceUndoWindow`.
internal const val RACE_UNDO_WINDOW_MS = 60_000L

/// The most `race_pings.since_start_line_s` holds (14 days, its CHECK).
internal const val RACE_PING_SINCE_START_MAX_S = 1_209_600L

/// Whole seconds from the committed [start] to [nowMs] (both device clock),
/// which the Self-timed spectator board orders by (#1306 M13). Null before a
/// start is committed — a Start press is no start line — and past what the
/// column holds. The phone's `_sinceStartLineS`.
internal fun raceSinceStartLineS(start: RaceFinish.Start?, nowMs: Long): Int? {
    val at = start?.epochMs ?: return null
    val s = (nowMs - at) / 1000
    if (s < 0) return 0
    return if (s > RACE_PING_SINCE_START_MAX_S) null else s.toInt()
}

/// How a result's start was detected (`event_results.start_detection`): a
/// start-line crossing or GO itself ([GATE]), or the runner's own Start press
/// ([DEVICE]).
internal enum class RaceStartDetection(val wire: String) { GATE("gate"), DEVICE("device") }

/// `race_finish v3` over this course, or null when it cannot finish itself:
/// no distance, no finish, or a finish line the route crosses before its end,
/// which finishes by hand only. A course with neither line in a gun mode is
/// v1's closest approach. Mirrors the phone's `_buildDetector`.
internal fun raceDetectorFor(
    course: RaceSessionClient.RaceCourse,
    selfTimed: Boolean,
    goDeviceMs: Long?,
): RaceFinishDetector? {
    if (course.finishLineSelfCross) return null
    val distance = course.distanceM ?: return null
    if (!distance.isFinite() || distance <= 0.0) return null
    val lat = course.finishLat ?: course.finishGate?.lat ?: return null
    val lng = course.finishLng ?: course.finishGate?.lng ?: return null
    return RaceFinishDetector(
        finishLat = lat,
        finishLng = lng,
        courseDistanceM = distance,
        startGate = course.startGate,
        finishGate = course.finishGate,
        mode = if (selfTimed) RaceFinish.StartMode.SELF_TIMED else RaceFinish.StartMode.GUN,
        goAtMs = if (selfTimed) null else goDeviceMs,
        lapCount = course.lapCount,
    )
}

/// The finish line armed again after a restart (#1307 m11): the first forward
/// crossing [x] strictly after the finish the runner took back at
/// [undoneFinishMs], covering [RaceFinish.MIN_DISTANCE_FRACTION] of the course
/// from the kept [start] (from the Start press without one). The share a
/// finish with no start line needs, not the 60 % a committed start earns, so
/// the early crossing that was taken back cannot finish again; the phone's
/// re-armed detector counts the same way. Null otherwise, and for a course
/// with no usable distance.
internal fun rearmedLineFinish(
    x: GateCrossing,
    start: RaceFinish.Start?,
    undoneFinishMs: Long,
    courseDistanceM: Double?,
): RaceFinish.Finish? {
    if (x.direction != GateDirection.FORWARD || x.tMs <= undoneFinishMs.toDouble()) return null
    val d = courseDistanceM ?: return null
    if (!d.isFinite() || d <= 0.0) return null
    if (x.coveredM - (start?.coveredM ?: 0.0) < d * RaceFinish.MIN_DISTANCE_FRACTION) return null
    return RaceFinish.Finish(
        epochMs = Math.round(x.tMs),
        distanceToFinishM = abs(x.offsetM),
        coveredM = x.coveredM,
        detection = RaceFinish.FinishDetection.GATE,
        start = start,
        gapped = x.gapped,
    )
}

/// The finish line a restarted recording is armed with, or null when the
/// course finishes by hand only.
internal fun rearmedFinishLine(course: RaceSessionClient.RaceCourse): GateCrossingDetector? {
    if (course.finishLineSelfCross) return null
    val gate = course.finishGate?.takeIf { RaceFinish.lineUsable(it) } ?: return null
    return GateCrossingDetector(gate)
}

/// Timing by the lines from the recording's Start (#1307 M1), the Kotlin half
/// of the phone's `RaceController` detection (decisions § 2450). Pure: no
/// Android, no I/O, no clock — `RunViewModel` hands it every fresh fix, the
/// race the recording is timed for, its course and the server offset.
///
/// Every fix is logged from the Start, bound to a race or not, and the
/// detector is (re)built over the log whenever the race and its course are
/// both known: a self-timed attempt as soon as it is armed, a gun race once
/// GO is. So a crossing in the seconds before the watch's 30 s poll hears GO,
/// or before the course loads, is kept and resolved against GO rather than
/// lost. A course with neither line keeps v1, which sees only fixes from GO
/// on (or, with no GO on record, from the bind on).
internal class RaceLineTimer(private val logMax: Int = RACE_FIX_LOG_MAX) {

    /// Called once per recording when a start-line crossing commits the
    /// start. The caller cues it; a throw is contained here.
    var onStartLineCrossed: (() -> Unit)? = null

    /// Where a contained failure is reported; the ViewModel logs it.
    var onFailure: (String, Throwable) -> Unit = { _, _ -> }

    /// A recording is running on this device.
    var recording: Boolean = false
        private set

    private val log = ArrayList<RaceFinish.Fix>()

    /// Log length when the recording bound: a v1 detector with no GO on
    /// record only ever saw fixes after the bind, and still does.
    private var bindIndex = 0
    private var bound = false

    private var key: String? = null
    private var target: RaceTarget? = null
    private var offsetMs = 0L

    var course: RaceSessionClient.RaceCourse? = null
        private set
    private var detector: RaceFinishDetector? = null

    /// The automatic finish found, live or on a replay.
    var finish: RaceFinish.Finish? = null
        private set
    private var pendingFinish: RaceFinish.Finish? = null

    /// The runner said "Not finished? Resume": this recording finishes by
    /// hand, from [keptStart].
    var voided: Boolean = false
        private set
    private var keptStart: RaceFinish.Start? = null

    /// A finish taken back before the app restarted, for the race [Rearm.key]:
    /// its start stands, and only a later finish-line crossing finishes.
    private class Rearm(val key: String, val start: RaceFinish.Start?, val undoneFinishMs: Long)

    private var rearm: Rearm? = null
    private var rearmLine: GateCrossingDetector? = null
    private var rearmTried = false

    /// The runner chose Finish race: the stream is closed.
    private var settled = false
    private var startCued = false

    /// Metres from the runner to the centre of the start line, until a start
    /// is committed; null without a course start line or a fix.
    var distanceToStartM: Double? = null
        private set

    /// Whether a detector is timing this recording right now.
    val detecting: Boolean get() = detector != null || rearmLine != null

    /// The start a finish is measured from: the automatic finish's, the
    /// detector's, the one kept through an undo, or the one an undo kept
    /// before a restart. Null for the Start press.
    val start: RaceFinish.Start?
        get() = finish?.start ?: detector?.start ?: keptStart ?: rearm?.takeIf { it.key == key }?.start

    /// A recording started: everything before it is forgotten.
    fun beginRecording() {
        reset()
        rearm = null
        log.clear()
        bindIndex = 0
        bound = false
        recording = true
    }

    /// The recording stopped or was discarded.
    fun endRecording() {
        beginRecording()
        recording = false
    }

    /// After a restart mid-recording, the finish the runner took back on this
    /// recording at [undoneFinishMs] (device clock), in the race [key], and the
    /// [start] it was measured from. That start is kept, and the finish line is
    /// armed again for a forward crossing after [undoneFinishMs] only, so the
    /// finish taken back is never found again. Call after [beginRecording].
    fun restoreUndone(key: String, start: RaceFinish.Start?, undoneFinishMs: Long) {
        rearm = Rearm(key, start, undoneFinishMs)
        rearmLine = null
        rearmTried = false
        if (finish == null) detector = null
    }

    /// The recording joined [race]. Idempotent.
    fun bind() {
        if (bound) return
        bound = true
        bindIndex = log.size
    }

    /// Bring the detector up to date with the race the recording is timed
    /// for, its course and the offset. Returns a finish found by a replay of
    /// the log (at GO, or when the course arrived), once.
    fun update(
        target: RaceTarget?,
        course: RaceSessionClient.RaceCourse?,
        serverOffsetMs: Long?,
    ): RaceFinish.Finish? {
        offsetMs = serverOffsetMs ?: 0L
        if (target == null) {
            if (!bound && key != null) reset()
            this.target = null
            return null
        }
        if (key != target.key) {
            reset()
            key = target.key
        }
        this.target = target
        if (course != null && this.course == null) {
            this.course = course
            if (finish == null) detector = null
        }
        return sync()
    }

    /// Feed one fresh, trusted fix, timed on the device clock at its own fix
    /// instant. Returns the finish on the fix that finalises it.
    fun offer(fix: RaceFinish.Fix): RaceFinish.Finish? {
        if (!recording || finish != null || settled) return null
        if (!fix.lat.isFinite() || !fix.lng.isFinite() || !fix.coveredM.isFinite()) return null
        log.add(fix)
        if (log.size > logMax + 1000) {
            log.subList(0, 1000).clear()
            bindIndex = if (bindIndex > 1000) bindIndex - 1000 else 0
        }
        updateDistanceToStart(fix)
        val line = rearmLine
        if (line != null) return if (voided) null else offerRearmed(line, fix)
        val d = detector ?: return null
        if (isV1(d) && !v1Sees(fix, log.size - 1, goDeviceMs())) return null
        val f = d.offer(fix)
        checkStartCue()
        return f?.let { onFinish(it) }
    }

    /// A finish the detector found and nobody has acted on yet, once.
    fun takePendingFinish(): RaceFinish.Finish? = pendingFinish.also { pendingFinish = null }

    /// "Finish race" (or a run that stopped on its own): close the stream
    /// and settle a closest approach open in the zone. Null when there was
    /// none, or after an undo.
    fun settle(): RaceFinish.Finish? {
        settled = true
        distanceToStartM = null
        finish?.let { return it }
        return detector?.finaliseNow()
    }

    /// The detector's lap rule at [coveredM] for a hand finish
    /// ([RaceFinishDetector.lapsMet]); null without a detector, after an
    /// undo (the re-armed line knows no laps) and with no lap rule.
    fun lapsMet(coveredM: Double): Boolean? = if (rearmLine != null) null else detector?.lapsMet(coveredM)

    /// "Not finished? Resume": forget the automatic finish and stop detecting.
    /// The start it was measured from is kept, so the hand finish after an
    /// undo is still timed from the start line. Returns whether there was one.
    fun voidAutoFinish(): Boolean {
        val f = finish ?: return false
        keptStart = f.start ?: detector?.start
        finish = null
        pendingFinish = null
        detector = null
        rearmLine = null
        voided = true
        return true
    }

    private fun reset() {
        key = null
        target = null
        course = null
        detector = null
        finish = null
        pendingFinish = null
        voided = false
        keptStart = null
        rearmLine = null
        rearmTried = false
        settled = false
        startCued = false
        distanceToStartM = null
    }

    private fun goDeviceMs(): Long? = target?.takeIf { !it.selfTimed }?.goServerMs?.let { it - offsetMs }

    private fun sync(): RaceFinish.Finish? {
        val t = target ?: return null
        val c = course ?: return null
        if (voided || finish != null || settled) return null
        rearm?.takeIf { it.key == t.key }?.let { return armAgain(c) }
        val goDevice = goDeviceMs()
        val d = detector
        if (d == null) {
            // A gun race waits for GO; a recording already bound (whose GO may
            // never have been on record) times as it always did.
            if (!t.selfTimed && goDevice == null && !bound) return null
            detector = raceDetectorFor(c, t.selfTimed, goDevice) ?: return null
            return replay(goDevice)
        }
        if (t.selfTimed || goDevice == null) return null
        val f = d.setGo(goDevice)?.let { onFinish(it) }
        checkStartCue()
        return f
    }

    /// The finish line, once per race, with the log replayed through it.
    private fun armAgain(c: RaceSessionClient.RaceCourse): RaceFinish.Finish? {
        if (rearmTried) return null
        rearmTried = true
        val line = rearmedFinishLine(c) ?: return null
        rearmLine = line
        for (fix in log) {
            val f = offerRearmed(line, fix)
            if (f != null) return f
        }
        return null
    }

    private fun offerRearmed(line: GateCrossingDetector, fix: RaceFinish.Fix): RaceFinish.Finish? {
        val r = rearm ?: return null
        val x = line.offer(GateFix(fix.lat, fix.lng, fix.epochMs.toDouble(), fix.coveredM)) ?: return null
        val f = rearmedLineFinish(x, r.start, r.undoneFinishMs, course?.distanceM) ?: return null
        return onFinish(f)
    }

    private fun replay(goDevice: Long?): RaceFinish.Finish? {
        val d = detector ?: return null
        val v1 = isV1(d)
        for ((i, fix) in log.withIndex()) {
            if (v1 && !v1Sees(fix, i, goDevice)) continue
            val f = d.offer(fix) ?: continue
            onFinish(f)
            checkStartCue()
            return f
        }
        checkStartCue()
        return null
    }

    private fun isV1(d: RaceFinishDetector): Boolean =
        d.mode == RaceFinish.StartMode.GUN && d.startGate == null && d.finishGate == null

    /// v1 holds nothing until GO, so it is shown only fixes from GO on, or,
    /// with no GO on record, only those after the recording bound.
    private fun v1Sees(fix: RaceFinish.Fix, index: Int, goDevice: Long?): Boolean =
        if (goDevice != null) fix.epochMs >= goDevice else bound && index >= bindIndex

    private fun onFinish(f: RaceFinish.Finish): RaceFinish.Finish {
        finish = f
        pendingFinish = f
        distanceToStartM = null
        return f
    }

    private fun checkStartCue() {
        val s = detector?.start ?: return
        distanceToStartM = null
        if (startCued || s.kind != RaceFinish.StartKind.LINE) return
        startCued = true
        try {
            onStartLineCrossed?.invoke()
        } catch (e: Throwable) {
            onFailure("race start cue failed; timing carries on", e)
        }
    }

    private fun updateDistanceToStart(fix: RaceFinish.Fix) {
        val gate = course?.startGate
        if (gate == null || target == null || start != null || rearm != null || finish != null || voided) {
            distanceToStartM = null
            return
        }
        distanceToStartM = RaceFinish.distanceM(fix.lat, fix.lng, gate.lat, gate.lng)
    }
}
