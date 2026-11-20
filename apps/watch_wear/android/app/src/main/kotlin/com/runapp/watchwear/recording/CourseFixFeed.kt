package com.runapp.watchwear.recording

import com.runapp.watchwear.GpsPoint
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.asSharedFlow

/// One fix the track file stored on the line, at the instant it stored:
/// `TrackWriter` writes `ts` as `Instant.ofEpochMilli(point.epochMs)`, so
/// [epochMs] is that `ts` to the millisecond.
data class CourseFix(val runId: String, val lat: Double, val lng: Double, val epochMs: Long) {
    companion object {
        fun of(runId: String, point: GpsPoint) = CourseFix(runId, point.lat, point.lng, point.epochMs)
    }
}

/// Every line fix the recording stores, in order, for the live course timer
/// (#1446). The server times a course on every stored fix that is not
/// `offTrack`, at its stored `ts`; the timer has to read the same fixes at the
/// same instants, or a fix dropped inside a 35 m checkpoint circle leaves the
/// wrist silent while the board times the run. `RecordingRepository.metrics`
/// cannot carry that: it is a conflated `StateFlow`, so a slow collector sees
/// only the latest point.
///
/// Written by `RunRecordingService` right after `TrackWriter.append`, read by
/// `RunViewModel`. [publish] never suspends and never blocks the fix path;
/// the buffer holds over an hour of 1 Hz fixes for a collector that falls
/// behind, and with no collector (no screen) a fix is simply not delivered.
object CourseFixFeed {
    const val BUFFER = 4096

    private val flow = MutableSharedFlow<CourseFix>(
        extraBufferCapacity = BUFFER,
        onBufferOverflow = BufferOverflow.DROP_OLDEST,
    )

    val fixes: SharedFlow<CourseFix> = flow.asSharedFlow()

    fun publish(fix: CourseFix) {
        flow.tryEmit(fix)
    }
}
