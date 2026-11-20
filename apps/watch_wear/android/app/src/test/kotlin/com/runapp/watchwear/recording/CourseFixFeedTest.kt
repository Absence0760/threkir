package com.runapp.watchwear.recording

import com.runapp.watchwear.GpsPoint
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Test
import java.io.File
import java.nio.file.Files
import java.time.Instant

/// The course timer's fix is the stored fix: the instant `CourseFix` carries
/// is the `ts` `TrackWriter` writes for it, to the millisecond, which is the
/// instant the server's matcher times the run by.
class CourseFixFeedTest {

    @Test
    fun `a course fix carries the stored fix's position and its stored ts, to the millisecond`() {
        val dir = Files.createTempDirectory("course-fix-feed").toFile()
        try {
            val writer = TrackWriter(File(dir, "run.json")).also { it.open() }
            val points = (0 until 5).map { i ->
                GpsPoint(
                    lat = 37.5 + i * 1e-5,
                    lng = -77.5,
                    ele = null,
                    epochMs = 1_800_000_000_123L + i * 1_037L,
                    elapsedRealtimeMs = 9_000L + i,
                )
            }
            val fixes = points.map { p ->
                writer.append(p)
                CourseFix.of("run-1", p)
            }
            val stored = Json.parseToJsonElement(writer.close().readText()).jsonArray.map { it.jsonObject }
            assertEquals(points.size, stored.size)
            for ((fix, row) in fixes.zip(stored)) {
                assertEquals(Instant.parse(row["ts"]!!.jsonPrimitive.content).toEpochMilli(), fix.epochMs)
                assertEquals(row["lat"]!!.jsonPrimitive.content.toDouble(), fix.lat, 0.0)
                assertEquals(row["lng"]!!.jsonPrimitive.content.toDouble(), fix.lng, 0.0)
                assertEquals("run-1", fix.runId)
            }
        } finally {
            dir.deleteRecursively()
        }
    }
}
