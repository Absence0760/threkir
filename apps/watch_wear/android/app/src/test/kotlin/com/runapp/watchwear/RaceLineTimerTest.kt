package com.runapp.watchwear

import java.time.Instant
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.longOrNull
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.PI
import kotlin.math.cos

/// Timing a race by its lines on the wrist (#1307), the same cases the
/// phone's `race_controller_test.dart` group "timing by the lines" pins:
/// the detector running from the recording's Start with a crossing before
/// GO resolved at GO, a gate finish, a parallel pass, a Stop in the circle,
/// a self-crossing course, the undo, the start cue and the distance to the
/// start line, and the crossings filed on the server clock.
class RaceLineTimerTest {

    // A straight course run due east along latitude 51.5: the start line at
    // x = 0, the finish line 5 km on, both facing east, 15 m each side.
    private val lat0 = 51.5
    private val lng0 = -0.1
    private val mPerDegLat = RaceFinish.EARTH_RADIUS_M * PI / 180.0
    private val mPerDegLng = mPerDegLat * cos(lat0 * PI / 180.0)
    private fun lngAt(eastM: Double) = lng0 + eastM / mPerDegLng

    private val startLine = Gate(lat0, lngAt(0.0), 90.0, 15.0)
    private val finishLine = Gate(lat0, lngAt(5000.0), 90.0, 15.0)
    private fun lined(selfCross: Boolean = false) = RaceSessionClient.RaceCourse(
        id = "course-5k",
        name = "5K",
        distanceM = 5000.0,
        finishLat = lat0,
        finishLng = lngAt(5000.0),
        startGate = startLine,
        finishGate = finishLine,
        finishLineSelfCross = selfCross,
    )

    private val go = 1_779_472_800_000L
    private val began = go - 120_000L
    private fun at(s: Int) = go + s * 1000L

    private val armed = RaceTarget("e1", "i1", selfTimed = false, goServerMs = null)
    private val live = armed.copy(goServerMs = go)

    private fun race(course: RaceSessionClient.RaceCourse = lined()) = ActiveRaceState(
        eventId = "e1",
        instanceStart = "i1",
        status = "running",
        startedAtMs = go,
        eventTitle = "Park 5K",
        course = course,
    )

    /// A fix [eastM] along the course and [northM] off it, having covered
    /// [coveredM] since the Start press, at device time GO + [s] + [shiftMs].
    private fun RaceLineTimer.fix(
        eastM: Double,
        s: Int,
        coveredM: Double,
        northM: Double = 0.0,
        shiftMs: Long = 0L,
    ): RaceFinish.Finish? = offer(RaceFinish.Fix(lat0 + northM / mPerDegLat, lngAt(eastM), at(s) + shiftMs, coveredM))

    /// Run from [fromM] to [toM] along the course, one fix every 2 s at 5 m/s
    /// from GO + [fromS]. Returns the first finish.
    private fun RaceLineTimer.runTo(
        toM: Double,
        fromM: Double = -30.0,
        fromS: Int = 0,
        northM: Double = 0.0,
        shiftMs: Long = 0L,
    ): RaceFinish.Finish? {
        var got: RaceFinish.Finish? = null
        var s = fromS
        var x = fromM
        while (x <= toM) {
            val f = fix(x, s, x + 30.0, northM, shiftMs)
            if (got == null) got = f
            x += 10.0
            s += 2
        }
        return got
    }

    /// A runner who started recording 30 m behind the line two minutes
    /// before GO, on a race still armed, with its course known.
    private fun armedTimer(course: RaceSessionClient.RaceCourse = lined()): RaceLineTimer =
        RaceLineTimer().apply {
            beginRecording()
            assertNull(update(armed, course, null))
        }

    private fun goAndBind(t: RaceLineTimer, course: RaceSessionClient.RaceCourse = lined(), offset: Long? = null) =
        t.update(live, course, offset).also { t.bind() }

    private fun result(
        t: RaceLineTimer,
        decision: RaceStopDecision,
        runId: String? = "run-1",
        offset: Long? = null,
        course: RaceSessionClient.RaceCourse = lined(),
    ) = buildRaceResult(
        race = race(course),
        decision = decision,
        userId = "u1",
        runId = runId,
        runStartedAtMs = began,
        elapsedS = 1_100,
        serverOffsetMs = offset,
        start = t.start,
    )

    private fun auto(f: RaceFinish.Finish) =
        RaceStopDecision(RaceFinish.Outcome.AUTO_FINISH, f.epochMs, f.coveredM, f)

