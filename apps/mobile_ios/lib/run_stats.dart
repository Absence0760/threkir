import 'dart:math';

import 'package:core_models/core_models.dart';

import 'l10n/gen/app_localizations.dart';
import 'run_altitude.dart';

/// Localized display name for a best-effort race distance. The dashboard +
/// run-detail best-effort tables key their maps on the canonical English
/// label (also used for the metres lookup), so this resolves that key to the
/// locale's distance name at render time. Unknown keys pass through.
String bestEffortDistanceLabel(AppLocalizations l10n, String key) {
  switch (key) {
    case '5 km':
      return l10n.raceDistance5k;
    case '10 km':
      return l10n.raceDistance10k;
    case 'Half Marathon':
      return l10n.raceDistanceHalfMarathon;
    case 'Marathon':
      return l10n.raceDistanceMarathon;
    default:
      return key;
  }
}

/// Whether every point of [track] carries the recorder's cumulative credited
/// distance ([Waypoint.cumulativeDistanceMetres]): finite, non-negative and
/// never decreasing. All or nothing, so a track that mixes stamped and
/// unstamped points (an older recorder's points ahead of a resumed session's)
/// measures on positions throughout rather than on two different axes.
/// Mirrors `hasRecordedDistances` in `apps/web/src/lib/runs/run_stats.ts`.
bool hasRecordedDistances(List<Waypoint> track) {
  if (track.length < 2) return false;
  var prev = 0.0;
  for (final w in track) {
    final d = w.cumulativeDistanceMetres;
    if (d == null || !d.isFinite || d < prev) return false;
    prev = d;
  }
  return true;
}

/// Distance along the run at each point of [track], metres: the axis splits
/// and moving time are measured on (`docs/features/gps_distance.md` § Splits
/// and moving time).
///
/// A track whose every point carries [Waypoint.cumulativeDistanceMetres] uses
/// it, scaled so the last point reads [totalDistanceMetres] when that is given:
/// the recorder's figure stops at the last stored fix while the run's distance
/// also counts what the estimator credited after it, and the server recompute
/// rewrites `distance_m` without touching the stored track. Otherwise the
/// hop-sum over the line positions ([Waypoint.lineLat] / [Waypoint.lineLng]),
/// unscaled, which is what every track before the key measures on. Pass
/// [totalDistanceMetres] only with the whole stored track (the owner's): a
/// privacy-clipped one ends short of the run and would be stretched. Mirrors
/// `trackCumulativeMetres` in `apps/web/src/lib/runs/run_stats.ts`.
List<double> trackCumulativeMetres(
  List<Waypoint> track, {
  double? totalDistanceMetres,
}) {
  final n = track.length;
  if (n == 0) return const [];
  if (hasRecordedDistances(track)) {
    final last = track[n - 1].cumulativeDistanceMetres!;
    final total = totalDistanceMetres;
    final scale = total != null && total.isFinite && total > 0 && last > 0
        ? total / last
        : 1.0;
    return [for (final w in track) w.cumulativeDistanceMetres! * scale];
  }
  final out = List<double>.filled(n, 0);
  for (var i = 1; i < n; i++) {
    final a = track[i - 1];
    final b = track[i];
    out[i] = out[i - 1] + haversineMetres(a.lineLat, a.lineLng, b.lineLat, b.lineLng);
  }
  return out;
}

/// ~1.8 km/h: slower than a slow walk, faster than GPS jitter standing still.
/// The finished moving time, the live Avg pace and the "Stopped" chip share
/// it.
const double kMovingMinSpeedMps = 0.5;

/// Display only: the clock keeps running (decisions § 4).
const Duration kStoppedAfter = Duration(seconds: 10);

/// The moving-time rule one segment at a time, shared by [movingTimeOf] and
/// the live screen. [extend] decides recorded-vs-position distance per
/// segment where [trackCumulativeMetres] decides for the whole track; they
/// agree on a recorder line, where every point is stamped.
class MovingTimeAccumulator {
  MovingTimeAccumulator({this.minSpeedMps = kMovingMinSpeedMps});

  final double minSpeedMps;
  int _movingMs = 0;
  DateTime? _lastMovingAt;
  int _extended = 0;

  Duration get movingTime => Duration(milliseconds: _movingMs);

  DateTime? get lastMovingAt => _lastMovingAt;

  void addSegment(DateTime? from, DateTime? to, double metres) {
    if (from == null || to == null) return;
    final dtMs = to.difference(from).inMilliseconds;
    if (dtMs <= 0) return;
    if (metres / (dtMs / 1000.0) >= minSpeedMps) {
      _movingMs += dtMs;
      _lastMovingAt = to;
    }
  }

