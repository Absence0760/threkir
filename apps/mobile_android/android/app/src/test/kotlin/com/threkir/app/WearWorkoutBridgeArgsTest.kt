package com.threkir.app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/// The method-channel seam of [WearWorkoutBridge]: the Data Layer itself needs
/// the GMS runtime, so what a host JVM can pin is which arguments become a
/// DataItem.
class WearWorkoutBridgeArgsTest {

    private val nowMs = 1_700_000_000_000L

    @Test
    fun `null args are refused`() {
        assertNull(parseWearWorkoutPushArgs(null, nowMs))
    }

    @Test
    fun `a missing or blank workout_json is refused rather than defaulted`() {
        assertNull(parseWearWorkoutPushArgs(emptyMap(), nowMs))
        assertNull(parseWearWorkoutPushArgs(mapOf("workout_json" to "  "), nowMs))
        assertNull(parseWearWorkoutPushArgs(mapOf("workout_json" to 7), nowMs))
    }

    @Test
    fun `the json passes through verbatim with its stamp`() {
        val json = """{"v":1,"plan_workout_id":"w-1"}"""
        val parsed = parseWearWorkoutPushArgs(
            mapOf("workout_json" to json, "updated_at_ms" to 42L),
            nowMs,
        )!!
        assertEquals(json, parsed.workoutJson)
        assertEquals(42L, parsed.updatedAtMs)
    }

    @Test
    fun `a missing stamp falls back to now`() {
        val parsed = parseWearWorkoutPushArgs(mapOf("workout_json" to """{"v":1}"""), nowMs)!!
        assertEquals(nowMs, parsed.updatedAtMs)
    }
}