    private fun iso(ms: Long) = Instant.ofEpochMilli(ms).toString()

    @Test
    fun `a crossing before the watch hears GO is kept and resolved at GO`() {
        val t = armedTimer()
        var cues = 0
        t.onStartLineCrossed = { cues++ }
        // GO went at +0; the runner crossed at +6 s and was 70 m on before the
        // watch's poll said so.
        t.runTo(70.0)
        assertFalse("a gun race waits for GO", t.detecting)
        assertEquals(0, cues)

        assertNull(goAndBind(t))
        assertTrue(t.detecting)
        assertEquals("the start is cued once it commits", 1, cues)

        val fin = t.runTo(5020.0, fromM = 80.0, fromS = 22)
        assertNotNull(fin)
        assertEquals(RaceFinish.FinishDetection.GATE, fin!!.detection)
        assertEquals(RaceFinish.StartKind.LINE, fin.start?.kind)
        assertEquals(at(6), fin.start!!.epochMs)
        assertEquals("the finish waits for the ViewModel once", fin, t.takePendingFinish())
        assertNull(t.takePendingFinish())

        val r = result(t, auto(fin))
        assertEquals("auto", r.finishMethod)
        assertEquals("gate", r.startDetection)
        assertEquals("gate", r.finishDetection)
        assertEquals(iso(at(6)), r.startAt)
        assertEquals(iso(fin.epochMs), r.finishAt)
        assertEquals("chip time runs from the start-line crossing", ((fin.epochMs - at(6)) / 1000).toInt(), r.chipTimeS)
        assertEquals(((fin.epochMs - go) / 1000).toInt(), r.gunTimeS)
        assertNull("no offset sample was taken", r.clockOffsetMs)
    }

    @Test
    fun `the crossings are filed on the server clock with the offset used`() {
        val t = armedTimer()
        // The device clock reads 2 s behind the server: device GO is GO - 2 s.
        goAndBind(t, offset = 2_000L)
        val fin = t.runTo(5020.0, shiftMs = -2_000L)!!
        val r = result(t, auto(fin), offset = 2_000L)
        assertEquals(2_000L, r.clockOffsetMs)
        assertEquals(iso(fin.epochMs + 2_000L), r.finishAt)
        assertEquals(iso(at(6)), r.startAt)
        val body = RaceSessionClient.resultBody(r)
        assertEquals(2_000L, body["clock_offset_ms"]!!.jsonPrimitive.longOrNull)
        assertEquals("gate", body["finish_detection"]!!.jsonPrimitive.contentOrNull)
    }

    @Test
    fun `a parallel pass 20 m from the finish line does not finish`() {
        val t = armedTimer()
        goAndBind(t)
        assertNull(t.runTo(4900.0))
        assertNull(t.runTo(5100.0, fromM = 4910.0, fromS = 2000, northM = 20.0))
        assertNull(t.finish)
        assertNull(t.takePendingFinish())
    }

    @Test
    fun `a Stop inside the finish circle files a zone finish`() {
        val t = armedTimer()
        goAndBind(t)
        assertNull(t.runTo(4990.0))
        val decision = raceFinishDecision(t.settle(), 5020.0, 5000.0, at(1500))
        assertEquals(RaceFinish.Outcome.AUTO_FINISH, decision.outcome)
        val r = result(t, decision)
        assertEquals("zone", r.finishDetection)
        assertEquals("gate", r.startDetection)
    }

    @Test
    fun `a course that crosses its own finish line finishes by hand only`() {
        val course = lined(selfCross = true)
        val t = armedTimer(course)
        goAndBind(t, course)
        assertFalse(t.detecting)
        assertNull(t.runTo(5100.0))
        assertNull(t.takePendingFinish())
        val decision = raceFinishDecision(t.settle(), 5130.0, 5000.0, at(1500))
        assertEquals(RaceFinish.Outcome.MANUAL_FINISH, decision.outcome)
        val r = result(t, decision, course = course)
        assertNull(r.finishDetection)
        assertEquals("no detector, so the start is the Start press", "device", r.startDetection)
        assertEquals(iso(began), r.startAt)
    }

    @Test
    fun `a runner already past the start line at GO starts at GO, uncued`() {
        val t = armedTimer()
        var cues = 0
        t.onStartLineCrossed = { cues++ }
        t.fix(5.0, -4, 35.0)
        t.fix(6.0, -2, 36.0)
        goAndBind(t)
        val fin = t.runTo(5020.0, fromM = 10.0, fromS = 2)!!
        assertEquals(RaceFinish.StartKind.GO, fin.start?.kind)
        assertEquals("nobody crossed the line", 0, cues)
        val r = result(t, auto(fin))
        assertEquals("gate", r.startDetection)
        assertEquals(iso(go), r.startAt)
        assertEquals("a runner whose start is GO has chip time = gun time", r.gunTimeS, r.chipTimeS)
    }

