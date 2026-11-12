package com.runapp.watchwear

import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import java.io.File
import java.nio.file.Files
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.PI
import kotlin.math.cos

/// The race kept on the watch across a restart (#1307 offline), the phone's
/// `race_active_cache` rules: a scheduled or self-timed race is kept with its
/// window and course and restored with no signal, so the restarted watch still
/// binds and times it by the lines; a race finished, cancelled or past its
/// window, a Host GO race and another account's race are not; sign-out
/// forgets it.
class RaceActiveCacheTest {

    private val lat0 = 51.5
    private val lng0 = -0.1
    private val mPerDegLat = RaceFinish.EARTH_RADIUS_M * PI / 180.0
    private val mPerDegLng = mPerDegLat * cos(lat0 * PI / 180.0)
    private fun lngAt(eastM: Double) = lng0 + eastM / mPerDegLng

    private val course = RaceSessionClient.RaceCourse(
        id = "course-5k",
        name = "5K",
        distanceM = 5000.0,
        finishLat = lat0,
        finishLng = lngAt(5000.0),
        startGate = Gate(lat0, lngAt(0.0), 90.0, 15.0),
        finishGate = Gate(lat0, lngAt(5000.0), 90.0, 15.0),
    )

    // Real wall-clock instants: ActiveRaceState judges armed / running on
    // the device clock, as the ViewModel does.
    private val now = System.currentTimeMillis()
    private val go = now - 60_000L

    private val scheduled = ActiveRaceState(
        eventId = "e1",
        instanceStart = "2026-05-22T18:00:00+00:00",
        status = "armed",
        startedAtMs = null,
        eventTitle = "Park 5K",
        course = course,
        startMode = "scheduled",
        startInstantMs = go,
        windowClosesAtMs = go + 3 * 3_600_000L,
    )

    /// [open] is a process (re)start: the DataStore before it is shut down
    /// and a fresh one reads the same file, so a store handed out earlier is
    /// not used after the next [open].
    private fun withStore(block: suspend (open: suspend () -> RaceResultStore) -> Unit) = runBlocking {
        val dir = Files.createTempDirectory("race-active").toFile()
        val file = File(dir, "race_results.preferences_pb")
        var job: Job? = null
        try {
            block {
                job?.cancelAndJoin()
                val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
                job = scope.coroutineContext[Job]
                RaceResultStore(PreferenceDataStoreFactory.create(scope = scope) { file })
            }
        } finally {
            job?.cancelAndJoin()
            dir.deleteRecursively()
        }
    }

    /// Keep [race] and its course as a poll with signal does.
    private suspend fun RaceResultStore.keep(race: ActiveRaceState, uid: String = "u1") {
        cacheCourse(CachedRaceCourse(uid, race.eventId, race.instanceStart, race.course!!))
        cacheActiveRace(activeRaceCacheEntry(uid, race))
    }

    @Test
    fun `a restart with no signal still binds and times the race from the cache`() = withStore { open ->
        open().keep(scheduled)

        val restored = open().restoreActiveRace("u1", now)
        assertNotNull("the race is known before any poll answers", restored)
        restored!!
        assertEquals("the lines came back with it", course, restored.course)
        assertTrue("its scheduled GO has passed, so it is live offline", restored.isRunning)
        assertEquals(go, restored.goAtMs)

        val bound = raceToBind(alreadyBound = false, runId = "run-1", endedRunId = null, active = restored)
        assertEquals("the recording binds with no signal", restored, bound)
        val target = raceTargetFor(bound, restored, recording = true)!!
        assertEquals(go, target.goServerMs)

        val timer = RaceLineTimer().apply { beginRecording() }
        timer.update(target, bound!!.course, serverOffsetMs = null)
        timer.bind()
        var fin: RaceFinish.Finish? = null
        var x = -30.0
        var t = go + 2_000L
        while (x <= 5020.0) {
            val f = timer.offer(RaceFinish.Fix(lat0, lngAt(x), t, x + 30.0))
            if (fin == null) fin = f
            x += 10.0
            t += 2_000L
        }
        assertNotNull("the finish line times it, offline", fin)
        assertEquals(RaceFinish.FinishDetection.GATE, fin!!.detection)
        assertEquals(RaceFinish.StartKind.LINE, fin.start?.kind)
    }

