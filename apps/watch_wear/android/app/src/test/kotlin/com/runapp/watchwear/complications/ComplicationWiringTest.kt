package com.runapp.watchwear.complications

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/// Source-level guards for the watch-face complication. The service, its
/// manifest entry and its update pushes all need a watch face hosting the
/// slot to exercise, so the contract is pinned on the text, per the module's
/// convention for platform-bound wiring.
class ComplicationWiringTest {

    private fun read(rel: String): String = File("src/main/$rel").readText()

    private val manifest by lazy { read("AndroidManifest.xml") }
    private val service by lazy {
        read("kotlin/com/runapp/watchwear/complications/ActiveRunComplicationService.kt")
    }
    private val recorder by lazy {
        read("kotlin/com/runapp/watchwear/recording/RunRecordingService.kt")
    }
    private val viewModel by lazy { read("kotlin/com/runapp/watchwear/RunViewModel.kt") }

    private fun serviceElement(): String =
        Regex("""<service\b[^>]*ActiveRunComplicationService[\s\S]*?</service>""")
            .find(manifest)?.value
            ?: error("no <service> element for ActiveRunComplicationService in the manifest")

    @Test
    fun `only the complication host can bind the data source`() {
        val el = serviceElement()
        assertTrue(
            "the service must require BIND_COMPLICATION_PROVIDER, or any app can bind it",
            el.contains(
                """android:permission="com.google.android.wearable.permission.BIND_COMPLICATION_PROVIDER"""",
            ),
        )
        assertTrue(
            "the update-request action is how faces find the source",
            el.contains("android.support.wearable.complications.ACTION_COMPLICATION_UPDATE_REQUEST"),
        )
    }

    @Test
    fun `the declared types are exactly the ones the service builds`() {
        val declared = Regex(
            """android:name="android\.support\.wearable\.complications\.SUPPORTED_TYPES"\s*android:value="([^"]+)"""",
        ).find(serviceElement())?.groupValues?.get(1)?.split(',')?.map { it.trim() }?.toSet()
        assertEquals(setOf("SHORT_TEXT", "LONG_TEXT", "ICON"), declared)
        // ICON is the manifest spelling of MONOCHROMATIC_IMAGE.
        for (built in listOf("SHORT_TEXT", "LONG_TEXT", "MONOCHROMATIC_IMAGE")) {
            assertTrue(
                "declared but never built: $built",
                service.contains("ComplicationType.$built ->"),
            )
        }
    }

    @Test
    fun `the periodic poll is a safety net, not a tight loop`() {
        val period = Regex(
            """android:name="android\.support\.wearable\.complications\.UPDATE_PERIOD_SECONDS"\s*android:value="(\d+)"""",
        ).find(serviceElement())?.groupValues?.get(1)?.toInt()
        assertTrue("expected an UPDATE_PERIOD_SECONDS of at least 30 min, got $period", (period ?: 0) >= 1800)
    }

    @Test
    fun `the recording service pushes on every stage transition`() {
        val hits = Regex("""ActiveRunComplicationService\s*\.requestUpdate\s*\(""")
            .findAll(recorder).count()
        // Start, pause, resume, stop, plus the once-a-minute ticker push.
        assertTrue("expected ≥5 complication pushes in RunRecordingService, found $hits", hits >= 5)
        assertTrue(
            "the ticker push must go through isComplicationPushTick, or it fires every 500 ms",
            recorder.contains("isComplicationPushTick("),
        )
    }

    @Test
    fun `the update request is guarded and bound through the application context`() {
        val body = Regex("""fun requestUpdate\(context: Context\)\s*\{([\s\S]*?)\n        \}""")
            .find(service)?.groupValues?.get(1)
            ?: error("no requestUpdate body in ActiveRunComplicationService")
        assertTrue("requestUpdate must catch: it runs inside onStartCommand", body.contains("catch (e: Throwable)"))
        assertTrue("and must report what it caught", body.contains("Log.w("))
        assertTrue("must bind through the application context", body.contains("context.applicationContext"))
        assertTrue(
            "nobody but requestUpdate may build an updater",
            Regex("""ComplicationDataSourceUpdateRequester\s*\.create""").findAll(service).count() == 1,
        )
    }

    @Test
    fun `the last run is banked only after the queue write`() {
        val handle = Regex("""private suspend fun handleFinishedRun[\s\S]*?\n    \}""").find(viewModel)?.value
            ?: error("no handleFinishedRun in RunViewModel")
        val queued = handle.indexOf("store.save(")
        val remembered = handle.indexOf("rememberLastRun(")
        assertTrue("handleFinishedRun must call rememberLastRun", remembered >= 0)
        assertTrue(
            "the complication must never name a run the queue failed to keep",
            queued in 0 until remembered,
        )
    }

    @Test
    fun `discarding a run takes it off the watch face`() {
        val discard = Regex("""fun discard\(\)\s*\{[\s\S]*?\n    \}""").find(viewModel)?.value
            ?: error("no discard() in RunViewModel")
        assertTrue(discard.contains("lastRunStore.clearIfFor("))
    }

    @Test
    fun `the request path makes no network call`() {
        for (banned in listOf("SupabaseClient", "OkHttp", "okhttp3", "fetch")) {
            assertTrue("the complication answers from local state only: found $banned", !service.contains(banned))
        }
    }
}
