package com.runapp.watchwear

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.double
import kotlinx.serialization.json.int
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

/// The live course timer against `fixtures/park_course_runs.json`, the case
/// table the `segments` pair's matcher is held to on web, the phone and the
/// server: synthetic 1 Hz runs with GPS error over the six Pocahontas course
/// lines, each fed fix by fix to a timer for every course. The fastest lap the
/// timer finishes on a course is the effort the matcher recorded there, to
/// the millisecond, and a course the matcher gave nothing finishes nothing.
class LiveCourseTimerTest {

    private val root: JsonObject = run {
        val f = WearLocales.findUp("fixtures/park_course_runs.json")
            ?: error("fixtures/park_course_runs.json not found")
        Json.parseToJsonElement(f.readText()).jsonObject
    }
    private val baseMs = Instant.parse(root["base_time"]!!.jsonPrimitive.content).toEpochMilli()
    private val courses = root["courses"]!!.jsonArray.map { it.jsonObject }
    private val cases = root["cases"]!!.jsonArray.map { it.jsonObject }

    private fun gate(o: JsonObject) = Gate(
        lat = o["lat"]!!.jsonPrimitive.double,
        lng = o["lng"]!!.jsonPrimitive.double,
        bearingDeg = o["bearing_deg"]!!.jsonPrimitive.double,
        halfWidthM = o["half_width_m"]!!.jsonPrimitive.double,
    )

    private fun spec(c: JsonObject, checkpoints: Boolean = true) = CourseTimingSpec(
        distanceM = c["distance_m"]!!.jsonPrimitive.double,
        startGate = gate(c["start_gate"]!!.jsonObject),
        endGate = gate(c["end_gate"]!!.jsonObject),
        checkpoints = if (!checkpoints) emptyList() else c["checkpoints"]!!.jsonArray.map {
            val p = it.jsonObject
            GatePoint(p["lat"]!!.jsonPrimitive.double, p["lng"]!!.jsonPrimitive.double)
        },
    )

    private data class Fix(val lat: Double, val lng: Double, val tMs: Double)

    /// The fixture's delta encoding: micro-degrees, one second apart unless
    /// `gaps` says otherwise.
    private fun decode(track: JsonObject): List<Fix> {
        val first = track["first"]!!.jsonArray.map { it.jsonPrimitive.long }
        val d = track["d"]!!.jsonArray.map { it.jsonPrimitive.long }
        val gaps = track["gaps"]!!.jsonArray.associate {
            val g = it.jsonArray
            g[0].jsonPrimitive.int to g[1].jsonPrimitive.int
        }
        var lat = first[0]
        var lng = first[1]
        var t = 0L
        val out = mutableListOf(Fix(lat / 1e6, lng / 1e6, baseMs.toDouble()))
        for (i in 1..d.size / 2) {
            lat += d[2 * i - 2]
            lng += d[2 * i - 1]
            t += (gaps[i] ?: 1)
            out.add(Fix(lat / 1e6, lng / 1e6, (baseMs + t * 1000).toDouble()))
        }
        return out
    }

    private class Run(val timer: LiveCourseTimer, val events: List<CourseEvent>, val settled: CourseEvent.Finished?)

    private fun run(spec: CourseTimingSpec, fixes: List<Fix>): Run {
        val timer = LiveCourseTimer(spec)
        val events = mutableListOf<CourseEvent>()
        for (f in fixes) events += timer.offer(f.lat, f.lng, f.tMs)
        val settled = timer.settle()
        return Run(timer, events, settled)
    }

