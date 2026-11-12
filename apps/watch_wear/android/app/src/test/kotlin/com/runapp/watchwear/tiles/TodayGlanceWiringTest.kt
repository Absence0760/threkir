package com.runapp.watchwear.tiles

import java.io.File
import org.junit.Assert.assertTrue
import org.junit.Test

/// Source-level guards for the "today" state's platform wiring: the push
/// wake-up, the tile's tap, and the run that retires the offer. None of it is
/// drivable on the host JVM (a Tiles host, a watch face and Play services
/// would all be needed), so the contract is pinned on the text, as
/// `ComplicationWiringTest` does for the complication.
class TodayGlanceWiringTest {

    private fun read(rel: String): String = File("src/main/$rel").readText()

    private val manifest by lazy { read("AndroidManifest.xml") }
    private val tile by lazy { read("kotlin/com/runapp/watchwear/tiles/ActiveRunTileService.kt") }
    private val listener by lazy { read("kotlin/com/runapp/watchwear/tiles/TodaysWorkoutListenerService.kt") }
    private val complication by lazy {
        read("kotlin/com/runapp/watchwear/complications/ActiveRunComplicationService.kt")
    }
    private val activity by lazy { read("kotlin/com/runapp/watchwear/MainActivity.kt") }
    private val viewModel by lazy { read("kotlin/com/runapp/watchwear/RunViewModel.kt") }
    private val bridge by lazy { read("kotlin/com/runapp/watchwear/WorkoutBridge.kt") }

    @Test
    fun `a new push wakes the listener on the bridge's path only`() {
        val el = Regex("""<service\b[^>]*TodaysWorkoutListenerService[\s\S]*?</service>""")
            .find(manifest)?.value
            ?: error("no <service> element for TodaysWorkoutListenerService in the manifest")
        val path = Regex("""const val PATH = "([^"]+)"""").find(bridge)!!.groupValues[1]
        assertTrue(el.contains("com.google.android.gms.wearable.DATA_CHANGED"))
        assertTrue(
            "the wake-up must be filtered to $path, or every Data Layer item starts the process",
            el.contains("""android:path="$path""""),
        )
    }

    @Test
    fun `the listener refreshes both glances through their guarded updaters`() {
        assertTrue(listener.contains("WorkoutBridge.PATH"))
        assertTrue(listener.contains("ActiveRunTileService.requestUpdate(this)"))
        assertTrue(listener.contains("ActiveRunComplicationService.requestUpdate(this)"))
    }

    @Test
    fun `the today entry expires at the glance's day end over an idle default`() {
        assertTrue(
            "the today entry must carry a validity ending at validUntilEpochMs",
            tile.contains(".setEndMillis(glance.validUntilEpochMs)"),
        )
        assertTrue(
            "the idle entry is the default, so the timeline must list it after today",
            tile.contains("tileOf(listOf(today, idle)"),
        )
        assertTrue(complication.contains("ComplicationDataTimeline("))
        assertTrue(complication.contains("Instant.ofEpochMilli(glance.validUntilEpochMs)"))
    }

    @Test
    fun `the tile always completes its future`() {
        val launch = Regex("""scope\.launch \{([\s\S]*?)\n        \}""").find(tile)?.groupValues?.get(1)
            ?: error("no scope.launch in ActiveRunTileService")
        assertTrue("the read must be caught", launch.contains("catch (e: Throwable)"))
        assertTrue("the future must be set after the catch", launch.trimEnd().endsWith("future.set(tile)"))
    }

    @Test
    fun `the tile's tap names the workout and the activity arms it`() {
        assertTrue(tile.contains("MainActivity.EXTRA_TODAY_WORKOUT_ID"))
        assertTrue(activity.contains("getStringExtra(EXTRA_TODAY_WORKOUT_ID)"))
        assertTrue("a warm start must arm it too", activity.contains("override fun onNewIntent"))
        assertTrue(activity.contains("vm.followWorkoutFromTile("))
        val arm = Regex("""fun followWorkoutFromTile\([^)]*\) \{([\s\S]*?)\n    \}""").find(viewModel)?.groupValues?.get(1)
            ?: error("no followWorkoutFromTile in RunViewModel")
        assertTrue("only on the pre-run screen", arm.contains("Stage.PreRun"))
        assertTrue("only the workout still on offer", arm.contains("todaysWorkout?.planWorkoutId != planWorkoutId"))
    }

    @Test
    fun `a finished run records the workout it followed and refreshes the tile`() {
        val remember = Regex("""private suspend fun rememberLastRun\([\s\S]*?\n    \}""").find(viewModel)?.value
            ?: error("no rememberLastRun in RunViewModel")
        assertTrue(remember.contains("planWorkoutId = m.workoutReview?.planWorkoutId"))
        assertTrue(remember.contains("ActiveRunTileService.requestUpdate("))
    }
}
