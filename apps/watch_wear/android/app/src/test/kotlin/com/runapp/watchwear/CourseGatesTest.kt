package com.runapp.watchwear

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.double
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.abs
import kotlin.math.min

/// The Kotlin reader of the box sections of `fixtures/course_gates_cases.json`,
/// the case table the `course_gates` pair shares with
/// `course_gates_test.dart` and web's `course_gates.test.ts`. A one-way port:
/// only the sections the live course timer reads ([PORTED]) are run here.
class CourseGatesTest {

    private val root: JsonObject = run {
        val f = WearLocales.findUp("fixtures/course_gates_cases.json")
            ?: error("fixtures/course_gates_cases.json not found")
        Json.parseToJsonElement(f.readText()).jsonObject
    }
    private val degTol = num(root["degreeTolerance"])
    private val bearingTol = num(root["bearingTolerance"])

    private fun num(el: JsonElement?): Double {
        val p = el as? JsonPrimitive ?: error("expected a number, got $el")
        return if (p.isString && p.content == "NaN") Double.NaN else p.double
    }

    private fun cases(section: String): List<JsonObject> = root[section]!!.jsonArray.map { it.jsonObject }
    private fun JsonObject.note(): String = this["note"]!!.jsonPrimitive.content

    private fun gate(el: JsonElement?): Gate? {
        if (el == null || el is JsonNull) return null
        val o = el.jsonObject
        return Gate(num(o["lat"]), num(o["lng"]), num(o["bearingDeg"]), num(o["halfWidthM"]))
    }

    private fun nearPoint(actual: GatePoint, expected: JsonElement, what: String) {
        val e = expected.jsonObject
        assertTrue("$what lat ${actual.lat}", abs(actual.lat - num(e["lat"])) <= degTol)
        assertTrue("$what lng ${actual.lng}", abs(actual.lng - num(e["lng"])) <= degTol)
    }

    private fun nearPoints(actual: List<GatePoint>, expected: JsonElement, what: String) {
        val e = expected.jsonArray
        assertEquals("$what: point count", e.size, actual.size)
        for (i in actual.indices) nearPoint(actual[i], e[i], "$what [$i]")
    }

    private fun nearGate(actual: Gate, expected: JsonElement, what: String) {
        val e = gate(expected)!!
        assertTrue("$what lat", abs(actual.lat - e.lat) <= degTol)
        assertTrue("$what lng", abs(actual.lng - e.lng) <= degTol)
        val d = abs(actual.bearingDeg - e.bearingDeg)
        assertTrue("$what bearing ${actual.bearingDeg} vs ${e.bearingDeg}", min(d, 360 - d) <= bearingTol)
        assertEquals("$what half-width", e.halfWidthM, actual.halfWidthM, 1e-9)
    }

    private fun whichName(w: GateWhich?) = w?.name?.lowercase() ?: "both"

    @Test
    fun `the ported sections are present and the spec is the one ported`() {
        assertEquals("course_gates v1", root["spec"]!!.jsonPrimitive.content)
        for (s in PORTED) assertTrue("section $s is empty", cases(s).isNotEmpty())
    }

    @Test
    fun `constants match the case table`() {
        val c = root["constants"]!!.jsonObject
        assertEquals(num(c["boxDepthM"]), COURSE_GATE_BOX_DEPTH_M, 0.0)
        assertEquals(num(c["sharedSpotM"]), COURSE_GATE_SHARED_SPOT_M, 0.0)
        assertEquals(num(c["sharedSpotDeg"]), COURSE_GATE_SHARED_SPOT_DEG, 0.0)
    }

    @Test
    fun normalizeBearing() {
        for (c in cases("normalizeBearing")) {
            val want = num(c["out"])
            val got = normalizeBearing(num(c["in"]))
            if (want.isNaN()) assertTrue(c.note(), got.isNaN()) else assertEquals(c.note(), want, got, 0.0)
        }
    }

    @Test
    fun gateBox() {
        for (c in cases("boxCorners")) {
            val got = gateBox(
                gate(c["gate"])!!,
                num(c["depthM"]),
                GateBoxSide.valueOf(c["side"]!!.jsonPrimitive.content.uppercase()),
                from = num(c["from"]),
                to = num(c["to"]),
            )
            nearPoints(got, c["corners"]!!, c.note())
        }
    }

    @Test
    fun gatesShareSpot() {
        for (c in cases("sharedSpot")) {
            assertEquals(c.note(), c["shared"]!!.jsonPrimitive.boolean, gatesShareSpot(gate(c["start"])!!, gate(c["finish"])!!))
        }
    }

    @Test
    fun gateBoxParts() {
        for (c in cases("boxParts")) {
            val got = gateBoxParts(gate(c["start"]), gate(c["finish"]), num(c["depthM"]))
            val note = c.note()
            assertEquals("$note layout", c["layout"]!!.jsonPrimitive.content, got.layout.name.lowercase())
            val parts = c["parts"]!!.jsonArray.map { it.jsonObject }
            assertEquals("$note part count", parts.size, got.parts.size)
            for ((i, w) in parts.withIndex()) {
                val p = got.parts[i]
                assertEquals("$note [$i] which", w["which"]!!.jsonPrimitive.content, whichName(p.which))
                nearPoints(p.box, w["box"]!!, "$note [$i] box")
                nearPoints(listOf(p.line.first, p.line.second), w["line"]!!, "$note [$i] line")
            }
            val marks = c["markers"]!!.jsonArray.map { it.jsonObject }
            assertEquals("$note marker count", marks.size, got.markers.size)
            for ((i, m) in marks.withIndex()) {
                assertEquals("$note marker [$i] which", m["which"]!!.jsonPrimitive.content, whichName(got.markers[i].which))
                nearPoint(got.markers[i].at, m["at"]!!, "$note marker [$i]")
            }
        }
    }

    @Test
    fun gateTimingEdges() {
        for (c in cases("timingEdges")) {
            val got = gateTimingEdges(gate(c["start"])!!, gate(c["finish"])!!, num(c["depthM"]))
            val note = c.note()
            assertEquals("$note layout", c["layout"]!!.jsonPrimitive.content, got.layout.name.lowercase())
            assertEquals("$note depth", num(c["depthM"]), got.depthM, 0.0)
            nearGate(got.startExit, c["startExit"]!!, "$note startExit")
            nearGate(got.finishEntry, c["finishEntry"]!!, "$note finishEntry")
        }
    }

    private companion object {
        val PORTED = listOf("normalizeBearing", "boxCorners", "sharedSpot", "boxParts", "timingEdges")
    }
}
