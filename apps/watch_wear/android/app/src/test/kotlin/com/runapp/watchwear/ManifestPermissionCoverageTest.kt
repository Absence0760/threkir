package com.runapp.watchwear

import android.Manifest
import android.content.pm.ServiceInfo
import android.os.Build
import com.runapp.watchwear.recording.RunRecordingService
import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/// A declared permission and a requested permission are two different
/// facts, and nothing in this module connected them.
///
/// `AndroidManifest.xml` declares what the app MAY hold;
/// `RunWatchApp.kt`'s `permissionLauncher.launch(...)` is the only place the
/// app ever ASKS for one. A runtime permission that appears in the first list
/// and not the second is never granted on any watch — and the failure is
/// invisible from inside the app, because the code that depends on it goes on
/// calling the API and the platform simply withholds the effect. That is how
/// `POST_NOTIFICATIONS` sat declared-but-unrequested: the recording service
/// posts its `OngoingActivity` notification on every tick, `startForeground`
/// succeeds, and on API 33+ the notification is kept out of the shade — so
/// the runner loses the ongoing-activity chip that is their way back into a
/// live run from the watch face, with nothing anywhere reporting an error.
///
/// The requirement is DERIVED from the manifest rather than listed here: a
/// hand-written list would cover the permissions someone remembered on the
/// day, and a permission added to the manifest tomorrow would be covered by
/// nothing. Everything the manifest declares is therefore held to one of
/// three answers — requested at runtime, install-time (so there is nothing to
/// request), or a registered exemption carrying its reason. An exemption
/// naming a permission the manifest no longer declares fails too, so the
/// register cannot go stale in the quiet direction.
class ManifestPermissionCoverageTest {

    private val manifest: String by lazy {
        File("src/main/AndroidManifest.xml").readText()
    }

    private val requestSite: String by lazy {
        File("src/main/kotlin/com/runapp/watchwear/ui/RunWatchApp.kt").readText()
    }

    private val buildScript: String by lazy {
        File("build.gradle.kts").readText()
    }

    private val serviceSource: String by lazy {
        File(
            "src/main/kotlin/com/runapp/watchwear/recording/RunRecordingService.kt",
        ).readText()
    }

    /// Granted at install with no dialog, so "did we request it" is not a
    /// question that can be asked of them.
    private val installTime = setOf(
        "INTERNET",
        "ACCESS_NETWORK_STATE",
        "WAKE_LOCK",
        "FOREGROUND_SERVICE",
        "FOREGROUND_SERVICE_LOCATION",
        "FOREGROUND_SERVICE_HEALTH",
        // Not a dialog either: it only permits LAUNCHING the system
        // whitelist prompt, which `system/BatteryOptimization.kt` does.
        "REQUEST_IGNORE_BATTERY_OPTIMIZATIONS",
        // Normal permission. `Vibrator.vibrate` is still refused without the
        // DECLARATION, which is the other direction this class now checks.
        "VIBRATE",
    )

    /// Runtime permissions the app deliberately does not ask for, each with
    /// the reason. Anything not here and not install-time must be in the
    /// launch array.
    private val exempt = emptyMap<String, String>()

    /// Platform APIs this module calls that the system refuses without a
    /// manifest declaration, and the permission each one needs.
    ///
    /// The OTHER direction from every test above, and the one nothing checked:
    /// those hold the manifest to the request site, so a permission declared
    /// and never asked for is caught, while a permission CALLED FOR and never
    /// declared is not — and that failure is quieter still. `Vibrator.vibrate`
    /// throws `SecurityException` across the binder with no declaration, the
    /// call site catches `Throwable` because a watch may genuinely have no
    /// vibrator, and the two are indistinguishable from inside the app: the
    /// pace alert's haptic had therefore never fired on any watch, on any
    /// build, and read as hardware (decisions § 1302).
    ///
    /// Keyed on the API rather than on a receiver name, because the
    /// requirement belongs to the call and not to whatever a local happens to
    /// be called this month.
    private val permissionGatedApis = mapOf(
        Regex("""\.vibrate\(""") to "VIBRATE",
    )

    private fun mainSources(): List<File> =
        File("src/main/kotlin").walkTopDown().filter { it.extension == "kt" }.toList()

    @Test
    fun `every permission-gated API this module calls is declared`() {
        val sources = mainSources().map { it.readText() }
        assertTrue("no Kotlin sources found — the scan is reading nothing", sources.size >= 10)
        val declared = declaredPermissions()
        val called = permissionGatedApis.filterKeys { re -> sources.any { re.containsMatchIn(it) } }
        // A table whose every entry has stopped matching is a guard asleep,
        // not a clean tree: the calls it names are all still made.
        assertEquals(
            "no permission-gated API matched anywhere under src/main — either " +
                "every call was removed (drop the table entries) or the patterns " +
                "have gone stale",
            permissionGatedApis.size,
            called.size,
        )
        val undeclared = called.values.filterNot { it in declared }.sorted()
        assertEquals(
            "called from src/main but never declared in AndroidManifest.xml, so " +
                "the platform refuses it on every device: $undeclared. The call " +
                "site's catch cannot tell you — it looks like absent hardware.",
            emptyList<String>(),
            undeclared,
        )
    }

