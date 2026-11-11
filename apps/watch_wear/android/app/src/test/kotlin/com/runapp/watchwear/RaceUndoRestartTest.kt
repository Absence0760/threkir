package com.runapp.watchwear

import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import java.io.File
import java.nio.file.Files
import java.time.Instant
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos

/// "Not finished? Resume" and then a restart of the app mid-recording (#1307
/// m11, owner's choice for a restart): the finish taken back is never found or
/// filed again, the start it was measured from is kept, and the finish line is
/// armed again for a later crossing. Wear's timer does not replay the track
/// recorded before a restart, so without the kept undo a restarted recording
/// starts afresh at its next fix; the last case pins what that cost.
class RaceUndoRestartTest {

    private val lat0 = 51.5
    private val lng0 = -0.1
    private val mPerDegLat = RaceFinish.EARTH_RADIUS_M * PI / 180.0
    private val mPerDegLng = mPerDegLat * cos(lat0 * PI / 180.0)
    private fun lngAt(eastM: Double) = lng0 + eastM / mPerDegLng

    private fun lined(selfCross: Boolean = false) = RaceSessionClient.RaceCourse(
        id = "course-5k",
        name = "5K",
        distanceM = 5000.0,
        finishLat = lat0,
        finishLng = lngAt(5000.0),
        startGate = Gate(lat0, lngAt(0.0), 90.0, 15.0),
        finishGate = Gate(lat0, lngAt(5000.0), 90.0, 15.0),
        finishLineSelfCross = selfCross,
    )

    private val go = 1_779_472_800_000L
    private fun at(s: Int) = go + s * 1000L

    private val live = RaceTarget("e1", "i1", selfTimed = false, goServerMs = go)

    private fun race(startMode: String = "scheduled") = ActiveRaceState(
        eventId = "e1",
        instanceStart = "i1",
        status = "running",
        startedAtMs = null,
        eventTitle = "Park 5K",
        course = lined(),
        startMode = startMode,
        startInstantMs = System.currentTimeMillis() - 60_000L,
        windowClosesAtMs = System.currentTimeMillis() + 3_600_000L,
    )

    private fun RaceLineTimer.fix(eastM: Double, s: Int, coveredM: Double): RaceFinish.Finish? =
        offer(RaceFinish.Fix(lat0, lngAt(eastM), at(s), coveredM))

    /// Along [xs], one fix every 2 s from GO + [fromS], the covered distance
    /// growing from [coveredFrom] by each step. Returns the first finish.
    private fun RaceLineTimer.path(xs: List<Double>, fromS: Int, coveredFrom: Double): RaceFinish.Finish? {
        var got: RaceFinish.Finish? = null
        var covered = coveredFrom
        var prev: Double? = null
        for ((i, x) in xs.withIndex()) {
            prev?.let { covered += abs(x - it) }
            prev = x
            val f = fix(x, fromS + 2 * i, covered)
            if (got == null) got = f
        }
        return got
    }

    private fun steps(from: Int, to: Int) =
        (if (from <= to) (from..to) else (from downTo to)).map { it * 10.0 }

    /// From 30 m behind the start line to 5020 m, crossing the finish line at
    /// GO + 1006 s from a start-line crossing at GO + 6 s.
    private val toTheLine = steps(-3, 502)

    /// On past the line, back over it the wrong way, and over it again.
    private val onAndBack = steps(503, 530) + steps(529, 495) + steps(496, 505)
    private val laterCrossingS = 1100 + 2 * onAndBack.lastIndexOf(5000.0)

    private class Undone(val entry: UndoneRaceFinish, val finish: RaceFinish.Finish)

    /// The session before the restart: a line finish, taken back.
    private fun raceAndUndo(): Undone {
        val t = RaceLineTimer().apply {
            beginRecording()
            update(live, lined(), null)
            bind()
        }
        val fin = t.path(toTheLine, 0, 0.0)!!
        assertEquals(RaceFinish.FinishDetection.GATE, fin.detection)
        assertEquals(at(1006), fin.epochMs)
        assertTrue(t.voidAutoFinish())
        val entry = undoneRaceFinishEntry(race(), "run-1", fin.epochMs, t.start)!!
        return Undone(entry, fin)
    }

