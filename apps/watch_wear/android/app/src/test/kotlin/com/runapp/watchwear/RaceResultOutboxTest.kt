package com.runapp.watchwear

import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import java.io.File
import java.nio.file.Files
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.cancel
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

/// What reaches the server for a race and in which order (#1307): a line
/// finish filed at once without its run and again with it, "Not finished?
/// Resume" deleting the runner's own automatic row or dropping one that never
/// left the watch, an undo with no signal deleting the finish before the
/// next result for that race, and the race course kept on the watch for a
/// race timed with no signal.
class RaceResultOutboxTest {

    private class FakeServer {
        val submitted = mutableListOf<PendingRaceResult>()
        val deleted = mutableListOf<Triple<String, String, String>>()
        val log = mutableListOf<String>()
        var submitError: Throwable? = null
        var deleteError: Throwable? = null
        var deleteStarted: CompletableDeferred<Unit>? = null
        var deleteHangs = false
        val failures = mutableListOf<String>()

        suspend fun submit(token: String, r: PendingRaceResult) {
            submitError?.let { throw it }
            submitted += r
            log += "submit ${r.finishMethod}"
        }

        suspend fun delete(token: String, uid: String, eventId: String, instance: String) {
            deleteStarted?.complete(Unit)
            if (deleteHangs) awaitCancellation()
            deleteError?.let { throw it }
            deleted += Triple(uid, eventId, instance)
            log += "delete"
        }
    }

    private fun withOutbox(block: suspend (RaceResultOutbox, RaceResultStore, FakeServer) -> Unit) = runBlocking {
        val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
        val dir = Files.createTempDirectory("race-outbox").toFile()
        try {
            val store = RaceResultStore(
                PreferenceDataStoreFactory.create(scope = scope) { File(dir, "race_results.preferences_pb") },
            )
            val server = FakeServer()
            val outbox = RaceResultOutbox(
                store = store,
                submit = server::submit,
                deleteAuto = server::delete,
                onFailure = { message, _ -> server.failures += message },
            )
            block(outbox, store, server)
        } finally {
            scope.cancel()
            dir.deleteRecursively()
        }
    }

    private val lineFinish = PendingRaceResult(
        userId = "u1",
        eventId = "e1",
        instanceStart = "i1",
        runId = null,
        durationS = 1006,
        distanceM = 5030.0,
        finisherStatus = "finished",
        finishMethod = "auto",
        gunTimeS = 1006,
        chipTimeS = 1000,
        startAt = "2026-05-22T18:00:06Z",
        finishAt = "2026-05-22T18:16:46Z",
        startDetection = "gate",
        finishDetection = "gate",
    )
    private val handFinish = lineFinish.copy(
        runId = "run-1",
        durationS = 1300,
        gunTimeS = 1300,
        chipTimeS = 1294,
        finishMethod = "manual",
        finishAt = "2026-05-22T18:21:40Z",
        finishDetection = null,
    )
    private val offline = java.io.IOException("Unable to resolve host")

    @Test
    fun `a line finish files without its run and Stop links it in place`() = withOutbox { outbox, store, server ->
        outbox.file("t", lineFinish)
        assertNull(server.submitted.single().runId)
        assertTrue(store.current().isEmpty())
        outbox.file("t", lineFinish.copy(runId = "run-1"))
        assertEquals("run-1", server.submitted.last().runId)
        assertTrue(store.current().isEmpty())
    }

    @Test
    fun `a finish with no signal is queued, and Stop's linked copy replaces it`() = withOutbox { outbox, store, server ->
        server.submitError = offline
        outbox.file("t", lineFinish)
        outbox.file(null, lineFinish.copy(runId = "run-1"))
        assertEquals(listOf(lineFinish.copy(runId = "run-1")), store.current())
        server.submitError = null
        outbox.replay("t", "u1")
        assertEquals("run-1", server.submitted.single().runId)
        assertTrue(store.current().isEmpty())
    }

    @Test
    fun `Not finished - Resume deletes the runner's own filed finish`() = withOutbox { outbox, store, server ->
        outbox.file("t", lineFinish)
        outbox.void("t", "u1", "e1", "i1")
        assertEquals(listOf(Triple("u1", "e1", "i1")), server.deleted)
        assertTrue(store.voids().isEmpty())
    }

    @Test
    fun `an undo drops a finish that was only queued`() = withOutbox { outbox, store, server ->
        server.submitError = offline
        outbox.file("t", lineFinish)
        outbox.void(null, "u1", "e1", "i1")
        server.submitError = null
        outbox.replay("t", "u1")
        assertTrue("the withdrawn finish never reaches the server", server.submitted.isEmpty())
        assertTrue(store.current().isEmpty())
    }

