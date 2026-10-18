package com.runapp.watchwear.workout

import com.runapp.watchwear.R
import com.runapp.watchwear.WearLocales
import com.runapp.watchwear.recording.DistanceUnit
import java.io.File
import java.time.LocalDate
import java.util.Locale
import javax.xml.parsers.DocumentBuilderFactory
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.w3c.dom.Element

/// The spoken half of today's workout: which feed speaks under which voice
/// preference, and the sentence it speaks, read through the real
/// `values*/strings.xml` so a test sentence is the one the watch says.
class WorkoutSpeechTest {

    private val en = XmlSpeechStrings("values")

    private fun step(
        kind: StepKind,
        distanceM: Int? = null,
        durationS: Int? = null,
        pace: Int = 300,
        repIndex: Int? = null,
        repTotal: Int? = null,
    ) = PushedStep(kind, repIndex, repTotal, distanceM, durationS, pace, 10)

    private fun workout(vararg steps: PushedStep, unpaced: Boolean = false) = PushedWorkout(
        planWorkoutId = "pw",
        scheduledDate = LocalDate.of(2026, 10, 18),
        workoutKind = if (unpaced) "walk_run" else "interval",
        unpaced = unpaced,
        steps = steps.toList(),
    )

    private fun say(s: PushedStep, unit: DistanceUnit = DistanceUnit.KM, paced: Boolean = true) =
        stepUtterance(s, paced, unit, en)

    // ----- which feed speaks -----

    private val full = WorkoutVoice()
    private val minimal = WorkoutVoice(verbosity = VoiceVerbosity.MINIMAL)

    @Test
    fun `the first step is spoken, unlike its haptic`() {
        assertEquals(WorkoutSpeech.Step(0), workoutSpeech(listOf(WorkoutEvent.Transition(-1, 0)), full))
    }

    @Test
    fun `several transitions in one feed speak the step the runner is now on`() {
        val events = listOf(WorkoutEvent.Warning(0), WorkoutEvent.Transition(0, 1), WorkoutEvent.Transition(1, 2))
        assertEquals(WorkoutSpeech.Step(2), workoutSpeech(events, full))
    }

    @Test
    fun `completion outranks the step it ended`() {
        val events = listOf(WorkoutEvent.Warning(2), WorkoutEvent.Complete)
        assertEquals(WorkoutSpeech.Complete, workoutSpeech(events, full))
        assertEquals(WorkoutSpeech.Complete, workoutSpeech(events, minimal))
    }

    @Test
    fun `full mode speaks the end-of-step warning and the drift nudge`() {
        assertEquals(WorkoutSpeech.StepEnding(1), workoutSpeech(listOf(WorkoutEvent.Warning(1)), full))
        assertEquals(
            WorkoutSpeech.Drift(ahead = false, deltaSPerKm = 40),
            workoutSpeech(listOf(WorkoutEvent.PaceDrift(0, ahead = false, deltaSPerKm = 40)), full),
        )
    }

    @Test
    fun `minimal mode keeps the step change and completion and drops the chatty cues`() {
        assertEquals(WorkoutSpeech.Step(1), workoutSpeech(listOf(WorkoutEvent.Transition(0, 1)), minimal))
        assertEquals(WorkoutSpeech.Complete, workoutSpeech(listOf(WorkoutEvent.Complete), minimal))
        assertNull(workoutSpeech(listOf(WorkoutEvent.Warning(1)), minimal))
        assertNull(workoutSpeech(listOf(WorkoutEvent.PaceDrift(0, ahead = true, deltaSPerKm = 40)), minimal))
    }

    @Test
    fun `voice off, or the workout_steps cue off, speaks nothing`() {
        val every = listOf(
            listOf(WorkoutEvent.Transition(-1, 0)),
            listOf(WorkoutEvent.Transition(0, 1)),
            listOf(WorkoutEvent.Warning(1)),
            listOf(WorkoutEvent.PaceDrift(0, ahead = false, deltaSPerKm = 40)),
            listOf(WorkoutEvent.Complete),
        )
        for (voice in listOf(WorkoutVoice(enabled = false), WorkoutVoice(workoutSteps = false))) {
            for (events in every) assertNull("$voice $events", workoutSpeech(events, voice))
        }
    }

    @Test
    fun `drift on a step being left gives way to the new step`() {
        val events = listOf(WorkoutEvent.PaceDrift(0, ahead = false, deltaSPerKm = 40), WorkoutEvent.Transition(0, 1))
        assertEquals(WorkoutSpeech.Step(1), workoutSpeech(events, full))
    }

