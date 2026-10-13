package com.runapp.watchwear

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.double
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.long
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/// The Kotlin half of the `race_finish` parity pair, held to the shared case
/// table `fixtures/race_finish_cases.json` that `race_finish_test.dart` reads
/// too. Every section of the file is run here; a section this reader does not
/// know fails the suite rather than going unchecked, because a section one
/// side skips is a rule that side no longer has to keep.
class RaceFinishTest {

    private val root: JsonObject = run {
        val f = WearLocales.findUp("fixtures/race_finish_cases.json")
            ?: error("fixtures/race_finish_cases.json not found above ${java.io.File(".").absolutePath}")
        Json.parseToJsonElement(f.readText()).jsonObject
    }

    private val sections = listOf(
        "distance", "zone", "coverage", "detector", "startFlag",
        "clockOffset", "gunTime", "chipTime", "stopOutcome", "resultTiming",
    )
    private val metaKeys = setOf(
        "spec", "reference", "readers", "schema", "constants",
        "t0EpochMs", "distanceToleranceM", "offsetToleranceMs", "origin",
    )

    private val t0 = root["t0EpochMs"]!!.jsonPrimitive.long
    private val distTol = root["distanceToleranceM"]!!.jsonPrimitive.double
    private val offsetTol = root["offsetToleranceMs"]!!.jsonPrimitive.double
    private val origin = root["origin"]!!.jsonObject
    private val finishLat = origin["finishLat"]!!.jsonPrimitive.double
    private val finishLng = origin["finishLng"]!!.jsonPrimitive.double

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

    private fun JsonObject.numOrNull(key: String): Double? =
        req(key).let { if (it is JsonNull) null else num(it) }

    private fun JsonObject.longOrNull(key: String): Long? =
        req(key).let { if (it is JsonNull) null else it.jsonPrimitive.long }

    private fun JsonObject.intOrNull(key: String): Int? =
        req(key).let { if (it is JsonNull) null else it.jsonPrimitive.int }

    private fun JsonObject.objOrNull(key: String): JsonObject? =
        req(key).let { if (it is JsonNull) null else it.jsonObject }

    private val metresPerDegLat = RaceFinish.EARTH_RADIUS_M * Math.PI / 180.0

    private fun fixOf(o: JsonObject) = RaceFinish.Fix(
        lat = finishLat + num(o["northM"]) / metresPerDegLat,
        lng = finishLng,
        epochMs = t0 + o["atS"]!!.jsonPrimitive.long * 1000L,
        coveredM = num(o["coveredM"]),
    )

    private fun atS(epochMs: Long): Long = (epochMs - t0) / 1000L

    // ───────────── the file itself ─────────────

    @Test
    fun `every section in the file is one this reader runs`() {
        val unknown = root.keys - metaKeys - sections.toSet()
        assertTrue("unknown section(s) in race_finish_cases.json: $unknown", unknown.isEmpty())
        val schemaSections = root["schema"]!!.jsonObject.keys - setOf("general", "constants", "origin")
        assertEquals(sections.toSet(), schemaSections)
        for (s in sections) assertTrue("section $s is empty", cases(s).isNotEmpty())
    }

    @Test
    fun `the constants match the file`() {
        val c = root["constants"]!!.jsonObject
        assertEquals(c["FINISH_ZONE_M"]!!.jsonPrimitive.double, RaceFinish.FINISH_RADIUS_M, 0.0)
        assertEquals(c["MIN_COVERAGE"]!!.jsonPrimitive.double, RaceFinish.MIN_DISTANCE_FRACTION, 0.0)
        assertEquals(c["LATE_START_AFTER_MS"]!!.jsonPrimitive.long, RaceFinish.LATE_START_AFTER_MS)
        assertEquals(c["LATE_START_FAR_M"]!!.jsonPrimitive.double, RaceFinish.LATE_START_FAR_M, 0.0)
        assertEquals(c["EARTH_RADIUS_M"]!!.jsonPrimitive.double, RaceFinish.EARTH_RADIUS_M, 0.0)
    }

    // ───────────── sections ─────────────

    @Test
    fun distance() {
        for (c in cases("distance")) {
            val a = c["a"]!!.jsonArray
            val b = c["b"]!!.jsonArray
            val d = RaceFinish.distanceM(
                a[0].jsonPrimitive.double, a[1].jsonPrimitive.double,
                b[0].jsonPrimitive.double, b[1].jsonPrimitive.double,
            )
            assertEquals(c.name(), c["expectM"]!!.jsonPrimitive.double, d, distTol)
        }
    }

    @Test
    fun zone() {
        for (c in cases("zone")) {
            assertEquals(
                c.name(),
                c["inZone"]!!.jsonPrimitive.boolean,
                RaceFinish.inFinishZone(num(c["distanceM"])),
            )
        }
    }

