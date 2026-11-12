package com.runapp.watchwear

import java.io.File
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/// `metadata.race_undone_finish_at` on a saved Wear run: the latest line
/// finish the runner took back, on the server clock as a result's
/// `finish_at` is, so a later re-time does not find that finish again. Absent
/// when nothing was taken back.
class RaceUndoneMetadataTest {

    private val undoneAt = 1_779_473_806_123L

    @Test
    fun `the undone instant is written on the server clock, as finish_at is`() {
        assertEquals("2026-05-22T18:16:46.123Z", raceUndoneFinishAtIso(undoneAt, null))
        assertEquals("2026-05-22T18:16:47.623Z", raceUndoneFinishAtIso(undoneAt, 1_500))
        assertEquals("2026-05-22T18:16:44.623Z", raceUndoneFinishAtIso(undoneAt, -1_500))
        assertNull(raceUndoneFinishAtIso(null, 1_500))

        val race = ActiveRaceState("e1", "i1", "running", startedAtMs = null, eventTitle = null)
        val finish = RaceFinish.Finish(undoneAt, 1.0, 5_000.0, RaceFinish.FinishDetection.GATE)
        val filed = buildRaceResult(
            race = race,
            decision = RaceStopDecision(RaceFinish.Outcome.AUTO_FINISH, undoneAt, 5_000.0, finish),
            userId = "u1",
            runId = null,
            runStartedAtMs = undoneAt - 1_000_000,
            elapsedS = 1_000,
            serverOffsetMs = 1_500,
        )
        assertEquals("the same instant the undone result was filed with", filed.finishAt, raceUndoneFinishAtIso(undoneAt, 1_500))
    }

    private fun metadata(undone: String?) = buildRunMetadata(
        activityType = "run",
        avgBpm = null,
        hrCoverage = null,
        steps = null,
        laps = emptyList(),
        lastModifiedAtIso = "2026-05-22T19:00:00Z",
        raceUndoneFinishAt = undone,
    )

    @Test
    fun `the key is written only when a finish was taken back`() {
        val iso = raceUndoneFinishAtIso(undoneAt, 0)
        assertEquals(iso, metadata(iso)["race_undone_finish_at"]?.jsonPrimitive?.contentOrNull)
        assertFalse(metadata(null).containsKey("race_undone_finish_at"))
    }

    @Test
    fun `a queued run carries it, and one queued before the field reads none`() {
        val json = Json { ignoreUnknownKeys = true }
        val run = QueuedRun(
            id = "run-1",
            startedAtIso = "2026-05-22T18:00:00Z",
            durationS = 1_000,
            distanceM = 5_000.0,
            trackFilePath = "/tmp/x.json",
            raceUndoneFinishAt = "2026-05-22T18:16:46.123Z",
        )
        assertEquals(run, json.decodeFromString(QueuedRun.serializer(), json.encodeToString(QueuedRun.serializer(), run)))
        val old = """{"id":"r","startedAtIso":"2026-05-22T18:00:00Z","durationS":1,"distanceM":1.0,"trackFilePath":"/t"}"""
        assertNull(json.decodeFromString(QueuedRun.serializer(), old).raceUndoneFinishAt)
    }

    @Test
    fun `the view model keeps the latest undo for the run and uploads it`() {
        val vm = File("src/main/kotlin/com/runapp/watchwear/RunViewModel.kt").readText()
        fun body(signature: String): String {
            val start = vm.indexOf(signature)
            assertTrue("`$signature` not found", start >= 0)
            val open = vm.indexOf('{', start)
            var depth = 0
            for (i in open until vm.length) {
                when (vm[i]) {
                    '{' -> depth++
                    '}' -> if (--depth == 0) return vm.substring(open, i + 1)
                }
            }
            error("unbalanced `$signature`")
        }
        assertTrue(body("private fun undoRaceFinish(").contains("raceUndoneAtMs = undoneAtMs"))
        assertTrue(body("private fun restoreUndoneFinish(").contains("entry.undoneFinishMs"))
        val finished = body("private suspend fun handleFinishedRun(")
        assertTrue(finished.contains("raceUndoneFinishAtIso(raceUndoneAtMs, serverClock.offsetMs)"))
        assertTrue(finished.contains("raceUndoneFinishAt = undoneFinishAt"))
        assertTrue(body("private suspend fun pushRun(").contains("raceUndoneFinishAt = run.raceUndoneFinishAt"))
        assertTrue(
            "a later finish does not forget the undo the saved run names",
            !body("private fun forgetUndoneFinish(").contains("raceUndoneAtMs"),
        )
    }
}
