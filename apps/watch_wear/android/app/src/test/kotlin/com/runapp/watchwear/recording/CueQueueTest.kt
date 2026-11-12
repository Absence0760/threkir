package com.runapp.watchwear.recording

import org.junit.Assert.assertEquals
import org.junit.Test

/// How a spoken cue enters the TTS queue when another is speaking.
class CueQueueTest {

    private fun mode(workoutCue: Boolean, workoutCueInFlight: Boolean = false, anyInFlight: Boolean = false) =
        cueQueueMode(workoutCue, workoutCueInFlight, anyInFlight)

    @Test
    fun `an idle engine speaks either cue at once`() {
        assertEquals(CueQueue.FLUSH, mode(workoutCue = true))
        assertEquals(CueQueue.FLUSH, mode(workoutCue = false))
    }

    @Test
    fun `a step cue waits behind a split rather than cutting it off`() {
        assertEquals(CueQueue.ADD, mode(workoutCue = true, anyInFlight = true))
    }

    @Test
    fun `a newer step cue replaces an older one still queued`() {
        assertEquals(CueQueue.FLUSH, mode(workoutCue = true, workoutCueInFlight = true, anyInFlight = true))
    }

    @Test
    fun `a split or pace alert waits behind a step cue`() {
        assertEquals(CueQueue.ADD, mode(workoutCue = false, workoutCueInFlight = true, anyInFlight = true))
    }

    @Test
    fun `a split replaces a split, as before the workout spoke`() {
        assertEquals(CueQueue.FLUSH, mode(workoutCue = false, anyInFlight = true))
    }
}