  /// Folds only the points not yet seen; a shorter track is a new recording.
  void extend(List<Waypoint> track) {
    if (track.length < _extended) reset();
    for (var i = _extended == 0 ? 1 : _extended; i < track.length; i++) {
      final a = track[i - 1];
      final b = track[i];
      final ca = a.cumulativeDistanceMetres;
      final cb = b.cumulativeDistanceMetres;
      addSegment(
        a.timestamp,
        b.timestamp,
        ca != null && cb != null
            ? cb - ca
            : haversineMetres(a.lineLat, a.lineLng, b.lineLat, b.lineLng),
      );
    }
    _extended = track.length;
  }

  void reset() {
    _movingMs = 0;
    _lastMovingAt = null;
    _extended = 0;
  }
}

/// Every argument is a fix timestamp, so one clock. [since] is the first fix
/// after start or resume, so a resume cannot open on a stale "Stopped". The
/// caller also hides the chip when GPS goes quiet: then the stillness is the
/// receiver's, not the runner's.
bool isStandingStill({
  required DateTime? latestFixAt,
  required DateTime? lastMovingAt,
  required DateTime? since,
}) {
  if (latestFixAt == null || since == null) return false;
  final from =
      lastMovingAt != null && lastMovingAt.isAfter(since) ? lastMovingAt : since;
  return latestFixAt.difference(from) >= kStoppedAfter;
}

/// Moving time only when GPS fixes measured the distance: a pedometer or
/// belt credits distance no fix spans, which would divide by too little
/// time, so those average over the clock.
Duration averagingTime({
  required bool gpsMeasured,
  required Duration movingTime,
  required Duration elapsed,
}) =>
    gpsMeasured ? movingTime : elapsed;

/// Compute **moving time** from a GPS track — the subset of elapsed time
/// during which the runner was actually moving, excluding stops at traffic
/// lights, water fountains, and so on. It replaced live auto-pause (decisions
/// § 4), as Strava and Nike Run Club do.
///
/// Distance per segment is read off [trackCumulativeMetres] (the estimator's
/// credit when the track carries it, so a stop the filter held still is not
/// moving time however far the raw fixes wandered).
Duration movingTimeOf(
  List<Waypoint> track, {
  double minSpeedMps = kMovingMinSpeedMps,
}) {
  if (track.length < 2) return Duration.zero;
  final cum = trackCumulativeMetres(track);
  final acc = MovingTimeAccumulator(minSpeedMps: minSpeedMps);
  for (var i = 1; i < track.length; i++) {
    acc.addSegment(
        track[i - 1].timestamp, track[i].timestamp, cum[i] - cum[i - 1]);
  }
  return acc.movingTime;
}

/// Relative slack on the window comparison. `cum` is an accumulated sum of
/// hundreds of great-circle legs, so a track that IS exactly the window
/// measures a hair either side of it and the strict `<` decided whether a
/// nominally-10.00 km effort produced a best at all on the last bit. Scaled by
/// the window rather than absolute, because the drift grows with the sum:
/// measured, an evenly-spaced 10 km track of 1 000 legs sums to
/// 9 999.999 999 999 900 m, and the largest relative drift over 20 000 legs of
/// a marathon window is 9.2e-14. 1e-9 of the marathon window is 42 um — four
/// orders of magnitude above that and far below any GPS fix. Web's
/// `WINDOW_TOLERANCE_RATIO` in `integrations/garmin-fit.ts` and the Deno
/// importer's own copy carry the same number.
const double windowToleranceRatio = 1e-9;

