package com.runapp.watchwear.recording

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.double
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/// Holds the port to the phone's summariser through the shared vectors
/// (`fixtures/gnss_signal_vectors.json`), which the Dart suite
/// `packages/run_recorder/test/gnss_signal_quality_test.dart` also replays.
class GnssSignalQualityTest {

    private val fixture: JsonObject = run {
        val f = File("../../../../fixtures/gnss_signal_vectors.json")
        Json.parseToJsonElement(f.readText()).jsonObject
    }

    private fun JsonObject.num(key: String): Double? =
        this[key]?.takeIf { it !is JsonNull }?.jsonPrimitive?.doubleOrNull

    private fun doubles(o: JsonObject, key: String): DoubleArray =
        o[key]!!.jsonArray.map { it.jsonPrimitive.double }.toDoubleArray()

    @Test
    fun `every sample case reduces the used satellites as the phone does`() {
        val cases = fixture["sampleCases"]!!.jsonArray
        assertTrue(cases.isNotEmpty())
        for (el in cases) {
            val c = el.jsonObject
            val name = c["name"]!!.jsonPrimitive.content
            val want = c["expect"]!!.jsonObject
            val got = gnssStatusSample(doubles(c, "cn0DbHz"), doubles(c, "carrierHz"))
            assertEquals(name, want.num("meanTopCn0DbHz"), got.meanTopCn0DbHz)
            assertEquals(name, want["usedInFix"]!!.jsonPrimitive.int, got.usedInFix)
            assertEquals(name, want["l5Used"]!!.jsonPrimitive.boolean, got.l5Used)
        }
    }

    @Test
    fun `every summary case matches the phone's metadata object`() {
        val cases = fixture["summaryCases"]!!.jsonArray
        assertTrue(cases.isNotEmpty())
        for (el in cases) {
            val c = el.jsonObject
            val name = c["name"]!!.jsonPrimitive.content
            val acc = GnssSignalAccumulator()
            for (s in c["samples"]!!.jsonArray) {
                val o = s.jsonObject
                acc.add(
                    GnssStatusSample(
                        meanTopCn0DbHz = o.num("meanTopCn0DbHz"),
                        usedInFix = o["usedInFix"]!!.jsonPrimitive.int,
                        l5Used = o["l5Used"]!!.jsonPrimitive.boolean,
                    )
                )
            }
            val want = c["expect"]
            val got = acc.summary()?.toJson()
            if (want == null || want is JsonNull) {
                assertNull(name, got)
                continue
            }
            val w = want.jsonObject
            assertEquals(name, w.keys, got!!.keys)
            for (k in w.keys) {
                assertEquals("$name: $k", w.num(k)!!, got.num(k)!!, 0.0)
            }
        }
    }

    @Test
    fun `a non-finite C N0 is used but not averaged`() {
        val s = gnssStatusSample(doubleArrayOf(Double.NaN, 30.0, 34.0), doubleArrayOf(Double.NaN, 0.0, 0.0))
        assertEquals(3, s.usedInFix)
        assertEquals(32.0, s.meanTopCn0DbHz!!, 0.0)
        assertFalse(s.l5Used)
    }
}
