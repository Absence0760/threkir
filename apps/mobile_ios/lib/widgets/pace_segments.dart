
import 'dart:math' as math;

import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'package:core_models/core_models.dart' show ActivityType;

import '../elevation_profile.dart' show cumulativeMetres;
import '../run_stats.dart' show haversineMetres;

/// Pace colour ramp — slow → fast, 6 buckets. Designed to read clearly
/// on top of the dark map style and to map "hotter colour = faster" in
/// a way that matches what runners already expect from NRC / Strava
/// heatmaps. Bucket count matches [_ageAlphas] / [_speedBreakpoints]:
/// 5 breakpoints partition the speed range into 6 buckets.
const _paceRamp = <Color>[
  Color(0xFFEF4444), // red — slowest
  Color(0xFFF97316), // orange
  Color(0xFFFBBF24), // amber
  Color(0xFFA3E635), // lime
  Color(0xFF10B981), // emerald
  Color(0xFF22D3EE), // cyan — fastest
];

/// Three age bands (oldest → newest) applied as alpha on top of the
/// pace colour. The tail of the run fades out like a comet; the
/// segment nearest the runner is fully opaque.
const _ageAlphas = <double>[0.55, 0.80, 1.0];

/// Speed break-points (m/s), slow → fast. Four of the activities use
/// pace (min/km); cycling is displayed as speed but the buckets are
/// expressed in m/s so a single helper handles both. Values chosen so
/// a "typical" pace falls in the middle two buckets.
///
/// Conversion: m/s = 1000 / (seconds-per-km). A 5:00/km pace is 3.33 m/s.
const _speedBreakpoints = <ActivityType, List<double>>{
  // Running: 7:30, 6:10, 5:15, 4:30, 3:45 per km
  ActivityType.run: [2.2, 2.7, 3.2, 3.7, 4.4],
  // Walking: 16:40, 12:50, 10:25, 9:15, 7:35 per km
  ActivityType.walk: [1.0, 1.3, 1.6, 1.8, 2.2],
  // Cycling: 12, 18, 24, 30, 36 km/h
  ActivityType.cycle: [3.3, 5.0, 6.7, 8.3, 10.0],
  // Hiking: slower than walking, wider spread
  ActivityType.hike: [0.8, 1.1, 1.4, 1.7, 2.2],
};

/// Which pace bucket the given speed falls into. Bucket 0 is slowest,
/// `breakpoints.length` is fastest. Clamped at both ends.
@visibleForTesting
int paceBucketForSpeed(double mps, ActivityType activity) {
  final breaks = _speedBreakpoints[activity]!;
  for (int i = 0; i < breaks.length; i++) {
    if (mps < breaks[i]) return i;
  }
  return breaks.length;
}

/// Which age band the segment at [segmentIndex] falls into, given a
/// total of [segmentCount] segments. Index 0 = oldest, index 2 = newest.
/// Short tracks (≤1 segment) are treated as fully newest.
@visibleForTesting
int ageBandFor(int segmentIndex, int segmentCount) {
  if (segmentCount <= 1) return 2;
  final f = segmentIndex / (segmentCount - 1);
  if (f < 1 / 3) return 0;
  if (f < 2 / 3) return 1;
  return 2;
}

/// Pace bucket for the single segment a→b under [activity]. A segment's
/// endpoints never move once both exist (the recorder only appends), so a
/// live caller can classify each segment exactly once and extend a cached
/// bucket list by the tail instead of re-walking the whole track per fix.
int paceBucketForSegment(Waypoint a, Waypoint b, ActivityType activity) {
  final mps = _segmentSpeedMps(a, b);
  return mps == null ? 0 : paceBucketForSpeed(mps, activity);
}

/// Per-segment pace buckets for [track] under [activity]. Segment i spans
/// `track[i]`→`track[i+1]`. Returns an empty list for tracks shorter than two
/// points. This is the O(n) haversine pass [buildPaceSegments] would otherwise
/// run on every rebuild; cache it and extend only the tail during recording.
List<int> computePaceBuckets(List<Waypoint> track, ActivityType activity) {
  final segCount = track.length - 1;
  if (segCount <= 0) return const [];
  return List<int>.generate(
    segCount,
    (i) => paceBucketForSegment(track[i], track[i + 1], activity),
  );
}

