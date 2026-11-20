package com.runapp.watchwear

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/// The Wearable Data Layer contracts, read off BOTH rails and compared.
///
/// The phone writes a `DataItem` at a path with a set of `DataMap` keys; the
/// watch listens at a path and reads a set of keys. Neither side can see the
/// other, and a mismatch produces no error anywhere in either process — the
/// listener simply never fires for a renamed path, and a renamed key reads as
/// absent. What the runner sees is that starring a route on the phone stops
/// reaching the wrist, or that the watch never signs in, with nothing to
/// attribute it to.
///
/// What guarded this before was a hardcoded literal in
/// `RoutesBridgeWiringTest` — `assertTrue(src.contains("/saved_routes"))` —
/// under a comment reading "must match the phone-side WearRoutesBridge.kt
/// PATH". That is an instruction, not an enforcement, and it is the exact
/// shape `scripts/check_watch_wire_vectors.mjs` exists to replace on the
/// firmware rails (`decisions.md § 641`):
/// rename the path on the phone and this suite stays green while the feature
/// is dead. The session bridge had no such assertion at all, on either side.
///
/// So both halves are READ. A key or path either rail declares and the other
/// does not is a failure, in both directions — a key the watch reads and the
/// phone never writes is the same defect seen from the other end, and reads at
/// runtime as a field that is permanently absent.
class DataLayerContractTest {

    private fun repoFile(rel: String): File =
        WearLocales.findUp(rel) ?: error("could not locate $rel from the test working dir")

    private fun watchSource(name: String): String =
        File("src/main/kotlin/com/runapp/watchwear/$name").readText()

    private val phoneAuth: String by lazy {
        repoFile(
            "apps/mobile_android/android/app/src/main/kotlin/com/threkir/app/WearAuthBridge.kt",
        ).readText()
    }

    private val phoneRoutes: String by lazy {
        repoFile(
            "apps/mobile_android/android/app/src/main/kotlin/com/threkir/app/WearRoutesBridge.kt",
        ).readText()
    }

    private val phoneWorkout: String by lazy {
        repoFile(
            "apps/mobile_android/android/app/src/main/kotlin/com/threkir/app/WearWorkoutBridge.kt",
        ).readText()
    }

    private val phoneParkCourses: String by lazy {
        repoFile(
            "apps/mobile_android/android/app/src/main/kotlin/com/threkir/app/WearParkCoursesBridge.kt",
        ).readText()
    }

