import 'dart:math';

/// The L5 / E5a / B2a carrier, and how far a reported carrier may sit from it
/// and still count. Every other GNSS band is tens of MHz away.
const double l5CarrierHz = 1176.45e6;
const double l5CarrierToleranceHz = 1.0e6;

/// One reading of the receiver's satellite status, reduced to the three
/// figures the run summary keeps. Built from the satellites the receiver used
/// in its fix; [meanTopCn0DbHz] is null when it used none.
class GnssStatusSample {
  const GnssStatusSample({
    required this.meanTopCn0DbHz,
    required this.usedInFix,
    required this.l5Used,
  });

  /// [cn0DbHz] and [carrierHz] hold one entry per satellite used in the fix,
  /// in the same order. A carrier the platform did not report is NaN or 0.
  /// The C/N0 mean is over the strongest four used satellites (fewer when
  /// fewer were used), the ones a position solution leans on hardest.
  factory GnssStatusSample.fromUsedSatellites(
    List<double> cn0DbHz,
    List<double> carrierHz,
  ) {
    final strengths = cn0DbHz.where((v) => v.isFinite && v >= 0).toList()
      ..sort((a, b) => b.compareTo(a));
    final top = strengths.take(4).toList();
    return GnssStatusSample(
      meanTopCn0DbHz: top.isEmpty
          ? null
          : top.reduce((a, b) => a + b) / top.length,
      usedInFix: cn0DbHz.length,
      l5Used: carrierHz.any(
        (f) => f.isFinite && (f - l5CarrierHz).abs() <= l5CarrierToleranceHz,
      ),
    );
  }

  final double? meanTopCn0DbHz;
  final int usedInFix;
  final bool l5Used;
}

/// Summarises a run's [GnssStatusSample]s into `metadata.gnss_signal`
/// (docs/backend/metadata.md). Histograms rather than a sample list, so a
/// hundred-hour run costs the same memory as a five-minute one: C/N0 in
/// 0.1 dB-Hz bins (0 to 99.9), used counts 0 to 99.
///
/// Percentiles are nearest-rank (the smallest value with at least
/// `ceil(percent * n / 100)` samples at or below it), so the median of an
/// even count is the lower middle value. The Wear OS port (`GnssSignalQuality.kt`) is pinned to this
/// one by `fixtures/gnss_signal_vectors.json`.
class GnssSignalAccumulator {
  static const int _cn0Bins = 1000;
  static const int _usedBins = 100;

  final List<int> _cn0 = List<int>.filled(_cn0Bins, 0);
  final List<int> _used = List<int>.filled(_usedBins, 0);
  int _samples = 0;
  int _fixSamples = 0;
  int _l5Samples = 0;

  int get samples => _samples;

  void add(GnssStatusSample s) {
    _samples++;
    _used[s.usedInFix.clamp(0, _usedBins - 1)]++;
    final cn0 = s.meanTopCn0DbHz;
    if (s.usedInFix < 1 || cn0 == null || !cn0.isFinite) return;
    _fixSamples++;
    _cn0[(cn0 * 10).round().clamp(0, _cn0Bins - 1)]++;
    if (s.l5Used) _l5Samples++;
  }

  /// The `metadata.gnss_signal` object, or null when no sample arrived (iOS,
  /// a phone without a receiver, an indoor run). The C/N0 figures and
  /// `l5_fraction` are over samples with at least one used satellite and are
  /// omitted when there were none; `used_median` is over every sample, so a
  /// stretch with no fix pulls it down.
  Map<String, dynamic>? toMetadata() {
    if (_samples == 0) return null;
    final out = <String, dynamic>{
      'samples': _samples,
      'used_median': _nearestRank(_used, _samples, 50),
    };
    if (_fixSamples > 0) {
      out['cn0_median_dbhz'] = _nearestRank(_cn0, _fixSamples, 50) / 10;
      out['cn0_p10_dbhz'] = _nearestRank(_cn0, _fixSamples, 10) / 10;
      out['l5_fraction'] = (_l5Samples / _fixSamples * 1000).round() / 1000;
    }
    return out;
  }

  /// Integer arithmetic for the rank: `0.1 * 30` is 3.0000000000000004 in
  /// floating point, and its ceiling would be off by one.
  static int _nearestRank(List<int> hist, int n, int percent) {
    final rank = max(1, (percent * n + 99) ~/ 100);
    var seen = 0;
    for (var i = 0; i < hist.length; i++) {
      seen += hist[i];
      if (seen >= rank) return i;
    }
    return hist.length - 1;
  }
}
