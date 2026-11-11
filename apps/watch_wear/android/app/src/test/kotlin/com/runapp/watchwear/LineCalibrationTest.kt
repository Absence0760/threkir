package com.runapp.watchwear

import java.io.File
import java.nio.file.Files
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.ZonedDateTime
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.roundToInt

/// The Wear half of the timing-line calibration figures (#1304 § 6), held to
/// the phone's `line_calibration_test.dart`: the same tracks, offsets and true
/// instants, and the same expected figures and CSV lines, so both devices
/// score a session alike. Plus the watch's own capture rule, its export file,
/// and a guard that nothing reaches the tool outside a debug-build branch.
class LineCalibrationTest {

    // A line at a distinctive spot, so a coordinate leaking into the CSV shows.
    private val lat0 = 47.123456
    private val lng0 = 8.654321
    private val mPerDegLat = 6371008.8 * PI / 180
    private val mPerDegLng = mPerDegLat * cos(lat0 * PI / 180)

    private val gate = Gate(lat0, lng0, 90.0, 15.0)
    private val cell = CalibrationCell(CalibrationApproach.DEG90, CalibrationPace.RUN)

    private val t0 = ZonedDateTime.of(2026, 11, 10, 7, 0, 0, 0, ZoneId.of("UTC")).toInstant().toEpochMilli()

    /// One fix [eastM] past the line and [northM] off its centre, [ms] after
    /// 07:00:00 on the device clock.
    private fun fix(eastM: Double, ms: Int, northM: Double = 0.0) = GateFix(
        lat = lat0 + northM / mPerDegLat,
        lng = lng0 + eastM / mPerDegLng,
        tMs = t0 + ms.toDouble(),
        coveredM = eastM + 100,
    )

    /// A pass west to east at 4 m/s with a fix a second, crossing the line
    /// [crossAtMs] after 07:00:00, half-way between two fixes.
    private fun pass(crossAtMs: Int, northM: Double = 0.0) =
        (-5..5).map { k -> fix(4.0 * (k * 1000 - 500) / 1000, crossAtMs + k * 1000 - 500, northM) }

    private fun truth(ms: Int) = (t0 + ms).toDouble()

    @Test
    fun `pairs each true crossing with the nearest detection on the server clock`() {
        val r = analyseCalibration(cell, listOf(pass(10000) + pass(40000)), gate, listOf(truth(11300), truth(41800)), 1500)
        assertEquals(2, r.trueCount)
        assertEquals(2, r.forwardCount)
        assertEquals(2, r.matched)
        assertEquals(0, r.missed)
        assertEquals(0, r.falseCrossings)
        assertEquals(listOf(200L, -300L), r.rows.map { it.errorMs })
        assertEquals(-50L, r.medianErrorMs)
        assertEquals(250L, r.medianAbsErrorMs)
        assertEquals(300L, r.p95AbsErrorMs)
    }

    @Test
    fun `a crossing outside the half-width is missed, and says so`() {
        val r = analyseCalibration(cell, listOf(pass(10000, northM = 25.0)), gate, listOf(truth(10000)), 0)
        assertEquals(1, r.missed)
        val row = r.rows.single()
        assertEquals(CalibrationOutcome.MISSED, row.outcome)
        assertEquals(CalibrationMissReason.OUTSIDE_HALF_WIDTH, row.missReason)
        assertEquals(25.0, abs(row.offsetM!!), 0.01)
    }

    @Test
    fun `a gap past rejectGapS is missed as gap_rejected, by its span`() {
        val r = analyseCalibration(cell, listOf(listOf(fix(-40.0, 0), fix(40.0, 70000))), gate, listOf(truth(60000)), 0)
        assertEquals(CalibrationMissReason.GAP_REJECTED, r.rows.single().missReason)
    }

    @Test
    fun `no crossing anywhere near is missed as no_crossing`() {
        val r = analyseCalibration(cell, listOf(pass(10000)), gate, listOf(truth(60000)), 0)
        assertEquals(1, r.missed)
        assertEquals("the pass at 07:00:10 matches no true crossing", 1, r.falseCrossings)
        assertEquals(CalibrationMissReason.NO_CROSSING, r.rows.first().missReason)
    }

