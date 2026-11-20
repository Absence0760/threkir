package com.threkir.app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/// The method-channel seam of [WearParkCoursesBridge]: the Data Layer itself
/// needs the GMS runtime, so what a host JVM can pin is which arguments
/// become a DataItem.
class WearParkCoursesBridgeArgsTest {

    private val nowMs = 1_700_000_000_000L

    @Test
    fun `null args are refused`() {
        assertNull(parseWearParkCoursesPushArgs(null, nowMs))
    }

    @Test
    fun `a missing or non-array courses_json is refused rather than defaulted`() {
        assertNull(parseWearParkCoursesPushArgs(emptyMap(), nowMs))
        assertNull(parseWearParkCoursesPushArgs(mapOf("courses_json" to "  "), nowMs))
        assertNull(parseWearParkCoursesPushArgs(mapOf("courses_json" to 7), nowMs))
        assertNull(parseWearParkCoursesPushArgs(mapOf("courses_json" to """{"courses":[]}"""), nowMs))
    }

    @Test
    fun `an empty array passes through, because it clears the wrist`() {
        val parsed = parseWearParkCoursesPushArgs(mapOf("courses_json" to "[]"), nowMs)!!
        assertEquals("[]", parsed.coursesJson)
    }

    @Test
    fun `the json passes through verbatim with its stamp`() {
        val json = """[{"id":"c1"}]"""
        val parsed = parseWearParkCoursesPushArgs(
            mapOf("courses_json" to json, "updated_at_ms" to 42L),
            nowMs,
        )!!
        assertEquals(json, parsed.coursesJson)
        assertEquals(42L, parsed.updatedAtMs)
    }

    @Test
    fun `a missing stamp falls back to now`() {
        val parsed = parseWearParkCoursesPushArgs(mapOf("courses_json" to "[]"), nowMs)!!
        assertEquals(nowMs, parsed.updatedAtMs)
    }
}