/// Fastest continuous `windowMetres` covered anywhere in the track.
///
/// This is what users expect "Fastest 5k" to mean — the quickest rolling
/// 5 km window inside any run, not `total_time * 5000 / total_distance`,
/// which just reports the overall average pace scaled to 5 km. The two
/// give the same answer only for runs that were paced perfectly evenly.
///
/// Returns null when the track has fewer than two timestamped points or
/// covers less than [windowMetres] total distance. Segments with missing
/// timestamps are tolerated — the algorithm skips them for the time sum
/// and lets the distance sum continue.
///
/// Algorithm: sliding window. For each endpoint `j`, advance the start
/// `i` forward as long as the window `[i+1, j]` still covers at least
/// [windowMetres]. When the window crosses the exact [windowMetres]
/// boundary, linearly interpolate inside the [i, i+1] segment to find
/// the precise start time — otherwise the result would be quantised to
/// whichever waypoint first pushed the window over the threshold, which
/// is noisy for sparse tracks. O(n).
///
/// [cumulative], when given, is the distance covered up to each waypoint
/// (same length as [track]) and replaces the raw haversine hop-sum — the
/// embedded-best writer passes the GPS distance estimator's cumulative so
/// GPS noise cannot close a window early.
Duration? fastestWindowOf(
  List<Waypoint> track,
  double windowMetres, {
  List<double>? cumulative,
}) {
  final n = track.length;
  if (n < 2 || windowMetres <= 0) return null;
  if (cumulative != null && cumulative.length != n) {
    throw ArgumentError.value(
        cumulative.length, 'cumulative', 'must have one entry per waypoint ($n)');
  }

  final cum = cumulative ?? List<double>.filled(n, 0);
  if (cumulative == null) {
    for (var i = 1; i < n; i++) {
      cum[i] = cum[i - 1] +
          haversineMetres(
            track[i - 1].lat,
            track[i - 1].lng,
            track[i].lat,
            track[i].lng,
          );
    }
  }
  final covers = windowMetres * (1 - windowToleranceRatio);
  if (cum[n - 1] < covers) return null;

  Duration? best;
  var i = 0;
  for (var j = 1; j < n; j++) {
    while (i + 1 < j && cum[j] - cum[i + 1] >= covers) {
      i++;
    }
    if (cum[j] - cum[i] < covers) continue;

    final ti = track[i].timestamp;
    final tj = track[j].timestamp;
    if (ti == null || tj == null) continue;

    final segDist = cum[i + 1] - cum[i];
    int startMs;
    if (segDist <= 0) {
      startMs = ti.millisecondsSinceEpoch;
    } else {
      final ti1 = track[i + 1].timestamp;
      if (ti1 == null) {
        startMs = ti.millisecondsSinceEpoch;
      } else {
        final targetCum = cum[j] - windowMetres;
        final fraction = ((targetCum - cum[i]) / segDist).clamp(0.0, 1.0);
        final a = ti.millisecondsSinceEpoch;
        final b = ti1.millisecondsSinceEpoch;
        startMs = a + ((b - a) * fraction).round();
      }
    }

    final windowMs = tj.millisecondsSinceEpoch - startMs;
    if (windowMs <= 0) continue;
    final d = Duration(milliseconds: windowMs);
    if (best == null || d < best) best = d;
  }
  return best;
}

/// One completed split: the 1-based tick index (km or mile), the elapsed
/// time across it, and its net elevation change in whole metres (positive =
/// gain; null when no point of the track carries an altitude). Each split
/// spans exactly one tick length by construction.
class RunSplit {
  const RunSplit(this.tick, this.duration, {this.elevationMetres});
  final int tick;
  final Duration duration;
  final int? elevationMetres;
}

