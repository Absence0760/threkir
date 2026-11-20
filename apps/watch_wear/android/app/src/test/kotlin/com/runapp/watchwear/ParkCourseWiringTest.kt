package com.runapp.watchwear

import java.io.File
import org.junit.Assert.assertTrue
import org.junit.Test

/// The live course timing wiring (#1446) that lives in `RunViewModel`,
/// `RunRecordingService` and the running screen, which need a device to run:
/// read as source, so a refactor that drops a link fails here. The rule is
/// pinned in `LiveCourseTimerTest`, the payload in `ParkCourseBridgeTest`.
class ParkCourseWiringTest {

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
    private val service = read("recording/RunRecordingService.kt")
    private val ui = read("ui/RunWatchApp.kt")

    @Test
    fun `start builds the timer from the picked course, the stage tick feeds it, each in its own catch`() {
        assertTrue(body(vm, "fun start(").contains("courseTimer = courseTimerFor(route, _state.value.courses)"))
        val tick = body(vm, "private fun observeRecording(")
        assertTrue(
            "the course feed has its own try, after the race's",
            Regex("""try \{\s+advanceCourseTimer\(m\)\s+\} catch""").containsMatchIn(tick),
        )
        val advance = body(vm, "private fun advanceCourseTimer(")
        assertTrue(advance.contains("raceFixOfferable("))
        assertTrue("the device clock, as the race feed", advance.contains("raceFixDeviceMs("))
        assertTrue(advance.contains("timer.offer("))
    }

    @Test
    fun `Stop settles the timer before the service stops, and a finished run drops it`() {
        val stop = body(vm, "fun stop(")
        val settle = stop.indexOf("settleCourseTimer()")
        assertTrue(settle >= 0 && settle < stop.indexOf("RunRecordingService.stop("))
        assertTrue(body(vm, "private suspend fun handleFinishedRun(").contains("courseTimer = null"))
    }

    @Test
    fun `every event buzzes and speaks through the service, which keeps each effect apart`() {
        val publish = body(vm, "private fun publishCourseEvents(")
        assertTrue(publish.contains("RunRecordingService.courseCue("))
        assertTrue(publish.contains("courseCueAfter("))
        assertTrue(service.contains("ACTION_COURSE_CUE -> courseCue("))
        val cue = body(service, "private fun courseCue(")
        assertTrue(cue.contains("vibrate("))
        assertTrue(cue.contains("cues?.announceCourse("))
        assertTrue("the buzz and the speech each catch", Regex("catch").findAll(cue).count() >= 2)
    }

    @Test
    fun `the picker lists the courses first and the running screen shows the cue, ambient too`() {
        assertTrue(ui.contains("routes = state.courses.map { it.asRoute() } + state.routes"))
        assertTrue(ui.contains("courseCue = state.courseCue"))
        assertTrue("shown in the ambient branch and the live one", Regex("courseCueText\\(courseCue\\)").findAll(ui).count() >= 2)
        assertTrue(body(vm, "private fun observeParkCourses(").contains("parkCourseBridge.current()"))
    }
}