    @Test
    fun `jitter standing on the line counts false and backward crossings`() {
        val fixes = (0 until 10).map { k -> fix(if (k % 2 == 0) -1.5 else 1.5, k * 1000) }
        val r = analyseCalibration(
            CalibrationCell(CalibrationApproach.STANDING, CalibrationPace.STILL),
            listOf(fixes),
            gate,
            emptyList(),
            0,
        )
        assertEquals(5, r.forwardCount)
        assertEquals(4, r.backwardCount)
        assertEquals(5, r.falseCrossings)
        assertNull(r.medianAbsErrorMs)
    }

    @Test
    fun `a bearing entered the wrong way round reads as backward_only`() {
        val r = analyseCalibration(cell, listOf(pass(10000)), Gate(lat0, lng0, 270.0, 15.0), listOf(truth(10000)), 0)
        assertEquals(CalibrationMissReason.BACKWARD_ONLY, r.rows.single().missReason)
    }

    @Test
    fun `a parallel pass leaves a near miss with its offset, out to three half-widths`() {
        val r = analyseCalibration(
            CalibrationCell(CalibrationApproach.PARALLEL20, CalibrationPace.RUN),
            listOf(pass(10000, northM = 20.0), pass(40000, northM = 40.0), pass(70000, northM = 50.0)),
            gate,
            emptyList(),
            0,
        )
        assertEquals(0, r.falseCrossings)
        assertEquals(2, r.nearMisses)
        assertEquals(listOf(-20, -40), r.rows.map { it.offsetM!!.roundToInt() })
    }

    @Test
    fun `recordings are never paired across`() {
        val a = listOf(fix(-10.0, 0), fix(10.0, 5000))
        val b = listOf(fix(-10.0, 25000), fix(-5.0, 26000))
        assertEquals(0, analyseCalibration(cell, listOf(a, b), gate, listOf(truth(2500)), 0).backwardCount)
        assertEquals(1, analyseCalibration(cell, listOf(a + b), gate, listOf(truth(2500)), 0).backwardCount)
    }

    @Test
    fun `a time-zone slip shows as detections an hour from every truth`() {
        val r = analyseCalibration(cell, listOf(pass(10000)), gate, listOf(truth(10000 + 3600000)), 0)
        assertEquals(0, r.matched)
        assertEquals(-3600000L, r.nearestDiffMs)
    }

    @Test
    fun `one detection pairs with one true crossing, the closer one`() {
        val r = analyseCalibration(cell, listOf(pass(10000)), gate, listOf(truth(13000), truth(10400)), 0)
        assertEquals(CalibrationOutcome.MISSED, r.rows[0].outcome)
        assertEquals(-400L, r.rows[1].errorMs)
    }

    @Test
    fun `median of an even count is the mean of the middle two`() {
        assertEquals(3L, calibrationMedianMs(listOf(4L, 1L, 3L, 2L)))
        assertEquals(3L, calibrationMedianMs(listOf(5L, 1L, 3L)))
        assertNull(calibrationMedianMs(emptyList()))
        assertEquals("half away from zero, as Dart rounds", -3L, calibrationMedianMs(listOf(-2L, -3L)))
        assertEquals(3L, calibrationMedianMs(listOf(2L, 3L)))
    }

    @Test
    fun `the 95th percentile is nearest-rank`() {
        assertEquals(190L, calibrationPercentileMs((1..20).map { it * 10L }, 95.0))
        assertEquals(7L, calibrationPercentileMs(listOf(7L), 95.0))
        assertEquals(114L, calibrationPercentileMs((1..120).map { it.toLong() }, 95.0))
    }

    @Test
    fun `the clock keeps the shortest round trip, at its midpoint`() {
        val c = CalibrationClock()
        c.addSample(t0, t0 + 400, t0 + 1700)
        c.addSample(t0, t0 + 100, t0 + 1550)
        c.addSample(t0, t0 + 300, t0 + 9000)
        c.addSample(t0, t0 + 100, t0 + 9000)
        assertEquals(100L, c.rttMs)
        assertEquals("a tie keeps the earlier", 1500L, c.offsetMs)
    }

