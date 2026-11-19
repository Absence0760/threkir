import 'dart:math' as math;

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';

import 'course_gates.dart'
    show GateBoxLayout, gateTimingEdges, kCourseGateBoxDepthM;
import 'gate_crossing.dart';
import 'geo.dart' show unwrapLonDeg;
import 'run_stats.dart' show haversineMetres;

/// Pure Dart port of `apps/web/src/lib/segments/segments.ts` (decisions §37).
/// Walks a run track to extract elapsed time over a (start, end)
/// distance window of a saved route. Stays in sync with the web copy.
///
/// Every position read off the run track is its line position
/// ([Waypoint.lineLat] / [Waypoint.lineLng]): the smoother's fix when the
/// stored waypoint carries both halves of it, else the raw one. Raw zig-zag
/// inflates the hop-summed distance, which moves the crossings and trips the
/// end-to-end guard on a run that did follow the segment. Timestamps are
/// untouched — the crossings still interpolate between the same fixes'
/// timestamps.

class SegmentSlice {
  final double startDistanceM;
  final double endDistanceM;
  const SegmentSlice({required this.startDistanceM, required this.endDistanceM});
}

class EffortResult {
  final double timeSeconds;
  final DateTime startedAt;
  const EffortResult({required this.timeSeconds, required this.startedAt});
}

/// Walks the run track once to compute elapsed time across a segment
/// slice. Returns null when the track is too short, has no timestamps,
/// or is too sparsely sampled (median step > segLen / 5).
EffortResult? computeEffortFromTrack(
  List<Waypoint> track,
  SegmentSlice segment,
) =>
    computeEffortsFromTrack(track, [segment]).first;

/// Times a run track over many segment slices at once, returning one result
/// per input slice. Identical per-slice semantics to [computeEffortFromTrack],
/// which delegates here.
///
/// Everything expensive here is a property of the TRACK, not of the slice —
/// the cumulative-distance array and the median sample step the sparsity
/// guard compares against. Calling the single-slice form in a loop rebuilt
/// and re-sorted both per slice, so a run over a segmented route cost
/// O(segments x points log points). Measured once here, the per-slice work is
/// two binary searches.
///
/// Mirrors `computeEffortsFromTrack` in
/// `apps/web/src/lib/segments/segments.ts`.
List<EffortResult?> computeEffortsFromTrack(
  List<Waypoint> track,
  List<SegmentSlice> segments,
) {
  final out = List<EffortResult?>.filled(segments.length, null);
  if (track.length < 2 || segments.isEmpty) return out;
  final index = _distanceIndex(track);
  for (var i = 0; i < segments.length; i++) {
    out[i] = _effortFromIndex(track, index, segments[i]);
  }
  return out;
}

class _TrackDistanceIndex {
  final List<double> cum;

  /// Median non-zero sample step; null when the track never moved.
  final double? medianStep;
  const _TrackDistanceIndex(this.cum, this.medianStep);
}

_TrackDistanceIndex _distanceIndex(List<Waypoint> track) {
  final cum = List<double>.filled(track.length, 0);
  final steps = <double>[];
  for (var i = 1; i < track.length; i++) {
    final a = track[i - 1];
    final b = track[i];
    final d = haversineMetres(a.lineLat, a.lineLng, b.lineLat, b.lineLng);
    cum[i] = cum[i - 1] + d;
    if (d > 0) steps.add(d);
  }
  if (steps.isEmpty) return _TrackDistanceIndex(cum, null);
  steps.sort();
  return _TrackDistanceIndex(cum, steps[steps.length ~/ 2]);
}