/// Per-tick splits from a track. [tickLengthM] is 1000 for km, 1609.344 for
/// miles; [startedAt] seeds the clock when a boundary-crossing point carries no
/// timestamp (imported runs may not stamp every point).
///
/// Emits one split per boundary the cumulative distance crosses, interpolating
/// the crossing time by the distance fraction along the crossing segment. A
/// single long inter-fix gap (a tunnel, a canyon/forest signal loss, or a
/// downsampled Strava/Garmin import) can straddle several boundaries at once;
/// the previous single-`tickEnd`-per-segment loop then re-used the segment's
/// end time for every boundary it crossed, so the 2nd and later splits reported
/// a 0:00 duration (which also poisoned the "fastest split" reduction). One
/// interpolated split per tick fixes that.
///
/// Distance is [trackCumulativeMetres] with [totalDistanceMetres]: pass the
/// run's distance and a track that carries the recorder's cumulative credit
/// places every boundary on the same axis as the headline figure.
///
/// Elevation is the net change across the split, read off
/// [runAltitudeSeries] — the barometer when the run carries one, else GPS
/// altitude, never an off-track fix's — so it agrees with the run's climb and
/// elevation chart. The altitude at a boundary is interpolated along the
/// distance axis between the nearest points that carry one, so a dropout is
/// carried across, and held flat past the first and last of them; a split
/// wholly outside the stretch that carries an altitude is null. Rounded
/// half toward +infinity, as `Math.round` does in the web twin
/// `computeRealSplits`.
List<RunSplit> computeSplitDurations(
  List<Waypoint> track,
  double tickLengthM,
  DateTime startedAt, {
  double? totalDistanceMetres,
}) {
  if (track.length < 2 || tickLengthM <= 0) return const [];
  // A track with no timestamp at all (a GPX route, a manual run's drawn
  // line) has no split times: every boundary fell back to [startedAt], so it
  // emitted one 0:00 split per tick. Web's computeRealSplits returns [] here.
  if (!track.any((w) => w.timestamp != null)) return const [];
  final cum =
      trackCumulativeMetres(track, totalDistanceMetres: totalDistanceMetres);
  final elevationOf = _splitElevationReader(runAltitudeSeries(track), cum);
  final splits = <RunSplit>[];
  var cumulative = 0.0;
  var nextTick = 1;
  var tickStart = track.first.timestamp ?? startedAt;
  var tickStartDist = 0.0;

  for (var i = 1; i < track.length; i++) {
    final a = track[i - 1];
    final b = track[i];
    final segStart = i == 1 ? 0.0 : cum[i - 1];
    cumulative = cum[i];
    final segDist = cumulative - segStart;
    final aTime = a.timestamp;
    // Fall back to the segment's own start, never to the run start. A GPX
    // import can leave a mid-track point untimestamped (route_parser sets
    // timestamp: null when a <trkpt> has no <time>), and substituting
    // startedAt there made bTime.difference(aTime) hugely NEGATIVE — the
    // interpolated crossing landed before tickStart, so that split reported a
    // negative duration and, because tickStart is then advanced to it, every
    // later split was garbage too.
    final bTime = b.timestamp ?? aTime ?? startedAt;

    while (segDist > 0 && cumulative >= nextTick * tickLengthM) {
      final boundaryDist = nextTick * tickLengthM;
      final f = (boundaryDist - segStart) / segDist;
      final interpolated = aTime != null
          ? aTime.add(Duration(
              milliseconds: (bTime.difference(aTime).inMilliseconds * f).round()))
          : bTime;
      // Crossing times are monotonic by construction: a split can be 0:00 but
      // never negative. Also absorbs a genuinely backwards timestamp, which
      // Android produces when it batches queued fixes or after an NTP
      // correction.
      final crossTime =
          interpolated.isBefore(tickStart) ? tickStart : interpolated;
      splits.add(RunSplit(
        nextTick,
        crossTime.difference(tickStart),
        elevationMetres: elevationOf(tickStartDist, boundaryDist),
      ));
      tickStart = crossTime;
      tickStartDist = boundaryDist;
      nextTick++;
    }
  }
  return splits;
}