    @Test
    fun `the CSV holds error figures and counts, and no coordinate or instant`() {
        val r = analyseCalibration(
            cell = CalibrationCell(CalibrationApproach.DEG90, CalibrationPace.RUN),
            recordings = listOf(pass(10000) + pass(40000, northM = 25.0)),
            gate = gate,
            trueCrossingsMs = listOf(truth(10250), truth(40000)),
            clockOffsetMs = 0,
            offsetRttMs = 7,
        )
        val csv = calibrationCsv(listOf(r))
        val lines = csv.trim().split('\n')
        assertEquals(
            "the phone's header, byte for byte",
            "kind,approach,pace,carry,crossing,outcome,error_ms,offset_m,gapped,miss_reason," +
                "true_count,forward_detected,backward_detected,matched,missed,false,near_miss," +
                "median_error_ms,median_abs_error_ms,p95_abs_error_ms,offset_rtt_ms",
            lines.first(),
        )
        assertEquals("two crossings and a summary", 4, lines.size)
        assertTrue(lines[1], lines[1].startsWith("crossing,90,run,wear_wrist,1,matched,-250,"))
        assertTrue(lines[2], lines[2].contains("missed,,-25.0,0,outside_half_width"))
        assertEquals("summary,90,run,wear_wrist,,,,,,,2,1,1,1,1,0,0,-250,250,250,7", lines[3])
        for (leak in listOf("47.12", "8.65", "2026", "07:00", "lat", "lng")) {
            assertFalse("$leak left the device", csv.contains(leak))
        }
        for (line in lines) assertEquals(CALIBRATION_CSV_COLUMNS.size, line.split(',').size)
        assertTrue("one line per row, newline-terminated", csv.endsWith("\n"))
    }

    @Test
    fun `offsets are written as Dart's toStringAsFixed(1) writes them`() {
        assertEquals("-25.0", fixed1(-25.0000001))
        assertEquals("0.3", fixed1(0.25))
        assertEquals("-0.3", fixed1(-0.25))
        assertEquals("-0.0", fixed1(-0.04))
        assertEquals("12.3", fixed1(12.34))
        assertEquals(3L, roundHalfAway(2.5))
        assertEquals(-3L, roundHalfAway(-2.5))
    }

    private fun at(ms: Long) = GateFix(lat0, lng0, ms.toDouble(), 10.0)

    @Test
    fun `the capture takes each fix once, by the race feed's rule`() {
        val c = LineCalibrationCapture().apply { start() }
        c.offer("run-1", recording = true, fixKey = 1, fix = at(t0 + 1250))
        c.offer("run-1", recording = true, fixKey = 1, fix = at(t0 + 1250))
        assertEquals("a re-emitted fix is not a second fix", 1, c.fixCount)
        assertEquals((t0 + 1250).toDouble(), c.recordings.single().single().tMs, 0.0)
        c.offer("run-1", recording = false, fixKey = 2, fix = at(t0 + 2250))
        assertEquals("a paused watch is not racing", 1, c.fixCount)
        c.offer("run-1", recording = true, fixKey = 3, fix = GateFix(Double.NaN, lng0, (t0 + 3000).toDouble(), 1.0))
        assertEquals(1, c.fixCount)
        c.offer(null, recording = true, fixKey = 4, fix = at(t0 + 4000))
        assertEquals(1, c.fixCount)
        assertEquals((t0 + 1250).toDouble(), c.firstFixMs!!, 0.0)
    }

    @Test
    fun `each recording is its own series`() {
        val c = LineCalibrationCapture().apply { start() }
        for ((i, id) in listOf("a", "a", "a", "b", "b").withIndex()) {
            c.offer(id, recording = true, fixKey = i.toLong() % 3, fix = at(t0 + i * 1000L))
        }
        assertEquals(listOf(3, 2), c.recordings.map { it.size })
    }

    @Test
    fun `the capture takes nothing until started, nothing after stop, and holds a bounded count`() {
        val c = LineCalibrationCapture(maxFixes = 2)
        c.offer("a", true, 1, at(t0))
        assertEquals(0, c.fixCount)
        c.start()
        assertTrue(c.active)
        for (k in 1..4) c.offer("a", true, k.toLong(), at(t0 + k))
        assertEquals(2, c.fixCount)
        c.stop()
        assertFalse(c.active)
        c.offer("a", true, 9, at(t0 + 9))
        assertEquals(2, c.fixCount)
        c.clear()
        assertEquals(0, c.fixCount)
        assertNull(c.firstFixMs)
    }