    @Test
    fun `step cues outrank a split, the drift nudge does not`() {
        assertTrue(WorkoutSpeech.Step(0).priority)
        assertTrue(WorkoutSpeech.StepEnding(0).priority)
        assertTrue(WorkoutSpeech.Complete.priority)
        assertTrue(!WorkoutSpeech.Drift(true, 30).priority)
    }

    @Test
    fun `an empty feed says nothing`() {
        assertNull(workoutSpeech(emptyList(), full))
    }

    @Test
    fun `the verbosity token reads like the registry`() {
        assertEquals(VoiceVerbosity.MINIMAL, VoiceVerbosity.fromPref("minimal"))
        assertEquals(VoiceVerbosity.FULL, VoiceVerbosity.fromPref("full"))
        assertEquals(VoiceVerbosity.FULL, VoiceVerbosity.fromPref(null))
        assertEquals(VoiceVerbosity.FULL, VoiceVerbosity.fromPref("MINIMAL"))
    }

    // ----- the step sentence, every kind -----

    @Test
    fun `a paced distance rep names its index, distance and pace`() {
        assertEquals(
            "Rep 3 of 6. 400 metres at 4 minutes per kilometre.",
            say(step(StepKind.Rep, distanceM = 400, pace = 240, repIndex = 3, repTotal = 6)),
        )
        assertEquals(
            "Rep. 400 metres at 4 minutes 5 seconds per kilometre.",
            say(step(StepKind.Rep, distanceM = 400, pace = 245)),
        )
    }

    @Test
    fun `a timed rep is a walk-run Run and carries its duration`() {
        assertEquals("Run 2 of 8. 1 minute 30 seconds.", say(step(StepKind.Rep, durationS = 90, repIndex = 2, repTotal = 8), paced = false))
        assertEquals("Run. 2 minutes.", say(step(StepKind.Rep, durationS = 120), paced = false))
    }

    @Test
    fun `walk steps name their index when they have one`() {
        assertEquals("Walk 1 of 8. 1 minute 30 seconds.", say(step(StepKind.Walk, durationS = 90, repIndex = 1, repTotal = 8), paced = false))
        assertEquals("Walk. 45 seconds.", say(step(StepKind.Walk, durationS = 45), paced = false))
    }

    @Test
    fun `warm-up and cool-down are the walking ones in an unpaced session`() {
        assertEquals("Warmup. 1 kilometre at 6 minutes per kilometre.", say(step(StepKind.Warmup, distanceM = 1000, pace = 360)))
        assertEquals("Warm-up walk. 5 minutes.", say(step(StepKind.Warmup, durationS = 300), paced = false))
        assertEquals("Cooldown. 1.5 kilometres at 6 minutes per kilometre.", say(step(StepKind.Cooldown, distanceM = 1500, pace = 360)))
        assertEquals("Cool-down walk. 5 minutes.", say(step(StepKind.Cooldown, durationS = 300), paced = false))
    }

    @Test
    fun `recovery and steady`() {
        assertEquals("Recovery. 200 metres at 7 minutes per kilometre.", say(step(StepKind.Recovery, distanceM = 200, pace = 420)))
        assertEquals("Recovery. 1 minute.", say(step(StepKind.Recovery, durationS = 60)))
        assertEquals("Steady. 8 kilometres at 5 minutes 30 seconds per kilometre.", say(step(StepKind.Steady, distanceM = 8000, pace = 330)))
    }

    @Test
    fun `an unpaced distance step is effort-led and carries no pace`() {
        assertEquals("Walk. 400 metres.", say(step(StepKind.Walk, distanceM = 400), paced = false))
        assertEquals("Warm-up walk. 1 kilometre.", say(step(StepKind.Warmup, distanceM = 1000), paced = false))
    }

    @Test
    fun `a mi runner hears miles or yards and a per-mile pace`() {
        val mi = DistanceUnit.MI
        // 400 m = 437.4 yd; 4:00/km = 386.2 s/mi = 6:26/mi.
        assertEquals(
            "Rep 3 of 6. 437 yards at 6 minutes 26 seconds per mile.",
            say(step(StepKind.Rep, distanceM = 400, pace = 240, repIndex = 3, repTotal = 6), mi),
        )
        // Only an exact mile drops the decimal, as on the phone.
        assertEquals("Steady. 1.0 miles at 8 minutes per mile.", say(step(StepKind.Steady, distanceM = 1610, pace = 298), mi))
        assertEquals("Steady. 2.0 miles at 8 minutes 3 seconds per mile.", say(step(StepKind.Steady, distanceM = 3219, pace = 300), mi))
        assertEquals("Walk. 437 yards.", say(step(StepKind.Walk, distanceM = 400), mi, paced = false))
    }

