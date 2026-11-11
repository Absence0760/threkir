package com.runapp.watchwear

import java.io.File
import java.math.BigDecimal
import java.math.RoundingMode
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.OffsetDateTime
import java.time.ZoneId
import kotlin.math.abs
import kotlin.math.ceil

/// Timing-line calibration on the watch (#1304 § 6), the Kotlin half of the
/// phone's `line_calibration.dart` (decisions § 2453): the error figures a
/// field session measures, from the fixes Wear's own feed hands the race
/// timer. Debug builds only — the entry, the screen and the capture feed all
/// sit behind `BuildConfig.DEBUG`, which a release build sets false.
///
/// The operator video-times each real crossing against an NTP-synced clock
/// and types those instants in afterwards: a tap would add a reaction time
/// the size of what is being measured. Nothing here keeps a fix past the
/// session or writes one anywhere: the capture is in memory, and
/// [calibrationCsv] carries error figures and counts only, in the phone's
/// format column for column.

/// The most fixes one capture holds: 12 h at one a second.
const val CALIBRATION_MAX_FIXES = 43_200

/// A detected crossing further than this from every true one is false, and a
/// true one with no detection this close is missed.
const val CALIBRATION_MATCH_WINDOW_MS = 10_000.0

/// How far out, in half-widths, a crossing of the extended line is still
/// exported as a [CalibrationOutcome.NEAR_MISS].
const val CALIBRATION_NEAR_MISS_WIDTHS = 3.0

/// The matrix cell a capture belongs to. Closed vocabularies, so nothing typed
/// by hand reaches the export; the wire values are the phone's.
enum class CalibrationApproach(val wire: String) {
    DEG90("90"),
    DEG30("30"),
    PARALLEL20("parallel_20m"),
    PARALLEL40("parallel_40m"),
    STANDING("standing_on_line"),
}

enum class CalibrationPace(val wire: String) { WALK("walk"), RUN("run"), STILL("still") }

/// Where the device rode. The phone writes `phone_hand` / `phone_pocket`; a
/// watch is always on the wrist.
enum class CalibrationCarry(val wire: String) { WRIST("wear_wrist") }

data class CalibrationCell(
    val approach: CalibrationApproach,
    val pace: CalibrationPace,
    val carry: CalibrationCarry = CalibrationCarry.WRIST,
)

/// The fixes the race timer is offered, captured while a session runs, by
/// the race feed's own rule ([raceFixOfferable]): recording and not paused,
/// once per fix, timed on the device clock at the fix's own instant
/// ([raceFixDeviceMs]). Each recording is its own series, as the timer starts
/// afresh with every recording, so the last fix of one run and the first of
/// the next are never a pair.
class LineCalibrationCapture(private val maxFixes: Int = CALIBRATION_MAX_FIXES) {

    var active: Boolean = false
        private set
    var fixCount: Int = 0
        private set

    private val series = ArrayList<ArrayList<GateFix>>()
    private var runId: String? = null
    private var lastFixKey = Long.MIN_VALUE

    val recordings: List<List<GateFix>> get() = series.map { it.toList() }

    /// The first fix's instant (device clock), or null before one.
    val firstFixMs: Double? get() = series.firstOrNull { it.isNotEmpty() }?.first()?.tMs

    fun start() {
        clear()
        active = true
    }

    fun stop() {
        active = false
    }

    fun clear() {
        active = false
        series.clear()
        fixCount = 0
        runId = null
        lastFixKey = Long.MIN_VALUE
    }

    /// One metrics update of recording [runId]: [fix] is its latest fix,
    /// [fixKey] that fix's identity, [recording] false while paused.
    fun offer(runId: String?, recording: Boolean, fixKey: Long, fix: GateFix) {
        if (!active || runId == null) return
        if (runId != this.runId) {
            this.runId = runId
            series.add(ArrayList())
            lastFixKey = Long.MIN_VALUE
        }
        if (!raceFixOfferable(recording, decided = false, fixKey = fixKey, lastFixKey = lastFixKey)) return
        lastFixKey = fixKey
        if (!fix.lat.isFinite() || !fix.lng.isFinite() || !fix.coveredM.isFinite()) return
        if (fixCount >= maxFixes) return
        fixCount++
        series.last().add(fix)
    }

