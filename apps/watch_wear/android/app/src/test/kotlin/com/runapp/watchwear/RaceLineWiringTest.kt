package com.runapp.watchwear

import java.io.File
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/// The parts of timing by the lines (#1307) that live in `RunViewModel` and
/// `RunRecordingService`, which need a device to run: read as source, so a
/// refactor that drops one fails here rather than on the start line. The
/// rules themselves are pinned in `RaceLineTimerTest` and
/// `RaceResultOutboxTest`.
class RaceLineWiringTest {

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

    private val vm = read("RunViewModel.kt")

    @Test
    fun `every fresh fix goes to the timer from the recording's Start, bound or not`() {
        val advance = body(vm, "private fun maybeAdvanceRaceFinish(")
        assertFalse("the feed must not wait for the bind", advance.contains("boundRace"))
        assertTrue(advance.contains("raceTimer.offer("))
        assertTrue(body(vm, "private fun syncRaceTimerRun(").contains("raceTimer.beginRecording()"))
        val tick = body(vm, "private fun observeRecording(")
        assertTrue(
            "the run is followed before it binds, and the timer updated after",
            Regex("""syncRaceTimerRun\(m\)\s+maybeBindRace\(m\)\s+updateRaceTimer\(\)""").containsMatchIn(tick),
        )
    }

    @Test
    fun `a line finish files at once, pauses, and opens the undo window`() {
        val f = body(vm, "private fun onRaceAutoFinish(")
        assertTrue(f.contains("RaceFinish.FinishDetection.GATE"))
        assertTrue(f.contains("fileLineFinish("))
        assertTrue(f.contains("RunRecordingService.pause("))
        assertTrue(f.contains("RACE_UNDO_WINDOW_MS"))
        assertTrue("the window closing stops the run", f.contains("RunRecordingService.stop("))
        assertTrue(body(vm, "private fun fileLineFinish(").contains("runId = null"))
    }

    @Test
    fun `the resume control inside the window is the undo`() {
        val resume = body(vm, "fun resume(")
        assertTrue(resume.indexOf("undoRaceFinish()") in 0 until resume.indexOf("RunRecordingService.resume("))
        val undo = body(vm, "private fun undoRaceFinish(")
        assertTrue(undo.contains("raceTimer.voidAutoFinish()"))
        assertTrue("an undo waits for the filing in flight", undo.contains("filing?.join()"))
        assertTrue(undo.contains("raceOutbox.void("))
    }

    @Test
    fun `the finished run files the same start the line saw`() {
        val finished = body(vm, "private suspend fun handleFinishedRun(")
        assertTrue(finished.contains("start = start"))
        assertTrue(finished.contains("raceTimer.endRecording()"))
        assertTrue(finished.contains("raceOutbox.file(null, raceResult)"))
    }

    @Test
    fun `the course is cached on the watch and read back with no signal`() {
        val load = body(vm, "private suspend fun loadRaceCourse(")
        assertTrue(load.contains("raceResults.cacheCourse("))
        assertTrue(load.contains("raceResults.cachedCourse("))
    }

    @Test
    fun `each crossing cue is its own L4 effect in the service`() {
        val svc = read("recording/RunRecordingService.kt")
        val cue = body(svc, "private fun raceCue(")
        assertTrue(Regex("""try \{\s+vibrate\(""").containsMatchIn(cue))
        assertTrue(Regex("""try \{\s+cues\?\.announceRaceCrossing\(""").containsMatchIn(cue))
        assertTrue(svc.contains("ACTION_RACE_CUE -> raceCue("))
        assertTrue(body(vm, "private fun cueRaceCrossing(").contains("catch (e: Throwable)"))
    }
}
