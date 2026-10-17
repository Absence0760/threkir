package com.runapp.watchwear.workout

/// One vibration: alternating off/on spans in milliseconds, starting with an
/// off span, the shape `VibrationEffect.createWaveform(timings, -1)` takes.
data class HapticPattern(val timingsMs: LongArray) {
    override fun equals(other: Any?): Boolean =
        other is HapticPattern && timingsMs.contentEquals(other.timingsMs)

    override fun hashCode(): Int = timingsMs.contentHashCode()
}

/// The wrist's step-cue vocabulary. Each is told apart by feel alone, so a
/// runner with the cues muted or no headphones still knows what happened, and
/// none can be mistaken for the pace alert's two short pulses (speed up) or
/// one 220 ms pulse (slow down), which the drift cue reuses as-is.
object WorkoutHaptics {
    /// A new step began: one long buzz.
    val STEP = HapticPattern(longArrayOf(0, 500))

    /// The step ends in the next 50 m or 10 s: three quick ticks.
    val STEP_ENDING = HapticPattern(longArrayOf(0, 70, 90, 70, 90, 70))

    /// The last step ended: two long buzzes.
    val COMPLETE = HapticPattern(longArrayOf(0, 500, 200, 500))
}

/// What the wrist does for a feed of [WorkoutEvent]s.
sealed interface WorkoutCue {
    data class Vibrate(val pattern: HapticPattern) : WorkoutCue

    /// Off the step's pace band: fire the run's existing pace-alert haptic in
    /// the direction the runner has to correct.
    data class PaceAlert(val tooSlow: Boolean) : WorkoutCue
}

/// The one cue a feed of [events] produces, or null. A feed is a moment, and
/// a wrist can only say one thing at a moment, so the most important event
/// wins: completion, then a new step, then the end-of-step warning, then
/// pace drift. The warning and the drift a runner fires just before leaving
/// a step describe the step being left, so a transition in the same feed
/// replaces them; several transitions in one feed (a GPS gap crossing short
/// steps) buzz once. The session's first transition is silent: the runner
/// has just pressed Start.
fun workoutCue(events: List<WorkoutEvent>): WorkoutCue? {
    if (events.any { it is WorkoutEvent.Complete }) {
        return WorkoutCue.Vibrate(WorkoutHaptics.COMPLETE)
    }
    if (events.any { it is WorkoutEvent.Transition && it.previousIndex >= 0 }) {
        return WorkoutCue.Vibrate(WorkoutHaptics.STEP)
    }
    if (events.any { it is WorkoutEvent.Warning }) {
        return WorkoutCue.Vibrate(WorkoutHaptics.STEP_ENDING)
    }
    val drift = events.lastOrNull { it is WorkoutEvent.PaceDrift } as WorkoutEvent.PaceDrift?
    return drift?.let { WorkoutCue.PaceAlert(tooSlow = !it.ahead) }
}
