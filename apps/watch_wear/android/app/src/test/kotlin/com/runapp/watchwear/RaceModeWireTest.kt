package com.runapp.watchwear

import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/// The race-mode wire contract on the watch: what the course reads parse,
/// what the `event_results` upsert carries, which failures are replayed, and
/// how a race run's result is assembled from the finish.
class RaceModeWireTest {

    @Test
    fun `course id and course row parse from PostgREST arrays`() {
        assertEquals("c1", RaceSessionClient.parseCourseId("""[{"course_id":"c1"}]"""))
        assertNull(RaceSessionClient.parseCourseId("""[{"course_id":null}]"""))
        assertNull(RaceSessionClient.parseCourseId("[]"))

        val course = RaceSessionClient.parseCourse(
            """[{"id":"c1","name":"10K","distance_m":10000,"finish_lat":51.1,"finish_lng":0.2}]""",
        )!!
        assertEquals("c1", course.id)
        assertEquals(10_000.0, course.distanceM!!, 0.0)
        assertEquals(51.1, course.finishLat!!, 0.0)
        assertEquals(0.2, course.finishLng!!, 0.0)
        assertNull(RaceSessionClient.parseCourse("""[{"name":"10K"}]"""))
    }

    @Test
    fun `a course with no finish point or a half pair parses with no finish`() {
        val none = RaceSessionClient.parseCourse(
            """[{"id":"c1","name":"10K","distance_m":10000,"finish_lat":null,"finish_lng":null}]""",
        )!!
        assertNull(none.finishLat)
        assertNull(none.finishLng)
        assertNull(RaceFinishDetector.forCourse(none.finishLat, none.finishLng, none.distanceM))
        assertEquals(
            RaceFinish.Outcome.MANUAL_FINISH,
            RaceFinish.manualOutcome(9_000.0, none.distanceM),
        )

        val half = RaceSessionClient.parseCourse(
            """[{"id":"c1","distance_m":10000,"finish_lat":51.1,"finish_lng":null}]""",
        )!!
        assertNull(half.finishLat)
        assertNull(half.finishLng)
    }

    @Test
    fun `a course with no distance has no auto finish and finishes by hand`() {
        val c = RaceSessionClient.parseCourse(
            """[{"id":"c1","distance_m":null,"finish_lat":51.1,"finish_lng":0.2}]""",
        )!!
        assertNull(RaceFinishDetector.forCourse(c.finishLat, c.finishLng, c.distanceM))
        assertEquals(RaceFinish.Outcome.MANUAL_FINISH, RaceFinish.manualOutcome(10.0, c.distanceM))
    }

    @Test
    fun `server timestamptz parses with an offset and fractional seconds`() {
        assertEquals(1_779_472_800_000L, parseServerInstantMs("2026-05-22T18:00:00+00:00"))
        assertEquals(1_779_472_800_250L, parseServerInstantMs("2026-05-22T18:00:00.25+00:00"))
        assertEquals(1_779_472_800_000L, parseServerInstantMs("2026-05-22T20:00:00+02:00"))
        assertNull(parseServerInstantMs("not a time"))
    }

    private val race = ActiveRaceState(
        eventId = "e1",
        instanceStart = "2026-05-22T18:00:00+00:00",
        status = "running",
        startedAtMs = 1_000_000L,
        eventTitle = "Club 10K",
        course = RaceSessionClient.RaceCourse("c1", "10K", 10_000.0, 51.1, 0.2),
    )

    @Test
    fun `an auto finish carries gun, chip, course and method`() {
        val r = buildRaceResult(
            race = race,
            decision = RaceStopDecision(RaceFinish.Outcome.AUTO_FINISH, 3_000_000L, 10_012.0),
            userId = "u1",
            runId = "run1",
            runStartedAtMs = 1_030_000L,
            elapsedS = 1_900,
            serverOffsetMs = 2_000L,
        )
        assertEquals(2002, r.gunTimeS)
        assertEquals(1970, r.chipTimeS)
        assertEquals(2002, r.durationS)
        assertEquals("finished", r.finisherStatus)
        assertEquals("auto", r.finishMethod)
        assertEquals("c1", r.courseId)
        assertEquals(10_012.0, r.distanceM, 0.0)

        val body = RaceSessionClient.resultBody(r)
        assertEquals("auto", body["finish_method"]!!.jsonPrimitive.contentOrNull)
        assertEquals(2002, body["gun_time_s"]!!.jsonPrimitive.intOrNull)
        assertEquals(1970, body["chip_time_s"]!!.jsonPrimitive.intOrNull)
        assertEquals("c1", body["course_id"]!!.jsonPrimitive.contentOrNull)
        assertEquals("run1", body["run_id"]!!.jsonPrimitive.contentOrNull)
    }

    @Test
    fun `a DNF row carries no method, no gun and no chip, and its duration is the elapsed recording`() {
        val r = buildRaceResult(
            race = race,
            decision = RaceStopDecision(RaceFinish.Outcome.DNF, null, 4_000.0),
            userId = "u1",
            runId = "run1",
            runStartedAtMs = 1_000_000L,
            elapsedS = 900,
            serverOffsetMs = 2_000L,
        )
        assertEquals("dnf", r.finisherStatus)
        assertNull(r.gunTimeS)
        assertNull(r.chipTimeS)
        assertEquals(900, r.durationS)
        assertEquals("c1", r.courseId)
        val body = RaceSessionClient.resultBody(r)
        assertFalse(body.containsKey("finish_method"))
        assertFalse(body.containsKey("gun_time_s"))
        assertFalse(body.containsKey("chip_time_s"))
        assertEquals(900, body["duration_s"]!!.jsonPrimitive.intOrNull)
    }

    @Test
    fun `a finish before the runner's own start carries no chip time and ranks on the elapsed recording`() {
        val r = buildRaceResult(
            race = race.copy(startedAtMs = null),
            decision = RaceStopDecision(RaceFinish.Outcome.MANUAL_FINISH, 999_000L, 9_500.0),
            userId = "u1",
            runId = "run1",
            runStartedAtMs = 1_000_000L,
            elapsedS = 1_234,
            serverOffsetMs = null,
        )
        assertNull(r.gunTimeS)
        assertNull(r.chipTimeS)
        assertEquals(1_234, r.durationS)
        assertFalse(RaceSessionClient.resultBody(r).containsKey("chip_time_s"))
    }

    @Test
    fun `only a refused body is dropped - offline, 5xx, 409 and 401 are replayed`() {
        assertFalse(isRetryableRaceResultFailure(RuntimeException("HTTP 400: bad column")))
        assertFalse(isRetryableRaceResultFailure(RuntimeException("HTTP 422: check")))
        assertTrue(isRetryableRaceResultFailure(RuntimeException("HTTP 409: fk run_id")))
        assertTrue(isRetryableRaceResultFailure(RuntimeException("HTTP 401: jwt expired")))
        assertTrue(isRetryableRaceResultFailure(RuntimeException("HTTP 503: down")))
        assertTrue(isRetryableRaceResultFailure(java.io.IOException("Unable to resolve host")))
    }

    @Test
    fun `a newer result for the same race and runner replaces the queued one`() {
        val a = PendingRaceResult("u1", "e1", "i1", "run1", 100, 1.0, "dnf")
        val b = a.copy(durationS = 90, finisherStatus = "finished", finishMethod = "manual")
        val other = a.copy(eventId = "e2")
        assertEquals(listOf(other, b), enqueueRaceResult(listOf(a, other), b))
    }
}
