package com.runapp.watchwear.workout

import com.runapp.watchwear.R
import com.runapp.watchwear.recording.DistanceUnit
import com.runapp.watchwear.recording.METRES_PER_MILE
import java.util.Locale
import kotlin.math.roundToInt

/// Universal `voice_feedback_verbosity` (docs/backend/settings.md). `minimal`
/// keeps the step change and the completion and drops the chatty in-step
/// cues (the end-of-step warning, the pace-drift nudge), as the phone does.
/// Anything but `minimal` is `full`, the registry default.
enum class VoiceVerbosity(val token: String) {
    FULL("full"),
    MINIMAL("minimal");

    companion object {
        fun fromPref(raw: String?): VoiceVerbosity = if (raw == MINIMAL.token) MINIMAL else FULL
    }
}

/// The three preferences the phone's run screen gates a spoken workout cue
/// on: `voice_feedback_enabled` (the master switch), the `workout_steps` id of
/// `voice_cue_types`, and `voice_feedback_verbosity`.
data class WorkoutVoice(
    val enabled: Boolean = true,
    val workoutSteps: Boolean = true,
    val verbosity: VoiceVerbosity = VoiceVerbosity.FULL,
)

/// What the wrist says for one feed of [WorkoutEvent]s.
sealed interface WorkoutSpeech {
    /// Whether the cue outranks a split or a pace alert in the speech queue
    /// (`cueQueueMode`).
    val priority: Boolean

    /// Step [index] began: say what to do.
    data class Step(val index: Int) : WorkoutSpeech {
        override val priority: Boolean get() = true
    }

    /// Step [index] ends in the next 50 m or 10 s.
    data class StepEnding(val index: Int) : WorkoutSpeech {
        override val priority: Boolean get() = true
    }

    data class Drift(val ahead: Boolean, val deltaSPerKm: Int) : WorkoutSpeech {
        override val priority: Boolean get() = false
    }

    data object Complete : WorkoutSpeech {
        override val priority: Boolean get() = true
    }
}

/// The one thing a feed of [events] says aloud under [voice], or null. Same
/// precedence as [workoutCue]: completion, then a new step, then the
/// end-of-step warning, then drift. Unlike the haptic, the session's first
/// step IS spoken, as on the phone: the buzz would only repeat the Start
/// press, the sentence says what the first step is. Several transitions in
/// one feed speak the step the runner is now on.
fun workoutSpeech(events: List<WorkoutEvent>, voice: WorkoutVoice): WorkoutSpeech? {
    if (!voice.enabled || !voice.workoutSteps) return null
    if (events.any { it is WorkoutEvent.Complete }) return WorkoutSpeech.Complete
    val step = events.lastOrNull { it is WorkoutEvent.Transition } as WorkoutEvent.Transition?
    if (step != null) return WorkoutSpeech.Step(step.currentIndex)
    if (voice.verbosity == VoiceVerbosity.MINIMAL) return null
    val ending = events.lastOrNull { it is WorkoutEvent.Warning } as WorkoutEvent.Warning?
    if (ending != null) return WorkoutSpeech.StepEnding(ending.index)
    val drift = events.lastOrNull { it is WorkoutEvent.PaceDrift } as WorkoutEvent.PaceDrift?
    return drift?.let { WorkoutSpeech.Drift(it.ahead, it.deltaSPerKm) }
}

/// The resource lookups the sentences are built from: the active locale's
/// resources on the watch, the `values*/strings.xml` files in a JVM test.
interface SpeechStrings {
    fun string(id: Int, vararg args: Any): String

    fun plural(id: Int, quantity: Int, vararg args: Any): String
}

/// The sentence for [speech] in the runner's [unit], or null when it names a
/// step [workout] does not have. The wording is the phone's
/// (`formatWorkoutStepUtterance`, `workoutStepProgressUtterance`,
/// `workoutPaceDriftUtterance` in `apps/mobile_android/lib/audio_cues.dart`).
fun renderWorkoutSpeech(
    speech: WorkoutSpeech,
    workout: PushedWorkout,
    unit: DistanceUnit,
    s: SpeechStrings,
): String? = when (speech) {
    WorkoutSpeech.Complete -> s.string(R.string.tts_workout_complete)
    is WorkoutSpeech.Step ->
        workout.steps.getOrNull(speech.index)?.let { stepUtterance(it, !workout.unpaced, unit, s) }
    is WorkoutSpeech.StepEnding -> workout.steps.getOrNull(speech.index)?.let {
        when {
            it.durationS != null -> s.string(R.string.tts_step_last_ten_seconds)
            unit == DistanceUnit.MI -> s.string(R.string.tts_step_last_fifty_mi)
            else -> s.string(R.string.tts_step_last_fifty_km)
        }
    }
    is WorkoutSpeech.Drift -> driftUtterance(speech.ahead, speech.deltaSPerKm, unit, s)
}