EffortResult? _effortFromIndex(
  List<Waypoint> track,
  _TrackDistanceIndex index,
  SegmentSlice segment,
) {
  final segLen = segment.endDistanceM - segment.startDistanceM;
  if (segLen <= 0) return null;

  final cum = index.cum;
  if (cum.last < segment.endDistanceM) return null;
  final median = index.medianStep;
  if (median == null) return null;

  // Sparsity guard mirroring segments.ts.
  if (median > segLen / 5) return null;

  final startMs = _msAtDistance(track, cum, segment.startDistanceM);
  final endMs = _msAtDistance(track, cum, segment.endDistanceM);
  if (startMs == null || endMs == null) return null;

  final elapsed = (endMs - startMs) / 1000.0;
  if (!(elapsed > 0)) return null;
  return EffortResult(
    timeSeconds: elapsed,
    // Truncate toward zero, as web's `new Date(startTs)` does (the Date
    // constructor applies ToInteger). `.round()` rounds half away from zero, so
    // an interpolated 2997.7386 ms start was written as …02.998Z here and
    // …02.997Z on web for the same effort.
    startedAt:
        DateTime.fromMillisecondsSinceEpoch(startMs.truncate(), isUtc: true),
  );
}

/// The catalogue matcher's version. Mirrors `GLOBAL_SEGMENT_MATCHER_VERSION`
/// in `apps/web/src/lib/segments/segments.ts`: 1 was the circles-only
/// matcher; 2 times a segment with a usable pair of lines by its line
/// crossings and reads only on-track fixes (issue #1308); 3 times every
/// complete lap of a loop, so a run's fastest lap is its effort (§ 2465); 4
/// times by the drawn start and finish boxes, with GPS slack at either end of
/// the recording and a longer gap across the finish (§ 2583).
const int kGlobalSegmentMatcherVersion = 4;

/// How far past the start box's exit edge a recording's first fix, or short
/// of the finish box a recording's last stretch, may sit and still count: the
/// GPS error of a phone standing at the line (decisions § 2583). Mirrors
/// `GLOBAL_SEGMENT_BOX_SLACK_M`.
const double kGlobalSegmentBoxSlackM = 5;

/// The longest gap between two fixes across the finish edge that still
/// finishes, when the straight-line speed across it is within
/// [kGlobalSegmentGapSpeedMin]..[kGlobalSegmentGapSpeedMax] of the runner's
/// average since the start. Up to [kGateRejectGapS] any crossing counts, as
/// for every line. Mirrors `GLOBAL_SEGMENT_FINISH_MAX_GAP_S` and the two
/// `GLOBAL_SEGMENT_GAP_SPEED_*`.
const double kGlobalSegmentFinishMaxGapS = 300;
const double kGlobalSegmentGapSpeedMin = 0.4;
const double kGlobalSegmentGapSpeedMax = 1.5;

/// Covered distance between the start and end must be within this fraction
/// of the segment's stored length, whichever way the segment is matched.
const double kGlobalSegmentLengthTolerance = 0.25;

/// How a catalogue effort was matched: between the segment's two lines, or
/// by the 35 m circles. Mirrors `GlobalSegmentMatchedBy` in
/// `apps/web/src/lib/types.ts` and the `global_segment_efforts.matched_by`
/// CHECK (migration 20271122002402).
enum GlobalSegmentMatchedBy { zone, gate }

/// A catalogue effort, with how it was matched.
class GlobalSegmentEffortResult extends EffortResult {
  final GlobalSegmentMatchedBy matchedBy;
  const GlobalSegmentEffortResult({
    required super.timeSeconds,
    required super.startedAt,
    required this.matchedBy,
  });
}

/// A free-standing catalogue-segment geometry (the global/famous-segment
/// layer — decisions §232). Carries its own polyline, so matching keys off
/// the run passing the segment's start then its end rather than a
/// distance-along-a-route window. Mirrors `GlobalSegmentGeometry` in
/// `apps/web/src/lib/segments/segments.ts`.
class GlobalSegmentGeometry {
  final List<Waypoint> points;
  final double distanceM;

  /// Ordered points the run must also pass, in order, within the match
  /// tolerance between the start and end crossings (a park course's
  /// `checkpoints`, decisions § 2383). The 25% length guard alone lets a
  /// runner cut a fifth off an out-and-back or take a cut-through on a trail
  /// network; a checkpoint on the far side of the cut refuses it.
  final List<Waypoint> checkpoints;

