package com.runapp.watchwear

import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import java.io.File
import java.nio.file.Files
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

/// The race-mode transitions `RunViewModel` makes while a race run records
/// (`RaceRun.kt`), and the result queue it banks into. Every case is the
/// question the ViewModel asks at that event; the ViewModel itself only
/// carries out the answer.
class RaceRunStateTest {

    private val finishLat = 51.5
    private val finishLng = -0.1
    private val metresPerDegLat = 6_371_000.0 * Math.PI / 180.0
    private val t0 = 1_800_000_000_000L

    private fun fix(northM: Double, coveredM: Double, atS: Int) = RaceFinish.Fix(
        lat = finishLat + northM / metresPerDegLat,
        lng = finishLng,
        epochMs = t0 + atS * 1000L,
        coveredM = coveredM,
    )

    private val running = ActiveRaceState(
        eventId = "e1",
        instanceStart = "2026-05-22T18:00:00+00:00",
        status = "running",
        startedAtMs = t0,
        eventTitle = "Club 5K",
        course = RaceSessionClient.RaceCourse("c1", "5K", 5000.0, 51.5, -0.1),
    )

    // ───────────── Stop ─────────────

    @Test
    fun `stop while running pauses`() {
        assertEquals(RaceStopAction.PAUSE, raceStopAction(paused = false, raceBound = true, decided = false))
    }

    @Test
    fun `stop while paused finishes the race`() {
        assertEquals(
            RaceStopAction.FINISH_RACE,
            raceStopAction(paused = true, raceBound = true, decided = false),
        )
    }

    @Test
    fun `stop with no race, or with the outcome decided, stops the run`() {
        assertEquals(RaceStopAction.STOP, raceStopAction(paused = false, raceBound = false, decided = false))
        assertEquals(RaceStopAction.STOP, raceStopAction(paused = true, raceBound = false, decided = false))
        assertEquals(RaceStopAction.STOP, raceStopAction(paused = false, raceBound = true, decided = true))
        assertEquals(RaceStopAction.STOP, raceStopAction(paused = true, raceBound = true, decided = true))
    }

    // ───────────── Finish race ─────────────

    @Test
    fun `a pending candidate finishes automatically at the candidate's time, not now`() {
        val d = RaceFinishDetector(finishLat, finishLng, 5000.0)
        assertNull(d.offer(fix(20.0, 4980.0, 0)))
        assertNull(d.offer(fix(6.0, 4994.0, 4)))
        assertTrue(d.isCandidate)
        val decision = raceFinishDecision(
            settled = d.finaliseNow(),
            coveredM = 5001.0,
            courseDistanceM = 5000.0,
            nowDeviceMs = t0 + 60_000L,
        )
        assertEquals(RaceFinish.Outcome.AUTO_FINISH, decision.outcome)
        assertEquals(t0 + 4_000L, decision.finishEpochMs)
        assertEquals(4994.0, decision.coveredM, 0.0)
    }

    @Test
    fun `with no candidate, 90 percent or more is a manual finish now`() {
        val now = t0 + 1_800_000L
        val at90 = raceFinishDecision(null, 4500.0, 5000.0, now)
        assertEquals(RaceFinish.Outcome.MANUAL_FINISH, at90.outcome)
        assertEquals(now, at90.finishEpochMs)
        assertEquals(4500.0, at90.coveredM, 0.0)
        assertEquals(RaceFinish.Outcome.MANUAL_FINISH, raceFinishDecision(null, 5200.0, 5000.0, now).outcome)
    }

    @Test
    fun `with no candidate, short of 90 percent is a DNF`() {
        val dnf = raceFinishDecision(null, 4499.0, 5000.0, t0)
        assertEquals(RaceFinish.Outcome.DNF, dnf.outcome)
        assertEquals("dnf", dnf.outcome.finisherStatus)
        assertNull(dnf.outcome.finishMethod)
    }

    @Test
    fun `with no course to gate on, finish race is the manual finish asked for`() {
        assertEquals(RaceFinish.Outcome.MANUAL_FINISH, raceFinishDecision(null, 10.0, null, t0).outcome)
    }

    // ───────────── Host End ─────────────

    @Test
    fun `host End while running or paused ends the race for an undecided runner`() {
        assertTrue(hostEndsRace("finished", decided = false))
        assertTrue(hostEndsRace("cancelled", decided = false))
        assertFalse(hostEndsRace("running", decided = false))
        assertFalse(hostEndsRace("armed", decided = false))
        assertFalse("an unreadable status is not an End", hostEndsRace(null, decided = false))
        // Ended while paused: the race is unbound, so the next Stop stops the
        // run rather than asking to finish a race that is over.
        assertEquals(RaceStopAction.STOP, raceStopAction(paused = true, raceBound = false, decided = false))
    }

    @Test
    fun `host End after this runner's finish does not swallow the result`() {
        assertFalse(hostEndsRace("finished", decided = true))
        assertFalse(hostEndsRace("cancelled", decided = true))
    }

    // ───────────── Binding ─────────────

    @Test
    fun `a recording binds to a running race once`() {
        assertSame(running, raceToBind(alreadyBound = false, runId = "run1", endedRunId = null, active = running))
        assertNull(raceToBind(alreadyBound = true, runId = "run1", endedRunId = null, active = running))
        assertNull(raceToBind(alreadyBound = false, runId = null, endedRunId = null, active = running))
        assertNull(raceToBind(alreadyBound = false, runId = "run1", endedRunId = null, active = null))
        assertNull(
            "an armed race has no gun to bind to yet",
            raceToBind(false, "run1", null, running.copy(status = "armed")),
        )
    }

