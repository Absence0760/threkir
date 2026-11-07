package com.runapp.watchwear

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.double
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/// The Kotlin reader of `fixtures/gate_crossing_cases.json`, the case table
/// the `gate_crossing` pairs share with `gate_crossing_test.dart` and web's
/// `gate_crossing.test.ts`. Every section of the file is run here; a section
/// this reader does not know fails the suite rather than going unchecked.
class GateCrossingTest {

    private val root: JsonObject = run {
        val f = WearLocales.findUp("fixtures/gate_crossing_cases.json")
            ?: error("fixtures/gate_crossing_cases.json not found above ${java.io.File(".").absolutePath}")
        Json.parseToJsonElement(f.readText()).jsonObject
    }

    private val sections = listOf("projection", "crossings")
    private val metaKeys = setOf(
        "spec", "reference", "readers", "schema", "constants",
        "t0EpochMs", "distanceToleranceM", "timeToleranceS", "fractionTolerance",
    )

    private val constants = root["constants"]!!.jsonObject
    private val t0 = num(root["t0EpochMs"])
    private val distTol = num(root["distanceToleranceM"])
    private val timeTol = num(root["timeToleranceS"])
    private val fracTol = num(root["fractionTolerance"])
    private val k = num(constants["EARTH_RADIUS_M"]) * Math.PI / 180.0

    private fun cases(section: String): List<JsonObject> =
        root[section]!!.jsonArray.map { it.jsonObject }

    private fun JsonObject.name(): String = this["name"]!!.jsonPrimitive.content

    /// A number-or-special field: a JSON number, or "NaN" / "Infinity" /
    /// "-Infinity".
    private fun num(el: JsonElement?): Double {
        val p = el as? JsonPrimitive ?: error("expected a number, got $el")
        if (!p.isString) return p.double
        return when (p.content) {
            "NaN" -> Double.NaN
            "Infinity" -> Double.POSITIVE_INFINITY
            "-Infinity" -> Double.NEGATIVE_INFINITY
            else -> error("not a number-or-special: ${p.content}")
        }
    }

    /// A nullable field must be present; a missing key is not a null.
    private fun JsonObject.req(key: String): JsonElement =
        this[key] ?: error("case ${this["name"]} has no '$key' (nullable fields are explicit)")

    private fun gateOf(o: JsonObject) = Gate(
        lat = num(o["lat"]),
        lng = num(o["lng"]),
        bearingDeg = num(o["bearingDeg"]),
        halfWidthM = num(o["halfWidthM"]),
    )

    private fun positionOf(gate: Gate, o: JsonObject): Pair<Double, Double> =
        if ("lat" in o) {
            num(o["lat"]) to num(o["lng"])
        } else {
            (gate.lat + num(o["northM"]) / k) to
                (gate.lng + num(o["eastM"]) / (k * Math.cos(gate.lat * Math.PI / 180.0)))
        }

    private fun fixOf(gate: Gate, o: JsonObject): GateFix {
        val (lat, lng) = positionOf(gate, o)
        return GateFix(lat = lat, lng = lng, tMs = t0 + num(o["atS"]) * 1000.0, coveredM = num(o["coveredM"]))
    }

    private fun optionsOf(el: JsonElement): GateCrossingOptions {
        if (el is JsonNull) return GateCrossingOptions()
        val o = el.jsonObject
        return GateCrossingOptions(
            maxGapS = num(o["maxGapS"]),
            maxHopM = num(o["maxHopM"]),
            rejectGapS = num(o["rejectGapS"]),
        )
    }

    private fun assertCrossing(where: String, e: JsonObject, actual: GateCrossing) {
        assertEquals("$where direction", e["direction"]!!.jsonPrimitive.content, actual.direction.name.lowercase())
        assertEquals("$where gapped", e["gapped"]!!.jsonPrimitive.boolean, actual.gapped)
        assertEquals("$where fraction", num(e["fraction"]), actual.fraction, fracTol)
        assertEquals("$where atS", num(e["atS"]), (actual.tMs - t0) / 1000.0, timeTol)
        assertEquals("$where coveredM", num(e["coveredM"]), actual.coveredM, distTol)
        assertEquals("$where offsetM", num(e["offsetM"]), actual.offsetM, distTol)
    }