  /// The segment's start and end lines (`global_segments.start_gate_*` /
  /// `end_gate_*`, decisions § 2402). When both are usable the segment is
  /// matched by its line crossings ONLY; otherwise by the circles.
  final Gate? startGate;
  final Gate? endGate;
  const GlobalSegmentGeometry({
    required this.points,
    required this.distanceM,
    this.checkpoints = const [],
    this.startGate,
    this.endGate,
  });
}

/// Scores a run track against a free-standing catalogue-segment geometry
/// and returns the effort time, or null if the run didn't run it.
///
/// Two rules, chosen per segment:
///
/// - **Boxes** (a segment with a usable start and end line, decisions
///   § 2402, § 2583): the start and finish boxes a course map draws
///   ([gateTimingEdges]). The clock starts when the run leaves the start box
///   forward and stops when it next enters the finish box, both interpolated
///   between fixes, with the covered distance between them within 25% of the
///   segment's length and every checkpoint passed in order between them. A
///   recording whose first fix is already up to [kGlobalSegmentBoxSlackM]
///   past the exit edge starts at that fix; one that ends in the finish box,
///   or that slack short of it, without entering finishes where its last
///   stretch there began. A gap across the finish edge longer than
///   [kGateRejectGapS] counts up to [kGlobalSegmentFinishMaxGapS] when it was
///   crossed at about the runner's own pace. Every complete lap is a
///   candidate and the fastest counts. Laps never overlap: once a lap closes,
///   only a start at or after its finish can open the next, and on a loop
///   whose end line is its start line but whose boxes are apart
///   ([linesChain]) the finish itself opens it (decisions § 2465). A run that
///   never leaves and enters the boxes is not matched by the circles instead:
///   no circle fallback.
/// - **Circles** (no usable pair of lines): the v1 CURATED end-to-end match:
///   the run must approach the segment's START within [toleranceM], then
///   reach its END within [toleranceM] LATER in the track, with the same
///   length guard and checkpoints, timed by [computeEffortFromTrack]'s own
///   distance-window logic.
///
/// Either way only on-track fixes ([trackLine]) are read, at their line
/// positions. Mirrors `computeGlobalSegmentEffort` in
/// `apps/web/src/lib/segments/segments.ts`.
GlobalSegmentEffortResult? computeGlobalSegmentEffort(
  List<Waypoint> track,
  GlobalSegmentGeometry segment, {
  double toleranceM = 35,
}) =>
    computeGlobalSegmentEfforts(track, [segment], toleranceM: toleranceM).first;