double? _segmentSpeedMps(Waypoint a, Waypoint b) {
  final ta = a.timestamp;
  final tb = b.timestamp;
  if (ta == null || tb == null) return null;
  final dtSec = tb.difference(ta).inMilliseconds / 1000.0;
  if (dtSec <= 0) return null;
  final d = haversineMetres(a.lat, a.lng, b.lat, b.lng);
  if (d <= 0) return null;
  return d / dtSec;
}

/// Build the list of [Polyline]s that make up the pace-coloured, age-faded
/// live track. Each segment is assigned a `(paceBucket, ageBand)` and
/// consecutive segments sharing both are coalesced into a single polyline
/// so the map doesn't have to draw one primitive per GPS fix.
///
/// [track] and [rendered] must be the same length; [rendered] is the
/// drawing-space coordinates (e.g. smoothed) while [track] provides the
/// raw timestamps for pace computation. Returns an empty list for tracks
/// with fewer than two points.
List<Polyline> buildPaceSegments({
  required List<Waypoint> track,
  required List<LatLng> rendered,
  required ActivityType activity,
  double strokeWidth = 6,
  List<int>? paceBuckets,
}) {
  assert(track.length == rendered.length,
      'track and rendered must have matching lengths');
  final n = track.length;
  if (n < 2) return const [];

  final segCount = n - 1;
  final paceBucket = paceBuckets ?? computePaceBuckets(track, activity);
  assert(paceBucket.length == segCount,
      'paceBuckets must have one entry per segment');

  final ageBand = List<int>.filled(segCount, 0);
  for (int i = 0; i < segCount; i++) {
    ageBand[i] = ageBandFor(i, segCount);
  }

  final out = <Polyline>[];
  int runStart = 0;
  void emit(int firstSeg, int lastSegExclusive) {
    final pts = rendered.sublist(firstSeg, lastSegExclusive + 1);
    final color = _paceRamp[paceBucket[firstSeg]]
        .withValues(alpha: _ageAlphas[ageBand[firstSeg]]);
    out.add(Polyline(points: pts, strokeWidth: strokeWidth, color: color));
  }

  for (int i = 1; i < segCount; i++) {
    if (paceBucket[i] != paceBucket[i - 1] ||
        ageBand[i] != ageBand[i - 1]) {
      emit(runStart, i);
      runStart = i;
    }
  }
  emit(runStart, segCount);

  return out;
}

/// Finished-run pace ramp, slow → fast. Sequential (one hue family, ordered
/// by lightness) rather than the live map's six-bucket traffic light, so a
/// steady run reads as one warm line instead of confetti. Kept in lockstep
/// with `PACE_GRADIENT_RAMP` in `pace_segments.ts`.
const paceGradientRamp = <Color>[
  Color(0xFFFACC15), // yellow — slowest
  Color(0xFFF97316), // orange
  Color(0xFFDC2626), // red — fastest
];

/// Half-width of the centred window [smoothedSpeeds] averages over. One GPS
/// fix a second at ~3 m apart has metres of position error, which swings a
/// fix-to-fix speed by 30-100 %; 30 s of travel averages that out while
/// still showing a hill or a stoplight.
const paceSmoothingHalfWindowS = 15.0;

/// Number of distance bins a finished-run pace line is drawn in.
const paceGradientBins = 128;

/// Per-point speed (m/s) over a centred ±[paceSmoothingHalfWindowS] window,
/// measured as along-track distance over elapsed time. Null where the point
/// has no timestamp or the window spans no time.
List<double?> smoothedSpeeds(List<Waypoint> track) {
  final n = track.length;
  final out = List<double?>.filled(n, null);
  if (n < 2) return out;
  final cum = cumulativeMetres(track);
  final secs = List<double?>.generate(n, (i) {
    final t = track[i].timestamp;
    return t == null ? null : t.millisecondsSinceEpoch / 1000.0;
  });
  var lo = 0;
  var hi = 0;
  for (var i = 0; i < n; i++) {
    final s = secs[i];
    if (s == null) continue;
    while (lo < i &&
        (secs[lo] == null || secs[lo]! < s - paceSmoothingHalfWindowS)) {
      lo++;
    }
    if (hi < i) hi = i;
    while (hi + 1 < n &&
        secs[hi + 1] != null &&
        secs[hi + 1]! <= s + paceSmoothingHalfWindowS) {
      hi++;
    }
    final dt = secs[hi]! - secs[lo]!;
    if (dt <= 0) continue;
    out[i] = (cum[hi] - cum[lo]) / dt;
  }
  return out;
}

