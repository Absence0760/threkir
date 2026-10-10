package com.runapp.watchwear.recording

import com.runapp.watchwear.GpsPoint
import java.io.File
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/// The most-used loop on the wrist, end to end: start a run, pause, resume,
/// stop, and then start the NEXT one.
///
/// The phone shipped a bug on exactly this path — a finished state that got
/// in the way of the next start — and nothing walked it. On Wear OS the loop
/// spans three parties: `RunViewModel` (stage machine the screens render),
/// `RunRecordingService` (writes `RecordingRepository`) and the repository
/// itself. The first two are Android-bound and, by this module's rule, not
/// driven without Robolectric; the repository is plain Kotlin.
///
/// So the loop is pinned in two halves. The repository half drives the
/// stage sequence the service performs, through the same transforms, and
/// checks what the next run inherits. The wiring half reads the service and
/// the ViewModel and pins that they still use the guards the first half
/// relies on: the service gates a start on `isActive` (so a `Finished` run
/// that has not been reset yet cannot refuse the next one) and opens a run
/// with a whole fresh `Metrics` (so nothing of the last run carries over),
/// and the ViewModel walks PostRun back to PreRun through `startNextRun`.
class NextRunLifecycleTest {

    @Before fun setUp() = RecordingRepository.reset()

    @After fun tearDown() = RecordingRepository.reset()

    // ───────────────────── the repository half ─────────────────────

    /// The service's own start: refused while a run is active, and otherwise
    /// a whole new `Metrics`, never a `copy` of whatever was there.
    private fun startRun(id: String, atMs: Long): Boolean {
        if (RecordingRepository.metrics.value.isActive) return false
        RecordingRepository.update {
            RecordingRepository.Metrics(
                stage = RecordingRepository.Stage.Recording,
                runId = id,
                startedAtMs = atMs,
                trackFilePath = "/tracks/$id.json",
            )
        }
        return true
    }

    private fun recordSomeDistance(metres: Double) {
        RecordingRepository.update {
            it.copy(
                distanceM = it.distanceM + metres,
                trackPointCount = it.trackPointCount + 1,
                latestPoint = GpsPoint(lat = 51.5, lng = -0.1, ele = null, epochMs = 0L),
            )
        }
    }

    private fun stage() = RecordingRepository.metrics.value.stage

    private fun finishTheRun() {
        RecordingRepository.update {
            it.copy(
                stage = RecordingRepository.Stage.Finished,
                distanceStepFilledM = 12.0,
                finishedHr = HeartRateClaim(avgBpm = 151.0, coverage = 0.97),
            )
        }
    }

    @Test
    fun `a run walks recording, paused, recording and finished under one id`() {
        assertTrue("an idle recorder accepts a start", startRun("run-a", atMs = 1_000L))
        assertEquals(RecordingRepository.Stage.Recording, stage())
        recordSomeDistance(400.0)

        RecordingRepository.update { it.copy(stage = RecordingRepository.Stage.Paused) }
        assertTrue("a paused run is still the active run", RecordingRepository.metrics.value.isActive)
        assertFalse(
            "a second start while paused must be refused, not open a second run",
            startRun("run-intruder", atMs = 2_000L),
        )

        RecordingRepository.update { it.copy(stage = RecordingRepository.Stage.Recording) }
        recordSomeDistance(600.0)
        RecordingRepository.update {
            it.copy(laps = listOf(RecordingRepository.Lap(number = 1, atMs = 300_000L, distanceM = it.distanceM)))
        }
        finishTheRun()

        val m = RecordingRepository.metrics.value
        assertEquals(RecordingRepository.Stage.Finished, m.stage)
        assertEquals("pause and resume keep the run's identity", "run-a", m.runId)
        assertEquals(1_000L, m.startedAtMs)
        assertEquals("distance either side of the pause is one run's", 1_000.0, m.distanceM, 1e-9)
        assertEquals(1, m.laps.size)
        assertEquals("/tracks/run-a.json", m.trackFilePath)
    }

    @Test
    fun `a finished run does not hold the recorder against the next start`() {
        startRun("run-a", atMs = 1_000L)
        recordSomeDistance(5_000.0)
        finishTheRun()

        // The window between the service publishing Finished and the
        // ViewModel banking and resetting it. A start landing here must open
        // the next run, not be refused because something is still on file.
        assertFalse(RecordingRepository.metrics.value.isActive)
        assertTrue("a Finished run must not refuse the next start", startRun("run-b", atMs = 9_000L))
        assertEquals(RecordingRepository.Stage.Recording, stage())
    }