/// The net elevation, whole metres, of the split from `start` to `end` along
/// the split axis: [cum] with the first point at 0, the axis the boundary loop
/// in [computeSplitDurations] walks. The altitude at each end is linear
/// between the nearest points of [altitudes] that carry one, and held at the
/// first / last of them for a split that only partly overlaps the measured
/// stretch. A split wholly before the first or after the last altitude is
/// null, not a held 0 m that would read as measured. Rounded half toward
/// +infinity, as `Math.round` does. Twin of `splitElevationReader` in
/// `run_stats.ts`.
int? Function(double start, double end) _splitElevationReader(
    List<double?> altitudes, List<double> cum) {
  final at = <double>[];
  final alt = <double>[];
  for (var i = 0; i < altitudes.length; i++) {
    final v = altitudes[i];
    if (v == null) continue;
    at.add(i == 0 ? 0 : cum[i]);
    alt.add(v);
  }
  if (alt.isEmpty) return (_, __) => null;
  double altitudeAt(double d) {
    if (d <= at.first) return alt.first;
    final last = at.length - 1;
    if (d >= at[last]) return alt[last];
    var lo = 0;
    var hi = last;
    while (hi - lo > 1) {
      final mid = (lo + hi) >> 1;
      if (at[mid] <= d) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    final span = at[hi] - at[lo];
    return span > 0
        ? alt[lo] + ((d - at[lo]) / span) * (alt[hi] - alt[lo])
        : alt[hi];
  }

  return (start, end) => end <= at.first || start >= at.last
      ? null
      : (altitudeAt(end) - altitudeAt(start) + 0.5).floor();
}

/// Great-circle distance between two lat/lng points in metres.
double haversineMetres(
  double lat1,
  double lng1,
  double lat2,
  double lng2,
) {
  const r = 6371000.0;
  final dLat = (lat2 - lat1) * pi / 180;
  final dLng = (lng2 - lng1) * pi / 180;
  final sinLat = sin(dLat / 2);
  final sinLng = sin(dLng / 2);
  final a = sinLat * sinLat +
      cos(lat1 * pi / 180) * cos(lat2 * pi / 180) * sinLng * sinLng;
  // Clamp before the arc; the web twin clamps identically. (An earlier pass
  // fixed only this side, on the false belief that web already clamped — it
  // used the unclamped atan2 form, so the pair stayed divergent with the NaN
  // moved to web. Both are clamped now.) Rounding
  // can push `a` a hair above 1 for a near-antipodal pair, and then
  // `sqrt(1 - a)` is NaN — which propagates silently: route_geometry's
  // interpolateAlongRoute would return the end waypoint (Dart's
  // `NaN.clamp(0, 1)` is 1.0) instead of the midpoint.
  final clamped = a > 1 ? 1.0 : (a < 0 ? 0.0 : a);
  return r * 2 * asin(sqrt(clamped));
}

/// Cumulative average pace so far, in seconds per kilometre: [seconds]
/// divided by the distance covered. The spoken split average passes the
/// [averagingTime] the on-screen Avg pace divides by, so the voice and the
/// tile agree. Returns null when either input is non-positive so a caller
/// can fall back rather than divide by zero or announce a meaningless pace.
double? averagePaceSecPerKm(double distanceMetres, int seconds) {
  if (distanceMetres <= 0 || seconds <= 0) return null;
  return seconds / (distanceMetres / 1000);
}

/// Distance a live recording should report, in metres: GPS track distance once
/// a fix has arrived, otherwise the pedometer estimate `steps × strideMetres`
/// so an indoor / treadmill session isn't pinned at zero.
///
/// Every distance-DERIVED behaviour resolves its source through here, not just
/// the on-screen readout — split ticks, split average pace and race-phase
/// transitions included. Reading the raw GPS figure at one of those sites
/// silently disables it for the whole of a pedometer-only run.
double liveDistanceMetres({
  required bool everHadGpsFix,
  required double gpsDistanceMetres,
  required int steps,
  required double strideMetres,
}) {
  if (everHadGpsFix || gpsDistanceMetres > 0) return gpsDistanceMetres;
  if (strideMetres <= 0 || steps <= 0) return 0;
  return steps * strideMetres;
}

/// Bracket key → dashboard PB label, and the shortest-first display order.
/// Shared by [bestEffortsFromPersonalRecords] and [pbAchievedAtByLabel] so the
/// time map and the achieved-date map stay keyed identically.
const _pbBracketLabels = <String, String>{
  '1_mile': 'Mile',
  '5k': '5 km',
  '8k': '8 km',
  '10k': '10 km',
  '12k': '12 km',
  'half_marathon': 'Half Marathon',
  'marathon': 'Marathon',
};
const _pbBracketOrder = <String, int>{
  '1_mile': 0,
  '5k': 1,
  '8k': 2,
  '10k': 3,
  '12k': 4,
  'half_marathon': 5,
  'marathon': 6,
};

/// Map the trigger-maintained `personal_records` cache rows to the dashboard's
/// label→Duration best-effort map, ordered shortest distance first. This is
/// the authoritative all-history source the dashboard prefers over scanning
/// the GPS tracks of whatever runs are resident in memory (which, under the
/// windowed store, is only a recent window — and which never saw cloud-synced
/// runs whose track lives in Storage). Mirrors web's `fetchPersonalRecords`
/// label + ordering. Unknown brackets are dropped.
Map<String, Duration> bestEffortsFromPersonalRecords(
    List<PersonalRecordRow> records) {
  final known = records
      .where((r) => _pbBracketLabels.containsKey(r.distance))
      .toList()
    ..sort((a, b) => (_pbBracketOrder[a.distance] ?? 99)
        .compareTo(_pbBracketOrder[b.distance] ?? 99));
  return {
    for (final r in known)
      _pbBracketLabels[r.distance]!: Duration(seconds: r.bestTimeS),
  };
}

/// The date each PB best-effort was achieved, keyed by the same label as
/// [bestEffortsFromPersonalRecords]. Age grade is age-sensitive, so the
/// dashboard uses the runner's age *when the PB was set* — not today — for the
/// server-sourced PBs that carry a real `achieved_at`. Unknown brackets drop.
Map<String, DateTime> pbAchievedAtByLabel(List<PersonalRecordRow> records) => {
      for (final r in records)
        if (_pbBracketLabels.containsKey(r.distance))
          _pbBracketLabels[r.distance]!: r.achievedAt,
    };