    companion object {
        /// The one capture the recording feed and the debug screen share.
        val shared = LineCalibrationCapture()
    }
}

/// The server clock minus the device's, from round trips to `server_now`.
/// The shortest round trip wins and a tie keeps the earlier, as the phone's
/// `CalibrationClock` does.
class CalibrationClock {
    var offsetMs: Long? = null
        private set

    /// The winning sample's round trip; the offset is good to half of it.
    var rttMs: Long? = null
        private set

    fun addSample(sentAtMs: Long, receivedAtMs: Long, serverAtMs: Long) {
        val rtt = receivedAtMs - sentAtMs
        if (rtt < 0) return
        val best = rttMs
        if (best != null && rtt >= best) return
        offsetMs = serverAtMs - (sentAtMs + rtt / 2)
        rttMs = rtt
    }
}

enum class CalibrationOutcome(val wire: String) {
    MATCHED("matched"),
    MISSED("missed"),
    FALSE_CROSSING("false"),

    /// The track crossed the extended line beyond the half-width, within
    /// [CALIBRATION_NEAR_MISS_WIDTHS] half-widths, and no true crossing
    /// explains it: kept for its lateral offset, which `halfWidthM` is
    /// calibrated from.
    NEAR_MISS("near_miss"),
}

/// Why a true crossing was not detected: beyond the half-width, inside a gap
/// past `rejectGapS` (judged by the pair's span), only a backward crossing
/// near it, or none.
enum class CalibrationMissReason(val wire: String) {
    OUTSIDE_HALF_WIDTH("outside_half_width"),
    GAP_REJECTED("gap_rejected"),
    BACKWARD_ONLY("backward_only"),
    NO_CROSSING("no_crossing"),
}

data class CalibrationRow(
    val outcome: CalibrationOutcome,
    /// Detected minus true, on the server clock: positive is late.
    val errorMs: Long? = null,
    /// The crossing's lateral offset from the line's centre, metres.
    val offsetM: Double? = null,
    val gapped: Boolean = false,
    val missReason: CalibrationMissReason? = null,
)

class CalibrationResult(
    val cell: CalibrationCell,
    val rows: List<CalibrationRow>,
    val trueCount: Int,
    val forwardCount: Int,
    val backwardCount: Int,
    /// The round trip the offset came from; null when it was typed.
    val offsetRttMs: Long? = null,
    /// The median, over the true crossings, of the nearest forward detection
    /// minus the truth with no window: far from zero when nothing matched
    /// points at a clock, offset or time-zone slip.
    val nearestDiffMs: Long? = null,
) {
    private fun count(o: CalibrationOutcome) = rows.count { it.outcome == o }
    val matched: Int get() = count(CalibrationOutcome.MATCHED)
    val missed: Int get() = count(CalibrationOutcome.MISSED)
    val falseCrossings: Int get() = count(CalibrationOutcome.FALSE_CROSSING)
    val nearMisses: Int get() = count(CalibrationOutcome.NEAR_MISS)

    private val errors: List<Long> get() = rows.mapNotNull { it.errorMs }
    val medianErrorMs: Long? get() = calibrationMedianMs(errors)
    val medianAbsErrorMs: Long? get() = calibrationMedianMs(errors.map { abs(it) })

    /// Nearest-rank, so below 20 matched crossings it is the largest error.
    val p95AbsErrorMs: Long? get() = calibrationPercentileMs(errors.map { abs(it) }, 95.0)
}

/// Dart's `round()`: half away from zero.
internal fun roundHalfAway(x: Double): Long = if (x < 0) -Math.round(-x) else Math.round(x)

