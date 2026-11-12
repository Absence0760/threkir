package com.threkir.app

import org.junit.Assert.assertEquals
import org.junit.Test

/// Pure-JVM tests for [RunClockAnchor]: the Live Update clock holds still
/// under per-update skew and re-anchors on a resume or a recovered run.
class RunClockAnchorTest {

    @Test
    fun `first post anchors at now minus elapsed`() {
        assertEquals(40_000L, RunClockAnchor.next(null, 100_000L, 60_000L))
    }

    @Test
    fun `sub-tolerance skew keeps the held anchor`() {
        val held = 40_000L
        assertEquals(held, RunClockAnchor.next(held, 101_000L, 60_600L))
        assertEquals(held, RunClockAnchor.next(held, 101_000L, 61_400L))
    }

    @Test
    fun `drift at the tolerance re-anchors`() {
        val held = 40_000L
        val now = 101_000L
        val elapsed = now - held - RunClockAnchor.TOLERANCE_MS
        assertEquals(now - elapsed, RunClockAnchor.next(held, now, elapsed))
    }

    @Test
    fun `a resume after a pause moves the anchor by the pause`() {
        val held = 40_000L
        // Paused for 30 s at 60 s elapsed, resumed one second later.
        assertEquals(71_000L, RunClockAnchor.next(held, 132_000L, 61_000L))
    }
}