    /// `const val PATH = "/x"` on either rail.
    private fun pathConst(src: String, where: String): String =
        Regex("""const val PATH = "([^"]+)"""").find(src)?.groupValues?.get(1)
            ?: error("no `const val PATH` in $where")

    /// `dataMap.putString("k", …)` / `putLong` / `putInt` — what the phone writes.
    private fun writtenKeys(src: String): Set<String> =
        Regex("""dataMap\.put\w+\("([^"]+)"""").findAll(src).map { it.groupValues[1] }.toSet()

    /// `dm.getString("k")` / `getLong` — what the watch reads. A key named
    /// by a `const val KEY_X = "k"` (as `ParkCourseBridge` names its three)
    /// is resolved to its string, so a constant cannot hide a key from the
    /// comparison; one that resolves to nothing fails rather than vanishing.
    private fun readKeys(src: String): Set<String> {
        val consts = Regex("""const val (\w+) = "([^"]+)"""").findAll(src)
            .associate { it.groupValues[1] to it.groupValues[2] }
        val literal = Regex("""\bdm\.get\w+\("([^"]+)"""").findAll(src).map { it.groupValues[1] }
        val named = Regex("""\bdm\.(?:get|containsKey)\w*\((\w+)\)""").findAll(src).map {
            val name = it.groupValues[1]
            consts[name] ?: error("watch reads DataMap key `$name`, which is no `const val` string")
        }
        return (literal + named).toSet()
    }

    private fun assertKeysAgree(written: Set<String>, read: Set<String>, contract: String) {
        assertTrue(
            "$contract: no DataMap keys parsed off the phone writer — the " +
                "comparison below would pass vacuously",
            written.isNotEmpty(),
        )
        assertEquals(
            "$contract: the phone writes these DataMap keys and the watch " +
                "reads none of them — a renamed key reads as absent, with no " +
                "error on either side",
            written.sorted(),
            read.sorted(),
        )
    }

    @Test
    fun `the session bridge path is the same string on both rails`() {
        assertEquals(
            "phone WearAuthBridge.PATH and watch SessionPayload.PATH must be " +
                "identical — a mismatch means the watch's listener never fires " +
                "and the wrist is never signed in",
            pathConst(phoneAuth, "phone WearAuthBridge.kt"),
            pathConst(watchSource("SessionBridge.kt"), "watch SessionBridge.kt"),
        )
    }

    @Test
    fun `the session bridge writes and reads the same DataMap keys`() {
        assertKeysAgree(
            written = writtenKeys(phoneAuth),
            read = readKeys(watchSource("SessionBridge.kt")),
            contract = "/supabase_session",
        )
    }

    @Test
    fun `the routes bridge path is the same string on both rails`() {
        assertEquals(
            "phone WearRoutesBridge.PATH and watch RoutesBridge.PATH must be " +
                "identical — a mismatch means every starred-route push lands " +
                "in the Data Layer graph and is read by nobody",
            pathConst(phoneRoutes, "phone WearRoutesBridge.kt"),
            pathConst(watchSource("RoutesBridge.kt"), "watch RoutesBridge.kt"),
        )
    }

    @Test
    fun `the routes bridge writes and reads the same DataMap keys`() {
        assertKeysAgree(
            written = writtenKeys(phoneRoutes),
            read = readKeys(watchSource("RoutesBridge.kt")),
            contract = "/saved_routes",
        )
    }

    @Test
    fun `the workout bridge path is the same string on both rails`() {
        assertEquals(
            "phone WearWorkoutBridge.PATH and watch WorkoutBridge.PATH must be " +
                "identical — a mismatch means today's workout reaches the graph " +
                "and never the pre-run screen",
            pathConst(phoneWorkout, "phone WearWorkoutBridge.kt"),
            pathConst(watchSource("WorkoutBridge.kt"), "watch WorkoutBridge.kt"),
        )
    }

    @Test
    fun `the workout bridge writes and reads the same DataMap keys`() {
        assertKeysAgree(
            written = writtenKeys(phoneWorkout),
            read = readKeys(watchSource("WorkoutBridge.kt")),
            contract = "/todays_workout",
        )
    }

    @Test
    fun `the park courses bridge path is the same string on both rails`() {
        assertEquals(
            "phone WearParkCoursesBridge.PATH and watch ParkCourseBridge.PATH " +
                "must be identical — a mismatch means a navigated course reaches " +
                "the graph and never the route picker",
            pathConst(phoneParkCourses, "phone WearParkCoursesBridge.kt"),
            pathConst(watchSource("ParkCourseBridge.kt"), "watch ParkCourseBridge.kt"),
        )
    }

    @Test
    fun `the park courses bridge writes and reads the same DataMap keys`() {
        assertKeysAgree(
            written = writtenKeys(phoneParkCourses),
            read = readKeys(watchSource("ParkCourseBridge.kt")),
            contract = "/park_courses",
        )
    }

    @Test
    fun `the park courses payload version is the one the watch reads`() {
        // The watch drops any other version whole (never as "no courses"),
        // so a phone that bumped its number alone would go silent.
        val phone = Regex("""const val PAYLOAD_VERSION = (\d+)""")
            .find(phoneParkCourses)?.groupValues?.get(1)?.toInt()
            ?: error("no `const val PAYLOAD_VERSION` in phone WearParkCoursesBridge.kt")
        assertEquals(PARK_COURSES_PAYLOAD_VERSION, phone)
    }

    @Test
    fun `the phone's session parser requires every field the watch reads`() {
        // The phone refuses a push missing any field
        // (`parseWearAuthPushArgs` → `bad_args`) and the watch refuses one
        // whose fields are blank (§ 879). Those are two guards over one field
        // list, written in two files, and a field added to the wire on one
        // side only would be validated by neither.
        val phoneFields = Regex("""args\["([^"]+)"\]""")
            .findAll(phoneAuth).map { it.groupValues[1] }.toSet()
        assertEquals(
            "every field the phone's method-channel parser validates must be " +
                "a DataMap key it then writes",
            phoneFields.sorted(),
            writtenKeys(phoneAuth).sorted(),
        )
    }
}