    @Test
    fun `every case times what the matcher timed, on every course`() {
        val slugs = courses.map { it["slug"]!!.jsonPrimitive.content }
        val specs = courses.map { spec(it) }
        assertEquals(6, slugs.size)
        assertEquals(18, cases.size)
        for (c in cases) {
            val key = c["key"]!!.jsonPrimitive.content
            val fixes = decode(c["track"]!!.jsonObject)
            val matched = c["matched"]!!.jsonObject
            for ((i, slug) in slugs.withIndex()) {
                val r = run(specs[i], fixes)
                val recorded = matched[slug]?.jsonObject
                val best = r.timer.best
                if (recorded == null) {
                    assertNull("$key on $slug: timed ${best?.elapsedS} s", best)
                    continue
                }
                assertNotNull("$key on $slug: no finish", best)
                val want = recorded["time_seconds"]!!.jsonPrimitive.double
                assertTrue(
                    "$key on $slug: ${best!!.elapsedS} s against the matcher's $want s",
                    abs(best.elapsedS - want) < 0.001,
                )
                assertEquals(
                    "$key on $slug: start",
                    recorded["started_offset_ms"]!!.jsonPrimitive.long,
                    Math.round(best.startMs) - baseMs,
                )
            }
        }
    }

    @Test
    fun `a timed run says timing started before it says finished, and each finish once`() {
        for (c in cases) {
            val want = c["want"]!!.jsonObject
            if (!want["effort"]!!.jsonPrimitive.boolean) continue
            val key = c["key"]!!.jsonPrimitive.content
            val own = courses.first { it["slug"]!!.jsonPrimitive.content == c["course"]!!.jsonPrimitive.content }
            val r = run(spec(own), decode(c["track"]!!.jsonObject))
            val firstStart = r.events.indexOfFirst { it is CourseEvent.Started }
            val firstFinish = r.events.indexOfFirst { it is CourseEvent.Finished }
            assertTrue("$key: no start cue", firstStart >= 0)
            assertTrue("$key: no finish cue", firstFinish > firstStart)
            assertEquals(key, r.timer.finished, r.events.filterIsInstance<CourseEvent.Finished>() + listOfNotNull(r.settled))
            val truth = want["truth_s"]!!.jsonPrimitive.double
            val tol = want["tolerance_s"]!!.jsonPrimitive.double
            assertTrue("$key: ${r.timer.best!!.elapsedS} vs $truth", abs(r.timer.best!!.elapsedS - truth) <= tol)
        }
    }

    @Test
    fun `three laps finish three times, the later laps opened by the finish`() {
        val c = cases.first { it["key"]!!.jsonPrimitive.content == "beaver_three_laps" }
        val beaver = courses.first { it["slug"]!!.jsonPrimitive.content == "beaver-lake-trail" }
        val spec = spec(beaver)
        // Beaver Lake's two boxes are apart but its lines chain: the finish
        // opens the next lap, so the start cue is said once and the runner is
        // never told timing started again mid-run.
        assertEquals(GateBoxLayout.APART, gateTimingEdges(spec.startGate, spec.endGate).layout)
        assertTrue(linesChain(spec.startGate, spec.endGate))
        val r = run(spec, decode(c["track"]!!.jsonObject))
        val laps = r.timer.finished
        assertEquals(3, laps.size)
        assertEquals("one start cue: the finish opens each later lap", 1, r.events.count { it is CourseEvent.Started })
        for (i in 1 until laps.size) assertTrue("lap ${i + 1} starts after lap $i ends", laps[i].startMs >= laps[i - 1].endMs)
        assertTrue("4:30/km is the fastest lap", laps[1].elapsedS < laps[0].elapsedS && laps[1].elapsedS < laps[2].elapsedS)
    }

    @Test
    fun `the cut and the shortcut are refused by the checkpoints alone`() {
        val beaver = courses.first { it["slug"]!!.jsonPrimitive.content == "beaver-lake-trail" }
        for (key in listOf("beaver_shortcut", "beaver_cut")) {
            val fixes = decode(cases.first { it["key"]!!.jsonPrimitive.content == key }["track"]!!.jsonObject)
            assertNull(key, run(spec(beaver), fixes).timer.best)
            assertNotNull("$key without checkpoints", run(spec(beaver, checkpoints = false), fixes).timer.best)
        }
    }

    @Test
    fun `stopping short, the wrong way and a parallel line never finish nor buzz a finish`() {
        val beaver = courses.first { it["slug"]!!.jsonPrimitive.content == "beaver-lake-trail" }
        for (key in listOf("beaver_short", "beaver_wrong_way", "beaver_nearby")) {
            val fixes = decode(cases.first { it["key"]!!.jsonPrimitive.content == key }["track"]!!.jsonObject)
            val r = run(spec(beaver), fixes)
            assertTrue(key, r.events.none { it is CourseEvent.Finished })
            assertNull(key, r.settled)
        }
    }

