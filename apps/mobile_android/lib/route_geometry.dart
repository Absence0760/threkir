import 'dart:math';

import 'package:core_models/core_models.dart' show Waypoint;

import 'geo.dart' show lonDeltaDeg, wrapLonDeg;
import 'run_stats.dart' show haversineMetres;

/// Pure geometry helpers for displaying a planned polyline. Lifted
/// to a stand-alone file (vs inlined in `route_detail_screen.dart`)
/// so the math can be unit-tested without booting a screen, and so
/// the helper is reachable from any other route-preview surface that
/// wants a scrubber (e.g. a future feed-card preview).

/// Interpolate the position along [waypoints] at the given
/// normalized [fraction] (0.0 = start, 1.0 = end). Returns null when
/// the polyline is too short to interpolate (`< 2` waypoints) or
/// [fraction] is not finite (NaN / ±Infinity) — clamping a non-finite
/// fraction would propagate NaN into the returned lat/lng.
///
/// Used by the route-detail screen's scrubber slider: the slider
/// emits a 0..1 value as the user drags from start to finish, this
/// helper produces the lat/lng to render the "runner" pulse on the
/// map.
///
/// Distance-weighted — a long segment between two waypoints takes
/// proportionally more of the scrubber's range than a short
/// segment, so dragging at constant speed feels like dragging the
/// runner at a constant pace along the route.
Waypoint? interpolateAlongRoute(
  List<Waypoint> waypoints,
  double fraction,
) {
  if (waypoints.length < 2) return null;
  if (!fraction.isFinite) return null;
  final f = fraction.clamp(0.0, 1.0);
  // Compute cumulative distance + segment lengths in one pass so
  // we can locate the target distance with a linear scan. The
  // polylines this is called on are bounded by the route builder
  // (typically < 1000 points), so the O(n) scan is fine.
  final totalLen = _cumulativeLengthM(waypoints);
  if (totalLen <= 0) {
    // Degenerate (all points coincident). Snap to the first.
    return waypoints.first;
  }
  final target = totalLen * f;
  var seen = 0.0;
  for (var i = 1; i < waypoints.length; i++) {
    final a = waypoints[i - 1];
    final b = waypoints[i];
    final segLen = haversineMetres(a.lat, a.lng, b.lat, b.lng);
    if (segLen <= 0) continue;
    final segEnd = seen + segLen;
    if (target <= segEnd || i == waypoints.length - 1) {
      // Target falls inside this segment OR we've reached the last
      // segment without overshooting (handles fraction=1.0 cleanly).
      final localT = ((target - seen) / segLen).clamp(0.0, 1.0);
      return Waypoint(
        lat: a.lat + (b.lat - a.lat) * localT,
        lng: wrapLonDeg(a.lng + lonDeltaDeg(a.lng, b.lng) * localT),
        elevationMetres: _lerpNullable(
          a.elevationMetres,
          b.elevationMetres,
          localT,
        ),
      );
    }
    seen = segEnd;
  }
  return waypoints.last;
}

/// How far past the expected position the matcher looks for the runner.
const double _routeMatchLookaheadM = 200;

/// How far behind the previous reading the matcher still accepts (GPS jitter).
const double _routeMatchBacktrackM = 50;

/// A windowed match further off the line than this is not trusted: the matcher
/// looks for the runner further along instead. The off-route alert threshold.
const double _routeMatchReacquireM = 40;
const double _alongFwdBiasPerM = 0.05;
const double _alongBackBiasPerM = 0.5;
const double _maxAlongBiasM = 20;
// Uncapped, far below anything the geometry can notice (a 100 km gap buys
// 10 cm): settles a candidate pair the capped bias cannot separate — the two
// limbs of an out-and-back seen with no previous reading — towards the anchor.
const double _alongContinuityPerM = 1e-6;

class RouteProgress {
  const RouteProgress({
    required this.alongM,
    required this.offRouteM,
    required this.remainingM,
  });