    private fun restarted(u: Undone, course: RaceSessionClient.RaceCourse = lined()): RaceLineTimer =
        RaceLineTimer().apply {
            beginRecording()
            restoreUndone("${u.entry.eventId}|${u.entry.instanceStart}", u.entry.start?.toStart(), u.entry.undoneFinishMs)
            update(live, course, null)
            bind()
        }

    @Test
    fun `the undo keeps its race, recording, finish instant and line start`() {
        val u = raceAndUndo()
        assertEquals("run-1", u.entry.runId)
        assertEquals("e1", u.entry.eventId)
        assertEquals(at(1006), u.entry.undoneFinishMs)
        val start = u.entry.start!!.toStart()!!
        assertEquals(RaceFinish.StartKind.LINE, start.kind)
        assertEquals(at(6), start.epochMs)
        assertEquals(u.finish.start, start)
    }

    @Test
    fun `after a restart the start stands and only a later crossing finishes`() {
        val u = raceAndUndo()
        val t = restarted(u)
        assertEquals("the line start survives the restart", u.finish.start, t.start)
        assertTrue(t.detecting)
        assertNull("no distance to a start line already crossed", t.distanceToStartM)

        val f = t.path(onAndBack, 1100, 5050.0)
        assertNotNull("the finish line is armed again", f)
        f!!
        assertEquals(RaceFinish.FinishDetection.GATE, f.detection)
        assertEquals(at(laterCrossingS), f.epochMs)
        assertTrue(f.epochMs > u.entry.undoneFinishMs)
        assertEquals(u.finish.start, f.start)
        assertEquals(f, t.takePendingFinish())

        val r = buildRaceResult(
            race = race(),
            decision = RaceStopDecision(RaceFinish.Outcome.AUTO_FINISH, f.epochMs, f.coveredM, f),
            userId = "u1",
            runId = null,
            runStartedAtMs = go - 120_000L,
            elapsedS = 1_400,
            serverOffsetMs = null,
            start = t.start,
        )
        assertEquals("gate", r.startDetection)
        assertEquals(Instant.ofEpochMilli(at(6)).toString(), r.startAt)
        assertEquals(laterCrossingS - 6, r.chipTimeS)
    }

    @Test
    fun `a re-armed line needs 90 percent of the course from the kept start`() {
        val start = RaceFinish.Start(at(6), 30.0, RaceFinish.StartKind.LINE)
        fun crossing(tMs: Long, coveredM: Double, dir: GateDirection = GateDirection.FORWARD) =
            GateCrossing(dir, 0.5, tMs.toDouble(), coveredM, 2.0, gapped = false)
        val undone = at(1006)
        assertNull("60 % from the start is not enough", rearmedLineFinish(crossing(at(2000), 30.0 + 3_500.0), start, undone, 5000.0))
        assertNull(rearmedLineFinish(crossing(at(2000), 30.0 + 4_499.0), start, undone, 5000.0))
        val f = rearmedLineFinish(crossing(at(2000), 30.0 + 4_500.0), start, undone, 5000.0)!!
        assertEquals(at(2000), f.epochMs)
        assertEquals(2.0, f.distanceToFinishM, 0.0)
        assertEquals(start, f.start)
        assertEquals(RaceFinish.FinishDetection.GATE, f.detection)
        assertNull("the instant taken back", rearmedLineFinish(crossing(undone, 6_000.0), start, undone, 5000.0))
        assertNull(rearmedLineFinish(crossing(at(2000), 6_000.0, GateDirection.BACKWARD), start, undone, 5000.0))
        assertNull(rearmedLineFinish(crossing(at(2000), 6_000.0), start, undone, null))
        assertNotNull("from the Start press without a start", rearmedLineFinish(crossing(at(2000), 4_500.0), null, undone, 5000.0))
    }

    @Test
    fun `a poll with no recording bound forgets an undo whose race it no longer finds`() {
        val u = raceAndUndo().entry
        assertTrue(undoneFinishOutlivesPoll(u, race()))
        assertFalse(undoneFinishOutlivesPoll(u, race().copy(eventId = "e2")))
        assertFalse(undoneFinishOutlivesPoll(u, null))
        assertFalse(undoneFinishOutlivesPoll(null, race()))
    }

