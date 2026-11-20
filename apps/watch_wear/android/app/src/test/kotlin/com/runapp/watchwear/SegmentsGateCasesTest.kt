package com.runapp.watchwear

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.double
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.long
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant
import kotlin.math.abs

/// The live course timer against `fixtures/segments_gate_cases.json`, the
/// `segments` pair's catalogue matcher cases (box rule § 2589) that web, the
/// phone and the Apple Watch (`CourseBoxTimerTests`) replay: each box case
/// streamed fix by fix and settled, giving the batch matcher's effort to the
/// millisecond. `park_course_runs.json` (`LiveCourseTimerTest`) holds the
/// timer to realistic runs; this table holds it to the rule's edges — the
/// interpolated line, the slack at either end, the finish gap, laps, the
/// shared box, checkpoints and off-track fixes.
class SegmentsGateCasesTest {

    private val root: JsonObject = run {
        val f = WearLocales.findUp("fixtures/segments_gate_cases.json")
            ?: error("fixtures/segments_gate_cases.json not found")
        Json.parseToJsonElement(f.readText()).jsonObject
    }
    private val baseMs = Instant.parse(root["base_time"]!!.jsonPrimitive.content).toEpochMilli()

    private fun gate(e: JsonElement?): Gate? {
        val o = (e as? JsonObject) ?: return null
        return Gate(
            lat = o["lat"]!!.jsonPrimitive.double,
            lng = o["lng"]!!.jsonPrimitive.double,
            bearingDeg = o["bearing_deg"]!!.jsonPrimitive.double,
            halfWidthM = o["half_width_m"]!!.jsonPrimitive.double,
        )
    }

    @Test
    fun `every box case gives the matcher's effort, and a case without both lines is not timed`() {
        var boxCases = 0
        for (c in root["cases"]!!.jsonArray.map { it.jsonObject }) {
            val name = c["name"]!!.jsonPrimitive.content
            val segment = c["segment"]!!.jsonObject
            val expect = c["expect"]?.takeUnless { it is JsonNull }?.jsonObject
            val start = gate(segment["start_gate"])
            val end = gate(segment["end_gate"])
            if (start == null || end == null) {
                // The server times these by its circles, which the wrist
                // never follows (the circle rule is not ported).
                assertEquals(name, "zone", expect?.get("matched_by")?.jsonPrimitive?.content)
                continue
            }
            boxCases++
            val timer = LiveCourseTimer(
                CourseTimingSpec(
                    distanceM = segment["distance_m"]!!.jsonPrimitive.double,
                    startGate = start,
                    endGate = end,
                    checkpoints = segment["checkpoints"]?.jsonArray?.map {
                        val p = it.jsonObject
                        GatePoint(p["lat"]!!.jsonPrimitive.double, p["lng"]!!.jsonPrimitive.double)
                    } ?: emptyList(),
                ),
            )
            assertTrue(name, timer.usable)
            // The server's `trackLine`: an off-track fix is never stored for
            // the timer (`CourseFixFeed` carries line fixes only).
            val events = mutableListOf<CourseEvent>()
            for (f in c["track"]!!.jsonArray.map { it.jsonObject }) {
                if (f["off_track"]?.jsonPrimitive?.booleanOrNull == true) continue
                val tMs = baseMs + Math.round(f["t"]!!.jsonPrimitive.double * 1000)
                events += timer.offer(f["lat"]!!.jsonPrimitive.double, f["lng"]!!.jsonPrimitive.double, tMs.toDouble())
            }
            timer.settle()?.let { events.add(it) }

            if (expect == null) {
                assertNull("$name: timed ${timer.best?.elapsedS} s", timer.best)
                assertTrue("$name: said Finished!", events.none { it is CourseEvent.Finished })
                continue
            }
            assertEquals(name, "gate", expect["matched_by"]!!.jsonPrimitive.content)
            val best = timer.best
            assertNotNull("$name: no effort", best)
            val want = expect["time_seconds"]!!.jsonPrimitive.double
            assertTrue("$name: ${best!!.elapsedS} s against $want s", abs(best.elapsedS - want) < 0.001)
            assertEquals(name, expect["started_offset_ms"]!!.jsonPrimitive.long, Math.round(best.startMs) - baseMs)
            val said = events.filterIsInstance<CourseEvent.Finished>().minOf { it.elapsedS }
            assertTrue("$name: the fastest Finished! said is the effort", abs(said - want) < 0.001)
            assertTrue("$name: timing starts before it finishes", events.first() is CourseEvent.Started)
        }
        assertEquals("every box case in the table is replayed", 23, boxCases)
    }
}
