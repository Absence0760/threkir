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
        "clockOffset", "gunTime", "chipTime", "stopOutcome", "resultTiming", "lines",
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
        assertEquals(c["MIN_COVERAGE_WITH_START"]!!.jsonPrimitive.double, RaceFinish.MIN_COVERAGE_WITH_START, 0.0)
        assertEquals(c["START_COMMIT_M"]!!.jsonPrimitive.double, RaceFinish.START_COMMIT_M, 0.0)
        assertEquals(c["LAP_SHORT_SHARE"]!!.jsonPrimitive.double, RaceFinish.LAP_SHORT_SHARE, 0.0)
        assertEquals(c["GATE_EARTH_RADIUS_M"]!!.jsonPrimitive.double, GATE_EARTH_RADIUS_M, 0.0)
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
                lapsMet = c.req("lapsMet").let { if (it is JsonNull) null else it.jsonPrimitive.boolean },
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
            val startAt = c.longOrNull("startMs")?.let { t0 + it }
            val elapsed = c["elapsedS"]!!.jsonPrimitive.int
            val expect = c["expect"]!!.jsonObject
            val durationS = expect["durationS"]!!.jsonPrimitive.int
            val gunTimeS = expect.intOrNull("gunTimeS")
            val chipTimeS = expect.intOrNull("chipTimeS")

            val t = RaceFinish.resultTiming(status == "finished", finishAt, gun, offset, started, elapsed, startAt)
            assertEquals("$name: durationS", durationS, t.durationS)
            assertEquals("$name: gunTimeS", gunTimeS, t.gunTimeS)
            assertEquals("$name: chipTimeS", chipTimeS, t.chipTimeS)

            // The row the watch actually files, where the recording's Start
            // is always known, must carry the same timing and method. It has
            // no line start until the lines reach the watch (#1307).
            if (started != null && startAt == null) {
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

    private val gateK = GATE_EARTH_RADIUS_M * Math.PI / 180.0

    private fun planeLat(o: JsonObject) = finishLat + num(o["northM"]) / gateK
    private fun planeLng(o: JsonObject) =
        finishLng + num(o["eastM"]) / (gateK * Math.cos(finishLat * Math.PI / 180.0))

    private fun gateOf(el: JsonElement): Gate? {
        if (el is JsonNull) return null
        val g = el.jsonObject
        return Gate(planeLat(g), planeLng(g), num(g["bearingDeg"]), num(g["halfWidthM"]))
    }

    private fun planeFix(o: JsonObject) = RaceFinish.Fix(
        lat = planeLat(o),
        lng = planeLng(o),
        epochMs = t0 + o["atS"]!!.jsonPrimitive.long * 1000L,
        coveredM = num(o["coveredM"]),
    )

    private fun assertStart(what: String, want: JsonElement, got: RaceFinish.Start?) {
        if (want is JsonNull) {
            assertNull(what, got)
            return
        }
        val w = want.jsonObject
        assertNotNull("$what: expected a start", got)
        assertEquals("$what atMs", w["atMs"]!!.jsonPrimitive.long, got!!.epochMs - t0)
        assertEquals("$what coveredM", num(w["coveredM"]), got.coveredM, distTol)
        assertEquals("$what kind", w["kind"]!!.jsonPrimitive.content, if (got.kind == RaceFinish.StartKind.GO) "go" else "line")
    }

    private fun assertFinish(what: String, want: JsonElement, got: RaceFinish.Finish?) {
        if (want is JsonNull) {
            assertNull(what, got)
            return
        }
        val w = want.jsonObject
        assertNotNull("$what: expected a finish", got)
        assertEquals("$what atMs", w["atMs"]!!.jsonPrimitive.long, got!!.epochMs - t0)
        assertEquals("$what coveredM", num(w["coveredM"]), got.coveredM, distTol)
        assertEquals("$what distanceToFinishM", num(w["distanceToFinishM"]), got.distanceToFinishM, distTol)
        assertEquals("$what detection", w["detection"]!!.jsonPrimitive.content, got.detection.wire)
        assertEquals("$what gapped", w["gapped"]!!.jsonPrimitive.boolean, got.gapped)
        assertStart("$what start", w.req("start"), got.start)
    }

    @Test
    fun lines() {
        for (c in cases("lines")) {
            val name = c.name()
            val expect = c["expect"]!!.jsonObject
            val goS = c.longOrNull("goS")
            val goAfter = c.intOrNull("goSetAfterFix")
            val d = RaceFinishDetector(
                finishLat, finishLng, num(c["courseDistanceM"]),
                startGate = gateOf(c.req("startGate")),
                finishGate = gateOf(c.req("finishGate")),
                mode = if (c["mode"]!!.jsonPrimitive.content == "selfTimed") RaceFinish.StartMode.SELF_TIMED else RaceFinish.StartMode.GUN,
                goAtMs = if (goS != null && goAfter == null) t0 + goS * 1000L else null,
                lapCount = c.intOrNull("lapCount"),
            )
            var finalisedAt: Int? = null
            var finish: RaceFinish.Finish? = null
            for ((i, el) in c["fixes"]!!.jsonArray.withIndex()) {
                var r = d.offer(planeFix(el.jsonObject))
                if (goAfter == i && goS != null) r = r ?: d.setGo(t0 + goS * 1000L)
                if (r != null && finalisedAt == null) {
                    finalisedAt = i
                    finish = r
                }
            }
            assertEquals("$name: finalisesAtFix", expect.intOrNull("finalisesAtFix"), finalisedAt)
            assertFinish("$name: finish", expect.req("finish"), finish)
            assertStart("$name: start", expect.req("start"), d.start)
            val lastCovered = num(c["fixes"]!!.jsonArray.last().jsonObject["coveredM"])
            assertEquals(
                "$name: lapsMet",
                expect.req("lapsMet").let { if (it is JsonNull) null else it.jsonPrimitive.boolean },
                d.lapsMet(lastCovered),
            )
            assertEquals(
                "$name: candidateAtS",
                expect.longOrNull("candidateAtS"),
                d.candidate?.let { atS(it.epochMs) },
            )
            val settled = d.finaliseNow()
            assertFinish("$name: settle", expect.req("settle"), settled)
            val timing = expect.objOrNull("timing")
            if (settled == null) {
                assertNull("$name: timing", timing)
                continue
            }
            assertNotNull("$name: timing", timing)
            val pressS = c.longOrNull("pressS")
            val t = RaceFinish.resultTiming(
                finished = true,
                finishAtMs = settled.epochMs,
                gunMs = goS?.let { t0 + it * 1000L },
                serverOffsetMs = 0L,
                recordingStartedMs = pressS?.let { t0 + it * 1000L },
                elapsedS = 0,
                startAtMs = settled.start?.epochMs,
            )
            assertEquals("$name: gunTimeS", timing!!.intOrNull("gunTimeS"), t.gunTimeS)
            assertEquals("$name: chipTimeS", timing.intOrNull("chipTimeS"), t.chipTimeS)
            assertEquals("$name: durationS", timing["durationS"]!!.jsonPrimitive.int, t.durationS)
        }
    }

    @Test
    fun `an unusable line is no line`() {
        val ok = Gate(51.5, -0.1, 0.0, 15.0)
        assertTrue(RaceFinish.lineUsable(ok))
        assertFalse(RaceFinish.lineUsable(null))
        assertFalse(RaceFinish.lineUsable(ok.copy(halfWidthM = 0.0)))
        assertFalse(RaceFinish.lineUsable(ok.copy(bearingDeg = Double.NaN)))
    }

    @Test
    fun `GO is fixed once set`() {
        val d = RaceFinishDetector(
            finishLat, finishLng, 1000.0,
            startGate = Gate(finishLat, finishLng, 0.0, 15.0),
            goAtMs = t0,
        )
        assertNull(d.setGo(t0 + 100_000L))
        d.offer(RaceFinish.Fix(finishLat + 10.0 / gateK, finishLng, t0 + 1000L, 0.0))
        assertEquals(t0, d.start?.epochMs)
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
        val f = d.offer(north(15.0, 2L, 5010.0))
        assertNotNull(f)
        assertNull(d.offer(north(0.0, 4L, 5020.0)))
        assertEquals(f, d.finish)
        assertFalse(d.isCandidate)
    }
}