    @Test
    fun `the run a race ended under is never re-bound`() {
        assertNull(raceToBind(alreadyBound = false, runId = "run1", endedRunId = "run1", active = running))
        assertSame(running, raceToBind(alreadyBound = false, runId = "run2", endedRunId = "run1", active = running))
    }

    // ───────────── Auto finish ─────────────

    @Test
    fun `no fix is offered while paused, so a paused watch never auto-finishes`() {
        assertFalse(raceFixOfferable(recording = false, decided = false, fixKey = 1L, lastFixKey = 0L))
        val d = RaceFinishDetector(finishLat, finishLng, 5000.0)
        val inZone = listOf(fix(8.0, 4992.0, 0), fix(3.0, 4997.0, 2), fix(15.0, 5010.0, 4))
        var last = Long.MIN_VALUE
        for (f in inZone) {
            if (raceFixOfferable(recording = false, decided = false, fixKey = f.epochMs, lastFixKey = last)) {
                last = f.epochMs
                d.offer(f)
            }
        }
        assertFalse(d.isCandidate)
        assertNull(d.finish)
    }

    @Test
    fun `a fix is offered once, and none after the outcome is decided`() {
        assertTrue(raceFixOfferable(recording = true, decided = false, fixKey = 2L, lastFixKey = 1L))
        assertFalse(raceFixOfferable(recording = true, decided = false, fixKey = 2L, lastFixKey = 2L))
        assertFalse(raceFixOfferable(recording = true, decided = true, fixKey = 3L, lastFixKey = 2L))
    }

    // ───────────── One clock ─────────────

    @Test
    fun `a fix is stamped on the device wall clock from its elapsedRealtime age`() {
        val nowWall = t0 + 500_000L
        assertEquals(nowWall - 2_000L, raceFixDeviceMs(98_000L, nowWall, 100_000L))
        assertEquals(nowWall, raceFixDeviceMs(100_000L, nowWall, 100_000L))
        assertEquals("no stamp is taken as now", nowWall, raceFixDeviceMs(null, nowWall, 100_000L))
        assertEquals("a stamp from the future is taken as now", nowWall, raceFixDeviceMs(100_500L, nowWall, 100_000L))
    }

    @Test
    fun `chip time from a device-stamped fix ignores a GPS clock that disagrees`() {
        val runStartedAt = t0
        val nowWall = t0 + 1_800_000L
        val stamped = raceFixDeviceMs(fixElapsedRealtimeMs = 9_000L, nowWallMs = nowWall, nowElapsedRealtimeMs = 10_000L)
        assertEquals(1799, RaceFinish.chipTimeS(stamped, runStartedAt))
    }

    @Test
    fun `the race clock's gun is moved onto the device clock by the offset`() {
        assertEquals(t0 - 4_000L, gunStartDeviceMs(t0, 4_000L))
        assertEquals(t0, gunStartDeviceMs(t0, null))
        assertNull(gunStartDeviceMs(null, 4_000L))
    }

    // ───────────── Result queue ─────────────

    private val mine = PendingRaceResult("u1", "e1", "i1", "run1", 1800, 5000.0, "finished", "auto")
    private val other = PendingRaceResult("u2", "e1", "i1", "run9", 2000, 5000.0, "finished", "manual")

    @Test
    fun `a session replays only its own account's results`() {
        assertEquals(listOf(mine), raceResultsToReplay(listOf(mine, other), "u1"))
        assertEquals(emptyList<PendingRaceResult>(), raceResultsToReplay(listOf(other), "u1"))
    }

    private fun withStore(block: suspend (RaceResultStore) -> Unit) = runBlocking {
        val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
        val dir = Files.createTempDirectory("race-results").toFile()
        try {
            val store = RaceResultStore(
                PreferenceDataStoreFactory.create(scope = scope) {
                    File(dir, "race_results.preferences_pb")
                },
            )
            block(store)
        } finally {
            scope.cancel()
            dir.deleteRecursively()
        }
    }

    @Test
    fun `remove drops exactly the sent result and leaves the rest queued`() {
        withStore { store ->
            store.add(mine)
            store.add(other)
            assertEquals(listOf(mine, other), store.current())
            store.remove(mine)
            assertEquals(listOf(other), store.current())
            store.remove(mine)
            assertEquals(listOf(other), store.current())
        }
    }

    @Test
    fun `sign-out's clear empties the queue for every account`() {
        withStore { store ->
            store.add(mine)
            store.add(other)
            store.clear()
            assertEquals(emptyList<PendingRaceResult>(), store.current())
            store.add(mine)
            assertEquals(listOf(mine), store.current())
        }
    }

    @Test
    fun `a newer result for the same race replaces the queued one in the store`() {
        withStore { store ->
            store.add(mine.copy(finisherStatus = "dnf", finishMethod = null))
            store.add(mine)
            assertEquals(listOf(mine), store.current())
        }
    }

    // ───────────── Wiring ─────────────

    @Test
    fun `the ViewModel never hands the detector a GPS fix's own time`() {
        val src = File("src/main/kotlin/com/runapp/watchwear/RunViewModel.kt").readText()
        assertFalse(
            "RaceFinish.Fix must be stamped on the device clock (raceFixDeviceMs), not GpsPoint.epochMs",
            Regex("""RaceFinish\.Fix\([^)]*\.epochMs""").containsMatchIn(src),
        )
        assertTrue(src.contains("raceFixDeviceMs("))
        assertTrue(src.contains("raceStopAction("))
        assertTrue(src.contains("hostEndsRace("))
        assertTrue(src.contains("raceToBind("))
        assertTrue(src.contains("raceFixOfferable("))
    }
}
