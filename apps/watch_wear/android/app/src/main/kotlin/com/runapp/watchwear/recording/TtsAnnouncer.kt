package com.runapp.watchwear.recording

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import com.runapp.watchwear.R
import com.runapp.watchwear.workout.PushedWorkout
import com.runapp.watchwear.workout.SpeechStrings
import com.runapp.watchwear.workout.WorkoutSpeech
import com.runapp.watchwear.workout.renderWorkoutSpeech
import java.util.Locale
import java.util.concurrent.ConcurrentHashMap

/// Thin wrapper around `android.speech.tts.TextToSpeech` used by
/// `RunRecordingService` to speak split announcements, pace alerts and the
/// steps of today's workout.
///
/// Ported in spirit from `apps/mobile_android/lib/audio_cues.dart` —
/// same phrasing ("1 kilometre, pace 5 minutes 30 seconds") so the
/// runner hears the same cues from the watch as from the phone. Engine
/// init is async; calls made before ready are silently dropped rather
/// than queued, because by the time TTS is live the relevant cue has
/// already moved on (worst case: the first km split is silent). The one
/// exception is a workout cue: the step it names is still the step the
/// runner is on when the engine comes up a second later, so the latest one
/// is held and spoken on ready.
///
/// A workout cue outranks the others in the queue ([cueQueueMode]): it
/// waits behind a split already being spoken instead of cutting it off, a
/// split or pace alert waits behind it, and a newer workout cue replaces an
/// older one still in the queue, which would only describe a step the runner
/// has left.
///
/// Safe to call from any thread — `TextToSpeech.speak` is internally
/// thread-safe. The service calls from its Default-dispatcher scope.
class TtsAnnouncer(context: Context) {
    private var tts: TextToSpeech? = null
    @Volatile private var ready: Boolean = false

    private val appContext = context.applicationContext

    private val audioManager =
        appContext.getSystemService(Context.AUDIO_SERVICE) as AudioManager

