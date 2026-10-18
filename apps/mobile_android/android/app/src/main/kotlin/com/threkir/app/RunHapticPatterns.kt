package com.threkir.app

/// One vibration pattern: alternating off/on segment lengths in ms (the first
/// is the delay before the first pulse) and the amplitude of each segment.
class RunHapticPattern(val timingsMs: LongArray, val amplitudes: IntArray)

/// The patterns the run screen can ask for, keyed by the wire names in
/// `lib/step_haptics.dart` (`RunHapticPattern.wireName`). Long pulses for
/// the workout's own structure, short sharp ones for pace alerts, so a
/// runner can tell a step change from a pace nudge through a pocket.
object RunHapticPatterns {
    private const val ON = 255
    private const val LONG = 250L
    private const val SHORT = 70L
    private const val GAP = 150L

    val byName: Map<String, RunHapticPattern> = mapOf(
        "step_work" to pulses(LONG, LONG, LONG),
        "step_ease" to pulses(LONG, LONG),
        "workout_complete" to pulses(700L, LONG, LONG),
        "pace_speed_up" to pulses(SHORT, SHORT),
        "pace_slow_down" to pulses(SHORT),
    )

    private fun pulses(vararg onMs: Long): RunHapticPattern {
        val timings = mutableListOf<Long>()
        val amplitudes = mutableListOf<Int>()
        onMs.forEachIndexed { i, on ->
            timings += if (i == 0) 0L else GAP
            amplitudes += 0
            timings += on
            amplitudes += ON
        }
        return RunHapticPattern(timings.toLongArray(), amplitudes.toIntArray())
    }
}