  /// Distance from the route start to the matched point, metres.
  final double alongM;

  /// Distance from the runner to the nearest point anywhere on the line, metres.
  final double offRouteM;

  /// Route length still to run from the matched point, metres.
  final double remainingM;
}

/// Where a runner FOLLOWING the route is along it, given where they were last.
///
/// The inverse of [interpolateAlongRoute] for a live GPS fix, which is rarely
/// exactly on the planned line. The globally nearest point is the wrong answer
/// whenever the line passes the same place twice: on a loop the finish is as
/// near as the start, so a run that has just begun reads as finished; on an
/// out-and-back the return leg lies on the outbound one; a figure-eight crosses
/// itself. This matcher only searches the stretch of route the runner can
/// plausibly be on — from [_routeMatchBacktrackM] behind [prevAlongM] to
/// [_routeMatchLookaheadM] past `prevAlongM + travelledM` (the start of the
/// route when there is no previous reading) — and within it breaks a tie
/// between overlapping legs in favour of forward progress, with a bias capped
/// at [_maxAlongBiasM] so it can never outweigh real distance off the line.
/// When nothing in that window is within [_routeMatchReacquireM], the rest of
/// the route ahead is searched, so a runner who skips ahead or returns after a
/// signal gap is re-acquired; a runner still off the line keeps the windowed
/// match.
///
/// Each segment is projected in its own local planar frame, anchored at that
/// segment's start, but candidates are ranked by the great-circle distance to
/// the projected foot, the way `route_snap.dart` does it: a perpendicular
/// measured inside a segment's frame is scaled by that segment's own cos(lat),
/// so it is not comparable across segments.
///
/// [RouteProgress.offRouteM] is always the distance to the nearest point on the
/// WHOLE line, never to the matched stretch: a runner standing on the route is
/// not off it, whichever lap or leg the matcher has them on.
///
/// Null when the polyline has `< 2` waypoints or the point is not finite. A
/// non-finite [prevAlongM] is no previous reading; a non-finite or negative
/// [travelledM] is zero. Twin of web `route_geometry.ts#progressAlongRoute`.
RouteProgress? progressAlongRoute(
  ({double lat, double lng}) point,
  List<Waypoint> waypoints,
  double? prevAlongM, {
  double travelledM = 0,
}) {
  if (waypoints.length < 2) return null;
  if (!point.lng.isFinite || !point.lat.isFinite) return null;
  const deg = pi / 180;
  const rPerDeg = 6371000.0 * deg;

  double offsetAt(int i, double t) {
    final a = waypoints[i];
    final b = waypoints[i + 1];
    final footLat = a.lat + (b.lat - a.lat) * t;
    final footLng = wrapLonDeg(a.lng + lonDeltaDeg(a.lng, b.lng) * t);
    return haversineMetres(point.lat, point.lng, footLat, footLng);
  }

  final n = waypoints.length - 1;
  final segStart = List<double>.filled(n, 0);
  final segLen = List<double>.filled(n, 0);
  final tFree = List<double>.filled(n, 0);
  var total = 0.0;
  var offRouteM = double.infinity;
  for (var i = 0; i < n; i++) {
    final a = waypoints[i];
    final b = waypoints[i + 1];
    segStart[i] = total;
    segLen[i] = haversineMetres(a.lat, a.lng, b.lat, b.lng);
    total += segLen[i];
    final cosLat = cos(a.lat * deg);
    final bx = lonDeltaDeg(a.lng, b.lng) * cosLat * rPerDeg;
    final by = (b.lat - a.lat) * rPerDeg;
    final px = lonDeltaDeg(a.lng, point.lng) * cosLat * rPerDeg;
    final py = (point.lat - a.lat) * rPerDeg;
    final abLenSq = bx * bx + by * by;
    tFree[i] = abLenSq <= 0
        ? 0.0
        : ((px * bx + py * by) / abLenSq).clamp(0.0, 1.0).toDouble();
    offRouteM = min(offRouteM, offsetAt(i, tFree[i]));
  }
  if (!offRouteM.isFinite || !total.isFinite) return null;

  final hasPrev = prevAlongM != null && prevAlongM.isFinite;
  final prev = hasPrev ? prevAlongM.clamp(0.0, total).toDouble() : 0.0;
  final travelled = travelledM.isFinite && travelledM > 0 ? travelledM : 0.0;
  final anchor = min(total, prev + travelled);
  final lo = hasPrev ? max(0.0, prev - _routeMatchBacktrackM) : 0.0;

  // Nearest point of the sub-line [fromM, toM], ranked by offset plus the
  // capped forward-progress bias around `anchor`.
  ({double alongM, double offsetM})? best(double fromM, double toM) {
    ({double alongM, double offsetM})? found;
    var bestCost = double.infinity;
    for (var i = 0; i < n; i++) {
      final s = segStart[i];
      final len = segLen[i];
      if (s > toM || s + len < fromM) continue;
      final tLo = len > 0 ? max(0.0, (fromM - s) / len) : 0.0;
      final tHi = len > 0 ? min(1.0, (toM - s) / len) : 0.0;
      final t = min(tHi, max(tLo, tFree[i]));
      final offsetM = offsetAt(i, t);
      final alongM = s + t * len;
      final gap = alongM - anchor;
      final bias = min(
        _maxAlongBiasM,
        gap >= 0 ? gap * _alongFwdBiasPerM : -gap * _alongBackBiasPerM,
      );
      final cost = offsetM + bias + gap.abs() * _alongContinuityPerM;
      if (cost < bestCost) {
        bestCost = cost;
        found = (alongM: alongM, offsetM: offsetM);
      }
    }
    return found;
  }

  var match = best(lo, anchor + _routeMatchLookaheadM);
  if (match == null || match.offsetM > _routeMatchReacquireM) {
    final ahead = best(lo, total);
    if (ahead != null &&
        (match == null || ahead.offsetM <= _routeMatchReacquireM)) {
      match = ahead;
    }
  }
  if (match == null) return null;
  final alongM = match.alongM.clamp(0.0, total).toDouble();
  return RouteProgress(
    alongM: alongM,
    offRouteM: offRouteM,
    remainingM: max(0.0, total - alongM),
  );
}