/// Scores a run track against a whole catalogue of segment geometries in one
/// sweep, returning one result per input segment (null where the run didn't
/// run it). Identical per-segment semantics to [computeGlobalSegmentEffort],
/// which delegates here.
///
/// The batch shape is what makes catalogue scoring affordable. Scored
/// one-at-a-time, every segment paid two full-track haversine passes before
/// the check that rejected it, so a sweep over the 500-segment catalogue was
/// O(segments x trackPoints) — essentially all of it spent measuring
/// distances to segments on other continents. Here the track's extent is
/// measured once and each segment is rejected against it in constant time, so
/// only the handful of geometries that could plausibly match walk the track.
///
/// Mirrors `computeGlobalSegmentEfforts` in
/// `apps/web/src/lib/segments/segments.ts`.
List<GlobalSegmentEffortResult?> computeGlobalSegmentEfforts(
  List<Waypoint> track,
  List<GlobalSegmentGeometry> segments, {
  double toleranceM = 35,
}) {
  final out = List<GlobalSegmentEffortResult?>.filled(segments.length, null);
  final line = trackLine(track);
  if (line.length < 2 || segments.isEmpty) return out;

  final bounds = _trackBounds(line);
  // Only built once a segment survives the extent test — a sweep that
  // rejects every segment must not pay a haversine pass at all.
  _TrackDistanceIndex? index;

  for (var i = 0; i < segments.length; i++) {
    final segment = segments[i];
    final pts = segment.points;
    if (pts.length < 2 || !(segment.distanceM > 0)) continue;
    final start = segment.startGate;
    final end = segment.endGate;
    if (start != null && end != null && gateUsable(start) && gateUsable(end)) {
      // A box edge is crossed on the chord between two fixes, so inside the
      // track's extent, and a box edge, or a fix within the slack of one,
      // lies within its half-width, its depth and the slack of the line's
      // centre.
      const reach = kCourseGateBoxDepthM + kGlobalSegmentBoxSlackM;
      if (!_boundsAdmit(
          bounds, start.lat, start.lng, start.halfWidthM + reach)) {
        continue;
      }
      if (!_boundsAdmit(bounds, end.lat, end.lng, end.halfWidthM + reach)) {
        continue;
      }
      index ??= _distanceIndex(line);
      out[i] = _scoreByGates(line, index, segment, start, end, toleranceM);
      continue;
    }
    if (!_boundsAdmit(bounds, pts.first.lat, pts.first.lng, toleranceM)) {
      continue;
    }
    if (!_boundsAdmit(bounds, pts.last.lat, pts.last.lng, toleranceM)) continue;
    index ??= _distanceIndex(line);
    final eff = _scoreAgainstTrack(line, index, segment, toleranceM);
    out[i] = eff == null
        ? null
        : GlobalSegmentEffortResult(
            timeSeconds: eff.timeSeconds,
            startedAt: eff.startedAt,
            matchedBy: GlobalSegmentMatchedBy.zone,
          );
  }
  return out;
}

/// Whether a segment's end line is also its start line: the end line's
/// centre within the start line's reach, facing within 90° of it. A loop whose
/// two lines are derived from one closed polyline is the usual case (Beaver
/// Lake); a lollipop or out-and-back finishes facing the other way and is not,
/// since the runner turns before starting again. On such a loop the crossing
/// that finishes a lap also starts the next, whichever fix the start line's
/// own crossing falls on. Mirrors `linesChain` in
/// `apps/web/src/lib/segments/segments.ts`.
bool linesChain(Gate start, Gate end) {
  if (haversineMetres(start.lat, start.lng, end.lat, end.lng) >
      start.halfWidthM) {
    return false;
  }
  final turn = (((end.bearingDeg - start.bearingDeg) % 360) + 540) % 360 - 180;
  return turn.abs() < 90;
}

class _PendingStart {
  final GateCrossing crossing;

  /// Track index of the fix before the crossing: checkpoints count from it.
  final int fromIdx;
  const _PendingStart(this.crossing, this.fromIdx);
}

/// The fixes either side of a step in the track, and the seconds between
/// them.
class _FixGap {
  final int fromIdx;
  final double fromMs;
  final double gapS;
  const _FixGap(this.fromIdx, this.fromMs, this.gapS);
}