    @Test
    fun `a start at GO is GO itself under the offset at filing`() {
        val t = armedTimer()
        t.fix(5.0, -4, 35.0, shiftMs = -400L)
        goAndBind(t, offset = 400L)
        val fin = t.runTo(5020.0, fromM = 10.0, fromS = 2, shiftMs = -400L)!!
        assertEquals(RaceFinish.StartKind.GO, fin.start?.kind)
        // A faster round trip refined the offset after GO was resolved.
        val r = result(t, auto(fin), offset = 455L)
        assertEquals(iso(go), r.startAt)
        assertEquals(r.gunTimeS, r.chipTimeS)
    }

    @Test
    fun `a throwing start cue costs the cue, not the timing`() {
        val t = armedTimer()
        val failures = mutableListOf<String>()
        t.onStartLineCrossed = { error("tts gone") }
        t.onFailure = { what, _ -> failures += what }
        goAndBind(t)
        val fin = t.runTo(5020.0)
        assertNotNull(fin)
        assertEquals(1, failures.size)
    }

    @Test
    fun `the distance to the start line shows until the start commits`() {
        val t = armedTimer()
        t.fix(-30.0, -10, 0.0)
        assertEquals(30.0, t.distanceToStartM!!, 0.5)
        goAndBind(t)
        t.runTo(100.0)
        assertNull(t.distanceToStartM)
    }

    @Test
    fun `no distance to the start line without a race or a line`() {
        val t = RaceLineTimer().apply { beginRecording() }
        t.fix(-30.0, -10, 0.0)
        assertNull("an ordinary run has no start line", t.distanceToStartM)
        t.update(armed, lined().copy(startGate = null), null)
        t.fix(-20.0, -8, 10.0)
        assertNull(t.distanceToStartM)
    }

    @Test
    fun `Not finished - Resume voids the finish and the rest finishes by hand from the line`() {
        val t = armedTimer()
        goAndBind(t)
        val fin = t.runTo(5020.0)!!
        assertEquals(RaceFinish.FinishDetection.GATE, fin.detection)

        assertTrue(t.voidAutoFinish())
        assertNull(t.finish)
        assertFalse(t.detecting)
        assertNull(t.takePendingFinish())
        assertNull(
            "after an undo the recording finishes by hand",
            t.runTo(5300.0, fromM = 5030.0, fromS = 1100),
        )
        assertNull(t.update(live, lined(), null))

        val decision = raceFinishDecision(t.settle(), 5330.0, 5000.0, at(1300))
        assertEquals(RaceFinish.Outcome.MANUAL_FINISH, decision.outcome)
        val r = result(t, decision)
        assertEquals("manual", r.finishMethod)
        assertNull(r.finishDetection)
        assertEquals("the hand finish is still timed from the start line", "gate", r.startDetection)
        assertEquals(iso(at(6)), r.startAt)
        assertEquals(1300 - 6, r.chipTimeS)
        assertFalse("nothing to void twice", t.voidAutoFinish())
    }

    @Test
    fun `a course that arrives after the finish line is replayed to the finish`() {
        val t = RaceLineTimer().apply { beginRecording() }
        assertNull(t.update(live, null, null))
        t.bind()
        assertNull(t.runTo(5020.0))
        val fin = t.update(live, lined(), null)
        assertNotNull("no signal at the line, the course read later times it", fin)
        assertEquals(RaceFinish.FinishDetection.GATE, fin!!.detection)
        assertEquals(fin, t.takePendingFinish())
    }

    @Test
    fun `a self-timed attempt times from the start-line crossing`() {
        val t = RaceLineTimer().apply { beginRecording() }
        t.update(RaceTarget("tt", "i1", selfTimed = true, goServerMs = null), lined(), null)
        t.bind()
        assertTrue("a self-timed attempt detects at once", t.detecting)
        val fin = t.runTo(5020.0)!!
        assertEquals(RaceFinish.FinishDetection.GATE, fin.detection)
        assertEquals(RaceFinish.StartKind.LINE, fin.start?.kind)
    }

