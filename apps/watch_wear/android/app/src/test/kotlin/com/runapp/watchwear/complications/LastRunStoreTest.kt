package com.runapp.watchwear.complications

import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import java.io.File
import java.nio.file.Files
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/// The complication's idle state reads this store, and a watch face is on
/// show to anyone, so what survives a discard or a sign-out matters as much
/// as what is written. Pinned against a real file-backed DataStore.
class LastRunStoreTest {

    private val run = LastRun(
        runId = "r1",
        distanceM = 5_123.0,
        durationS = 1_574,
        unit = "km",
        finishedAtMs = 1_800_000_000_000L,
    )

    private fun withStore(block: suspend (LastRunStore) -> Unit) = runBlocking {
        val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
        val dir = Files.createTempDirectory("last-run").toFile()
        try {
            val store = LastRunStore(
                PreferenceDataStoreFactory.create(scope = scope) {
                    File(dir, "last_run.preferences_pb")
                },
            )
            block(store)
        } finally {
            scope.cancel()
            dir.deleteRecursively()
        }
    }

    @Test
    fun `an empty store has no last run`() {
        withStore { store -> assertNull(store.current()) }
    }

    @Test
    fun `the saved run reads back whole`() {
        withStore { store ->
            store.save(run)
            assertEquals(run, store.current())
        }
    }

    @Test
    fun `a newer run replaces the older one`() {
        withStore { store ->
            store.save(run)
            val next = run.copy(runId = "r2", distanceM = 8_000.0)
            store.save(next)
            assertEquals(next, store.current())
        }
    }

    @Test
    fun `discarding a different run leaves the entry alone`() {
        withStore { store ->
            store.save(run)
            store.clearIfFor("r0")
            assertEquals(run, store.current())
        }
    }

    @Test
    fun `discarding the run it names drops the entry`() {
        withStore { store ->
            store.save(run)
            store.clearIfFor("r1")
            assertNull(store.current())
        }
    }

    @Test
    fun `clear drops the entry whatever it names`() {
        withStore { store ->
            store.save(run)
            store.clear()
            assertNull(store.current())
        }
    }

    @Test
    fun `an unreadable entry reads as no last run`() {
        assertNull(decodeLastRun(null))
        assertNull(decodeLastRun("{not json"))
        assertNull(decodeLastRun("""{"runId":"r1"}"""))
    }

    @Test
    fun `a field added by a later build does not lose the entry`() {
        val raw = encodeLastRun(run).dropLast(1) + ""","laterField":7}"""
        assertEquals(run, decodeLastRun(raw))
    }
}