    @Test
    fun `the next run inherits nothing from the finished one`() {
        startRun("run-a", atMs = 1_000L)
        recordSomeDistance(5_000.0)
        RecordingRepository.update {
            it.copy(
                laps = listOf(RecordingRepository.Lap(1, 300_000L, 1_000.0)),
                steps = 6_000,
                offRouteDistanceM = 55.0,
                routeRemainingM = 2_000.0,
                trackOverlayPoints = listOf(RouteMath.LatLng(51.5, -0.1)),
            )
        }
        finishTheRun()

        startRun("run-b", atMs = 9_000L)
        val m = RecordingRepository.metrics.value
        assertEquals("run-b", m.runId)
        assertEquals(9_000L, m.startedAtMs)
        assertEquals("/tracks/run-b.json", m.trackFilePath)
        assertEquals(0.0, m.distanceM, 0.0)
        assertEquals(0L, m.elapsedMs)
        assertEquals(0, m.trackPointCount)
        assertTrue("the last run's laps would split the next one", m.laps.isEmpty())
        assertNull(m.steps)
        assertNull(m.latestPoint)
        assertNull("a finished claim on a live run would be stamped on the wrong run", m.finishedHr)
        assertNull(m.distanceStepFilledM)
        assertNull(m.offRouteDistanceM)
        assertNull(m.routeRemainingM)
        assertTrue(m.trackOverlayPoints.isEmpty())
    }

    @Test
    fun `banking and resetting returns the recorder to idle, ready for another run`() {
        startRun("run-a", atMs = 1_000L)
        recordSomeDistance(5_000.0)
        finishTheRun()

        // `handleFinishedRun` resets once the run is in the upload queue.
        RecordingRepository.resetIfFinished("run-a")
        assertEquals(RecordingRepository.Stage.Idle, stage())
        assertNull(RecordingRepository.metrics.value.runId)

        assertTrue(startRun("run-b", atMs = 9_000L))
        recordSomeDistance(250.0)
        finishTheRun()
        val m = RecordingRepository.metrics.value
        assertEquals("run-b", m.runId)
        assertNotEquals("each run is its own row", "run-a", m.runId)
        assertEquals("the second run measures only itself", 250.0, m.distanceM, 1e-9)
    }

    @Test
    fun `a late reset for the finished run leaves the next run recording`() {
        // `handleFinishedRun` resets on a background job after the queue
        // write. A start landing first used to be wiped back to Idle while the
        // service kept recording it: frozen screen, and a stop dropped on the
        // null run id.
        startRun("run-a", atMs = 1_000L)
        recordSomeDistance(5_000.0)
        finishTheRun()
        assertTrue(startRun("run-b", atMs = 9_000L))
        recordSomeDistance(120.0)

        RecordingRepository.resetIfFinished("run-a")

        val m = RecordingRepository.metrics.value
        assertEquals(RecordingRepository.Stage.Recording, m.stage)
        assertEquals("run-b", m.runId)
        assertEquals(120.0, m.distanceM, 1e-9)
    }

    @Test
    fun `the scoped reset leaves an unfinished run alone, even its own`() {
        startRun("run-a", atMs = 1_000L)
        RecordingRepository.resetIfFinished("run-a")
        assertEquals(
            "only a Finished run is the cleanup's to reset",
            RecordingRepository.Stage.Recording,
            stage(),
        )
    }

    @Test
    fun `the finished-run cleanup clears only that run's checkpoint`() {
        fun cp(id: String) = Checkpoint(
            runId = id,
            startedAtMs = 1_000L,
            savedAtMs = 16_000L,
            distanceM = 40.0,
            trackFilePath = "/tracks/$id.json",
            trackPointCount = 3,
        )
        assertTrue(checkpointClearableFor(cp("run-a"), "run-a"))
        assertFalse(
            "the next run's checkpoint is its only crash protection",
            checkpointClearableFor(cp("run-b"), "run-a"),
        )
        assertTrue("an unreadable checkpoint recovers nothing", checkpointClearableFor(null, "run-a"))
    }

    // ───────────────────── the wiring half ─────────────────────

    private val serviceSrc: String =
        File("src/main/kotlin/com/runapp/watchwear/recording/RunRecordingService.kt").readText()

    private val viewModelSrc: String =
        File("src/main/kotlin/com/runapp/watchwear/RunViewModel.kt").readText()

    private val appSrc: String =
        File("src/main/kotlin/com/runapp/watchwear/ui/RunWatchApp.kt").readText()

    /// The named member's body, the way `CheckpointHandoffWiringTest` reads
    /// one: from the signature to the first closing brace at member depth.
    private fun body(src: String, signature: String): String {
        val normalised = src.replace(" suspend fun ", " fun ")
        val block = Regex("""${Regex.escape(signature)}[\s\S]*?\n    \}""").find(normalised)
        assertTrue("expected a $signature body", block != null)
        return block!!.value
    }

