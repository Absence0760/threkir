package com.threkir.app

import java.io.File
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZonedDateTime
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/// The widget's read side, held to `fixtures/today_widget_snapshot.json`: the
/// snapshots the Dart writer is held to as well
/// (`apps/mobile_android/test/today_widget_test.dart`), and what the widget
/// shows for each on a given local date.
class TodayWidgetSnapshotTest {

    private val fixture: JSONObject = run {
        // Gradle runs tests with cwd = `apps/mobile_android/android/app`.
        JSONObject(File("../../../../fixtures/today_widget_snapshot.json").readText())
    }

    private fun snapshot(name: String): String =
        if (name == "not_json") "not json"
        else fixture.getJSONObject("snapshots").getJSONObject(name).toString()

    private fun JSONObject.nullableString(key: String): String? =
        if (isNull(key)) null else getString(key)

    @Test
    fun `every render vector draws what the fixture says`() {
        val vectors = fixture.getJSONArray("render_vectors")
        assertTrue("fixture has no render vectors", vectors.length() > 0)
        for (i in 0 until vectors.length()) {
            val v = vectors.getJSONObject(i)
            val name = v.getString("name")
            val expect = v.getJSONObject("expect")
            val view = selectTodayWidgetView(
                snapshot(v.getString("snapshot")),
                LocalDate.parse(v.getString("today")),
            )
            assertEquals(name, expect.getString("state"), view.state.name.lowercase())
            assertEquals(name, expect.nullableString("header"), view.header)
            assertEquals(name, expect.nullableString("title"), view.title)
            assertEquals(name, expect.nullableString("detail"), view.detail)
            assertEquals(name, expect.nullableString("badge"), view.badge)
            assertEquals(name, expect.nullableString("link"), view.link)
        }
    }

    @Test
    fun `no snapshot is the stale state with nothing read`() {
        for (json in listOf(null, "", "  ")) {
            val view = selectTodayWidgetView(json, LocalDate.of(2026, 10, 18))
            assertEquals(TodayWidgetView.State.STALE, view.state)
            assertNull(view.title)
            assertNull(view.link)
        }
    }

    @Test
    fun `a snapshot missing its labels is never half read`() {
        val view = selectTodayWidgetView("""{"v":1,"plan_id":"p","days":[]}""", LocalDate.of(2026, 10, 18))
        assertEquals(TodayWidgetView.State.STALE, view.state)
        assertNull(view.header)
    }

    @Test
    fun `an unknown day state is stale rather than guessed`() {
        val root = JSONObject(snapshot("typical"))
        root.getJSONArray("days").getJSONObject(0).put("state", "maybe")
        val view = selectTodayWidgetView(root.toString(), LocalDate.of(2026, 10, 18))
        assertEquals(TodayWidgetView.State.STALE, view.state)
        assertNull(view.title)
    }

    @Test
    fun `update args need a non-blank snapshot`() {
        assertNull(parseHomeWidgetUpdateArgs(null))
        assertNull(parseHomeWidgetUpdateArgs(emptyMap()))
        assertNull(parseHomeWidgetUpdateArgs(mapOf("snapshot_json" to " ")))
        assertNull(parseHomeWidgetUpdateArgs(mapOf("snapshot_json" to 7)))
        assertEquals("""{"v":1}""", parseHomeWidgetUpdateArgs(mapOf("snapshot_json" to """{"v":1}""")))
    }

    @Test
    fun `the midnight alarm lands just after the next local midnight`() {
        val zone = ZoneId.of("Europe/London")
        val now = ZonedDateTime.of(2026, 10, 18, 23, 59, 0, 0, zone)
        val expected = ZonedDateTime.of(2026, 10, 19, 0, 1, 0, 0, zone)
        assertEquals(expected.toInstant().toEpochMilli(), nextLocalMidnightMs(now))
    }

    @Test
    fun `the midnight alarm survives a zone whose midnight DST skips`() {
        // Chile springs forward at local midnight: 00:00 does not exist, so
        // the day starts at 01:00.
        val zone = ZoneId.of("America/Santiago")
        val now = ZonedDateTime.of(2026, 9, 5, 22, 0, 0, 0, zone)
        val start = LocalDate.of(2026, 9, 6).atStartOfDay(zone)
        assertEquals(start.plusMinutes(1).toInstant().toEpochMilli(), nextLocalMidnightMs(now))
        assertTrue(nextLocalMidnightMs(now) > now.toInstant().toEpochMilli())
    }
}