/// One colour stop on a finished-run pace line: [fraction] is the position
/// along the track by distance (0..1), [t] the pace on the run's own scale
/// (0 = slowest, 1 = fastest).
class PaceStop {
  final double fraction;
  final double t;
  const PaceStop(this.fraction, this.t);
}

/// Colour stops for a finished run's pace line, one per non-empty distance
/// bin. The domain is the run's own 5th-95th percentile of smoothed speed, so
/// a stop at a crossing or a GPS spike cannot stretch the scale for the rest
/// of the run. Empty when the track carries no usable timing.
List<PaceStop> paceGradientStops(
  List<Waypoint> track, {
  int bins = paceGradientBins,
}) {
  final n = track.length;
  if (n < 2 || bins < 1) return const [];
  final speeds = smoothedSpeeds(track);
  final known = [for (final v in speeds) if (v != null) v]..sort();
  if (known.isEmpty) return const [];
  final lo = known[((known.length - 1) * 0.05).floor()];
  final hi = known[((known.length - 1) * 0.95).floor()];
  final span = hi - lo;

  final cum = cumulativeMetres(track);
  final total = cum[n - 1];
  if (total <= 0) return const [];

  final sums = List<double>.filled(bins, 0);
  final counts = List<int>.filled(bins, 0);
  for (var i = 0; i < n; i++) {
    final v = speeds[i];
    if (v == null) continue;
    final t = span < 0.05 ? 0.5 : ((v - lo) / span).clamp(0.0, 1.0);
    final bin = math.min(bins - 1, (cum[i] / total * bins).floor());
    sums[bin] += t;
    counts[bin]++;
  }
  return [
    for (var b = 0; b < bins; b++)
      if (counts[b] > 0) PaceStop((b + 0.5) / bins, sums[b] / counts[b]),
  ];
}

/// The [paceGradientRamp] colour at [t] (0 = slowest, 1 = fastest).
Color paceGradientColour(double t) {
  final c = t.clamp(0.0, 1.0) * (paceGradientRamp.length - 1);
  final i = math.min(c.floor(), paceGradientRamp.length - 2);
  return Color.lerp(paceGradientRamp[i], paceGradientRamp[i + 1], c - i)!;
}

/// Polylines for a finished run's pace line: the track cut at the
/// [paceGradientStops] bin boundaries, each piece coloured by its bin.
/// Neighbouring bins differ by a shade, so the pieces read as one continuous
/// gradient. Empty when the track carries no usable timing.
List<Polyline> buildPaceGradientPolylines({
  required List<Waypoint> track,
  required List<LatLng> rendered,
  double strokeWidth = 5,
}) {
  assert(track.length == rendered.length,
      'track and rendered must have matching lengths');
  final stops = paceGradientStops(track);
  if (stops.isEmpty) return const [];
  final n = track.length;
  final cum = cumulativeMetres(track);
  final total = cum[n - 1];
  final tByBin = List<double?>.filled(paceGradientBins, null);
  for (final s in stops) {
    tByBin[math.min(paceGradientBins - 1, (s.fraction * paceGradientBins).floor())] =
        s.t;
  }
  var carried = stops.first.t;
  for (var b = 0; b < paceGradientBins; b++) {
    carried = tByBin[b] ?? carried;
    tByBin[b] = carried;
  }
  int binOf(int i) =>
      math.min(paceGradientBins - 1, (cum[i] / total * paceGradientBins).floor());

  final out = <Polyline>[];
  var start = 0;
  for (var i = 1; i < n; i++) {
    final last = i == n - 1;
    if (!last && binOf(i) == binOf(start)) continue;
    out.add(Polyline(
      points: rendered.sublist(start, i + 1),
      strokeWidth: strokeWidth,
      color: paceGradientColour(tByBin[binOf(start)]!),
    ));
    start = i;
  }
  return out;
}