/// The median, the mean of the two middle values for an even count, rounded
/// to the millisecond. Null for no values.
fun calibrationMedianMs(values: List<Long>): Long? {
    if (values.isEmpty()) return null
    val v = values.sorted()
    val n = v.size
    if (n % 2 == 1) return v[n / 2]
    return roundHalfAway((v[n / 2 - 1] + v[n / 2]) / 2.0)
}

/// The nearest-rank [p]th percentile: the smallest value with at least p %
/// of the values at or below it. Null for no values.
fun calibrationPercentileMs(values: List<Long>, p: Double): Long? {
    if (values.isEmpty()) return null
    val v = values.sorted()
    val rank = ceil(p / 100 * v.size).toInt().coerceIn(1, v.size)
    return v[rank - 1]
}

private fun crossingsIn(recordings: List<List<GateFix>>, gate: Gate, o: GateCrossingOptions): List<GateCrossing> =
    recordings.flatMap { crossingsOf(it, gate, o) }

private class CalibrationPair(val t: Int, val d: Int, val err: Double)

/// Score one capture against the operator's true crossing instants (epoch
/// milliseconds on the server clock). Each recording goes through
/// `gate_crossing` with the shipped options; a fix instant is on the device
/// clock, and [clockOffsetMs] (server minus device) puts it on the server
/// clock. Each true crossing pairs with the forward crossing nearest it within
/// [windowMs], closest pairs first, each used once. The phone's
/// `analyseCalibration`, rule for rule.
fun analyseCalibration(
    cell: CalibrationCell,
    recordings: List<List<GateFix>>,
    gate: Gate,
    trueCrossingsMs: List<Double>,
    clockOffsetMs: Long,
    offsetRttMs: Long? = null,
    windowMs: Double = CALIBRATION_MATCH_WINDOW_MS,
    options: GateCrossingOptions = GateCrossingOptions(),
): CalibrationResult {
    val all = crossingsIn(recordings, gate, options)
    val forward = all.filter { it.direction == GateDirection.FORWARD }
    val backward = all.filter { it.direction == GateDirection.BACKWARD }
    val truth = trueCrossingsMs
    fun serverMs(c: GateCrossing) = c.tMs + clockOffsetMs

    val pairs = ArrayList<CalibrationPair>()
    for (i in truth.indices) {
        for (j in forward.indices) {
            val err = serverMs(forward[j]) - truth[i]
            if (abs(err) <= windowMs) pairs.add(CalibrationPair(i, j, err))
        }
    }
    pairs.sortWith(compareBy<CalibrationPair>({ abs(it.err) }, { it.t }, { it.d }))
    val trueTaken = HashMap<Int, CalibrationPair>()
    val detTaken = HashSet<Int>()
    for (p in pairs) {
        if (trueTaken.containsKey(p.t) || p.d in detTaken) continue
        trueTaken[p.t] = p
        detTaken.add(p.d)
    }

    val wide = Gate(gate.lat, gate.lng, gate.bearingDeg, 1e9)
    val beyond = crossingsIn(recordings, wide, options)
        .filter { it.direction == GateDirection.FORWARD && abs(it.offsetM) > gate.halfWidthM }
    val beyondTaken = HashSet<Int>()

    val rows = ArrayList<CalibrationRow>()
    for (i in truth.indices) {
        val m = trueTaken[i]
        if (m != null) {
            val c = forward[m.d]
            rows.add(CalibrationRow(CalibrationOutcome.MATCHED, roundHalfAway(m.err), c.offsetM, c.gapped))
            continue
        }
        rows.add(missedRow(truth[i], clockOffsetMs, windowMs, beyond, beyondTaken, backward, recordings, gate, options))
    }
    for (j in forward.indices) {
        if (j in detTaken) continue
        rows.add(CalibrationRow(CalibrationOutcome.FALSE_CROSSING, offsetM = forward[j].offsetM, gapped = forward[j].gapped))
    }
    val nearLimit = gate.halfWidthM * CALIBRATION_NEAR_MISS_WIDTHS
    for (k in beyond.indices) {
        val c = beyond[k]
        if (k in beyondTaken || abs(c.offsetM) > nearLimit) continue
        rows.add(CalibrationRow(CalibrationOutcome.NEAR_MISS, offsetM = c.offsetM, gapped = c.gapped))
    }

    val nearest = ArrayList<Long>()
    if (forward.isNotEmpty()) {
        for (t in truth) {
            var best = Double.POSITIVE_INFINITY
            for (c in forward) {
                val d = serverMs(c) - t
                if (abs(d) < abs(best)) best = d
            }
            nearest.add(roundHalfAway(best))
        }
    }

    return CalibrationResult(
        cell = cell,
        rows = rows,
        trueCount = truth.size,
        forwardCount = forward.size,
        backwardCount = backward.size,
        offsetRttMs = offsetRttMs,
        nearestDiffMs = calibrationMedianMs(nearest),
    )
}