    @Test
    fun `a self-timed window that is open is restored, unarmed`() = withStore { open ->
        val selfTimed = scheduled.copy(startMode = "self_timed", attemptArmed = true)
        open().keep(selfTimed)
        val restored = open().restoreActiveRace("u1", now)!!
        assertTrue(restored.isSelfTimed)
        assertEquals("the attempt is armed again by hand, as on the phone", false, restored.attemptArmed)
        assertNull(
            "and nothing binds until it is",
            raceToBind(alreadyBound = false, runId = "run-1", endedRunId = null, active = restored),
        )
    }

    @Test
    fun `a race whose window has closed is not restored`() = withStore { open ->
        open().keep(scheduled.copy(status = "running", windowClosesAtMs = now - 1_000L))
        assertNull(open().restoreActiveRace("u1", now))
    }

    @Test
    fun `a finished or cancelled race is not restored`() = withStore { open ->
        val store = open()
        for (status in listOf("finished", "cancelled")) {
            store.keep(scheduled.copy(status = status))
            assertNull(status, store.restoreActiveRace("u1", now))
        }
    }

    @Test
    fun `an armed race not yet at GO is restored armed`() = withStore { open ->
        open().keep(scheduled.copy(startInstantMs = now + 600_000L, windowClosesAtMs = now + 4_200_000L))
        val restored = open().restoreActiveRace("u1", now)!!
        assertTrue(restored.isArmed)
        assertNull(
            "an armed race binds nothing",
            raceToBind(alreadyBound = false, runId = "run-1", endedRunId = null, active = restored),
        )
    }

    @Test
    fun `a Host GO race is not kept, and a poll with no race forgets the last`() = withStore { open ->
        val store = open()
        store.keep(scheduled)
        assertNull(activeRaceCacheEntry("u1", scheduled.copy(startMode = "host_go")))
        store.cacheActiveRace(activeRaceCacheEntry("u1", scheduled.copy(startMode = "host_go")))
        assertNull("only the host knows a Host GO race's GO", store.cachedActiveRace())
        store.keep(scheduled)
        store.cacheActiveRace(activeRaceCacheEntry("u1", null))
        assertNull(store.restoreActiveRace("u1", now))
    }

    @Test
    fun `another account's race is not restored`() = withStore { open ->
        open().keep(scheduled, uid = "u1")
        assertNull(open().restoreActiveRace("u2", now))
    }

    @Test
    fun `a course cached for another course id is not attached`() {
        val entry = activeRaceCacheEntry("u1", scheduled)!!
        val other = course.copy(id = "course-10k")
        assertNull(restorableActiveRace(entry, "u1", now, other)!!.course)
        assertEquals(course, restorableActiveRace(entry, "u1", now, course)!!.course)
    }

    @Test
    fun `sign-out forgets the race and its course`() = withStore { open ->
        val store = open()
        store.keep(scheduled)
        store.clear()
        assertNull(store.cachedActiveRace())
        assertNull(store.cachedCourse("u1", scheduled.eventId, scheduled.instanceStart))
        assertNull("nor does a restart bring it back", open().restoreActiveRace("u1", now))
    }

    @Test
    fun `the effective status follows the window on the device`() {
        fun at(status: String, mode: String, nowMs: Long) =
            raceEffectiveStatus(status, mode, startInstantMs = 1_000L, windowClosesAtMs = 2_000L, nowMs = nowMs)
        assertEquals("armed", at("armed", "scheduled", 999L))
        assertEquals("running", at("armed", "scheduled", 1_000L))
        assertEquals("finished", at("armed", "self_timed", 2_000L))
        assertEquals("finished", at("running", "scheduled", 2_000L))
        assertEquals("cancelled", at("cancelled", "scheduled", 1_500L))
        assertEquals("Host GO is what the row says", "armed", at("armed", "host_go", 5_000L))
    }
}
