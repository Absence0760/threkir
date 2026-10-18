package com.runapp.watchwear.workout

import java.io.File
import org.junit.Assert.assertTrue
import org.junit.Test

/// Source-level guard for how today's workout is wired through the recording
/// service and the view model, the halves no host JVM can run (a Service, a
/// Data Layer client). The pure halves are `WorkoutRunnerTest`,
/// `WorkoutCuesTest` and `WorkoutPushFixtureTest`.
class WorkoutWiringTest {

    private val service: String =
        File("src/main/kotlin/com/runapp/watchwear/recording/RunRecordingService.kt").readText()

    private val vm: String =
        File("src/main/kotlin/com/runapp/watchwear/RunViewModel.kt").readText()

    private fun body(src: String, signature: String): String {
        val start = src.indexOf(signature)
        assertTrue("missing $signature", start >= 0)
        val end = src.indexOf("\n    }\n", start)
        return src.substring(start, end)
    }

    @Test
    fun `the ticker feeds the runner on the active clock, and a paused run is not fed`() {
        assertTrue(
            "the ticker must feed the runner the active elapsed it just computed",
            Regex("""RecordingRepository\.update \{ it\.copy\(elapsedMs = elapsed\) \}\s*\n\s*feedWorkout\(elapsed\)""")
                .containsMatchIn(service),
        )
        val feed = body(service, "private fun feedWorkout(")
        assertTrue("a paused run must not feed the runner", feed.contains("if (isPaused()) return"))
    }

    @Test
    fun `the lap press also skips the current step`() {
        val lap = body(service, "private fun markLap()")
        assertTrue(lap.contains("workoutRunner?.skipStep()"))
        assertTrue(lap.contains("publishWorkout(events)"))
    }

    @Test
    fun `the general pace alert stands down while the workout owns pace`() {
        val announce = body(service, "private fun announceProgress(")
        assertTrue(announce.contains("workoutRunner?.ownsPaceCues == true"))
        assertTrue(announce.contains("if (!workoutOwnsPace && target != null"))
    }

    @Test
    fun `the review rides the checkpoint and the finished metrics`() {
        assertTrue(
            body(service, "private suspend fun writeCheckpoint()")
                .contains("workoutReview = synchronized(workoutLock) { workoutRunner?.review() }"),
        )
        val stop = body(service, "private fun stopRecording()")
        assertTrue(stop.contains("workoutReview = workoutReview"))
    }

    @Test
    fun `the view model queues and uploads the review on every path`() {
        assertTrue(body(vm, "private suspend fun handleFinishedRun(").contains("workoutReview = m.workoutReview"))
        assertTrue(body(vm, "fun recoverCheckpoint()").contains("workoutReview = cp.workoutReview"))
        assertTrue(body(vm, "private suspend fun pushRun(").contains("workout = run.workoutReview"))
    }

    @Test
    fun `Start re-checks the day and passes the workout only when the runner follows it`() {
        val start = body(vm, "fun start()")
        assertTrue("the day check must run again at Start", start.contains("refreshTodaysWorkout()"))
        assertTrue(start.contains("_state.value.todaysWorkout?.takeIf { _state.value.followWorkout }"))
        assertTrue(start.contains("workoutJson = workoutJson"))
    }
}