    // USAGE_ASSISTANCE_NAVIGATION_GUIDANCE asks the platform to duck
    // (briefly lower) other audio rather than pause it. On Samsung One
    // UI the attribute alone is not enough — without an explicit
    // AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK request a cue can fully pause
    // the runner's Spotify (persona round-5 samsung-watch). The same
    // attributes back both the TTS engine and the focus request so they
    // agree on the ducking contract.
    private val audioAttributes =
        AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_ASSISTANCE_NAVIGATION_GUIDANCE)
            .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
            .build()

    private val focusRequest =
        AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK)
            .setAudioAttributes(audioAttributes)
            // Cues never resume after a duck-and-pause from a higher
            // priority owner; we re-request focus per utterance, so we
            // don't need pause/resume callbacks here.
            .setWillPauseWhenDucked(false)
            .build()

    // Utterances spoken or queued, by id, valued by whether each is a
    // workout cue. Focus is held while any is in flight, so a rapid
    // start→done→start sequence keeps it and an error path cannot leak it.
    // Every callback that ends an utterance — done, error, and stop, which a
    // QUEUE_FLUSH delivers to whatever it flushed — removes its id.
    private val inFlight = ConcurrentHashMap<String, Boolean>()
    private val queueLock = Any()
    @Volatile private var holdsFocus = false

    @Volatile private var heldWorkoutCue: String? = null

    private val speechStrings = object : SpeechStrings {
        override fun string(id: Int, vararg args: Any): String =
            if (args.isEmpty()) appContext.getString(id) else appContext.getString(id, *args)

        override fun plural(id: Int, quantity: Int, vararg args: Any): String =
            appContext.resources.getQuantityString(id, quantity, *args)
    }

    init {
        // Construct lazily — the engine init spawns a thread and
        // doesn't block the caller.
        tts = TextToSpeech(context.applicationContext) { status ->
            if (status == TextToSpeech.SUCCESS) {
                // Speak in the device locale so split / pace cues match the
                // UI language. If the engine has no voice data for that
                // locale, setLanguage returns LANG_MISSING_DATA /
                // LANG_NOT_SUPPORTED and the engine keeps its default voice —
                // the cue is still spoken (best-effort), just in another
                // accent, which beats silence.
                tts?.language = Locale.getDefault()
                tts?.setSpeechRate(0.5f)
                tts?.setAudioAttributes(audioAttributes)
                tts?.setOnUtteranceProgressListener(
                    object : UtteranceProgressListener() {
                        override fun onStart(utteranceId: String?) {}

                        override fun onDone(utteranceId: String?) =
                            release(utteranceId)

                        @Deprecated("Required override; onError(id, code) is the live path")
                        override fun onError(utteranceId: String?) =
                            release(utteranceId)

                        override fun onError(utteranceId: String?, errorCode: Int) =
                            release(utteranceId)

                        override fun onStop(utteranceId: String?, interrupted: Boolean) =
                            release(utteranceId)
                    },
                )
                ready = true
                heldWorkoutCue?.let {
                    heldWorkoutCue = null
                    speak(it, workoutCue = true)
                }
            }
        }
    }

    fun announceStart() = speak(appContext.getString(R.string.tts_run_started))

    fun announceFinish(distanceM: Double, durationS: Int, unit: DistanceUnit) =
        speak(
            appContext.getString(
                when (unit) {
                    DistanceUnit.KM -> R.string.tts_run_complete_km
                    DistanceUnit.MI -> R.string.tts_run_complete_mi
                },
                finishDistanceSpoken(distanceM, unit),
                finishMinutes(durationS),
            ),
        )

    /// Announce the completion of split [splitIndex] — the [splitIndex]th
    /// whole kilometre or mile, per the runner's [unit] — with the pace
    /// reported in seconds-per-km and converted for the read-out. Mirrors
    /// the Android wording so a runner carrying both devices doesn't hear
    /// two different dialects.
    fun announceSplit(splitIndex: Int, paceSecPerKm: Double?, unit: DistanceUnit) {
        val res = appContext.resources
        val label = res.getQuantityString(
            when (unit) {
                DistanceUnit.KM -> R.plurals.tts_split_unit_km
                DistanceUnit.MI -> R.plurals.tts_split_unit_mi
            },
            splitIndex,
            splitIndex,
        )
        val ms = paceMinSecFor(paceSecPerKm, unit)
        val tail = if (ms == null) {
            ""
        } else {
            appContext.getString(
                when (unit) {
                    DistanceUnit.KM -> R.string.tts_pace_tail_km
                    DistanceUnit.MI -> R.string.tts_pace_tail_mi
                },
                ms.first,
                ms.second,
            )
        }
        speak(appContext.getString(R.string.tts_split_phrase, label, tail))
    }

    fun announcePaceAlert(tooSlow: Boolean) =
        speak(
            appContext.getString(
                if (tooSlow) R.string.tts_pace_alert_fast else R.string.tts_pace_alert_slow,
            ),
        )

    /// Speak [speech] for [workout] in the runner's [unit]. L4: a resource or
    /// format failure is logged and the cue is lost, nothing else.
    fun announceWorkout(speech: WorkoutSpeech, workout: PushedWorkout, unit: DistanceUnit) {
        val phrase = try {
            renderWorkoutSpeech(speech, workout, unit, speechStrings)
        } catch (e: Throwable) {
            android.util.Log.w(TAG, "workout cue not rendered", e)
            null
        } ?: return
        speak(phrase, workoutCue = speech.priority)
    }

    fun shutdown() {
        try {
            tts?.stop()
            tts?.shutdown()
        } catch (_: Throwable) { /* best-effort */ }
        // Drop any focus we still hold, whatever stop() reported.
        synchronized(queueLock) {
            inFlight.clear()
            heldWorkoutCue = null
            abandonFocus()
        }
        tts = null
        ready = false
    }

    private fun speak(phrase: String, workoutCue: Boolean = false) {
        // Allow empty phrases to no-op silently (formatPaceTail
        // returns "" when pace is unknown, which the split caller
        // appends unconditionally).
        if (phrase.isBlank()) return
        if (!ready) {
            if (workoutCue) heldWorkoutCue = phrase
            return
        }
        val utteranceId = "cue-${System.nanoTime()}"
        try {
            val mode = synchronized(queueLock) {
                val mode = cueQueueMode(
                    workoutCue = workoutCue,
                    workoutCueInFlight = inFlight.containsValue(true),
                    anyInFlight = inFlight.isNotEmpty(),
                )
                // The engine reports each flushed utterance through onStop,
                // later; what it flushes is out of the queue now.
                if (mode == CueQueue.FLUSH) inFlight.clear()
                inFlight[utteranceId] = workoutCue
                requestFocus()
                mode
            }
            val result = tts?.speak(
                phrase,
                if (mode == CueQueue.FLUSH) TextToSpeech.QUEUE_FLUSH else TextToSpeech.QUEUE_ADD,
                null,
                utteranceId,
            )
            // speak() returning ERROR means no callback will fire for this
            // id, so release it here to avoid a leak.
            if (result != TextToSpeech.SUCCESS) release(utteranceId)
        } catch (e: Throwable) {
            android.util.Log.w(TAG, "cue not spoken", e)
            release(utteranceId)
        }
    }

    private fun release(utteranceId: String?) {
        synchronized(queueLock) {
            if (utteranceId != null) inFlight.remove(utteranceId)
            if (inFlight.isEmpty()) abandonFocus()
        }
    }

    private fun requestFocus() {
        if (holdsFocus) return
        try {
            audioManager.requestAudioFocus(focusRequest)
            holdsFocus = true
        } catch (_: Throwable) { /* best-effort — still speak */ }
    }

    private fun abandonFocus() {
        if (!holdsFocus) return
        holdsFocus = false
        try {
            audioManager.abandonAudioFocusRequest(focusRequest)
        } catch (_: Throwable) { /* best-effort */ }
    }

    private companion object {
        const val TAG = "TtsAnnouncer"
    }
}