private fun missedRow(
    truthMs: Double,
    offsetMs: Long,
    windowMs: Double,
    beyond: List<GateCrossing>,
    beyondTaken: MutableSet<Int>,
    backward: List<GateCrossing>,
    recordings: List<List<GateFix>>,
    gate: Gate,
    options: GateCrossingOptions,
): CalibrationRow {
    fun near(c: GateCrossing) = abs(c.tMs + offsetMs - truthMs) <= windowMs
    var pick = -1
    for (k in beyond.indices) {
        if (k in beyondTaken || !near(beyond[k])) continue
        if (pick < 0 || abs(beyond[k].tMs - truthMs) < abs(beyond[pick].tMs - truthMs)) pick = k
    }
    if (pick >= 0) {
        beyondTaken.add(pick)
        return CalibrationRow(
            CalibrationOutcome.MISSED,
            offsetM = beyond[pick].offsetM,
            gapped = beyond[pick].gapped,
            missReason = CalibrationMissReason.OUTSIDE_HALF_WIDTH,
        )
    }
    val deviceMs = truthMs - offsetMs
    val rejectMs = options.rejectGapS * 1000
    for (r in recordings) {
        for (i in 1 until r.size) {
            val a = r[i - 1]
            val b = r[i]
            if (b.tMs - a.tMs <= rejectMs) continue
            if (deviceMs < a.tMs || deviceMs > b.tMs) continue
            val sa = gateProjection(gate, a.lat, a.lng).s
            val sb = gateProjection(gate, b.lat, b.lng).s
            if ((sa < 0) != (sb < 0)) {
                return CalibrationRow(CalibrationOutcome.MISSED, gapped = true, missReason = CalibrationMissReason.GAP_REJECTED)
            }
        }
    }
    if (backward.any { near(it) }) {
        return CalibrationRow(CalibrationOutcome.MISSED, missReason = CalibrationMissReason.BACKWARD_ONLY)
    }
    return CalibrationRow(CalibrationOutcome.MISSED, missReason = CalibrationMissReason.NO_CROSSING)
}

/// The phone's `kCalibrationCsvColumns`, in order: the export is read by the
/// same tooling whichever device made it.
val CALIBRATION_CSV_COLUMNS = listOf(
    "kind",
    "approach",
    "pace",
    "carry",
    "crossing",
    "outcome",
    "error_ms",
    "offset_m",
    "gapped",
    "miss_reason",
    "true_count",
    "forward_detected",
    "backward_detected",
    "matched",
    "missed",
    "false",
    "near_miss",
    "median_error_ms",
    "median_abs_error_ms",
    "p95_abs_error_ms",
    "offset_rtt_ms",
)