    @Test
    fun `an undo with no signal deletes the finish before the next result`() = withOutbox { outbox, store, server ->
        outbox.file("t", lineFinish)
        server.deleteError = offline
        outbox.void("t", "u1", "e1", "i1")
        assertTrue(server.deleted.isEmpty())
        assertEquals(listOf(PendingRaceVoid("u1", "e1", "i1")), store.voids())

        server.deleteError = null
        outbox.file("t", handFinish)
        assertEquals(
            "the withdrawn finish goes before the hand finish is sent",
            listOf("submit auto", "delete", "submit manual"),
            server.log,
        )
        assertTrue(store.voids().isEmpty())
        assertTrue(store.current().isEmpty())
    }

    @Test
    fun `a delete that still has no signal holds the next result back`() = withOutbox { outbox, store, server ->
        server.deleteError = offline
        outbox.void(null, "u1", "e1", "i1")
        outbox.file("t", handFinish)
        assertTrue("the hand finish must not land beside the auto one", server.submitted.isEmpty())
        assertEquals(listOf(handFinish), store.current())

        server.deleteError = null
        outbox.replay("t", "u1")
        assertEquals(listOf("delete", "submit manual"), server.log)
        assertTrue(store.voids().isEmpty())
    }

    @Test
    fun `a refused delete drops the void and lets the result through`() = withOutbox { outbox, store, server ->
        server.deleteError = RuntimeException("HTTP 403: rls")
        outbox.void("t", "u1", "e1", "i1")
        assertTrue("a refusal is not worth replaying", store.voids().isEmpty())
        outbox.file("t", handFinish)
        assertEquals(listOf(handFinish), server.submitted)
    }

    @Test
    fun `a cancelled delete is not reported as a send failure`() = withOutbox { outbox, store, server ->
        server.deleteError = CancellationException("scope cancelled")
        try {
            outbox.void("t", "u1", "e1", "i1")
            fail("the cancellation must reach the caller")
        } catch (expected: CancellationException) {
        }
        assertTrue("a cancellation is not a retryable send failure", server.failures.isEmpty())
        assertEquals(listOf(PendingRaceVoid("u1", "e1", "i1")), store.voids())
    }

    @Test
    fun `an undo cancelled mid-delete still keeps the void`() = withOutbox { outbox, store, server ->
        outbox.file("t", lineFinish)
        server.deleteHangs = true
        val started = CompletableDeferred<Unit>()
        server.deleteStarted = started
        coroutineScope {
            val job = launch { outbox.void("t", "u1", "e1", "i1") }
            started.await()
            job.cancelAndJoin()
        }
        assertTrue(server.failures.isEmpty())
        assertEquals(
            "the withdrawn finish is deleted on the next poll rather than left on the board",
            listOf(PendingRaceVoid("u1", "e1", "i1")),
            store.voids(),
        )
        server.deleteHangs = false
        server.deleteStarted = null
        outbox.replay("t", "u1")
        assertEquals(listOf(Triple("u1", "e1", "i1")), server.deleted)
        assertTrue(store.voids().isEmpty())
    }

    @Test
    fun `a replay sends only the signed-in account's results and voids`() = withOutbox { outbox, store, server ->
        server.submitError = offline
        server.deleteError = offline
        outbox.file("t", lineFinish.copy(userId = "u2"))
        outbox.void(null, "u2", "e9", "i9")
        server.submitError = null
        server.deleteError = null
        outbox.replay("t", "u1")
        assertTrue(server.submitted.isEmpty())
        assertTrue(server.deleted.isEmpty())
        assertEquals(1, store.current().size)
        assertEquals(1, store.voids().size)
        store.clear()
        assertTrue(store.current().isEmpty())
        assertTrue(store.voids().isEmpty())
    }

    @Test
    fun `the race course is kept on the watch for its account and race only`() = withOutbox { _, store, _ ->
        val course = RaceSessionClient.RaceCourse(
            id = "c1",
            name = "5K",
            distanceM = 5000.0,
            finishLat = 51.5,
            finishLng = -0.03,
            startGate = Gate(51.5, -0.1, 90.0, 15.0),
            finishGate = Gate(51.5, -0.03, 90.0, 15.0),
            finishLineSelfCross = false,
        )
        assertNull(store.cachedCourse("u1", "e1", "i1"))
        store.cacheCourse(CachedRaceCourse("u1", "e1", "i1", course))
        assertEquals(
            "the lines survive the round trip, so detection needs no network",
            course,
            store.cachedCourse("u1", "e1", "i1"),
        )
        assertNull("another account's course is not this one's", store.cachedCourse("u2", "e1", "i1"))
        assertNull("another race's course is not this one's", store.cachedCourse("u1", "e2", "i1"))
        store.clear()
        assertNull("sign-out forgets it", store.cachedCourse("u1", "e1", "i1"))
    }
}
