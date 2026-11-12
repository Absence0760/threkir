package com.runapp.watchwear.workout

import java.io.File
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/// Source-level guard for how the spoken workout cues are wired: the service,
/// the TTS engine and the view model are the halves no host JVM can run. The
/// pure halves are `WorkoutSpeechTest` and `CueQueueTest`.
class WorkoutSpeechWiringTest {

    private val service: String =
        File("src/main/kotlin/com/runapp/watchwear/recording/RunRecordingService.kt").readText()

    private val announcer: String =
        File("src/main/kotlin/com/runapp/watchwear/recording/TtsAnnouncer.kt").readText()

    private val vm: String =
        File("src/main/kotlin/com/runapp/watchwear/RunViewModel.kt").readText()

    private fun body(src: String, signature: String): String {
        val start = src.indexOf(signature)
        assertTrue("missing $signature", start >= 0)
        val end = src.indexOf("\n    }\n", start)
        return src.substring(start, end)
    }

    @Test
    fun `every workout feed buzzes and then speaks`() {
        val publish = body(service, "private fun publishWorkout(")
        val haptic = publish.indexOf("workoutCue(events)")
        val speech = publish.indexOf("speakWorkout(events)")
        assertTrue("the haptic must still fire", haptic >= 0)
        assertTrue("the feed must reach the spoken half", speech > haptic)
    }

    @Test
    fun `workout drift buzzes without the generic spoken pace alert`() {
        val publish = body(service, "private fun publishWorkout(")
        assertTrue(publish.contains("is WorkoutCue.PaceAlert -> vibratePaceAlert(cue.tooSlow)"))
        assertFalse(
            "firePaceAlert speaks the run's generic alert, ungated by minimal mode",
            publish.contains("firePaceAlert("),
        )
    }

    @Test
    fun `the spoken half is gated by every voice preference and cannot throw into the ticker`() {
        val speak = body(service, "private fun speakWorkout(")
        assertTrue("the master switch goes through cues", speak.contains("val announcer = cues ?: return"))
        assertTrue(speak.contains("enabled = voiceFeedbackEnabled"))
        assertTrue(speak.contains("workoutSteps = workoutStepCuesEnabled"))
        assertTrue(speak.contains("verbosity = voiceFeedbackVerbosity"))
        assertTrue(speak.contains("announcer.announceWorkout(speech, workout, preferredUnit)"))
        assertTrue("L4: a speech failure stays here", speak.trimStart().let { it.contains("try {") && it.contains("catch (e: Throwable)") })
    }

    @Test
    fun `the preferences ride the start intent from the universal bag`() {
        val start = body(service, "private fun startRecording(")
        assertTrue(start.contains("this.voiceFeedbackVerbosity = voiceFeedbackVerbosity"))
        assertTrue(start.contains("this.workoutStepCuesEnabled = workoutStepCuesEnabled"))
        assertTrue(service.contains("VoiceVerbosity.fromPref(\n                    intent.getStringExtra(EXTRA_VOICE_VERBOSITY)"))
        assertTrue(service.contains("intent.getBooleanExtra(EXTRA_WORKOUT_STEP_CUES, true)"))
        assertTrue(service.contains("putExtra(EXTRA_VOICE_VERBOSITY, voiceFeedbackVerbosity.token)"))
        assertTrue(service.contains("putExtra(EXTRA_WORKOUT_STEP_CUES, workoutStepCuesEnabled)"))

        val apply = body(vm, "private fun applyUniversalPrefsAsync()")
        assertTrue(apply.contains("voiceFeedbackVerbosity = settings.voiceFeedbackVerbosity"))
        assertTrue(apply.contains("workoutStepCuesEnabled = settings.workoutStepCuesEnabled"))
        val vmStart = body(vm, "fun start()")
        assertTrue(vmStart.contains("voiceFeedbackVerbosity = _state.value.voiceFeedbackVerbosity"))
        assertTrue(vmStart.contains("workoutStepCuesEnabled = _state.value.workoutStepCuesEnabled"))
    }

    @Test
    fun `the announcer renders from resources and queues by priority`() {
        val announce = body(announcer, "fun announceWorkout(")
        assertTrue(announce.contains("renderWorkoutSpeech(speech, workout, unit, speechStrings)"))
        assertTrue("a render failure is logged, not thrown", announce.contains("catch (e: Throwable)"))
        assertTrue(announce.contains("speak(phrase, workoutCue = speech.priority)"))

        val speak = body(announcer, "private fun speak(")
        assertTrue(speak.contains("cueQueueMode("))
        assertTrue(speak.contains("TextToSpeech.QUEUE_ADD"))
        assertTrue("a workout cue before the engine is ready is held", speak.contains("heldWorkoutCue = phrase"))
        assertTrue("the held cue is spoken on ready", announcer.contains("speak(it, workoutCue = true)"))
    }

    @Test
    fun `a flushed utterance releases its hold on audio focus`() {
        // QUEUE_FLUSH reports what it dropped through onStop, not onDone; an
        // utterance released by neither keeps the runner's music ducked.
        assertTrue(
            Regex("""override fun onStop\(utteranceId: String\?, interrupted: Boolean\) =\s*release\(utteranceId\)""")
                .containsMatchIn(announcer),
        )
    }
}
