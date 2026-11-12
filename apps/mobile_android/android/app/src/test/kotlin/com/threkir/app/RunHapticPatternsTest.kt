package com.threkir.app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/// Pure-JVM tests for [RunHapticPatterns]: the wire names match the Dart
/// enum (`lib/step_haptics.dart`), every waveform is well-formed for
/// `VibrationEffect.createWaveform`, and the patterns stay distinct by feel.
class RunHapticPatternsTest {

    @Test
    fun `table names exactly the Dart wire names`() {
        assertEquals(
            setOf("step_work", "step_ease", "workout_complete", "pace_speed_up", "pace_slow_down"),
            RunHapticPatterns.byName.keys,
        )
    }

    @Test
    fun `every waveform is well formed`() {
        for ((name, p) in RunHapticPatterns.byName) {
            assertEquals("$name timings vs amplitudes", p.timingsMs.size, p.amplitudes.size)
            assertEquals("$name starts at once", 0L, p.timingsMs[0])
            assertTrue("$name has an even segment count", p.timingsMs.size % 2 == 0)
            p.amplitudes.forEachIndexed { i, a ->
                if (i % 2 == 0) assertEquals("$name segment $i is a gap", 0, a)
                else assertTrue("$name segment $i is a pulse", a in 1..255)
            }
            assertTrue("$name has no negative segment", p.timingsMs.all { it >= 0 })
            assertTrue("$name stays under 2 s", p.timingsMs.sum() <= 2000)
        }
    }

    private fun pulses(name: String) = RunHapticPatterns.byName.getValue(name).timingsMs.size / 2
    private fun longestPulse(name: String) =
        RunHapticPatterns.byName.getValue(name).timingsMs.filterIndexed { i, _ -> i % 2 == 1 }.max()

    @Test
    fun `step patterns are told apart by pulse count`() {
        assertEquals(3, pulses("step_work"))
        assertEquals(2, pulses("step_ease"))
        assertNotEquals(pulses("pace_speed_up"), pulses("pace_slow_down"))
    }

    @Test
    fun `step cues are long pulses, pace cues short ones`() {
        val shortest = listOf("step_work", "step_ease", "workout_complete")
            .minOf { n -> RunHapticPatterns.byName.getValue(n).timingsMs.filterIndexed { i, _ -> i % 2 == 1 }.min() }
        val longestPace = maxOf(longestPulse("pace_speed_up"), longestPulse("pace_slow_down"))
        assertTrue(shortest >= 2 * longestPace)
    }

    @Test
    fun `workout complete opens with the longest pulse of all`() {
        val complete = RunHapticPatterns.byName.getValue("workout_complete").timingsMs[1]
        for (name in RunHapticPatterns.byName.keys - "workout_complete") {
            assertTrue(name, complete > longestPulse(name))
        }
    }
}