/// Compute the total polyline length (metres) via cumulative
/// haversine. Cheap O(n) — same shape the recorder + run-stats
/// helpers use elsewhere in the app.
double polylineLengthMetres(List<Waypoint> waypoints) =>
    _cumulativeLengthM(waypoints);

/// Convert a distance-along-route in [distanceM] to a lat/lng on [waypoints].
/// Out-of-range distances clamp to the route's start / end. Returns null when
/// the line has no usable geometry (`< 2` points, zero length) or the distance
/// isn't finite. Dart twin of web `route_geometry.ts#markerPointAtDistance`.
Waypoint? markerPointAtDistance(List<Waypoint> waypoints, double distanceM) {
  if (waypoints.length < 2) return null;
  if (!distanceM.isFinite) return null;
  final total = polylineLengthMetres(waypoints);
  if (total <= 0) return null;
  final clamped = distanceM.clamp(0.0, total);
  return interpolateAlongRoute(waypoints, clamped / total);
}

double _cumulativeLengthM(List<Waypoint> waypoints) {
  var total = 0.0;
  for (var i = 1; i < waypoints.length; i++) {
    final a = waypoints[i - 1];
    final b = waypoints[i];
    total += haversineMetres(a.lat, a.lng, b.lat, b.lng);
  }
  return total;
}

double? _lerpNullable(double? a, double? b, double t) {
  if (a == null && b == null) return null;
  if (a == null) return b;
  if (b == null) return a;
  return a + (b - a) * t;
}