    @Test
    fun `whole distances drop the decimal and agree in number`() {
        assertEquals("1 kilometre", spokenDistance(1000.0, DistanceUnit.KM, en))
        assertEquals("5 kilometres", spokenDistance(5000.0, DistanceUnit.KM, en))
        assertEquals("1.2 kilometres", spokenDistance(1200.0, DistanceUnit.KM, en))
        assertEquals("999 metres", spokenDistance(999.0, DistanceUnit.KM, en))
        assertEquals("1 mile", spokenDistance(1609.344, DistanceUnit.MI, en))
        assertEquals("3 miles", spokenDistance(3 * 1609.344, DistanceUnit.MI, en))
        assertEquals("1.5 miles", spokenDistance(1.5 * 1609.344, DistanceUnit.MI, en))
        assertEquals("1 Kilometer", spokenDistance(1000.0, DistanceUnit.KM, XmlSpeechStrings("values-de")))
    }

    @Test
    fun `a duration speaks minutes and seconds like the phone`() {
        assertEquals("45 seconds", spokenDuration(45, en))
        assertEquals("1 minute", spokenDuration(60, en))
        assertEquals("2 minutes", spokenDuration(120, en))
        assertEquals("2 minutes 5 seconds", spokenDuration(125, en))
    }

    // ----- warning, drift, completion -----

    private val mixed = workout(
        step(StepKind.Rep, distanceM = 400, pace = 240, repIndex = 1, repTotal = 2),
        step(StepKind.Recovery, durationS = 90),
    )

    @Test
    fun `the end-of-step warning is time-based on a timed step and unit-aware on a distance one`() {
        assertEquals("Fifty metres to go", renderWorkoutSpeech(WorkoutSpeech.StepEnding(0), mixed, DistanceUnit.KM, en))
        assertEquals("Fifty yards to go", renderWorkoutSpeech(WorkoutSpeech.StepEnding(0), mixed, DistanceUnit.MI, en))
        assertEquals("Ten seconds to go", renderWorkoutSpeech(WorkoutSpeech.StepEnding(1), mixed, DistanceUnit.KM, en))
        assertEquals("Ten seconds to go", renderWorkoutSpeech(WorkoutSpeech.StepEnding(1), mixed, DistanceUnit.MI, en))
    }

    @Test
    fun `the drift nudge is rounded to five seconds in the runner's unit, never below five`() {
        assertEquals(
            "Pick it up — 25 seconds per kilometre behind pace.",
            driftUtterance(ahead = false, deltaSPerKm = 23, unit = DistanceUnit.KM, s = en),
        )
        assertEquals(
            "Ease up — 5 seconds per kilometre ahead of pace.",
            driftUtterance(ahead = true, deltaSPerKm = 2, unit = DistanceUnit.KM, s = en),
        )
        // 23 s/km × 1.609 = 37.0 s/mi → 35.
        assertEquals(
            "Pick it up — 35 seconds per mile behind pace.",
            driftUtterance(ahead = false, deltaSPerKm = 23, unit = DistanceUnit.MI, s = en),
        )
    }

    @Test
    fun `completion and a step the workout does not have`() {
        assertEquals("Workout complete. Nice work.", renderWorkoutSpeech(WorkoutSpeech.Complete, mixed, DistanceUnit.KM, en))
        assertNull(renderWorkoutSpeech(WorkoutSpeech.Step(9), mixed, DistanceUnit.KM, en))
        assertNull(renderWorkoutSpeech(WorkoutSpeech.StepEnding(9), mixed, DistanceUnit.KM, en))
    }

    @Test
    fun `the session's pacing decides whether a step carries pace`() {
        val walkRun = workout(step(StepKind.Rep, distanceM = 400, repIndex = 1, repTotal = 4), unpaced = true)
        assertEquals("Rep 1 of 4. 400 metres.", renderWorkoutSpeech(WorkoutSpeech.Step(0), walkRun, DistanceUnit.KM, en))
        assertEquals(
            "Rep 1 of 2. 400 metres at 4 minutes per kilometre.",
            renderWorkoutSpeech(WorkoutSpeech.Step(0), mixed, DistanceUnit.KM, en),
        )
    }

    // ----- every locale -----

