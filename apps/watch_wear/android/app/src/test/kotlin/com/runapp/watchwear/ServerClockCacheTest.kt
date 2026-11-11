package com.runapp.watchwear

import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import java.io.File
import java.nio.file.Files
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/// The server clock offset kept on the watch across a restart (#1307
/// offline): the entry a ping makes, the 24 h expiry, the seed that lets a
/// live sample replace it by `ServerClockOffset`'s own rule, the DataStore
/// round trip and sign-out, and the view model's wiring.
class ServerClockCacheTest {

    private val t0 = 1_779_472_800_000L

    private fun sample(sentAt: Long, rtt: Long, serverAt: Long) =
        RaceSessionClient.ClockSample(sentAt, sentAt + rtt, serverAt)

    @Test
    fun `a sample keeps the offset ServerClockOffset takes from it, with its round trip`() {
        val s = sample(t0, 400, t0 + 1_700)
        val live = ServerClockOffset().apply { addSample(s.sentAtMs, s.receivedAtMs, s.serverAtMs) }
        val e = clockOffsetEntry(s)!!
        assertEquals(live.offsetMs, e.offsetMs)
        assertEquals(1_500L, e.offsetMs)
        assertEquals(400L, e.rttMs)
        assertEquals("sampled when the answer came back", t0 + 400, e.sampledAtMs)
        assertNull("a round trip that ran backwards is no sample", clockOffsetEntry(sample(t0, -1, t0)))
    }

    @Test
    fun `a seeded offset is exact and a live sample replaces it by the shortest round trip`() {
        for (rtt in listOf(0L, 1L, 7L, 400L)) {
            val c = ServerClockOffset().apply { seed(CachedClockOffset(-2_345, rtt, t0)) }
            assertEquals("round trip $rtt", -2_345L, c.offsetMs)
        }
        val kept = CachedClockOffset(offsetMs = 1_500, rttMs = 100, sampledAtMs = t0)

        val longer = ServerClockOffset().apply { seed(kept) }
        longer.addSample(t0, t0 + 300, t0 + 9_000)
        assertEquals("a longer round trip does not replace it", 1_500L, longer.offsetMs)

        val tie = ServerClockOffset().apply { seed(kept) }
        tie.addSample(t0, t0 + 100, t0 + 1_650)
        assertEquals("a tie takes the newer", 1_600L, tie.offsetMs)

        val shorter = ServerClockOffset().apply { seed(kept) }
        shorter.addSample(t0, t0 + 40, t0 + 1_420)
        assertEquals(1_400L, shorter.offsetMs)
    }

    @Test
    fun `clockSampleWins is ServerClockOffset's rule`() {
        val c = ServerClockOffset()
        var best: Long? = null
        val rtts = listOf(400L, 500L, 400L, -5L, 100L, 300L, 100L, 0L, 50L)
        for ((i, rtt) in rtts.withIndex()) {
            val before = c.offsetMs
            val serverAt = t0 + 10_000 * (i + 1)
            val wins = clockSampleWins(rtt, best)
            c.addSample(t0, t0 + rtt, serverAt)
            if (wins) {
                assertEquals("sample $i wins", clockOffsetEntry(sample(t0, rtt, serverAt))!!.offsetMs, c.offsetMs)
                best = rtt
            } else {
                assertEquals("sample $i loses", before, c.offsetMs)
            }
        }
        assertFalse(clockSampleWins(-1, null))
    }

    @Test
    fun `an offset is restored for a day after its sample and not after`() {
        val e = CachedClockOffset(1_500, 80, t0)
        assertEquals(e, restorableClockOffset(e, t0))
        assertEquals(e, restorableClockOffset(e, t0 + CLOCK_OFFSET_MAX_AGE_MS))
        assertEquals(24 * 3_600_000L, CLOCK_OFFSET_MAX_AGE_MS)
        assertNull("past a day", restorableClockOffset(e, t0 + CLOCK_OFFSET_MAX_AGE_MS + 1))
        assertNull("a device clock set back since", restorableClockOffset(e, t0 - 1))
        assertNull(restorableClockOffset(null, t0))
        assertNull(restorableClockOffset(e.copy(rttMs = -1), t0))
    }

    private fun withStore(block: suspend (open: suspend () -> RaceResultStore, raw: suspend (String) -> Unit) -> Unit) =
        runBlocking {
            val dir = Files.createTempDirectory("race-clock").toFile()
            val file = File(dir, "race_results.preferences_pb")
            var job: Job? = null
            var store: androidx.datastore.core.DataStore<androidx.datastore.preferences.core.Preferences>? = null
            suspend fun reopen() {
                job?.cancelAndJoin()
                val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
                job = scope.coroutineContext[Job]
                store = PreferenceDataStoreFactory.create(scope = scope) { file }
            }
            try {
                block(
                    {
                        reopen()
                        RaceResultStore(store!!)
                    },
                    { text ->
                        reopen()
                        store!!.edit { it[stringPreferencesKey("race_clock_offset_v1")] = text }
                    },
                )
            } finally {
                job?.cancelAndJoin()
                dir.deleteRecursively()
            }
        }

    @Test
    fun `the offset survives a restart and sign-out forgets it`() = withStore { open, _ ->
        val e = CachedClockOffset(-820, 64, t0)
        open().cacheClockOffset(e)
        val after = open()
        assertEquals(e, after.cachedClockOffset())
        after.cacheClockOffset(null)
        assertNull(open().cachedClockOffset())

        open().cacheClockOffset(e)
        open().clear()
        assertNull("sign-out clears it with the race cache", open().cachedClockOffset())
    }

    @Test
    fun `an unreadable kept offset reads as none`() = withStore { open, raw ->
        raw("{not json")
        assertNull(open().cachedClockOffset())
    }

    private fun read(rel: String) = File("src/main/kotlin/com/runapp/watchwear/$rel").readText()

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
    fun `the view model keeps a winning sample and restores the offset before the race`() {
        val vm = read("RunViewModel.kt")
        val sampleFn = body(vm, "private fun onClockSample(")
        assertTrue(sampleFn.contains("clockSampleWins("))
        assertTrue(sampleFn.indexOf("rememberClockOffset(sample)") > sampleFn.indexOf("serverClock.addSample("))
        assertTrue(body(vm, "private fun rememberClockOffset(").contains("raceResults.cacheClockOffset(entry)"))
        val restore = body(vm, "private suspend fun restoreClockOffset(")
        assertTrue(restore.contains("restorableClockOffset(raceResults.cachedClockOffset()"))
        assertTrue("a live sample already in wins", restore.contains("if (serverClock.offsetMs != null) return"))
        assertTrue(restore.contains("serverClock.seed(entry)"))
        val race = body(vm, "private suspend fun restoreCachedRace(")
        assertTrue(
            "the offset is restored before the race is judged on it",
            race.indexOf("restoreClockOffset()") in 0 until race.indexOf("raceResults.restoreActiveRace("),
        )
        val teardown = body(vm, "private suspend fun tearDownSession(")
        assertTrue(teardown.contains("raceResults.clear()"))
        assertTrue(teardown.contains("serverClock = ServerClockOffset()"))
        assertTrue(teardown.contains("clockRestoreTried = false"))
    }
}