    // ───────────── the file itself ─────────────

    @Test
    fun `every section in the file is one this reader runs`() {
        val unknown = root.keys - metaKeys - sections.toSet()
        assertTrue("unknown section(s) in gate_crossing_cases.json: $unknown", unknown.isEmpty())
        val schemaSections = root["schema"]!!.jsonObject.keys - setOf("general", "constants", "gate", "position")
        assertEquals(sections.toSet(), schemaSections)
        for (s in sections) assertTrue("section $s is empty", cases(s).isNotEmpty())
    }

    @Test
    fun `the constants match the file`() {
        assertEquals(num(constants["EARTH_RADIUS_M"]), GATE_EARTH_RADIUS_M, 0.0)
        assertEquals(num(constants["MAX_GAP_S"]), GATE_MAX_GAP_S, 0.0)
        assertEquals(num(constants["MAX_HOP_M"]), GATE_MAX_HOP_M, 0.0)
        assertEquals(num(constants["REJECT_GAP_S"]), GATE_REJECT_GAP_S, 0.0)
        assertEquals(num(constants["HALF_WIDTH_RACE_M"]), GATE_HALF_WIDTH_RACE_M, 0.0)
        assertEquals(num(constants["HALF_WIDTH_SEGMENT_M"]), GATE_HALF_WIDTH_SEGMENT_M, 0.0)
    }

    // ───────────── sections ─────────────

    @Test
    fun projection() {
        for (c in cases("projection")) {
            val gate = gateOf(c["gate"]!!.jsonObject)
            val (lat, lng) = positionOf(gate, c["point"]!!.jsonObject)
            val got = gateProjection(gate, lat, lng)
            val e = c["expect"]!!.jsonObject
            assertEquals("${c.name()}: s", num(e["s"]), got.s, distTol)
            assertEquals("${c.name()}: u", num(e["u"]), got.u, distTol)
        }
    }

    @Test
    fun crossings() {
        for (c in cases("crossings")) {
            val name = c.name()
            val gate = gateOf(c["gate"]!!.jsonObject)
            val options = optionsOf(c.req("options"))
            val fixes = c["fixes"]!!.jsonArray.map { fixOf(gate, it.jsonObject) }
            val expected = c["expect"]!!.jsonArray.map { it.jsonObject }

            val detector = GateCrossingDetector(gate, options)
            for ((i, fix) in fixes.withIndex()) {
                val got = detector.offer(fix)
                val e = expected.firstOrNull { it["afterFix"]!!.jsonPrimitive.int == i }
                if (e == null) {
                    assertNull("$name: offer(fixes[$i]) should be null", got)
                } else {
                    assertNotNull("$name: offer(fixes[$i]) should return a crossing", got)
                    assertCrossing("$name: offer(fixes[$i])", e, got!!)
                }
            }

            val settled = detector.settle()
            assertEquals("$name: settle() count", expected.size, settled.size)
            for ((i, x) in settled.withIndex()) assertCrossing("$name: settle()[$i]", expected[i], x)

            val after = c.req("fixesAfterSettle")
            if (after !is JsonNull) {
                for (f in after.jsonArray) {
                    assertNull("$name: offer after settle", detector.offer(fixOf(gate, f.jsonObject)))
                }
            }
            assertEquals("$name: settle() unchanged", expected.size, detector.settle().size)

            val batch = crossingsOf(fixes, gate, options)
            assertEquals("$name: crossingsOf count", expected.size, batch.size)
            for ((i, x) in batch.withIndex()) assertCrossing("$name: crossingsOf[$i]", expected[i], x)
        }
    }
}