    @Test
    fun `every shipped locale renders every sentence with nothing left unformatted`() {
        val steps = listOf(
            step(StepKind.Warmup, distanceM = 1000, pace = 360),
            step(StepKind.Rep, distanceM = 400, pace = 245, repIndex = 3, repTotal = 6),
            step(StepKind.Rep, durationS = 90, repIndex = 2, repTotal = 8),
            step(StepKind.Recovery, durationS = 61),
            step(StepKind.Walk, distanceM = 400, repIndex = 1, repTotal = 3),
            step(StepKind.Steady, distanceM = 8500, pace = 330),
            step(StepKind.Cooldown, durationS = 300),
        )
        for (dir in listOf("values") + WearLocales.translatedDirs()) {
            val s = XmlSpeechStrings(dir)
            for (unpaced in listOf(false, true)) {
                val w = workout(*steps.toTypedArray(), unpaced = unpaced)
                for (unit in DistanceUnit.entries) {
                    val said = buildList {
                        steps.indices.forEach {
                            add(renderWorkoutSpeech(WorkoutSpeech.Step(it), w, unit, s))
                            add(renderWorkoutSpeech(WorkoutSpeech.StepEnding(it), w, unit, s))
                        }
                        add(renderWorkoutSpeech(WorkoutSpeech.Complete, w, unit, s))
                        add(renderWorkoutSpeech(WorkoutSpeech.Drift(true, 30), w, unit, s))
                        add(renderWorkoutSpeech(WorkoutSpeech.Drift(false, 30), w, unit, s))
                    }
                    for (line in said) {
                        assertTrue("$dir $unit: $line", !line.isNullOrBlank())
                        assertTrue("$dir $unit unformatted: $line", !line!!.contains('%') && !line.contains('{'))
                        assertTrue("$dir $unit escape left in: $line", !line.contains('\\'))
                    }
                }
            }
        }
    }

    @Test
    fun `a German runner hears German`() {
        val de = XmlSpeechStrings("values-de")
        assertEquals(
            "Wiederholung 3 von 6. 400 Meter bei 4 Minuten pro Kilometer.",
            stepUtterance(step(StepKind.Rep, distanceM = 400, pace = 240, repIndex = 3, repTotal = 6), true, DistanceUnit.KM, de),
        )
        assertEquals("Gehen 1 von 8. 1 Minute 30 Sekunden.", stepUtterance(step(StepKind.Walk, durationS = 90, repIndex = 1, repTotal = 8), false, DistanceUnit.KM, de))
    }

    @Test
    fun `the Japanese rep counter keeps the total before the index`() {
        val ja = XmlSpeechStrings("values-ja")
        assertEquals(
            "レップ 6本中3本目。400メートルを1キロメートルあたり4分で。",
            stepUtterance(step(StepKind.Rep, distanceM = 400, pace = 240, repIndex = 3, repTotal = 6), true, DistanceUnit.KM, ja),
        )
    }
}

/// [SpeechStrings] over a `values*/strings.xml` file: the resource name is
/// recovered from the `R` id by reflection, so the id the production code
/// names is the entry the test reads. Plural selection is English-shaped (one
/// for 1, other otherwise; French's one also takes 0; Japanese has only
/// other), enough for the quantities these sentences use.
class XmlSpeechStrings(private val dir: String) : SpeechStrings {
    private val strings = mutableMapOf<String, String>()
    private val plurals = mutableMapOf<String, Map<String, String>>()
    private val locale: Locale = when (dir) {
        "values" -> Locale.ENGLISH
        else -> Locale.forLanguageTag(dir.removePrefix("values-").removePrefix("b+").replace('+', '-'))
    }

    init {
        val doc = DocumentBuilderFactory.newInstance().newDocumentBuilder()
            .parse(File(WearLocales.resDir(), "$dir/strings.xml"))
        val s = doc.getElementsByTagName("string")
        for (i in 0 until s.length) {
            val el = s.item(i) as Element
            strings[el.getAttribute("name")] = unescape(el.textContent)
        }
        val p = doc.getElementsByTagName("plurals")
        for (i in 0 until p.length) {
            val el = p.item(i) as Element
            val items = el.getElementsByTagName("item")
            plurals[el.getAttribute("name")] = (0 until items.length).associate {
                val item = items.item(it) as Element
                item.getAttribute("quantity") to unescape(item.textContent)
            }
        }
    }

    override fun string(id: Int, vararg args: Any): String {
        val name = nameOf(R.string::class.java, id)
        val template = strings[name] ?: error("$dir has no string $name")
        return String.format(locale, template, *args)
    }

    override fun plural(id: Int, quantity: Int, vararg args: Any): String {
        val name = nameOf(R.plurals::class.java, id)
        val forms = plurals[name] ?: error("$dir has no plurals $name")
        val one = quantity == 1 || (locale.language == "fr" && quantity == 0)
        val template = (if (one) forms["one"] else null) ?: forms.getValue("other")
        return String.format(locale, template, *args)
    }

    private fun nameOf(type: Class<*>, id: Int): String =
        type.fields.first { it.type == Int::class.javaPrimitiveType && it.getInt(null) == id }.name

    private fun unescape(raw: String): String =
        raw.replace("\\'", "'").replace("\\\"", "\"").replace("\\n", "\n")
}
