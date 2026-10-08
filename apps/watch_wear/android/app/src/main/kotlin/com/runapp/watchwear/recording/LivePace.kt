package com.runapp.watchwear.recording

/// Live pace over the GPS distance estimator's last ~200 m.
///
/// Each sample is the estimator's clock and its cumulative distance at a fix,
/// so pace is the filtered distance gained over the window, never the sum of
/// fix-to-fix hops. The hop-sum over-reads by the GPS jitter the estimator
/// removes: a steady 5:00/km with fixes 1.25 m either side of the line sums to
/// 4:00/km. The pace-alert gate and the split cue both read this value, so
/// that error told the runner they were ahead when they were on pace.
///
/// [seal] empties the window at every pause, resume and new estimator
/// segment, and [add] seals on its own across a fix interval longer than
/// [gapS], the span the estimator re-anchors over without crediting: a window
/// spanning a gap whose time carries no distance would read far too slow.
class LivePaceWindow(private val gapS: Double = ESTIMATOR_GAP_S) {

    private val samples = ArrayDeque<Pair<Double, Double>>()
    private var sinceSeal = 0

    fun seal() {
        samples.clear()
        sinceSeal = 0
    }

    fun add(t: Double, distanceM: Double) {
        if (!t.isFinite() || !distanceM.isFinite()) return
        val last = samples.lastOrNull()
        if (last != null && t <= last.first) return
        if (last != null && t - last.first > gapS) seal()
        samples.addLast(t to distanceM)
        sinceSeal++
        while (samples.size > 2 && distanceM - samples[1].second >= WINDOW_M) {
            samples.removeFirst()
        }
    }

    /// Seconds per km; null until the window since the last seal holds
    /// [MIN_SAMPLES] fixes and [MIN_WINDOW_M].
    val secondsPerKm: Double?
        get() {
            if (sinceSeal < MIN_SAMPLES || samples.size < 2) return null
            val (t0, m0) = samples.first()
            val (t1, m1) = samples.last()
            val gained = m1 - m0
            val seconds = t1 - t0
            if (gained < MIN_WINDOW_M || seconds <= 0) return null
            return seconds / gained * 1000.0
        }

    companion object {
        const val WINDOW_M = 200.0
        const val MIN_WINDOW_M = 50.0
        const val MIN_SAMPLES = 5

        /// The spec's `GAP_S` at the 1 s interval this recorder requests
        /// (`GpsRecorder`), i.e. the estimator's own re-anchor window.
        const val ESTIMATOR_GAP_S = 10.0
    }
}
