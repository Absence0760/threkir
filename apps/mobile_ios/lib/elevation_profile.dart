import 'dart:math' as math;

import 'package:core_models/core_models.dart';

import 'run_stats.dart' show haversineMetres;

// Shaping for the run-detail elevation chart: gap filling, distance-window
// smoothing and the y-axis domain. Twin of
// `apps/web/src/lib/runs/elevation_profile.ts`, plus `elevationSeries`, whose
// web half is `elevationSeries` in `runs/key_stats.ts` — keep them in lockstep
// so one run draws the same profile on both.

/// Fewest real altitude samples a track needs before it has a profile.
const minElevationSamples = 2;

/// Half-width of the along-track window [smoothElevation] averages over.
/// Phone GPS altitude wanders by metres between fixes a second apart; an
/// 80 m window keeps a real climb and drops the per-fix sawtooth.
const elevationSmoothingHalfWindowM = 40.0;

/// Smallest vertical span the chart will draw. Stretching 3 m of jitter over
/// the full chart height made a flat run look mountainous.
const elevationMinSpanM = 30.0;

/// One elevation per track point with the gaps filled, or null when fewer
/// than [minElevationSamples] points carry an altitude.
///
/// A gap is never sea level: filling it with 0 drew a dropout as a cliff to
/// the floor and dragged the axis down with it. Interior gaps interpolate
/// linearly in index; leading and trailing gaps carry the nearest sample, the
/// same carry-across `computeElevationGain` applies, so the chart and the
/// climb figure beside it agree about what a gap means.
List<double>? elevationSeries(List<Waypoint> track) {
  if (track.length < 2) return null;
  final known = <int>[
    for (var i = 0; i < track.length; i++)
      if (track[i].elevationMetres?.isFinite ?? false) i,
  ];
  if (known.length < minElevationSamples) return null;

  double eleAt(int i) => track[i].elevationMetres!;
  final out = List<double>.filled(track.length, 0);
  for (final k in known) {
    out[k] = eleAt(k);
  }
  for (var i = 0; i < known.first; i++) {
    out[i] = eleAt(known.first);
  }
  for (var i = known.last + 1; i < track.length; i++) {
    out[i] = eleAt(known.last);
  }
  for (var k = 1; k < known.length; k++) {
    final a = known[k - 1];
    final b = known[k];
    final span = b - a;
    if (span < 2) continue;
    final rise = eleAt(b) - eleAt(a);
    for (var i = a + 1; i < b; i++) {
      out[i] = eleAt(a) + rise * (i - a) / span;
    }
  }
  return out;
}

/// Distance from the start to each point of [track], in metres.
List<double> cumulativeMetres(List<Waypoint> track) {
  final out = List<double>.filled(track.length, 0);
  for (var i = 1; i < track.length; i++) {
    final a = track[i - 1], b = track[i];
    out[i] = out[i - 1] + haversineMetres(a.lat, a.lng, b.lat, b.lng);
  }
  return out;
}

/// Centred moving average of [series] over the points within ±h of each
/// point's along-track distance, where h is [halfWindowM] shrunk near either
/// end so the window stays symmetric. A one-sided window at the ends would
/// drag the first and last values toward the middle; a symmetric one leaves
/// a straight climb exactly as recorded, ends included. Same length as the
/// input, so a hovered index still maps back to the same track point.
List<double> smoothElevation(
  List<double> series,
  List<double> cumulativeM, {
  double halfWindowM = elevationSmoothingHalfWindowM,
}) {
  final n = series.length;
  if (n != cumulativeM.length) {
    throw ArgumentError('series and cumulativeM must match');
  }
  final prefix = List<double>.filled(n + 1, 0);
  for (var i = 0; i < n; i++) {
    prefix[i + 1] = prefix[i] + series[i];
  }
  int firstAtLeast(double d) {
    var lo = 0, hi = n - 1;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (cumulativeM[mid] < d) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  int lastAtMost(double d) {
    var lo = 0, hi = n - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (cumulativeM[mid] > d) {
        hi = mid - 1;
      } else {
        lo = mid;
      }
    }
    return lo;
  }

  final total = n > 0 ? cumulativeM[n - 1] : 0.0;
  final out = List<double>.filled(n, 0);
  for (var i = 0; i < n; i++) {
    final h = [halfWindowM, cumulativeM[i] - cumulativeM[0], total - cumulativeM[i]]
        .reduce((a, b) => a < b ? a : b);
    final lo = math.min(i, firstAtLeast(cumulativeM[i] - h));
    final hi = math.max(i, lastAtMost(cumulativeM[i] + h));
    out[i] = (prefix[hi + 1] - prefix[lo]) / (hi - lo + 1);
  }
  return out;
}

/// The y-axis range for a profile spanning [min]..[max] metres: at least
/// [elevationMinSpanM] tall, centred on the data, plus 10 % headroom on each
/// side so the line never touches the frame.
({double lo, double hi}) elevationDomain(double min, double max) {
  var a = min < max ? min : max;
  var b = min < max ? max : min;
  final span = b - a;
  if (span < elevationMinSpanM) {
    final extra = (elevationMinSpanM - span) / 2;
    a -= extra;
    b += extra;
  }
  final pad = (b - a) * 0.1;
  return (lo: a - pad, hi: b + pad);
}