    @Test
    fun coverage() {
        for (c in cases("coverage")) {
            assertEquals(
                c.name(),
                c["met"]!!.jsonPrimitive.boolean,
                RaceFinish.meetsDistanceGate(num(c["coveredM"]), c.numOrNull("courseDistanceM")),
            )
        }
    }

    @Test
    fun detector() {
        for (c in cases("detector")) {
            val name = c.name()
            val d = RaceFinishDetector(finishLat, finishLng, num(c["courseDistanceM"]))
            val expect = c["expect"]!!.jsonObject
            var finalisedAt: Int? = null
            var finish: RaceFinish.Finish? = null
            for ((i, el) in c["fixes"]!!.jsonArray.withIndex()) {
                val r = d.offer(fixOf(el.jsonObject))
                if (r != null && finalisedAt == null) {
                    finalisedAt = i
                    finish = r
                } else if (finalisedAt != null) {
                    assertEquals("$name: an offer after the finish moved it", finish, d.finish)
                }
            }
            assertEquals("$name: finalisesAtFix", expect.intOrNull("finalisesAtFix"), finalisedAt)
            val ef = expect.objOrNull("finish")
            if (ef == null) {
                assertNull("$name: finish", finish)
            } else {
                assertNotNull("$name: expected a finish", finish)
                val f = finish!!
                assertEquals("$name: finish atS", ef["atS"]!!.jsonPrimitive.long, atS(f.epochMs))
                assertEquals(
                    "$name: finish distance",
                    ef["distanceToFinishM"]!!.jsonPrimitive.double,
                    f.distanceToFinishM,
                    distTol,
                )
                assertEquals("$name: finish covered", num(ef["coveredM"]), f.coveredM, 0.0)
            }
            assertEquals(
                "$name: candidateAtS",
                expect.longOrNull("candidateAtS"),
                d.candidate?.let { atS(it.epochMs) },
            )
            val settled = d.finaliseNow()
            assertEquals("$name: settleAtS", expect.longOrNull("settleAtS"), settled?.let { atS(it.epochMs) })
            c["fixesAfterSettle"]?.jsonArray?.forEach { el ->
                d.offer(fixOf(el.jsonObject))
                assertEquals("$name: a fix after settle moved the finish", settled, d.finish)
            }
        }
    }

    @Test
    fun startFlag() {
        for (c in cases("startFlag")) {
            assertEquals(
                c.name(),
                c["flagged"]!!.jsonPrimitive.boolean,
                RaceFinish.startFlagged(
                    gunMs = t0 + c["gunMs"]!!.jsonPrimitive.long,
                    recordingStartedMs = t0 + c["recordingStartedMs"]!!.jsonPrimitive.long,
                    firstFixFromStartM = c.numOrNull("firstFixFromStartM"),
                ),
            )
        }
    }

    @Test
    fun clockOffset() {
        for (c in cases("clockOffset")) {
            val o = ServerClockOffset()
            for (el in c["samples"]!!.jsonArray) {
                val s = el.jsonObject
                o.addSample(
                    sentAtMs = s["sentMs"]!!.jsonPrimitive.long,
                    receivedAtMs = s["receivedMs"]!!.jsonPrimitive.long,
                    serverAtMs = s["serverMs"]!!.jsonPrimitive.long,
                )
            }
            val expect = c["expect"]!!.jsonObject
            assertEquals("${c.name()}: known", expect["known"]!!.jsonPrimitive.boolean, o.offsetMs != null)
            assertEquals(
                "${c.name()}: offsetMs",
                expect["offsetMs"]!!.jsonPrimitive.double,
                (o.offsetMs ?: 0L).toDouble(),
                offsetTol,
            )
        }
    }

    @Test
    fun gunTime() {
        for (c in cases("gunTime")) {
            assertEquals(
                c.name(),
                c.intOrNull("gunTimeS"),
                RaceFinish.gunTimeS(
                    finishEpochMs = t0 + c["finishMs"]!!.jsonPrimitive.long,
                    serverOffsetMs = c["offsetMs"]!!.jsonPrimitive.long,
                    startedAtMs = t0 + c["gunMs"]!!.jsonPrimitive.long,
                ),
            )
        }
    }

    @Test
    fun chipTime() {
        for (c in cases("chipTime")) {
            assertEquals(
                c.name(),
                c.intOrNull("chipTimeS"),
                RaceFinish.chipTimeS(
                    finishEpochMs = t0 + c["finishMs"]!!.jsonPrimitive.long,
                    runStartedAtMs = t0 + c["startMs"]!!.jsonPrimitive.long,
                ),
            )
        }
    }

