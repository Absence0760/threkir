package com.runapp.watchwear.recording

/// A receiver silent this long hands the run to fused. It is longer than the
/// estimator's own gap window, which already bridges a shorter silence on
/// Doppler and the pedometer, better than fused would.
internal const val GNSS_STALE_AFTER_MS = 12_000L

/// The receiver takes the run back after this many consecutive usable fixes,
/// each within [GNSS_STALE_AFTER_MS] of the last, so a receiver flickering
/// under canopy doesn't interleave two sources fix by fix.
internal const val GNSS_RETAKE_FIXES = 3

/// A watch with no receiver, or one whose provider refuses the request, ends
/// the stream on every open; fused is already recording, so the receiver is
/// retried slowly rather than on every retry tick.
internal const val GNSS_REOPEN_INTERVAL_MS = 30_000L

/// The accuracy a fix must report to be recorded. The fused stream applies
/// the same gate before it emits.
internal const val FIX_ACCURACY_GATE_M = 30.0

/// What to do with one fix: [feed] records it, [rollSegment] ends the current
/// estimator segment first because the run just changed source.
data class SourceVerdict(val feed: Boolean, val rollSegment: Boolean)

/// Chooses between the satellite receiver (`GPS_PROVIDER`) and the fused
/// provider for each fix — the Wear port of `RunRecorder`'s source arbitration
/// in `packages/run_recorder/lib/src/run_recorder.dart`.
///
/// Fused blends non-GNSS estimates into both its position and its speed,
/// biased the same way, so the estimator cannot correct one against the
/// other; on Wear OS it can also hand the watch the paired phone's location.
/// The receiver's speed is its own Doppler, so the receiver wins whenever it
/// is delivering steadily. Only a fix the recorder would use counts as
/// delivering: under canopy a receiver keeps sending 30 m+ fixes rather than
/// falling silent, and those must not hold fused off.
///
/// Times are arrival times on a monotonic clock: the receiver's fix stamps
/// are GNSS time and fused's are not, so the two cannot be compared.
///
/// [live] is true while the run is recording and not paused. A paused fix is
/// still arbitrated, so the source is right on resume, but never fed.
class LocationSourceArbiter {
    private var lastGnssArrivalMs: Long? = null
    private var gnssStreak = 0
    private var onGnss = false
    private var gnssFixesRecorded = 0
    private var fusedFixesRecorded = 0
    private var gnssLastOpenAtMs: Long? = null

    fun onGnssFix(accuracyM: Double?, nowMs: Long, live: Boolean): SourceVerdict {
        if (!isUsable(accuracyM)) return DROP
        val last = lastGnssArrivalMs
        val steady = last != null && nowMs - last <= GNSS_STALE_AFTER_MS
        gnssStreak = if (steady) gnssStreak + 1 else 1
        lastGnssArrivalMs = nowMs
        var roll = false
        if (!onGnss) {
            if (gnssStreak < GNSS_RETAKE_FIXES) return DROP
            roll = switchSource(toGnss = true, live = live)
        }
        if (!live) return SourceVerdict(feed = false, rollSegment = roll)
        gnssFixesRecorded++
        return SourceVerdict(feed = true, rollSegment = roll)
    }

    fun onFusedFix(nowMs: Long, live: Boolean): SourceVerdict {
        var roll = false
        if (onGnss) {
            val last = lastGnssArrivalMs!!
            if (nowMs - last <= GNSS_STALE_AFTER_MS) return DROP
            roll = switchSource(toGnss = false, live = live)
        }
        if (!live) return SourceVerdict(feed = false, rollSegment = roll)
        fusedFixesRecorded++
        return SourceVerdict(feed = true, rollSegment = roll)
    }

    /// Whether the receiver stream may be opened now, stamping the attempt
    /// when it may. The first open of a session is always allowed.
    fun mayOpenReceiver(nowMs: Long): Boolean {
        val last = gnssLastOpenAtMs
        if (last != null && nowMs - last < GNSS_REOPEN_INTERVAL_MS) return false
        gnssLastOpenAtMs = nowMs
        return true
    }

    /// `metadata.location_provider`: `"gps"`, `"fused"`, or `"mixed"` when
    /// the run fell back to fused for part of it.
    fun locationProvider(): String = when {
        gnssFixesRecorded > 0 && fusedFixesRecorded > 0 -> "mixed"
        gnssFixesRecorded > 0 -> "gps"
        else -> "fused"
    }

    /// Back to fused, nothing counted, receiver free to open. Called when a
    /// recording session starts, so each run describes its own fixes.
    fun reset() {
        lastGnssArrivalMs = null
        gnssStreak = 0
        onGnss = false
        gnssFixesRecorded = 0
        fusedFixesRecorded = 0
        gnssLastOpenAtMs = null
    }

    /// The two sources disagree on position by metres and on speed by up to a
    /// quarter, and the learned Doppler scale, cross-check and accuracy scale
    /// would otherwise carry one source's bias into the other for minutes, so
    /// a switch mid-run starts a new estimator segment.
    private fun switchSource(toGnss: Boolean, live: Boolean): Boolean {
        val hadFixes = gnssFixesRecorded + fusedFixesRecorded > 0
        onGnss = toGnss
        if (!toGnss) gnssStreak = 0
        return live && hadFixes
    }

    private fun isUsable(accuracyM: Double?): Boolean =
        accuracyM != null && !accuracyM.isNaN() && accuracyM <= FIX_ACCURACY_GATE_M

    private companion object {
        val DROP = SourceVerdict(feed = false, rollSegment = false)
    }
}