    @Test
    fun `the crossing taken back is not found again, replayed or live`() {
        val u = raceAndUndo()
        val replayed = RaceLineTimer().apply {
            beginRecording()
            restoreUndone("e1|i1", u.entry.start?.toStart(), u.entry.undoneFinishMs)
        }
        // The fixes around the crossing taken back reach the restarted timer
        // before its race does, and are replayed when it arrives.
        assertNull(replayed.path(steps(495, 505), 996, 5020.0))
        assertNull(replayed.update(live, lined(), null))
        replayed.bind()
        assertNull(replayed.takePendingFinish())
        assertNotNull("a later crossing still finishes", replayed.path(onAndBack, 1100, 5100.0))

        val liveFeed = restarted(u)
        assertNull(liveFeed.path(steps(495, 505), 996, 5020.0))
        assertNull(liveFeed.takePendingFinish())
    }

    @Test
    fun `a second undo after a restart keeps the same start and stops detecting`() {
        val u = raceAndUndo()
        val t = restarted(u)
        val f = t.path(onAndBack, 1100, 5050.0)!!
        assertTrue(t.voidAutoFinish())
        assertFalse(t.detecting)
        assertEquals(u.finish.start, t.start)
        val again = undoneRaceFinishEntry(race(), "run-1", f.epochMs, t.start)!!
        assertEquals(at(laterCrossingS), again.undoneFinishMs)
        assertEquals(u.entry.start, again.start)
        assertNull(t.path(steps(495, 520), 1400, 6000.0))
    }

    @Test
    fun `a course finished by hand only is not armed again, and keeps its start`() {
        val u = raceAndUndo()
        val t = restarted(u, lined(selfCross = true))
        assertFalse(t.detecting)
        assertNull(t.path(onAndBack, 1100, 5050.0))
        assertEquals(u.finish.start, t.start)
    }

    @Test
    fun `another race's undo is not applied`() {
        val u = raceAndUndo()
        val t = RaceLineTimer().apply {
            beginRecording()
            restoreUndone("e2|i9", u.entry.start?.toStart(), u.entry.undoneFinishMs)
            update(live, lined(), null)
            bind()
        }
        assertEquals(
            "timed afresh: past the start line at its first fix, its start is GO",
            RaceFinish.StartKind.GO,
            run {
                t.path(steps(503, 505), 1100, 5050.0)
                t.start?.kind
            },
        )
    }

    @Test
    fun `without the kept undo a restarted recording lost its line start`() {
        val t = RaceLineTimer().apply {
            beginRecording()
            update(live, lined(), null)
            bind()
        }
        assertNull(t.path(onAndBack, 1100, 5050.0))
        assertEquals(RaceFinish.StartKind.GO, t.start?.kind)
    }

    @Test
    fun `the undo is matched to its recording, and a self-timed attempt is armed again`() {
        val u = raceAndUndo()
        assertEquals(u.entry, undoneFinishFor(u.entry, "run-1"))
        assertNull(undoneFinishFor(u.entry, "run-2"))
        assertNull(undoneFinishFor(u.entry, null))
        assertNull(undoneFinishFor(null, "run-1"))

        val selfTimed = race("self_timed")
        assertFalse(selfTimed.attemptArmed)
        val undone = u.entry
        assertTrue(raceToRebindAfterUndo(selfTimed, undone)!!.attemptArmed)
        assertEquals(selfTimed, raceToRebindAfterUndo(selfTimed, null))
        val other = selfTimed.copy(eventId = "e2")
        assertEquals("another race binds as it would", other, raceToRebindAfterUndo(other, undone))
        val scheduled = race()
        assertEquals(scheduled, raceToRebindAfterUndo(scheduled, undone))
        assertNull(raceToRebindAfterUndo(null, undone))
        assertNotNull(
            raceToBind(alreadyBound = false, runId = "run-1", endedRunId = null, active = raceToRebindAfterUndo(selfTimed, undone)),
        )
        assertNull(raceToBind(alreadyBound = false, runId = "run-1", endedRunId = null, active = selfTimed))
    }