/// Dart's `toStringAsFixed(1)`: the exact binary value rounded half away from
/// zero, keeping the sign of a negative that rounds to zero.
internal fun fixed1(v: Double): String {
    val s = BigDecimal(v).setScale(1, RoundingMode.HALF_UP).toPlainString()
    return if (v < 0 && !s.startsWith("-")) "-$s" else s
}

/// The export: one `crossing` row per scored crossing and one `summary` row
/// per capture, byte for byte the phone's `calibrationCsv`. Every field is an
/// enum wire value or a number derived from the errors; the lateral offset is
/// relative to the line, to 0.1 m.
fun calibrationCsv(results: List<CalibrationResult>): String {
    val out = StringBuilder(CALIBRATION_CSV_COLUMNS.joinToString(",")).append('\n')
    fun n(v: Number?) = v?.toString() ?: ""
    fun m(v: Double?) = v?.let(::fixed1) ?: ""
    for (r in results) {
        val cell = listOf(r.cell.approach.wire, r.cell.pace.wire, r.cell.carry.wire)
        for ((i, row) in r.rows.withIndex()) {
            val fields = listOf("crossing") + cell + listOf(
                "${i + 1}",
                row.outcome.wire,
                n(row.errorMs),
                m(row.offsetM),
                if (row.gapped) "1" else "0",
                row.missReason?.wire ?: "",
            ) + List(11) { "" }
            out.append(fields.joinToString(",")).append('\n')
        }
        val summary = listOf("summary") + cell + List(6) { "" } + listOf(
            n(r.trueCount),
            n(r.forwardCount),
            n(r.backwardCount),
            n(r.matched),
            n(r.missed),
            n(r.falseCrossings),
            n(r.nearMisses),
            n(r.medianErrorMs),
            n(r.medianAbsErrorMs),
            n(r.p95AbsErrorMs),
            n(r.offsetRttMs),
        )
        out.append(summary.joinToString(",")).append('\n')
    }
    return out.toString()
}

/// Parse the operator's video-timed instants, as epoch milliseconds: one per
/// line (or comma or semicolon), a time of day `HH:MM:SS(.ffffff)` on [day]
/// in [zone], or an ISO-8601 instant (read in [zone] when it names none).
/// Null when any non-blank entry does not parse.
fun parseCalibrationInstants(text: String, day: LocalDate, zone: ZoneId): List<Double>? {
    val out = ArrayList<Double>()
    val clock = Regex("""^(\d{1,2}):(\d{2}):(\d{2})(?:\.(\d{1,6}))?$""")
    for (raw in text.split(Regex("[\n,;]"))) {
        val line = raw.trim()
        if (line.isEmpty()) continue
        val c = clock.find(line)
        if (c != null) {
            val h = c.groupValues[1].toInt()
            val mi = c.groupValues[2].toInt()
            val s = c.groupValues[3].toInt()
            if (h > 23 || mi > 59 || s > 59) return null
            val frac = c.groupValues[4]
            val us = if (frac.isEmpty()) 0L else frac.padEnd(6, '0').toLong()
            val at = day.atTime(h, mi, s).atZone(zone).toInstant().toEpochMilli()
            out.add(at.toDouble() + us / 1000.0)
            continue
        }
        out.add(isoInstantMs(line, zone) ?: return null)
    }
    return out
}

private fun isoInstantMs(text: String, zone: ZoneId): Double? {
    val iso = text.replace(' ', 'T')
    val instant = runCatching { OffsetDateTime.parse(iso).toInstant() }.getOrNull()
        ?: runCatching { LocalDateTime.parse(iso).atZone(zone).toInstant() }.getOrNull()
        ?: return null
    return instant.epochSecond * 1000.0 + instant.nano / 1_000_000.0
}

/// Where a debug build keeps the export, under the app's private files, so it
/// leaves the watch only by `adb` (`run-as`) and never by a share or a sync.
fun writeCalibrationCsv(filesDir: File, csv: String): File {
    val f = File(filesDir, "line_calibration.csv")
    f.writeText(csv)
    return f
}