    @Test
    fun `the service refuses a start only while a run is active`() {
        val fn = body(serviceSrc, "private fun startRecording(")
        assertTrue(
            "the start gate must be isActive (Recording or Paused), which a Finished run is not",
            fn.contains("if (RecordingRepository.metrics.value.isActive) return"),
        )
        assertFalse(
            "gating a start on Finished or on not-Idle refuses the next run until the " +
                "ViewModel has banked and reset the last one",
            fn.contains("Stage.Finished") || fn.contains("Stage.Idle"),
        )
    }

    @Test
    fun `the service opens each run on fresh state`() {
        val fn = body(serviceSrc, "private fun startRecording(")
        assertTrue(
            "a start must write a whole new Metrics, not a copy of the last run's",
            Regex("""RecordingRepository\.update\s*\{\s*RecordingRepository\.Metrics\(""").containsMatchIn(fn),
        )
        for (reset in listOf(
            "laps.clear()",
            "bankedGpsDistanceM = 0.0",
            "bankedStepDistanceM = 0.0",
            "pausedAccumulatedMs = 0",
            "pausedSinceMs = 0",
            "bpmSum = 0",
            "bpmCount = 0",
            "hrAvailableMs = 0",
            "trackOverlay.clear()",
            "lastAnnouncedSplit = 0",
        )) {
            assertTrue("startRecording must reset `$reset` or the next run inherits it", fn.contains(reset))
        }
        assertTrue(
            "each run gets its own track file",
            fn.contains("TrackWriter.fileFor(applicationContext, runId)"),
        )
    }

    @Test
    fun `the ViewModel starts only from PreRun, on a new id and zeroed counters`() {
        val fn = body(viewModelSrc, "fun start()")
        assertTrue(fn.contains("if (_state.value.stage != Stage.PreRun) return"))
        assertTrue("every run mints its own id", fn.contains("UUID.randomUUID().toString()"))
        for (field in listOf(
            "elapsedMs = 0",
            "distanceM = 0.0",
            "lapCount = 0",
            "thisRunId = runId",
            "thisRunSynced = false",
            "syncFault = null",
        )) {
            assertTrue("start() must set `$field` for the new run", fn.contains(field))
        }
        assertTrue("the service is told the same id", fn.contains("runId = runId"))
    }

    @Test
    fun `PostRun leads back to PreRun through startNextRun`() {
        val fn = body(viewModelSrc, "fun startNextRun()")
        assertTrue("Next must land on the screen that can start a run", fn.contains("stage = Stage.PreRun"))
        assertTrue("the finished run must not stay this screen's run", fn.contains("thisRunId = null"))
        assertTrue(fn.contains("thisRunSynced = false"))

        assertTrue(appSrc.contains("onStartNext = vm::startNextRun"))
        assertTrue(
            "the synced run's primary button is the way to the next run",
            appSrc.contains("onClick = if (synced) onStartNext else onSync"),
        )
        assertTrue(
            "an unsynced run must still offer Next, or the runner is held behind a sync",
            appSrc.contains("onClick = onStartNext,"),
        )
        assertTrue("the countdown is what starts the run", appSrc.contains("vm.start()"))
    }

    @Test
    fun `the post-bank reset does not move the screen`() {
        val fn = body(viewModelSrc, "private fun observeRecording()")
        assertTrue(fn.contains("RecordingRepository.Stage.Finished -> handleFinishedRun(m)"))
        assertTrue(
            "Idle is what the reset publishes; reacting to it would pull the runner off " +
                "PostRun mid-summary",
            fn.contains("RecordingRepository.Stage.Idle -> Unit"),
        )
    }

    @Test
    fun `the finished-run cleanup never clears or resets unscoped`() {
        val fn = body(viewModelSrc, "private fun handleFinishedRun(")
        assertFalse(
            "an unscoped reset wipes a next run that started before the cleanup ran",
            fn.contains("RecordingRepository.reset()"),
        )
        assertFalse(
            "an unscoped clear deletes the next run's crash checkpoint",
            fn.contains("checkpoints.clear()"),
        )
    }

    @Test
    fun `a finished run is shown, banked, and only then cleared from the recorder`() {
        val fn = body(viewModelSrc, "private fun handleFinishedRun(")
        val postRun = fn.indexOf("stage = Stage.PostRun")
        val save = fn.indexOf("store.save(")
        val reset = fn.indexOf("RecordingRepository.resetIfFinished(runId)")
        assertTrue("the summary must be shown", postRun >= 0)
        assertTrue("the run must be queued", save >= 0)
        assertTrue("the recorder must be returned to Idle", reset >= 0)
        assertTrue("the summary does not wait on the queue write", postRun < save)
        assertTrue(
            "resetting before the save would drop the only copy of a run the queue has not taken",
            save < reset,
        )
    }
}