    @Test
    fun `a course with no lines keeps v1 and sees only fixes from GO`() {
        val v1 = RaceSessionClient.RaceCourse("c1", "5K", 5000.0, lat0, lngAt(5000.0))
        val t = RaceLineTimer().apply { beginRecording() }
        t.update(armed, v1, null)
        // A warm-up lap that passes the finish point before GO, 90 % covered.
        t.fix(4995.0, -60, 4600.0)
        t.fix(5000.0, -58, 4605.0)
        t.fix(5005.0, -56, 4610.0)
        t.fix(5100.0, -40, 4700.0)
        assertNull(goAndBind(t, v1))
        assertNull(t.finish)
    }

    @Test
    fun `a new recording forgets the last one`() {
        val t = armedTimer()
        goAndBind(t)
        t.runTo(5020.0)
        t.beginRecording()
        assertNull(t.finish)
        assertFalse(t.detecting)
        assertNull(t.start)
        t.endRecording()
        assertFalse(t.recording)
        assertNull(t.fix(0.0, 0, 0.0))
    }

    @Test
    fun `the watch follows the bound race, else the armed or live one while recording`() {
        val active = race().copy(status = "armed")
        assertNull(raceTargetFor(null, active, recording = false))
        val armedT = raceTargetFor(null, active, recording = true)!!
        assertNull("GO is not known while the race is armed", armedT.goServerMs)
        assertEquals(go, raceTargetFor(null, race(), recording = true)!!.goServerMs)
        assertEquals(go, raceTargetFor(race(), null, recording = false)!!.goServerMs)

        val selfTimed = race().copy(startMode = "self_timed", startInstantMs = go - 3_600_000L)
        assertNull("a self-timed race waits for the attempt", raceTargetFor(null, selfTimed, recording = true))
        val attempt = raceTargetFor(null, selfTimed.copy(attemptArmed = true), recording = true)!!
        assertTrue(attempt.selfTimed)
        assertNull(attempt.goServerMs)
        assertNull(raceTargetFor(null, race().copy(status = "finished"), recording = true))
    }

    @Test
    fun `a ping carries the seconds since the committed start, and none before one`() {
        val t = armedTimer()
        assertNull("no start yet", raceSinceStartLineS(t.start, at(30)))
        goAndBind(t)
        t.runTo(100.0)
        assertEquals(RaceFinish.StartKind.LINE, t.start?.kind)
        assertEquals(24, raceSinceStartLineS(t.start, at(30) + 400L))
        assertEquals("a device clock that stepped back reads as the start", 0, raceSinceStartLineS(t.start, at(0)))
        assertNull(
            "past what the column holds",
            raceSinceStartLineS(t.start, at(6) + (RACE_PING_SINCE_START_MAX_S + 1) * 1000L),
        )
    }

    // ───────────── the crossing columns ─────────────

    @Test
    fun `a result with no crossings still clears them, and leaves the offset alone`() {
        val r = PendingRaceResult("u1", "e1", "i1", "run1", 900, 4000.0, "dnf")
        val body = RaceSessionClient.resultBody(r)
        for (k in listOf("start_at", "finish_at", "start_detection", "finish_detection")) {
            assertTrue("$k must be sent so an earlier phone row's crossings go", body.containsKey(k))
            assertEquals(JsonNull, body[k])
        }
        assertFalse("the offset is a device fact, never cleared", body.containsKey("clock_offset_ms"))
    }

    @Test
    fun `a DNF files no crossing, and a line finish files without its run`() {
        val t = armedTimer()
        goAndBind(t)
        t.runTo(1000.0)
        val dnf = result(t, RaceStopDecision(RaceFinish.Outcome.DNF, null, 1030.0), offset = 300L)
        assertNull(dnf.startAt)
        assertNull(dnf.finishAt)
        assertNull(dnf.startDetection)
        assertNull(dnf.finishDetection)

        val fin = t.runTo(5020.0, fromM = 1010.0, fromS = 210)!!
        val atLine = result(t, auto(fin), runId = null)
        assertFalse(
            "the run row does not exist until Stop saves it",
            RaceSessionClient.resultBody(atLine).containsKey("run_id"),
        )
        val linked = result(t, auto(fin), runId = "run-1")
        assertEquals("the same finish, not a new time", atLine.copy(runId = "run-1"), linked)
    }

    @Test
    fun `the detection unions match event_results' CHECKs`() {
        assertEquals(listOf("gate", "device"), RaceStartDetection.values().map { it.wire })
        assertEquals(listOf("zone", "gate"), RaceFinish.FinishDetection.values().map { it.wire })
    }
}