GlobalSegmentEffortResult? _scoreByGates(
  List<Waypoint> line,
  _TrackDistanceIndex index,
  GlobalSegmentGeometry segment,
  Gate startGate,
  Gate endGate,
  double toleranceM,
) {
  final len = segment.distanceM;
  final minCovered = len * (1 - kGlobalSegmentLengthTolerance);
  final maxCovered = len * (1 + kGlobalSegmentLengthTolerance);
  final edges = gateTimingEdges(startGate, endGate);
  final exit = edges.startExit;
  final entry = edges.finishEntry;
  final startDetector = GateCrossingDetector(exit);
  final endDetector = GateCrossingDetector(entry);

  // Apart, the finish box is not the start box, so on a loop whose end line
  // is its start line the finish opens the next lap. A shared box is left
  // forward again to start the next.
  final chained =
      edges.layout == GateBoxLayout.apart && linesChain(startGate, endGate);
  var pending = <_PendingStart>[];
  double? bestStartMs;
  double? bestEndMs;
  var prevIdx = -1;
  var prevMs = double.negativeInfinity;
  // The fixes since the last one outside the finish box and its slack.
  var tailIdx = -1;
  var tailMs = double.nan;
  var tailGap = const _FixGap(-1, double.nan, 0);
  var prevEntryS = double.nan;

  _PendingStart? pick(
      double endCoveredM, int endIdx, double endMs, _FixGap gap) {
    pending = [
      for (final s in pending)
        if (endCoveredM - s.crossing.coveredM <= maxCovered) s,
    ];
    // Pending starts are in time order, so the last valid one is the latest
    // start and so the fastest lap ending here.
    _PendingStart? picked;
    for (final s in pending) {
      if (endCoveredM - s.crossing.coveredM < minCovered) continue;
      if (!(endMs > s.crossing.tMs)) continue;
      if (gap.gapS > kGateRejectGapS &&
          !_plausibleGap(s, index.cum, gap, endIdx)) {
        continue;
      }
      if (!_passesCheckpoints(
          line, segment.checkpoints, s.fromIdx, endIdx, toleranceM)) {
        continue;
      }
      picked = s;
    }
    return picked;
  }

  void record(double startMs, double endMs) {
    if (bestStartMs == null || endMs - startMs < bestEndMs! - bestStartMs!) {
      bestStartMs = startMs;
      bestEndMs = endMs;
    }
  }

  for (var i = 0; i < line.length; i++) {
    final p = line[i];
    final ts = p.timestamp;
    if (ts == null) continue;
    final tMs = ts.millisecondsSinceEpoch.toDouble();
    final lat = p.lineLat;
    final lng = p.lineLng;
    // The detectors drop these too; skipping them here keeps prevIdx on the
    // fix the detectors last accepted.
    if (!lat.isFinite || !lng.isFinite || tMs <= prevMs) continue;
    final fix = GateFix(lat: lat, lng: lng, tMs: tMs, coveredM: index.cum[i]);
    final endCrossing = endDetector.offer(fix);
    final startCrossing = startDetector.offer(fix);

    final gap = _FixGap(prevIdx, prevMs, (tMs - prevMs) / 1000);
    final inFinish = gateProjection(entry, lat, lng);
    if (inFinish.s >= -kGlobalSegmentBoxSlackM &&
        inFinish.s <= edges.depthM &&
        inFinish.u.abs() <= entry.halfWidthM) {
      if (tailIdx < 0) {
        tailIdx = i;
        tailMs = tMs;
        tailGap = gap;
      }
    } else {
      tailIdx = -1;
    }

    final GateCrossing? entered;
    if (endCrossing != null && endCrossing.direction == GateDirection.forward) {
      entered = endCrossing;
    } else if (gap.gapS > kGateRejectGapS &&
        gap.gapS <= kGlobalSegmentFinishMaxGapS) {
      entered = _enteredAcrossGap(
        prevEntryS,
        inFinish,
        entry.halfWidthM,
        prevMs,
        index.cum[prevIdx],
        fix,
        pending.isEmpty ? null : pending.last,
      );
    } else {
      entered = null;
    }
    prevEntryS = inFinish.s;

    GateCrossing? closedBy;
    if (entered != null) {
      final chosen = pick(entered.coveredM, i, entered.tMs, gap);
      if (chosen != null) {
        record(chosen.crossing.tMs, entered.tMs);
        // Laps never overlap: nothing that started before this finish can
        // start the next lap.
        pending = [];
        closedBy = entered;
      }
    }
    if (closedBy != null && chained) {
      pending.add(_PendingStart(closedBy, prevIdx));
    }
    if (startCrossing != null &&
        startCrossing.direction == GateDirection.forward &&
        (closedBy == null || startCrossing.tMs >= closedBy.tMs)) {
      pending.add(_PendingStart(startCrossing, prevIdx));
    } else if (prevIdx < 0) {
      // A recording begun on the line: its first fix just past the exit edge
      // starts the clock there.
      final atStart = gateProjection(exit, lat, lng);
      if (atStart.s >= 0 &&
          atStart.s <= kGlobalSegmentBoxSlackM &&
          atStart.u.abs() <= exit.halfWidthM) {
        pending.add(_PendingStart(
          GateCrossing(
            direction: GateDirection.forward,
            fraction: 0,
            tMs: tMs,
            coveredM: index.cum[i],
            offsetM: atStart.u,
            gapped: false,
          ),
          i,
        ));
      }
    }
    prevIdx = i;
    prevMs = tMs;
  }

  // A recording that ends in the finish box, or just short of it, without
  // having crossed into it finishes where its last stretch there began.
  if (tailIdx >= 0 && pending.isNotEmpty) {
    final chosen = pick(index.cum[tailIdx], tailIdx, tailMs, tailGap);
    if (chosen != null) record(chosen.crossing.tMs, tailMs);
  }

  final startMs = bestStartMs;
  final endMs = bestEndMs;
  if (startMs == null || endMs == null) return null;
  return GlobalSegmentEffortResult(
    timeSeconds: (endMs - startMs) / 1000,
    startedAt:
        DateTime.fromMillisecondsSinceEpoch(startMs.round(), isUtc: true),
    matchedBy: GlobalSegmentMatchedBy.gate,
  );
}

