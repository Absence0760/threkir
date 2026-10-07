package com.runapp.watchwear

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/// Source-level guards for the Wear OS AndroidManifest. The audit pass
/// flagged two manifest issues Play reviewers regress on: a redundant
/// application-level cleartext-traffic flag, and a body-sensor
/// permission the app can neither obtain nor use. These tests pin both.
///
/// Pure-JVM JUnit, no Robolectric — matches the rest of the test
/// module's "read the source, assert a pattern" pattern (see
/// `RoutesBridgeWiringTest`, `ScreenWiringTest`).
class ManifestGuardsTest {

    private val manifest: String by lazy {
        File("src/main/AndroidManifest.xml").readText()
    }

    @Test
    fun `BODY_SENSORS_BACKGROUND is not declared`() {
        // Why, and this reverses what this guard used to assert: the
        // permission was declared for two years on the claim that HR
        // "stops streaming once the display goes ambient" without it.
        // Two facts kill that claim. It was never passed to
        // `permissionLauncher.launch`, so no watch has ever granted it
        // — a declared-and-unrequested runtime permission is inert.
        // And it is not the permission this app's heart rate depends
        // on: Health Services documents BODY_SENSORS_BACKGROUND against
        // PassiveMonitoringClient, while `HeartRateMonitor` uses
        // MeasureClient, whose background access is documented as "no"
        // and is not something a permission grant changes. What DOES
        // govern sensor access from the recording service is the
        // foreground-service type it starts with, guarded separately in
        // `ManifestPermissionCoverageTest`.
        //
        // So the declaration bought no capability and cost a sensor
        // permission on the install prompt and the Play Data Safety
        // form. Re-adding it needs a MeasureClient -> ExerciseClient
        // migration to be worth anything, and that is a code change
        // this guard should see first.
        assertFalse(
            "AndroidManifest.xml must not declare BODY_SENSORS_BACKGROUND — " +
                "it gates PassiveMonitoringClient, and this app reads heart " +
                "rate through MeasureClient.",
            manifest.contains(
                "android.permission.BODY_SENSORS_BACKGROUND"
            ),
        )
        assertTrue(
            "BODY_SENSORS itself must stay declared — MeasureClient needs it",
            Regex("""<uses-permission\s+android:name="android\.permission\.BODY_SENSORS"\s*/>""")
                .containsMatchIn(manifest),
        )
    }

    @Test
    fun `application does not set usesCleartextTraffic=true`() {
        // Why: the network security config (res/xml/network_security_config.xml)
        // is the canonical mechanism — it whitelists 10.0.2.2 (the
        // emulator host) and nothing else. The application-level
        // attribute is redundant for actual behaviour, but Play
        // reviewers read it without cross-checking the NSC and flag
        // it as a security gap on the manifest scan.
        val applicationOpenTag = Regex(
            """<application\b[^>]*>""",
            RegexOption.DOT_MATCHES_ALL,
        ).find(manifest)?.value
            ?: error("Could not find <application> element in manifest")
        assertFalse(
            "<application> must not set android:usesCleartextTraffic=\"true\". " +
                "The networkSecurityConfig attribute carries the same intent " +
                "with a tighter scope; Play reviewers flag the redundant attribute.",
            applicationOpenTag.contains("usesCleartextTraffic=\"true\""),
        )
    }

    @Test
    fun `networkSecurityConfig is still wired`() {
        // Why: the previous test removes the broad cleartext-traffic
        // toggle, but the dev-loopback NSC must stay attached
        // otherwise local Supabase (http://10.0.2.2:24321) becomes
        // unreachable in debug builds.
        val applicationOpenTag = Regex(
            """<application\b[^>]*>""",
            RegexOption.DOT_MATCHES_ALL,
        ).find(manifest)?.value
            ?: error("Could not find <application> element in manifest")
        assertTrue(
            "<application> must still declare " +
                "android:networkSecurityConfig=\"@xml/network_security_config\"",
            applicationOpenTag.contains(
                "networkSecurityConfig=\"@xml/network_security_config\""
            ),
        )
        assertTrue(
            "res/xml/network_security_config.xml must exist",
            File("src/main/res/xml/network_security_config.xml").exists(),
        )
    }

    @Test
    fun `Sentry starts only from the app's own DSN-gated init`() {
        // Why: sentry-android merges a SentryInitProvider into the manifest
        // that starts the SDK before any app code runs. With no DSN — every
        // debug build, and any release built without `-PSENTRY_DSN` — it
        // throws "DSN is required" and the app dies on launch, before the
        // DSN check that makes crash reporting optional. Turning auto-init
        // off leaves the explicit init as the only way in, so the init has
        // to stay in the Application class (ahead of the recording service
        // and the tile service, not just MainActivity) and stay gated.
        val sources = File("src/main/kotlin").walkTopDown()
            .filter { it.isFile && it.extension == "kt" }
            .associate { it.path to it.readText() }
        val initSites = sources.filterValues { it.contains("SentryAndroid.init(") }.keys
        if (initSites.isEmpty()) return

        assertTrue(
            "The app initialises Sentry by hand, so <application> must declare " +
                "<meta-data android:name=\"io.sentry.auto-init\" android:value=\"false\"/>; " +
                "otherwise SentryInitProvider throws on an empty DSN at launch.",
            Regex(
                """<meta-data\s+android:name="io\.sentry\.auto-init"\s+android:value="false"\s*/>""",
            ).containsMatchIn(manifest),
        )
        assertFalse(
            "Do not declare io.sentry.dsn in the manifest — the DSN comes from " +
                "BuildConfig.SENTRY_DSN and the gate in WatchWearApplication.",
            manifest.contains("io.sentry.dsn"),
        )
        assertEquals(
            "SentryAndroid.init must live only in WatchWearApplication",
            setOf("src/main/kotlin/com/runapp/watchwear/WatchWearApplication.kt"),
            initSites,
        )
        val applicationOpenTag = Regex(
            """<application\b[^>]*>""",
            RegexOption.DOT_MATCHES_ALL,
        ).find(manifest)?.value
            ?: error("Could not find <application> element in manifest")
        assertTrue(
            "<application> must name .WatchWearApplication, or its Sentry init never runs",
            applicationOpenTag.contains("android:name=\".WatchWearApplication\""),
        )
        val app = sources.getValue("src/main/kotlin/com/runapp/watchwear/WatchWearApplication.kt")
        assertTrue(
            "WatchWearApplication must skip Sentry init when SENTRY_DSN is blank",
            app.contains("isBlank()") && app.indexOf("isBlank()") < app.indexOf("SentryAndroid.init("),
        )
    }
}