/// "Warmup", "Rep 3 of 6", "Walk 2 of 5", "Cool-down walk": the phone's
/// `workoutStepName`. A timed work rep is a walk-run "Run"; an unpaced
/// warm-up or cool-down is the walking one of a walk-run session.
fun stepName(step: PushedStep, paced: Boolean, s: SpeechStrings): String {
    val i = step.repIndex
    val n = step.repTotal
    return when (step.kind) {
        StepKind.Warmup -> s.string(if (paced) R.string.tts_step_warmup else R.string.tts_step_warmup_walk)
        StepKind.Rep -> when {
            i != null && n != null ->
                s.string(if (step.isDurationBased) R.string.tts_step_run_of else R.string.tts_step_rep_of, i, n)
            else -> s.string(if (step.isDurationBased) R.string.tts_step_run else R.string.tts_step_rep)
        }
        StepKind.Recovery -> s.string(R.string.tts_step_recovery)
        StepKind.Walk ->
            if (i != null && n != null) s.string(R.string.tts_step_walk_of, i, n) else s.string(R.string.tts_step_walk)
        StepKind.Steady -> s.string(R.string.tts_step_steady)
        StepKind.Cooldown -> s.string(if (paced) R.string.tts_step_cooldown else R.string.tts_step_cooldown_walk)
    }
}

/// "Rep 3 of 6. 400 metres at 4 minutes per kilometre." for a paced distance
/// step, "Walk 1 of 8. 1 minute 30 seconds." for a timed one. An unpaced
/// distance step is effort-led, so it carries no pace: "Walk. 400 metres."
fun stepUtterance(step: PushedStep, paced: Boolean, unit: DistanceUnit, s: SpeechStrings): String {
    val intro = stepName(step, paced, s)
    step.durationS?.let { return s.string(R.string.tts_step_duration, intro, spokenDuration(it, s)) }
    val distance = spokenDistance(step.distanceM!!.toDouble(), unit, s)
    if (!paced) return s.string(R.string.tts_step_distance, intro, distance)
    return s.string(R.string.tts_step_distance_pace, intro, distance, spokenStepPace(step.paceSPerKm, unit, s))
}

/// "1 minute 30 seconds", "45 seconds", "2 minutes": the phone's
/// `_spokenDuration`.
fun spokenDuration(seconds: Int, s: SpeechStrings): String {
    val m = seconds / 60
    val sec = seconds % 60
    if (m == 0) return s.string(R.string.tts_duration_seconds, sec)
    val minutes = s.plural(R.plurals.tts_duration_minutes, m, m)
    return if (sec == 0) minutes else s.string(R.string.tts_duration_minutes_seconds, minutes, sec)
}

/// The phone's `formatSpokenDistance`: kilometres or metres for a km runner,
/// miles or yards for a mi runner, a whole value without its ".0", one
/// decimal otherwise, and a period decimal in every locale because most
/// engines read a comma aloud as the word.
fun spokenDistance(metres: Double, unit: DistanceUnit, s: SpeechStrings): String {
    if (unit == DistanceUnit.MI) {
        val miles = metres / METRES_PER_MILE
        if (miles < 1) return s.string(R.string.tts_distance_short_mi, (metres * YARDS_PER_METRE).roundToInt())
        if (miles == Math.rint(miles)) {
            val n = miles.roundToInt()
            return s.plural(R.plurals.tts_split_unit_mi, n, n)
        }
        return s.string(R.string.tts_distance_mi, oneDecimal(miles))
    }
    if (metres < 1000) return s.string(R.string.tts_distance_short_km, metres.roundToInt())
    val km = metres / 1000
    if (km == Math.rint(km)) {
        val n = km.roundToInt()
        return s.plural(R.plurals.tts_split_unit_km, n, n)
    }
    return s.string(R.string.tts_distance_km, oneDecimal(km))
}

/// "4 minutes per kilometre", "6 minutes 26 seconds per mile": the step's
/// target pace, converted to the mile and rounded to the second for a mi
/// runner.
fun spokenStepPace(paceSPerKm: Int, unit: DistanceUnit, s: SpeechStrings): String {
    val perUnit = when (unit) {
        DistanceUnit.KM -> paceSPerKm
        DistanceUnit.MI -> (paceSPerKm * (METRES_PER_MILE / 1000.0)).roundToInt()
    }
    val m = perUnit / 60
    val sec = perUnit % 60
    return when (unit) {
        DistanceUnit.KM ->
            if (sec == 0) s.string(R.string.tts_step_pace_km_whole, m) else s.string(R.string.tts_step_pace_km, m, sec)
        DistanceUnit.MI ->
            if (sec == 0) s.string(R.string.tts_step_pace_mi_whole, m) else s.string(R.string.tts_step_pace_mi, m, sec)
    }
}

/// "Pick it up — 15 seconds per kilometre behind pace.": the miss converted to
/// the runner's unit and rounded to 5 s, never below 5 s, since the cue only
/// fires on a miss of at least twice the tolerance.
fun driftUtterance(ahead: Boolean, deltaSPerKm: Int, unit: DistanceUnit, s: SpeechStrings): String {
    val perUnit = when (unit) {
        DistanceUnit.KM -> deltaSPerKm.toDouble()
        DistanceUnit.MI -> deltaSPerKm * (METRES_PER_MILE / 1000.0)
    }
    val delta = ((perUnit / 5).roundToInt() * 5).coerceAtLeast(5)
    return s.string(
        when (unit) {
            DistanceUnit.KM -> if (ahead) R.string.tts_pace_drift_ahead_km else R.string.tts_pace_drift_behind_km
            DistanceUnit.MI -> if (ahead) R.string.tts_pace_drift_ahead_mi else R.string.tts_pace_drift_behind_mi
        },
        delta,
    )
}

private const val YARDS_PER_METRE = 1.09361

private fun oneDecimal(value: Double): String = "%.1f".format(Locale.US, value)