/// The finish edge entered across a gap the line rule refuses: the fix
/// before it short of the edge, the fix after it in the finish box's lane at
/// or past the edge. The path inside the gap is unknown, and the straight
/// line across it cuts the bend before a finish, so the entry is timed back
/// from the fix after the gap at the runner's average pace since [since]
/// (the latest pending start), within the gap. Mirrors `enteredAcrossGap` in
/// `apps/web/src/lib/segments/segments.ts`.
GateCrossing? _enteredAcrossGap(
  double prevS,
  GateProjection cur,
  double halfWidthM,
  double prevMs,
  double prevCoveredM,
  GateFix fix,
  _PendingStart? since,
) {
  if (since == null ||
      !(prevS < 0) ||
      cur.s < 0 ||
      cur.u.abs() > halfWidthM) {
    return null;
  }
  final paceS = (prevMs - since.crossing.tMs) / 1000;
  final paceM = prevCoveredM - since.crossing.coveredM;
  if (!(paceS > 0) || !(paceM > 0)) return null;
  final backS = cur.s / (paceM / paceS);
  final tMs = math.max(prevMs, fix.tMs - backS * 1000);
  return GateCrossing(
    direction: GateDirection.forward,
    fraction: (tMs - prevMs) / (fix.tMs - prevMs),
    tMs: tMs,
    coveredM: math.max(prevCoveredM, fix.coveredM - cur.s),
    offsetM: cur.u,
    gapped: true,
  );
}

/// Whether a gap of more than [kGateRejectGapS] before fix [toIdx] may still
/// finish: at most [kGlobalSegmentFinishMaxGapS], and crossed at about the
/// runner's own pace, its straight-line speed within
/// [kGlobalSegmentGapSpeedMin]..[kGlobalSegmentGapSpeedMax] of their average
/// from [start] to the fix before the gap.
bool _plausibleGap(
    _PendingStart start, List<double> cum, _FixGap gap, int toIdx) {
  if (gap.gapS > kGlobalSegmentFinishMaxGapS || gap.fromIdx < 0) return false;
  final soFarS = (gap.fromMs - start.crossing.tMs) / 1000;
  final soFarM = cum[gap.fromIdx] - start.crossing.coveredM;
  if (!(soFarS > 0) || !(soFarM > 0)) return false;
  final avg = soFarM / soFarS;
  final across = (cum[toIdx] - cum[gap.fromIdx]) / gap.gapS;
  return across >= kGlobalSegmentGapSpeedMin * avg &&
      across <= kGlobalSegmentGapSpeedMax * avg;
}

