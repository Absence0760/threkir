package com.runapp.watchwear.workout

import java.time.LocalDate
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Test

class WorkoutCuesTest {

    @Test
    fun `the session's first transition is silent`() {
        assertNull(workoutCue(listOf(WorkoutEvent.Transition(-1, 0))))
    }

    @Test
    fun `a new step buzzes once however many steps one feed crossed`() {
        val events = listOf(
            WorkoutEvent.Warning(0),
            WorkoutEvent.Transition(0, 1),
            WorkoutEvent.Transition(1, 2),
        )
        assertEquals(WorkoutCue.Vibrate(WorkoutHaptics.STEP), workoutCue(events))
    }

    @Test
    fun `completion outranks the step it ended`() {
        val events = listOf(WorkoutEvent.Warning(2), WorkoutEvent.Complete)
        assertEquals(WorkoutCue.Vibrate(WorkoutHaptics.COMPLETE), workoutCue(events))
    }

    @Test
    fun `the end-of-step warning ticks`() {
        assertEquals(
            WorkoutCue.Vibrate(WorkoutHaptics.STEP_ENDING),
            workoutCue(listOf(WorkoutEvent.Warning(1))),
        )
    }

    @Test
    fun `pace drift reuses the pace alert in the direction to correct`() {
        assertEquals(
            WorkoutCue.PaceAlert(tooSlow = true),
            workoutCue(listOf(WorkoutEvent.PaceDrift(0, ahead = false, deltaSPerKm = 40))),
        )
        assertEquals(
            WorkoutCue.PaceAlert(tooSlow = false),
            workoutCue(listOf(WorkoutEvent.PaceDrift(0, ahead = true, deltaSPerKm = 40))),
        )
    }

    @Test
    fun `drift on a step being left is dropped for the new step's buzz`() {
        val events = listOf(
            WorkoutEvent.PaceDrift(0, ahead = false, deltaSPerKm = 40),
            WorkoutEvent.Transition(0, 1),
        )
        assertEquals(WorkoutCue.Vibrate(WorkoutHaptics.STEP), workoutCue(events))
    }

    @Test
    fun `nothing happened is no cue`() {
        assertNull(workoutCue(emptyList()))
    }

    @Test
    fun `the three patterns are distinct from each other`() {
        val all = listOf(WorkoutHaptics.STEP, WorkoutHaptics.STEP_ENDING, WorkoutHaptics.COMPLETE)
        assertEquals(all.size, all.toSet().size)
        assertNotEquals(WorkoutHaptics.STEP, WorkoutHaptics.COMPLETE)
    }

    @Test
    fun `a runner fed through a whole session buzzes for each step and once at the end`() {
        val rep = PushedStep(StepKind.Rep, 1, 2, distanceM = 400, durationS = null, paceSPerKm = 240, toleranceSPerKm = 10)
        val runner = WorkoutRunner(
            PushedWorkout("pw", LocalDate.of(2026, 10, 17), "interval", unpaced = true, steps = listOf(rep, rep)),
        )
        val cues = listOf(
            runner.onTotals(0.0, 0.0, 0),
            runner.onTotals(400.0, 96.0, 0),
            runner.onTotals(800.0, 192.0, 0),
        ).mapNotNull(::workoutCue)
        assertEquals(
            listOf(
                WorkoutCue.Vibrate(WorkoutHaptics.STEP),
                WorkoutCue.Vibrate(WorkoutHaptics.COMPLETE),
            ),
            cues,
        )
    }
}
