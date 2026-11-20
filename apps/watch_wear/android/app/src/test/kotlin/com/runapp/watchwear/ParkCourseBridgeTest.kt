package com.runapp.watchwear

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/// The watch's reader of `fixtures/wear_park_courses_payload.json`, the
/// `/park_courses` contract the phone's writer will be held to (decisions
/// § 2595): which courses the watch keeps, which it refuses whole, and which
/// deliveries it ignores rather than reading as "no courses".
class ParkCourseBridgeTest {

    private val root: JsonObject = run {
        val f = WearLocales.findUp("fixtures/wear_park_courses_payload.json")
            ?: error("fixtures/wear_park_courses_payload.json not found")
        Json.parseToJsonElement(f.readText()).jsonObject
    }
    private val json = Json { ignoreUnknownKeys = true }

    private fun section(name: String) = root[name]!!.jsonArray.map { it.jsonObject }
    private fun JsonObject.name() = this["name"]!!.jsonPrimitive.content

    private fun withRepeat(c: JsonObject): JsonObject {
        val course = c["course"]!!.jsonObject
        val repeat = c["repeat"]?.jsonObject ?: return course
        val field = repeat["field"]!!.jsonPrimitive.content
        val copies = JsonArray(List(repeat["count"]!!.jsonPrimitive.int) { repeat["point"]!! })
        return JsonObject(course + (field to copies))
    }

    private fun coursesOf(c: JsonObject): JsonArray {
        val listed = c["courses_json"]!!.jsonArray
        val rep = c["repeat_course"]?.jsonObject ?: return listed
        val base = rep["course"]!!.jsonObject
        val baseId = base["id"]!!.jsonPrimitive.content
        val extra = List(rep["count"]!!.jsonPrimitive.int) { i -> JsonObject(base + ("id" to JsonPrimitive("$baseId$i"))) }
        return JsonArray(listed + extra)
    }

    @Test
    fun `the spec and version are the ones this reader implements`() {
        assertEquals("wear_park_courses v1", root["spec"]!!.jsonPrimitive.content)
        assertEquals(1, PARK_COURSES_PAYLOAD_VERSION)
        assertEquals("/park_courses", ParkCourseBridge.PATH)
    }

    @Test
    fun `every case keeps the courses it names, in order`() {
        for (c in section("cases")) {
            val got = parseParkCoursesJson(json, coursesOf(c).toString())
            assertNotNull(c.name(), got)
            val want = c["expected"]!!.jsonArray.map { it.jsonPrimitive.content }
            assertEquals(c.name(), want, got!!.map { it.id })
        }
    }

    @Test
    fun `a kept course carries what the timer and the picker need`() {
        val course = section("cases")[0]["courses_json"]!!.jsonArray[0].jsonObject
        val parsed = parseParkCourse(course)!!
        assertEquals(course["distance_m"]!!.jsonPrimitive.content.toDouble(), parsed.timing.distanceM, 0.0)
        assertEquals(course["checkpoints"]!!.jsonArray.size, parsed.timing.checkpoints.size)
        assertTrue(LiveCourseTimer(parsed.timing).usable)
        val row = parsed.asRoute()
        assertEquals(parsed.id, row.courseId)
        assertTrue(row.id.startsWith(ParkCourse.ROUTE_ID_PREFIX))
        assertEquals(parsed.waypoints, row.waypoints)
    }

    @Test
    fun `every rejected course is refused whole`() {
        for (c in section("rejected_courses")) {
            assertNull(c.name(), parseParkCourse(withRepeat(c)))
        }
    }

    @Test
    fun `every dropped payload is ignored, never read as no courses`() {
        for (c in section("dropped_payloads")) {
            val v = c["payload_version"]
            val version = if (v == null || v is JsonNull) null else v.jsonPrimitive.int
            val raw = c["courses_json"]!!.let { el ->
                if (el is JsonPrimitive && el.isString) el.content else el.toString()
            }
            assertNull(c.name(), ParkCourseBridge.parseParkCoursesPush(version, raw, 1L))
        }
        assertNotNull(ParkCourseBridge.parseParkCoursesPush(1, "[]", 1L))
    }

    @Test
    fun `an older delivery never rolls the courses back`() {
        assertTrue(shouldApplyParkCoursesPush(0L, 5L))
        assertTrue(!shouldApplyParkCoursesPush(5L, 4L))
        assertTrue(!shouldApplyParkCoursesPush(5L, 5L))
    }
}
