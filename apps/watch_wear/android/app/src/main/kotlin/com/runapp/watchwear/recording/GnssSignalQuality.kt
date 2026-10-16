package com.runapp.watchwear.recording

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlin.math.abs
import kotlin.math.max

/// The L5 / E5a / B2a carrier, and how far a reported carrier may sit from it
/// and still count. Every other GNSS band is tens of MHz away.
const val L5_CARRIER_HZ = 1176.45e6
const val L5_CARRIER_TOLERANCE_HZ = 1.0e6

/// One reading of the receiver's satellite status, reduced to the three
/// figures the run summary keeps. [meanTopCn0DbHz] is null when the receiver
/// used no satellite.
data class GnssStatusSample(
    val meanTopCn0DbHz: Double?,
    val usedInFix: Int,
    val l5Used: Boolean,
)

/// Port of the phone's `GnssStatusSample.fromUsedSatellites`
/// (`packages/run_recorder/lib/src/gnss_signal_quality.dart`). [cn0DbHz] and
/// [carrierHz] hold one entry per satellite used in the fix, in the same
/// order; a carrier the platform did not report is NaN or 0. The C/N0 mean is
/// over the strongest four, summed in descending order so the result is
/// bit-identical to the Dart side.
fun gnssStatusSample(cn0DbHz: DoubleArray, carrierHz: DoubleArray): GnssStatusSample {
    val top = cn0DbHz.filter { it.isFinite() && it >= 0 }.sortedDescending().take(4)
    var sum = 0.0
    for (v in top) sum += v
    return GnssStatusSample(
        meanTopCn0DbHz = if (top.isEmpty()) null else sum / top.size,
        usedInFix = cn0DbHz.size,
        l5Used = carrierHz.any { it.isFinite() && abs(it - L5_CARRIER_HZ) <= L5_CARRIER_TOLERANCE_HZ },
    )
}

/// `metadata.gnss_signal`, carried on the queued run and the checkpoint.
@Serializable
data class GnssSignalSummary(
    val samples: Int,
    val usedMedian: Int,
    val cn0MedianDbHz: Double? = null,
    val cn0P10DbHz: Double? = null,
    val l5Fraction: Double? = null,
)

fun GnssSignalSummary.toJson(): JsonObject = buildJsonObject {
    put("samples", samples)
    put("used_median", usedMedian)
    if (cn0MedianDbHz != null) put("cn0_median_dbhz", cn0MedianDbHz)
    if (cn0P10DbHz != null) put("cn0_p10_dbhz", cn0P10DbHz)
    if (l5Fraction != null) put("l5_fraction", l5Fraction)
}

/// Port of the phone's `GnssSignalAccumulator`, pinned to it by
/// `fixtures/gnss_signal_vectors.json`. Histograms rather than a sample list,
/// so a hundred-hour run costs the same memory as a short one: C/N0 in
/// 0.1 dB-Hz bins (0 to 99.9), used counts 0 to 99. Percentiles are
/// nearest-rank, so the median of an even count is the lower middle value.
/// Not thread-safe; the caller serialises access.
class GnssSignalAccumulator {
    private val cn0 = IntArray(CN0_BINS)
    private val used = IntArray(USED_BINS)
    private var samples = 0
    private var fixSamples = 0
    private var l5Samples = 0

    fun add(s: GnssStatusSample) {
        samples++
        used[s.usedInFix.coerceIn(0, USED_BINS - 1)]++
        val c = s.meanTopCn0DbHz
        if (s.usedInFix < 1 || c == null || !c.isFinite()) return
        fixSamples++
        cn0[Math.round(c * 10).coerceIn(0L, (CN0_BINS - 1).toLong()).toInt()]++
        if (s.l5Used) l5Samples++
    }

    /// Null when no reading arrived. The C/N0 figures and the L5 share are
    /// over readings with at least one used satellite; the used median is
    /// over every reading.
    fun summary(): GnssSignalSummary? {
        if (samples == 0) return null
        val hasFix = fixSamples > 0
        return GnssSignalSummary(
            samples = samples,
            usedMedian = nearestRank(used, samples, 50),
            cn0MedianDbHz = if (hasFix) nearestRank(cn0, fixSamples, 50) / 10.0 else null,
            cn0P10DbHz = if (hasFix) nearestRank(cn0, fixSamples, 10) / 10.0 else null,
            l5Fraction = if (hasFix) Math.round(l5Samples.toDouble() / fixSamples * 1000) / 1000.0 else null,
        )
    }

    private companion object {
        const val CN0_BINS = 1000
        const val USED_BINS = 100

        fun nearestRank(hist: IntArray, n: Int, percent: Int): Int {
            val rank = max(1, (percent * n + 99) / 100)
            var seen = 0
            for (i in hist.indices) {
                seen += hist[i]
                if (seen >= rank) return i
            }
            return hist.size - 1
        }
    }
}