    @Test
    fun `nothing is kept without a race, recording or finish, and an unknown start kind is the Start press`() {
        val s = RaceFinish.Start(at(6), 30.0, RaceFinish.StartKind.GO, gapped = true)
        assertEquals(s, keptRaceStart(s).toStart())
        assertNull(KeptRaceStart(at(6), 30.0, "SOMETHING_NEW").toStart())
        assertNull(undoneRaceFinishEntry(null, "run-1", at(1), s))
        assertNull(undoneRaceFinishEntry(race(), null, at(1), s))
        assertNull(undoneRaceFinishEntry(race(), "run-1", null, s))
        assertNull(undoneRaceFinishEntry(race(), "run-1", at(1), null)!!.start)
    }

    @Test
    fun `the undo survives a restart of the store and sign-out forgets it`() = runBlocking {
        val dir = Files.createTempDirectory("race-undone").toFile()
        val file = File(dir, "race_results.preferences_pb")
        var job: Job? = null
        suspend fun open(): RaceResultStore {
            job?.cancelAndJoin()
            val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
            job = scope.coroutineContext[Job]
            return RaceResultStore(PreferenceDataStoreFactory.create(scope = scope) { file })
        }
        try {
            val entry = raceAndUndo().entry
            open().keepUndoneFinish(entry)
            assertEquals(entry, open().undoneFinish())
            open().keepUndoneFinish(null)
            assertNull(open().undoneFinish())
            open().keepUndoneFinish(entry)
            open().clear()
            assertNull(open().undoneFinish())
        } finally {
            job?.cancelAndJoin()
            dir.deleteRecursively()
        }
    }

    private fun body(src: String, signature: String): String {
        val start = src.indexOf(signature)
        assertTrue("`$signature` not found", start >= 0)
        val open = src.indexOf('{', start)
        var depth = 0
        for (i in open until src.length) {
            when (src[i]) {
                '{' -> depth++
                '}' -> if (--depth == 0) return src.substring(open, i + 1)
            }
        }
        error("unbalanced `$signature`")
    }

    @Test
    fun `the view model keeps the undo, restores it with the recording and forgets it after`() {
        val vm = File("src/main/kotlin/com/runapp/watchwear/RunViewModel.kt").readText()
        val undo = body(vm, "private fun undoRaceFinish(")
        assertTrue(
            "the finish instant is read before the void clears it",
            undo.indexOf("raceStopDecision?.finishEpochMs") in 0 until undo.indexOf("raceTimer.voidAutoFinish()"),
        )
        assertTrue(
            "the start is read after the void keeps it",
            undo.indexOf("keepUndoneFinish(undoneRaceFinishEntry(") > undo.indexOf("raceTimer.voidAutoFinish()"),
        )
        val sync = body(vm, "private fun syncRaceTimerRun(")
        assertTrue(sync.indexOf("restoreUndoneFinish(id)") > sync.indexOf("raceTimer.beginRecording()"))
        val restore = body(vm, "private fun restoreUndoneFinish(")
        assertTrue(restore.contains("undoneFinishFor(raceResults.undoneFinish(), runId)"))
        assertTrue("a recording moved on is left alone", restore.contains("if (raceTimerRunId != runId)"))
        assertTrue(restore.contains("raceTimer.restoreUndone("))
        assertTrue(body(vm, "private fun maybeBindRace(").contains("raceToRebindAfterUndo(_state.value.activeRace, raceUndone)"))
        assertTrue("another recording's undo is dropped", restore.contains("dropKeptUndone()"))
        assertTrue(body(vm, "private suspend fun refreshRace(").contains("forgetUndoneUnlessPolled(newState)"))
        val polled = body(vm, "private suspend fun forgetUndoneUnlessPolled(")
        assertTrue("never while a recording is bound", polled.contains("if (boundRace != null) return"))
        assertTrue(polled.contains("undoneFinishOutlivesPoll(kept, active)"))
        for (sig in listOf(
            "private fun onRaceAutoFinish(",
            "private fun onRaceEndedByHost(",
            "private suspend fun handleFinishedRun(",
        )) {
            assertTrue("$sig forgets the undo", body(vm, sig).contains("forgetUndoneFinish()"))
        }
        val teardown = body(vm, "private suspend fun tearDownSession(")
        assertTrue(teardown.contains("raceResults.clear()"))
        assertTrue(teardown.contains("raceUndone = null"))
    }
}