    /// Short names, with the Android 16 granular health permissions kept
    /// under their `health.` prefix (`health.READ_HEART_RATE`). Without the
    /// optional group a declared health permission would not parse at all,
    /// and every check in this class would pass it by never seeing it.
    private fun declaredPermissions(): Set<String> =
        Regex("""<uses-permission\s+android:name="android\.permission\.((?:health\.)?[A-Z_0-9]+)"""")
            .findAll(manifest)
            .map { it.groupValues[1] }
            .toSet()

    /// The health permissions are not on `Manifest.permission`: the SDK
    /// constant is `android.health.connect.HealthPermissions.X`, and a call
    /// site may also name the string itself.
    private fun permissionReferences(source: String): Set<String> =
        (
            Regex("""Manifest\.permission\.([A-Z_0-9]+)""").findAll(source)
                .map { it.groupValues[1] } +
                Regex("""HealthPermissions\.([A-Z_0-9]+)""").findAll(source)
                    .map { "health." + it.groupValues[1] } +
                Regex(""""android\.permission\.((?:health\.)?[A-Z_0-9]+)"""").findAll(source)
                    .map { it.groupValues[1] }
            ).toSet()

    private fun requestedPermissions(): Set<String> = permissionReferences(requestSite)

    @Test
    fun `the manifest declares a permission set this guard can read`() {
        // A regex that silently stops matching would make every assertion
        // below pass vacuously.
        val declared = declaredPermissions()
        assertTrue(
            "no <uses-permission> parsed out of the manifest — the guard is " +
                "reading nothing and would pass on anything",
            declared.size >= 8,
        )
        assertTrue(
            "ACCESS_FINE_LOCATION must parse out — it is the one permission " +
                "without which the app has no product",
            "ACCESS_FINE_LOCATION" in declared,
        )
    }

    @Test
    fun `every runtime permission the manifest declares is requested or exempted`() {
        val unaccounted = (declaredPermissions() - installTime - exempt.keys - requestedPermissions())
            .sorted()
        assertEquals(
            "declared in AndroidManifest.xml but never requested at runtime, " +
                "so it can never be granted: $unaccounted. Add it to the " +
                "permissionLauncher.launch array in RunWatchApp.kt, or register " +
                "it in this test's `exempt` map with the reason.",
            emptyList<String>(),
            unaccounted,
        )
    }

    @Test
    fun `the notification permission is requested, and behind the API gate`() {
        // The regression this guard was written for. POST_NOTIFICATIONS did
        // not exist before API 33 and minSdk here is 30, so it is requested
        // conditionally — but the condition must not be what removes it.
        assertTrue(
            "POST_NOTIFICATIONS must be requested — the ongoing-activity " +
                "notification is the runner's route back into a live run",
            "POST_NOTIFICATIONS" in requestedPermissions(),
        )
        assertTrue(
            "the POST_NOTIFICATIONS request must sit behind a TIRAMISU " +
                "version gate (minSdk is 30 and the permission is API 33+)",
            requestSite.contains("Build.VERSION_CODES.TIRAMISU"),
        )
    }

    @Test
    fun `fine location is requested together with coarse`() {
        // ACCESS_COARSE_LOCATION used to be exempted on the theory that
        // asking for it would offer an approximate choice. From Android 12
        // that choice is offered either way, and a FINE request without
        // COARSE is ignored with no dialog, so leaving it out cost every
        // fresh install on Wear OS 4+ the location prompt itself.
        val requested = requestedPermissions()
        assertTrue("ACCESS_FINE_LOCATION must be requested", "ACCESS_FINE_LOCATION" in requested)
        assertTrue(
            "ACCESS_COARSE_LOCATION must be requested alongside FINE — " +
                "Android 12+ ignores a FINE request without it",
            "ACCESS_COARSE_LOCATION" in requested,
        )
    }

    @Test
    fun `no exemption outlives the permission it excuses`() {
        val declared = declaredPermissions()
        val stale = exempt.keys.filter { it !in declared }.sorted()
        assertEquals(
            "exempted from the runtime request but no longer declared in the " +
                "manifest: $stale. Drop the entry — an exemption for a " +
                "permission that does not exist reads as coverage and is none.",
            emptyList<String>(),
            stale,
        )
        val pointless = exempt.keys.filter { it in requestedPermissions() }.sorted()
        assertEquals(
            "exempted from the runtime request AND requested anyway: " +
                "$pointless. One of the two is wrong.",
            emptyList<String>(),
            pointless,
        )
    }

    private fun declaredServiceTypes(): Set<String> {
        val serviceTag = Regex(
            """<service\b[^>]*RunRecordingService[^>]*/>""",
            RegexOption.DOT_MATCHES_ALL,
        ).find(manifest)?.value
            ?: error("Could not find the RunRecordingService <service> element")
        return Regex("""foregroundServiceType="([^"]+)"""")
            .find(serviceTag)?.groupValues?.get(1)
            ?.split('|')?.map { it.trim() }?.toSet()
            ?: error("RunRecordingService declares no foregroundServiceType")
    }

    @Test
    fun `the foreground service enumerates every type its permissions claim`() {
        // FOREGROUND_SERVICE_HEALTH without "health" in foregroundServiceType
        // is a SecurityException the moment the service starts on API 34+,
        // and the service reads heart rate on every run. The two halves live
        // in different elements of the same file and neither implies the
        // other.
        val types = declaredServiceTypes()
        val declared = declaredPermissions()
        val expected = buildSet {
            if ("FOREGROUND_SERVICE_LOCATION" in declared) add("location")
            if ("FOREGROUND_SERVICE_HEALTH" in declared) add("health")
        }
        assertEquals(
            "every FOREGROUND_SERVICE_<TYPE> permission the manifest declares " +
                "must appear in the service's foregroundServiceType, and " +
                "vice versa",
            expected,
            types,
        )
    }

    @Test
    fun `the service starts with every foreground-service type the manifest declares`() {
        // The manifest and `startForeground` are two separate declarations
        // of the same fact and neither implies the other. From API 34 it is
        // the RUNTIME mask that decides whether a service may keep using a
        // while-in-use permission while the app is not visible — so a
        // manifest that says `location|health` while the code passes
        // LOCATION alone buys the app a sensor permission, a
        // FOREGROUND_SERVICE_HEALTH declaration and a Play Data Safety line
        // for a service type it never actually starts as. That was the
        // state here: the manifest half of the 2026-05-30 store-privacy
        // audit landed and the code half did not.
        //
        // Derived from the manifest, not listed: adding a third type
        // tomorrow is covered by this without anyone remembering to.
        val missing = declaredServiceTypes()
            .map { "FOREGROUND_SERVICE_TYPE_" + it.uppercase() }
            .filterNot { serviceSource.contains(it) }
            .sorted()
        assertEquals(
            "declared in the manifest's foregroundServiceType but never " +
                "passed to startForeground in RunRecordingService.kt: " +
                "$missing. Either pass the type or stop declaring it.",
            emptyList<String>(),
            missing,
        )
    }

    @Test
    fun `the health service type is withheld until its prerequisite is granted`() {
        // Passing FOREGROUND_SERVICE_TYPE_HEALTH before BODY_SENSORS or
        // ACTIVITY_RECOGNITION has been granted is refused by the platform,
        // not ignored — and a runner is entitled to decline both and still
        // record a GPS run. So the mask is computed, and the health bit is
        // the conditional half.
        val location = ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION
        val health = ServiceInfo.FOREGROUND_SERVICE_TYPE_HEALTH
        val api34 = Build.VERSION_CODES.UPSIDE_DOWN_CAKE
        // Two distinct non-zero bits, or every equality below holds for
        // any mask at all and the test asserts nothing.
        assertTrue(
            "the platform type constants must be distinct non-zero bits, " +
                "got location=$location health=$health",
            location != 0 && health != 0 && (location and health) == 0,
        )

        assertEquals(
            "both granted-prerequisite and API 34+ must yield location|health",
            location or health,
            RunRecordingService.foregroundServiceTypeMask(api34, true),
        )
        assertEquals(
            "no body-sensor or activity permission means location alone",
            location,
            RunRecordingService.foregroundServiceTypeMask(api34, false),
        )
        assertEquals(
            "the health type does not exist before API 34",
            location,
            RunRecordingService.foregroundServiceTypeMask(api34 - 1, true),
        )
        assertTrue(
            "location is unconditional — it is what the run itself needs",
            (0..2).all { i ->
                val m = RunRecordingService.foregroundServiceTypeMask(
                    api34 - 1 + i,
                    i % 2 == 0,
                )
                m and location == location
            },
        )
    }

    private fun targetSdk(): Int =
        Regex("""\btargetSdk\s*=\s*(\d+)""").find(buildScript)?.groupValues?.get(1)?.toInt()
            ?: error("no `targetSdk = N` in app/build.gradle.kts — the split guard reads nothing")

    /// The permission list `startForegroundCompat` hands `hasAnyPermission`
    /// to decide whether the health service type may be passed.
    private fun healthTypePrerequisites(): Set<String> {
        val start = serviceSource.indexOf("private fun startForegroundCompat")
        assertTrue("startForegroundCompat not found in RunRecordingService.kt", start >= 0)
        val call = Regex("""hasAnyPermission\(([^)]*)\)""")
            .find(serviceSource, start)?.groupValues?.get(1)
            ?: error("startForegroundCompat no longer calls hasAnyPermission(...)")
        return permissionReferences(call)
    }

    /// Every place one heart-rate permission has to be wired, as the list of
    /// places it is NOT. Used for BODY_SENSORS (must be empty, which proves
    /// each probe still reads something) and for READ_HEART_RATE.
    private fun heartRateWiringGaps(permission: String, fullName: String): List<String> =
        buildList {
            if (permission !in declaredPermissions()) {
                add("AndroidManifest.xml does not declare $fullName")
            }
            if (permission !in requestedPermissions()) {
                add("RunWatchApp.kt's permissionLauncher array does not request it")
            }
            val graded = permissionOutcome(
                mapOf(
                    Manifest.permission.ACCESS_FINE_LOCATION to true,
                    fullName to false,
                ),
            )
            if (PermissionCost.HeartRate !in graded.costs) {
                add("permissionOutcome does not grade its denial as PermissionCost.HeartRate")
            }
            if (permission !in healthTypePrerequisites()) {
                add(
                    "startForegroundCompat's hasAnyPermission(...) does not count it " +
                        "toward the health foreground-service type",
                )
            }
        }

    @Test
    fun `heart rate is wired through READ_HEART_RATE before targetSdk reaches 36`() {
        // Measured 2026-11-15 on a Wear OS 6 (API 36) emulator, release
        // build: Health Services' MeasureClient refuses HEART_RATE_BPM with
        // "doesn't have permission to access
        // android.permission.health.READ_HEART_RATE". At targetSdk 35 the
        // platform treats that permission as a split of BODY_SENSORS, so the
        // BODY_SENSORS dialog grants both and heart rate works. From
        // targetSdk 36 the split stops applying: an app that still only
        // asks for BODY_SENSORS gets "No HR" on every Wear OS 6 watch, with
        // nothing failing anywhere. decisions § 2546.
        val sdk = targetSdk()
        assertTrue("targetSdk parsed as $sdk, which cannot be right", sdk in 30..99)

        val probe = heartRateWiringGaps("BODY_SENSORS", Manifest.permission.BODY_SENSORS)
        assertEquals(
            "BODY_SENSORS, which IS wired today, reads as unwired — a probe in " +
                "heartRateWiringGaps has gone stale and the READ_HEART_RATE " +
                "check below would fail or pass for the wrong reason",
            emptyList<String>(),
            probe,
        )

        val gaps = heartRateWiringGaps("health.READ_HEART_RATE", READ_HEART_RATE)
        if (sdk < 36) return
        assertEquals(
            "targetSdk is $sdk. From targetSdk 36 Android 16 no longer treats " +
                "$READ_HEART_RATE as a split of BODY_SENSORS, and Health " +
                "Services' MeasureClient refuses heart rate without it, so a " +
                "BODY_SENSORS-only app records \"No HR\" on Wear OS 6. Wire it " +
                "everywhere BODY_SENSORS is (declare BODY_SENSORS with " +
                "maxSdkVersion=\"35\", request READ_HEART_RATE on API 36+ " +
                "only, add it to docs/compliance/store_declarations.json). " +
                "See decisions § 2546. Missing",
            emptyList<String>(),
            gaps,
        )
    }

    @Test
    fun `the heart-rate split guard can tell a wired permission from an unwired one`() {
        // Below targetSdk 36 the guard above returns before asserting, so
        // nothing would notice if heartRateWiringGaps stopped finding gaps.
        // Until the wiring lands READ_HEART_RATE must read as missing
        // everywhere; once it is wired this collapses to the empty list and
        // the probe above is what keeps the guard honest.
        val gaps = heartRateWiringGaps("health.READ_HEART_RATE", READ_HEART_RATE)
        assertFalse(
            "READ_HEART_RATE is partly wired ($gaps still missing) — finish it " +
                "in the same change, a half-wired permission is the state the " +
                "split guard exists to refuse",
            gaps.isNotEmpty() && gaps.size < 4,
        )
    }

    private companion object {
        /// `android.health.connect.HealthPermissions.READ_HEART_RATE` (API 36);
        /// spelled out so the JVM test needs no API-36 stub.
        const val READ_HEART_RATE = "android.permission.health.READ_HEART_RATE"
    }
}
