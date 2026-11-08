import 'dart:math' as math;

import 'package:core_models/core_models.dart';

import 'geo.dart' show unwrapLonDeg;

/// Simplify a polyline using the Ramer–Douglas–Peucker algorithm. Returns
/// a subset of [points] that preserves the shape within [epsilonMetres] of
/// perpendicular distance from the straight-line segments. Used to turn a
/// noisy GPS track from a run into a cleaner saved route.
///
/// 10 m is a good default for running — it collapses jitter while keeping
/// every turn the runner actually took.
List<Waypoint> simplifyTrack(
  List<Waypoint> points, {
  double epsilonMetres = 10,
}) {
  if (points.length < 3) return List.of(points);

  final keep = List<bool>.filled(points.length, false);
  keep[0] = true;
  keep[points.length - 1] = true;
  _dpStep(points, 0, points.length - 1, epsilonMetres, keep);

  final out = <Waypoint>[];
  for (int i = 0; i < points.length; i++) {
    if (keep[i]) out.add(points[i]);
  }
  return out;
}

/// Reduce [points] to at most [maxPoints] by *priority* Douglas–Peucker: keep
/// the two endpoints, then repeatedly restore whichever dropped point lies
/// furthest from the chord that replaced it, until the budget is spent or no
/// dropped point deviates from its chord at all.
///
/// This is [simplifyTrack] inverted. That one takes a tolerance and returns
/// however many points survive it; a fixed-capacity consumer needs the opposite
/// — a fixed point count, with the tolerance falling out of it. The custom
/// watch's `CRS1` course frame carries a bounded number of positions and
/// refuses a longer one outright, so the phone has to arrive at a count.
///
/// Even decimation would also fit under a cap, but it spends the budget
/// uniformly — as much of it on a straight as on a switchback — and the
/// switchbacks are the geometry a breadcrumb exists to show. Both endpoints are
/// always kept, so the result is never the head of a route with its tail cut
/// off.
///
/// Mobile-only, outside the `route_simplify.ts` parity pair (like
/// [computeElevationLoss]) — web has no fixed-capacity course consumer.
List<Waypoint> simplifyToBudget(
  List<Waypoint> points, {
  required int maxPoints,
}) {
  if (maxPoints < 2) {
    throw ArgumentError.value(maxPoints, 'maxPoints', 'must be at least 2');
  }
  if (points.length <= maxPoints) return List.of(points);

  final keep = List<bool>.filled(points.length, false);
  keep[0] = true;
  keep[points.length - 1] = true;
  var kept = 2;

  final pending = <_Split>[];
  final seed = _splitOf(points, 0, points.length - 1);
  if (seed != null) pending.add(seed);

  while (kept < maxPoints && pending.isNotEmpty) {
    var bestAt = 0;
    for (var i = 1; i < pending.length; i++) {
      if (pending[i].distance > pending[bestAt].distance) bestAt = i;
    }
    final best = pending.removeAt(bestAt);
    // The winner deviates by nothing, so neither does anything still pending —
    // every remaining point lies on a chord already kept and adds no shape.
    if (best.distance <= 0) break;
    keep[best.index] = true;
    kept++;
    final left = _splitOf(points, best.first, best.index);
    if (left != null) pending.add(left);
    final right = _splitOf(points, best.index, best.last);
    if (right != null) pending.add(right);
  }

  final out = <Waypoint>[];
  for (int i = 0; i < points.length; i++) {
    if (keep[i]) out.add(points[i]);
  }
  return out;
}

class _Split {
  final int first;
  final int last;
  final int index;
  final double distance;

  const _Split(this.first, this.last, this.index, this.distance);
}

/// The interior point of `points[first..last]` furthest from the chord between
/// them, or null when the span has no interior.
_Split? _splitOf(List<Waypoint> points, int first, int last) {
  if (last <= first + 1) return null;
  double maxDist = 0;
  int maxIndex = first + 1;
  for (int i = first + 1; i < last; i++) {
    final d = _perpDistanceMetres(points[i], points[first], points[last]);
    if (d > maxDist) {
      maxDist = d;
      maxIndex = i;
    }
  }
  return _Split(first, last, maxIndex, maxDist);
}

void _dpStep(
  List<Waypoint> points,
  int first,
  int last,
  double eps,
  List<bool> keep,
) {
  if (last <= first + 1) return;
  double maxDist = 0;
  int maxIndex = first;
  for (int i = first + 1; i < last; i++) {
    final d = _perpDistanceMetres(points[i], points[first], points[last]);
    if (d > maxDist) {
      maxDist = d;
      maxIndex = i;
    }
  }
  if (maxDist > eps) {
    keep[maxIndex] = true;
    _dpStep(points, first, maxIndex, eps, keep);
    _dpStep(points, maxIndex, last, eps, keep);
  }
}

/// Perpendicular distance from [point] to the segment [a..b], in metres.
/// Uses an equirectangular projection — accurate enough at the ~100 m scale
/// Douglas–Peucker cares about, and vastly cheaper than per-point great
/// circle math.
double _perpDistanceMetres(Waypoint point, Waypoint a, Waypoint b) {
  const r = 6371000.0;
  final latRad = a.lat * math.pi / 180;
  final cosLat = math.cos(latRad);

  double x(double lngDeg) => lngDeg * math.pi / 180 * cosLat * r;
  double y(Waypoint w) => w.lat * math.pi / 180 * r;

  // The frame is absolute, so [b] and [point] are expressed on [a]'s side of
  // the antimeridian before they enter it. Within a hemisphere the unwrap
  // returns each longitude unchanged, bit for bit.
  final ax = x(a.lng);
  final ay = y(a);
  final bx = x(unwrapLonDeg(a.lng, b.lng));
  final by = y(b);
  final px = x(unwrapLonDeg(a.lng, point.lng));
  final py = y(point);

  final dx = bx - ax;
  final dy = by - ay;
  final lengthSq = dx * dx + dy * dy;
  if (lengthSq == 0) {
    final ex = px - ax;
    final ey = py - ay;
    return math.sqrt(ex * ex + ey * ey);
  }

  final t = (((px - ax) * dx) + ((py - ay) * dy)) / lengthSq;
  final tClamped = t.clamp(0.0, 1.0);
  final projX = ax + tClamped * dx;
  final projY = ay + tClamped * dy;
  final fx = px - projX;
  final fy = py - projY;
  return math.sqrt(fx * fx + fy * fy);
}