    @Test
    fun stopOutcome() {
        for (c in cases("stopOutcome")) {
            val cand = c.objOrNull("candidate")?.let {
                RaceFinish.Finish(
                    epochMs = t0 + it["atMs"]!!.jsonPrimitive.long,
                    distanceToFinishM = it["distanceToFinishM"]!!.jsonPrimitive.double,
                    coveredM = it["coveredM"]!!.jsonPrimitive.double,
                )
            }
            val decision = raceFinishDecision(
                settled = cand,
                coveredM = num(c["coveredM"]),
                courseDistanceM = c.numOrNull("courseDistanceM"),
                stoppedAtMs = t0 + c["nowMs"]!!.jsonPrimitive.long,
            )
            val expect = c["expect"]!!.jsonObject
            assertEquals(
                "${c.name()}: status",
                expect["finisherStatus"]!!.jsonPrimitive.content,
                decision.outcome.finisherStatus,
            )
            assertEquals(
                "${c.name()}: method",
                expect.req("method").jsonPrimitive.contentOrNull,
                decision.outcome.finishMethod,
            )
            assertEquals(
                "${c.name()}: finishAtMs",
                expect.longOrNull("finishAtMs"),
                decision.finishEpochMs?.let { it - t0 },
            )
        }
    }

    private fun outcomeOf(status: String, method: String?): RaceFinish.Outcome =
        RaceFinish.Outcome.values().single { it.finisherStatus == status && it.finishMethod == method }

    @Test
    fun resultTiming() {
        for (c in cases("resultTiming")) {
            val name = c.name()
            val o = c["outcome"]!!.jsonObject
            val status = o["finisherStatus"]!!.jsonPrimitive.content
            val method = o.req("method").jsonPrimitive.contentOrNull
            val finishAt = o.longOrNull("finishAtMs")?.let { t0 + it }
            val gun = c.longOrNull("gunMs")?.let { t0 + it }
            val offset = c["offsetMs"]!!.jsonPrimitive.long
            val started = c.longOrNull("recordingStartedMs")?.let { t0 + it }
            val elapsed = c["elapsedS"]!!.jsonPrimitive.int
            val expect = c["expect"]!!.jsonObject
            val durationS = expect["durationS"]!!.jsonPrimitive.int
            val gunTimeS = expect.intOrNull("gunTimeS")
            val chipTimeS = expect.intOrNull("chipTimeS")

            val t = RaceFinish.resultTiming(status == "finished", finishAt, gun, offset, started, elapsed)
            assertEquals("$name: durationS", durationS, t.durationS)
            assertEquals("$name: gunTimeS", gunTimeS, t.gunTimeS)
            assertEquals("$name: chipTimeS", chipTimeS, t.chipTimeS)

            // The row the watch actually files, where the recording's Start
            // is always known, must carry the same timing and method.
            if (started != null) {
                val row = buildRaceResult(
                    race = ActiveRaceState("e1", "i1", "running", gun, null),
                    decision = RaceStopDecision(outcomeOf(status, method), finishAt, 1000.0),
                    userId = "u1",
                    runId = "r1",
                    runStartedAtMs = started,
                    elapsedS = elapsed,
                    serverOffsetMs = offset,
                )
                assertEquals("$name: row durationS", durationS, row.durationS)
                assertEquals("$name: row gunTimeS", gunTimeS, row.gunTimeS)
                assertEquals("$name: row chipTimeS", chipTimeS, row.chipTimeS)
                assertEquals("$name: row finish_method", method, row.finishMethod)
                assertEquals("$name: row status", status, row.finisherStatus)
            }
        }
    }

    // ───────────── Kotlin-only surface ─────────────

    @Test
    fun `forCourse needs the course's finish point and a positive distance`() {
        assertNull(RaceFinishDetector.forCourse(null, null, 5000.0))
        assertNull(RaceFinishDetector.forCourse(finishLat, null, 5000.0))
        assertNull(RaceFinishDetector.forCourse(finishLat, finishLng, null))
        assertNull(RaceFinishDetector.forCourse(finishLat, finishLng, 0.0))
        assertNull(RaceFinishDetector.forCourse(finishLat, finishLng, Double.NaN))
        assertNotNull(RaceFinishDetector.forCourse(finishLat, finishLng, 5000.0))
    }

    @Test
    fun `the finish is answered once and held after`() {
        val d = RaceFinishDetector(finishLat, finishLng, 5000.0)
        val north = { m: Double, s: Long, cov: Double ->
            RaceFinish.Fix(finishLat + m / metresPerDegLat, finishLng, t0 + s * 1000L, cov)
        }
        assertNull(d.offer(north(-10.0, 0L, 4990.0)))
        val f = d.offer(north(10.0, 2L, 5010.0))
        assertNotNull(f)
        assertNull(d.offer(north(0.0, 4L, 5020.0)))
        assertEquals(f, d.finish)
        assertFalse(d.isCandidate)
    }
}