/// Whether the track passes every checkpoint, in order, between the start and
/// end crossings. Each checkpoint takes the FIRST in-tolerance track index at
/// or after the previous one's, so a checkpoint only reachable by doubling
/// back past a later one fails rather than matching out of order.
bool _passesCheckpoints(
  List<Waypoint> track,
  List<Waypoint> checkpoints,
  int startIdx,
  int endIdx,
  double toleranceM,
) {
  if (checkpoints.isEmpty) return true;
  var cursor = startIdx;
  for (final cp in checkpoints) {
    var hit = -1;
    for (var i = cursor; i <= endIdx; i++) {
      if (haversineMetres(track[i].lineLat, track[i].lineLng, cp.lat, cp.lng) <=
          toleranceM) {
        hit = i;
        break;
      }
    }
    if (hit < 0) return false;
    cursor = hit;
  }
  return true;
}

/// Latitude / longitude extent of a run track. Longitudes are unwrapped
/// around the first point (`geo.dart`), so a track straddling the
/// antimeridian stays one narrow interval instead of appearing to span the
/// globe.
class _TrackBounds {
  final double minLat;
  final double maxLat;
  final double refLon;
  final double minLon;
  final double maxLon;
  const _TrackBounds({
    required this.minLat,
    required this.maxLat,
    required this.refLon,
    required this.minLon,
    required this.maxLon,
  });
}

/// Metres per degree of latitude on the 6371 km sphere [haversineMetres] uses is
/// 111_195; the smaller figure here is deliberate, so every degree window
/// derived from a tolerance comes out slightly WIDER than the true one. The
/// extent test must never reject a segment the full scan would have matched.
const double _conservativeMetresPerDeg = 110574;

_TrackBounds _trackBounds(List<Waypoint> track) {
  final refLon = track.first.lineLng;
  var minLat = track.first.lineLat;
  var maxLat = minLat;
  var minLon = refLon;
  var maxLon = refLon;
  for (var i = 1; i < track.length; i++) {
    final lat = track[i].lineLat;
    if (lat < minLat) {
      minLat = lat;
    } else if (lat > maxLat) {
      maxLat = lat;
    }
    final lon = unwrapLonDeg(refLon, track[i].lineLng);
    if (lon < minLon) {
      minLon = lon;
    } else if (lon > maxLon) {
      maxLon = lon;
    }
  }
  return _TrackBounds(
    minLat: minLat,
    maxLat: maxLat,
    refLon: refLon,
    minLon: minLon,
    maxLon: maxLon,
  );
}

/// Whether any point of the track could lie within [toleranceM] of [point].
/// Conservative by construction: false means every track point is provably
/// further away, true means "maybe, go and measure".
///
/// Latitude is exact — spherical distance is never less than the meridian
/// separation. Longitude uses the tangent-meridian bound: everything within
/// an angular distance s of a point at latitude phi lies within
/// asin(sin s / cos phi) of its meridian, taken here as the linear s / cos phi.
/// That linearisation only under-states the window as the ratio approaches 1,
/// which cannot happen while the window is still under a degree — so past a
/// degree, where the test has stopped discriminating anyway, it admits.
bool _boundsAdmit(
  _TrackBounds bounds,
  double pointLat,
  double pointLng,
  double toleranceM,
) {
  final padLat = toleranceM / _conservativeMetresPerDeg;
  if (pointLat < bounds.minLat - padLat || pointLat > bounds.maxLat + padLat) {
    return false;
  }

  final cosLat = math.cos(pointLat * math.pi / 180);
  if (cosLat <= 0) return true;
  final padLon = padLat / cosLat;
  if (padLon >= 1) return true;

  final lon = unwrapLonDeg(bounds.refLon, pointLng);
  return lon >= bounds.minLon - padLon && lon <= bounds.maxLon + padLon;
}

