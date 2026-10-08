/// Pure helper that computes the per-canonical-distance fastest
/// embedded effort for a Run's GPS track and merges it into the
/// metadata bag. Persona-hunt Round 2 finding Pro #4 — pre-fix the
/// canonical `personal_records` cache only considered whole-run
/// distance, so a sub-20 5k inside an 18 km long run never landed in
/// the user's PR list. The refresher reads the promoted
/// `runs.fastest_X_s` columns alongside whole-run candidates
/// (migration 20270325_001; metadata keys before that); this helper
/// still writes the keys into the in-memory bag at save time, and the
/// api_client save path lifts them onto the columns — the same
/// carrier pattern as activity_type / is_dnf.
///
/// Same canonical distances + bracket midpoints the SQL trigger
/// uses (the trigger's brackets are ±2% wide; the helper picks the
/// midpoint distance per `docs/backend/metadata.md` so a 5.05 km effort
/// inside a long run is searched as 5000 m exactly).

import 'package:core_models/core_models.dart';
import 'package:run_recorder/run_recorder.dart' show GpsDistanceEstimator;

import 'run_stats.dart';

/// (promoted_column, distance_metres) pairs the trigger looks for.
const _embeddedBestDistances = <String, double>{
  'fastest_5k_s': 5000,
  'fastest_10k_s': 10000,
  'fastest_half_marathon_s': 21097.5,
  'fastest_marathon_s': 42195,
};

/// Distance covered up to each waypoint of [track], replaying it through the
/// spec-v1.1 GPS distance estimator (docs/features/gps_distance.md) — the
/// filter that owns the run's headline distance. The raw hop-sum is inflated
/// by GPS noise, so a "5 km" window measured on it closes early and the best
/// reads too fast. `t` is seconds since the first timestamped waypoint, and
/// the expected fix interval is the median positive interval so a sparse
/// track (the custom watch's 15 s / 60 s modes) is not re-anchored on every
/// fix. A waypoint without a timestamp carries the previous cumulative.
///
/// Lockstep with `estimatorCumulativeMetres` in
/// `apps/web/src/lib/integrations/garmin-fit.ts` and
/// `apps/job_worker/internal/embedded_bests.go`.
List<double> estimatorCumulativeMetres(
  List<Waypoint> track, {
  double maxSpeedMps = 10.0,
}) {
  final est = GpsDistanceEstimator(
    maxSpeedMps: maxSpeedMps,
    expectedIntervalS: medianFixIntervalS(track),
  );
  final out = List<double>.filled(track.length, 0);
  int? t0;
  for (var i = 0; i < track.length; i++) {
    final w = track[i];
    final ts = w.timestamp;
    if (ts != null) {
      final us = ts.microsecondsSinceEpoch;
      t0 ??= us;
      est.addFix(
        t: (us - t0) / 1e6,
        lat: w.lat,
        lng: w.lng,
        accuracyM: w.accuracyMetres,
        speedMps: w.speedMps,
        speedAccuracyMps: w.speedAccuracyMps,
        bearingDeg: w.bearingDeg,
      );
    }
    out[i] = est.distanceM;
  }
  return out;
}

/// The file's own per-waypoint distance stream (FIT `record.distance`),
/// rebased to 0 at the first waypoint, or null when it cannot stand in for
/// the estimator: absent, a length other than the track's, any entry
/// missing / non-finite / negative, a step backwards, or no distance gained
/// at all. A device stream is what the watch measured, so it is preferred
/// over re-estimating from the positions — the same choice Strava makes. One
/// bad sample rejects the whole stream rather than splicing two measurements
/// of the same run together.
///
/// Lockstep with `deviceCumulativeMetres` in
/// `apps/web/src/lib/integrations/garmin-fit.ts` and
/// `apps/backend/supabase/functions/_shared/strava.ts`.
List<double>? deviceCumulativeMetres(List<double?>? stream, int pointCount) {
  if (stream == null || stream.length != pointCount || pointCount < 2) {
    return null;
  }
  final out = List<double>.filled(pointCount, 0);
  var prev = double.negativeInfinity;
  for (var i = 0; i < pointCount; i++) {
    final v = stream[i];
    if (v == null || !v.isFinite || v < 0 || v < prev) return null;
    prev = v;
    out[i] = v;
  }
  final base = out.first;
  if (!(out.last > base)) return null;
  for (var i = 0; i < pointCount; i++) {
    out[i] -= base;
  }
  return out;
}

/// Median of the positive intervals (seconds) between consecutive
/// timestamped waypoints; 1.0 when there are none. An even count takes the
/// mean of the two middle values.
double medianFixIntervalS(List<Waypoint> track) {
  final intervals = <double>[];
  int? prev;
  for (final w in track) {
    final ts = w.timestamp;
    if (ts == null) continue;
    final us = ts.microsecondsSinceEpoch;
    if (prev != null && us > prev) intervals.add((us - prev) / 1e6);
    prev = us;
  }
  if (intervals.isEmpty) return 1.0;
  intervals.sort();
  final mid = intervals.length ~/ 2;
  return intervals.length.isOdd
      ? intervals[mid]
      : (intervals[mid - 1] + intervals[mid]) / 2;
}

/// Returns `metadata` with `fastest_X_s` keys merged in for each
/// canonical distance the track is long enough to cover. Measured on
/// [deviceDistancesMetres] when it passes [deviceCumulativeMetres],
/// otherwise on the estimator's cumulative ([estimatorCumulativeMetres])
/// with the speed ceiling of `metadata['activity_type']` (run when
/// absent). Existing
/// keys in `metadata` are preserved unless the helper computes a
/// FASTER time for the same key (defensive: a manual edit by the
/// runner overrides the auto-detection only if it's faster — the
/// auto value is the floor).
///
/// Returns `metadata` unchanged if the track has fewer than 3
/// points or no canonical distance fits inside it. Callers pass
/// the merged result back to the api_client save path.
Map<String, dynamic>? enrichMetadataWithEmbeddedBests({
  required List<Waypoint> track,
  Map<String, dynamic>? metadata,
  List<double?>? deviceDistancesMetres,
}) {
  if (track.length < 3) return metadata;
  final out = Map<String, dynamic>.from(metadata ?? const {});
  final rawType = out[MetadataKeys.activityType];
  final activity = ActivityType.fromName(rawType is String ? rawType : null);
  final cum = deviceCumulativeMetres(deviceDistancesMetres, track.length) ??
      estimatorCumulativeMetres(
        track,
        maxSpeedMps: activity.maxSpeedMps,
      );
  for (final entry in _embeddedBestDistances.entries) {
    final fastest = fastestWindowOf(track, entry.value, cumulative: cum);
    if (fastest == null) continue;
    // Rounded, not truncated: web's computeEmbeddedBests and the Go
    // recompute round the same milliseconds.
    final secs = (fastest.inMilliseconds / 1000).round();
    if (secs <= 0) continue;
    final existing = out[entry.key];
    final existingSecs = existing is int
        ? existing
        : (existing is num ? existing.toInt() : null);
    // Keep the fastest. A manually-edited value that's faster than
    // the auto-computed one wins (rare); the auto-computed value
    // wins when the existing key was slower / absent / non-numeric.
    if (existingSecs == null || secs < existingSecs) {
      out[entry.key] = secs;
    }
  }
  return out;
}