    @Test
    fun `a recording that ends in the finish box finishes on settle`() {
        val start = Gate(lat = 0.0, lng = 0.0, bearingDeg = 0.0, halfWidthM = 15.0)
        val end = Gate(lat = 1000.0 / 111_195.0, lng = 0.0, bearingDeg = 0.0, halfWidthM = 15.0)
        val timer = LiveCourseTimer(CourseTimingSpec(distanceM = 1000.0, startGate = start, endGate = end))
        val degPerM = 1.0 / 111_195.0
        val events = mutableListOf<CourseEvent>()
        // -20 m to 997 m (3 m short of the finish line, inside the 5 m slack)
        // at 4 m/s, then standing.
        var t = 0.0
        var y = -20.0
        while (y <= 997.0) {
            events += timer.offer(y * degPerM, 0.0, t)
            y += 4.0
            t += 1000.0
        }
        repeat(10) { events += timer.offer(997.0 * degPerM, 0.0, t); t += 1000.0 }
        assertEquals(1, events.count { it is CourseEvent.Started })
        assertTrue(events.none { it is CourseEvent.Finished })
        val settled = timer.settle()
        assertNotNull(settled)
        assertTrue("standing adds nothing: ${settled!!.elapsedS}", settled.elapsedS < 251.0)
    }

    @Test
    fun `an unusable course is never timed`() {
        val bad = CourseTimingSpec(
            distanceM = 0.0,
            startGate = Gate(0.0, 0.0, 0.0, 15.0),
            endGate = Gate(0.0, 0.0, 0.0, 15.0),
        )
        val timer = LiveCourseTimer(bad)
        assertTrue(!timer.usable)
        assertTrue(timer.offer(0.0, 0.0, 0.0).isEmpty())
        assertNull(timer.settle())
    }

    @Test
    fun `a course time reads as the runner reads a clock`() {
        assertEquals("8:42:10", formatCourseTime(8 * 3600 + 42 * 60 + 10.2))
        assertEquals("16:05", formatCourseTime(965.4))
        assertEquals("0:59", formatCourseTime(59.4))
        assertEquals("1:00:00", formatCourseTime(3599.6))
        assertEquals("0:00", formatCourseTime(-3.0))
    }

    @Test
    fun `the screen says the last thing the timer did`() {
        assertNull(courseCueAfter(null, emptyList()))
        val started = courseCueAfter(null, listOf(CourseEvent.Started(0.0)))
        assertEquals(CourseCueView(finishedS = null), started)
        val done = courseCueAfter(started, listOf(CourseEvent.Finished(0.0, 965_000.0)))
        assertEquals(CourseCueView(finishedS = 965.0), done)
        assertEquals("a quiet fix keeps the cue", done, courseCueAfter(done, emptyList()))
        assertEquals(started, courseCueAfter(done, listOf(CourseEvent.Started(1.0))))
    }

    @Test
    fun `only a picked course that is still offered and timeable gets a timer`() {
        val beaver = courses.first { it["slug"]!!.jsonPrimitive.content == "beaver-lake-trail" }
        val course = ParkCourse(
            id = "c1",
            routeId = null,
            name = "Beaver Lake Trail",
            laps = 1,
            timing = spec(beaver),
            waypoints = listOf(SavedRoute.Waypoint(0.0, 0.0), SavedRoute.Waypoint(0.0, 0.001)),
        )
        assertNotNull(courseTimerFor(course.asRoute(), listOf(course)))
        assertNull("no route", courseTimerFor(null, listOf(course)))
        assertNull("a saved route", courseTimerFor(SavedRoute("r", "Mine", 1000.0, course.waypoints), listOf(course)))
        assertNull("taken off the watch", courseTimerFor(course.asRoute(), emptyList()))
        val untimeable = course.copy(timing = course.timing.copy(distanceM = 0.0))
        assertNull("no length", courseTimerFor(untimeable.asRoute(), listOf(untimeable)))
    }
}