EffortResult? _scoreAgainstTrack(
  List<Waypoint> track,
  _TrackDistanceIndex index,
  GlobalSegmentGeometry segment,
  double toleranceM,
) {
  final cum = index.cum;
  final pts = segment.points;
  final start = pts.first;
  final end = pts.last;

  var startIdx = -1;
  var startBest = double.infinity;
  for (var i = 0; i < track.length; i++) {
    final d =
        haversineMetres(track[i].lineLat, track[i].lineLng, start.lat, start.lng);
    if (d < startBest) {
      startBest = d;
      startIdx = i;
    }
  }
  if (startIdx < 0 || startBest > toleranceM) return null;

  var endIdx = -1;
  var endBest = double.infinity;
  for (var i = startIdx + 1; i < track.length; i++) {
    final d =
        haversineMetres(track[i].lineLat, track[i].lineLng, end.lat, end.lng);
    if (d < endBest) {
      endBest = d;
      endIdx = i;
    }
  }
  if (endIdx < 0 || endBest > toleranceM) return null;

  final dStart = cum[startIdx];
  final dEnd = cum[endIdx];
  if (dEnd <= dStart) return null;

  // End-to-end guard: covered distance must be ~the segment length so a
  // straight-line shortcut between distant endpoints isn't mistaken for
  // running the segment.
  if ((dEnd - dStart - segment.distanceM).abs() / segment.distanceM >
      kGlobalSegmentLengthTolerance) {
    return null;
  }

  if (!_passesCheckpoints(
      track, segment.checkpoints, startIdx, endIdx, toleranceM)) {
    return null;
  }

  return _effortFromIndex(
    track,
    index,
    SegmentSlice(startDistanceM: dStart, endDistanceM: dEnd),
  );
}

/// Auto-effort generation for a run on its parent route. Mirrors
/// `computeSegmentEffortsForRun` in web `data.ts`. Idempotent against
/// the unique(segment_id, run_id) constraint via upsert with
/// ignoreDuplicates inside `recordSegmentEffort`.
Future<int> autoComputeEffortsForRun({
  required ApiClient api,
  required String runId,
  required String userId,
  required String routeId,
  required List<Waypoint> track,
}) async {
  if (track.length < 2) return 0;
  final viewerId = api.userId;
  if (viewerId == null || viewerId != userId) return 0;

  final segments = await api.fetchSegmentsForRoute(routeId);
  if (segments.isEmpty) return 0;

  var written = 0;
  final efforts = computeEffortsFromTrack(
    track,
    [
      for (final seg in segments)
        SegmentSlice(
          startDistanceM: seg.startDistanceM,
          endDistanceM: seg.endDistanceM,
        ),
    ],
  );
  for (var i = 0; i < segments.length; i++) {
    final seg = segments[i];
    final eff = efforts[i];
    if (eff == null) continue;
    try {
      await api.recordSegmentEffort(
        segmentId: seg.id,
        runId: runId,
        timeSeconds: eff.timeSeconds.round(),
        startedAt: eff.startedAt,
      );
      written++;
    } catch (_) {
      // Ignore individual insert failures; RLS or duplicate keys
      // simply skip the row rather than abort the whole walk.
    }
  }
  return written;
}

double? _msAtDistance(
  List<Waypoint> track,
  List<double> cum,
  double target,
) {
  // [cum] is non-decreasing, so the first index reaching [target] is a binary
  // search rather than a walk from the start of the track.
  var lo = 1;
  var hi = track.length - 1;
  var found = -1;
  while (lo <= hi) {
    final mid = (lo + hi) >> 1;
    if (cum[mid] < target) {
      lo = mid + 1;
    } else {
      found = mid;
      hi = mid - 1;
    }
  }
  if (found > 0) {
    final prev = cum[found - 1];
    final here = cum[found];
    final a = track[found - 1];
    final b = track[found];
    if (a.timestamp == null || b.timestamp == null) return null;
    final tA = a.timestamp!.millisecondsSinceEpoch.toDouble();
    final tB = b.timestamp!.millisecondsSinceEpoch.toDouble();
    final span = here - prev;
    final frac = span > 0 ? (target - prev) / span : 0;
    return tA + (tB - tA) * frac;
  }
  return null;
}