    @Test
    fun `typed instants read as times of day on the capture day, or ISO instants`() {
        val zone = ZoneId.of("Europe/Zurich")
        val day = LocalDate.of(2026, 11, 10)
        val got = parseCalibrationInstants("07:42:13.48\n\n07:43:01, 2026-11-10T12:00:00.250Z", day, zone)!!
        fun local(h: Int, m: Int, s: Int, ms: Int) =
            LocalDateTime.of(2026, 11, 10, h, m, s, ms * 1_000_000).atZone(zone).toInstant().toEpochMilli().toDouble()
        assertEquals(local(7, 42, 13, 480), got[0], 0.0)
        assertEquals(local(7, 43, 1, 0), got[1], 0.0)
        assertEquals(
            ZonedDateTime.of(2026, 11, 10, 12, 0, 0, 250_000_000, ZoneId.of("UTC")).toInstant().toEpochMilli().toDouble(),
            got[2],
            0.0,
        )
        assertEquals(
            "an ISO instant with no zone is read in the device's",
            local(7, 42, 13, 0),
            parseCalibrationInstants("2026-11-10T07:42:13", day, zone)!!.single(),
            0.0,
        )
        assertEquals(0.123, parseCalibrationInstants("00:00:00.000123", day, ZoneId.of("UTC"))!!.single() -
            ZonedDateTime.of(2026, 11, 10, 0, 0, 0, 0, ZoneId.of("UTC")).toInstant().toEpochMilli(), 1e-9)
    }

    @Test
    fun `an entry that is not an instant refuses the lot`() {
        val zone = ZoneId.of("UTC")
        val day = LocalDate.of(2026, 11, 10)
        assertNull(parseCalibrationInstants("07:42:13\nlater", day, zone))
        assertNull(parseCalibrationInstants("25:00:00", day, zone))
        assertEquals(emptyList<Double>(), parseCalibrationInstants("", day, zone))
    }

    @Test
    fun `server_now answers with a JSON string instant`() {
        assertEquals(t0 + 1512, RaceSessionClient.parseServerNowMs("\"2026-11-10T07:00:01.512345+00:00\""))
        assertNull(RaceSessionClient.parseServerNowMs("{}"))
        assertNull(RaceSessionClient.parseServerNowMs("not json"))
        assertNull(RaceSessionClient.parseServerNowMs("\"yesterday\""))
    }

    @Test
    fun `the export is written to the app's private files only`() {
        val dir = Files.createTempDirectory("line-calibration").toFile()
        try {
            val f = writeCalibrationCsv(dir, "kind\n")
            assertEquals(File(dir, "line_calibration.csv"), f)
            assertEquals("kind\n", f.readText())
        } finally {
            dir.deleteRecursively()
        }
    }

    @Test
    fun `nothing reaches the tool outside a BuildConfig DEBUG branch`() {
        // A release build sets BuildConfig.DEBUG false, so a reference inside
        // `if (BuildConfig.DEBUG ...)` is never reached there. Any other
        // reference would ship the tool.
        val own = setOf("LineCalibration.kt", "LineCalibrationScreen.kt")
        val refs = ArrayList<String>()
        for (f in KotlinSources.mainSources()) {
            if (f.name in own) continue
            val lines = KotlinSources.codeView(f.readText()).lines()
            for ((i, l) in lines.withIndex()) {
                if (!l.contains("LineCalibration") || l.trimStart().startsWith("import ")) continue
                refs.add("${f.name}:${i + 1}")
                val window = lines.subList(maxOf(0, i - 3), i + 1).joinToString("\n")
                assertTrue(
                    "${f.name}:${i + 1} reaches the calibration tool outside a BuildConfig.DEBUG branch",
                    window.contains("if (BuildConfig.DEBUG"),
                )
            }
        }
        assertTrue("the capture feed and the screen's entry exist", refs.size >= 2)
        val ui = File(KotlinSources.mainRoot(), "com/runapp/watchwear/ui/RunWatchApp.kt").readText()
        assertTrue(
            "the pre-run entry is handed only in a debug build",
            Regex("""onOpenCalibration = if \(BuildConfig\.DEBUG\)""").containsMatchIn(ui),
        )
        val gradle = WearLocales.findUp("apps/watch_wear/android/app/build.gradle.kts")
        assertNotNull(gradle)
        assertTrue("BuildConfig is generated", gradle!!.readText().contains("buildConfig = true"))
    }
}
