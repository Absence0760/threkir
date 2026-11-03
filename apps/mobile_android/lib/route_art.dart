import 'dart:math' as math;

import 'package:core_models/core_models.dart' show Waypoint;

import 'geo.dart' show lonDeltaDeg, unwrapLonDeg, wrapLonDeg;
import 'route_simplify.dart' show simplifyTrack;
import 'route_snap.dart' show snapToPolyline;
import 'run_stats.dart' show haversineMetres;

/// Route art: turn a freehand stroke drawn on the map into routable
/// waypoints, plan the snapping calls within OSRM's per-call limit, and grade
/// how close the snapped route stays to the drawing (decisions § 2263).
///
/// Dart twin of `apps/web/src/lib/routes/route_art.ts` — same constants, same
/// algorithm, same outputs; the two suites carry the same cases.
///
/// Coordinates are `[lng, lat]`, the shape OSRM speaks and [snapToPolyline]
/// takes.

/// The proxy's per-call coordinate ceiling (`MAX_ROUTE_COORDS` on web).
const int kRouteArtMaxCoordsPerCall = 60;

/// Five calls of 60 sharing their seam points: 1 + 5 × 59.
const int kRouteArtMaxPoints = 296;

/// Target gap between routed points before the budget forces it wider.
const double kRouteArtSpacingM = 60;

/// Hand jitter below this is dropped before anything else runs.
const double kRouteArtMinStepM = 2;
const double kRouteArtMinStrokeM = 300;
const double kRouteArtMaxStrokeM = 100000;

/// A stroke ending this close to its start (share of its length) is a loop.
const double kRouteArtCloseFraction = 0.08;
const double kRouteArtCloseMinM = 40;
const double kRouteArtCloseMaxM = 250;

/// Evenly spaced samples taken along each line when grading.
const int kRouteArtSamples = 101;

/// Tolerance is this share of the drawing's bounding-box diagonal, clamped.
const double kRouteArtToleranceFraction = 0.05;
const double kRouteArtToleranceMinM = 25;
const double kRouteArtToleranceMaxM = 120;

/// Below this the match is refused rather than saved as a different shape.
const int kRouteArtMinScore = 60;
const int kRouteArtCloseScore = 85;

/// How far each drawn point may reach for a way, then the one retry's reach.
const int kRouteArtSnapRadiusM = 150;
const int kRouteArtWideSnapRadiusM = 400;

/// Draggable pins left on a matched drawing.
const double kRouteArtAnchorSpacingM = 500;
const int kRouteArtMaxAnchors = 12;

const int _budgetAttempts = 24;
const double _budgetGrowth = 1.25;
const double _seamDedupeM = 1;

double _dist(List<double> a, List<double> b) =>
    haversineMetres(a[1], a[0], b[1], b[0]);

List<double> _lerp(List<double> a, List<double> b, double f) => [
      wrapLonDeg(a[0] + lonDeltaDeg(a[0], b[0]) * f),
      a[1] + (b[1] - a[1]) * f,
    ];

double _clamp(double v, double lo, double hi) => math.min(hi, math.max(lo, v));

double polylineLengthM(List<List<double>> line) {
  var total = 0.0;
  for (var i = 1; i < line.length; i++) {
    total += _dist(line[i - 1], line[i]);
  }
  return total;
}

/// Insert evenly spaced points so no gap exceeds [spacingM]. Every input
/// vertex is kept, so the corners simplification chose survive exactly.
List<List<double>> densifyLine(List<List<double>> line, double spacingM) {
  if (line.length < 2 || !(spacingM > 0)) {
    return [for (final p in line) [p[0], p[1]]];
  }
  final out = <List<double>>[];
  for (var i = 0; i < line.length - 1; i++) {
    final a = line[i];
    final b = line[i + 1];
    final n = math.max(1, (_dist(a, b) / spacingM).ceil());
    for (var k = 0; k < n; k++) {
      out.add(_lerp(a, b, k / n));
    }
  }
  final last = line.last;
  out.add([last[0], last[1]]);
  return out;
}

enum StrokeRejection { tooShort, tooLong, tooComplex }

/// Result of [prepareStroke]: either the routable points or why there are
/// none.
class PreparedStroke {
  const PreparedStroke._({
    this.points = const [],
    this.lengthM = 0,
    this.closed = false,
    this.spacingM = 0,
    this.rejection,
  });

  final List<List<double>> points;
  final double lengthM;
  final bool closed;
  final double spacingM;
  final StrokeRejection? rejection;

  bool get ok => rejection == null;
}

/// Clean a raw stroke into at most [kRouteArtMaxPoints] routable points:
/// drop invalid and jitter points, close a nearly-closed loop, simplify, then
/// densify. When the budget is exceeded the spacing and tolerance widen
/// together until it fits.
PreparedStroke prepareStroke(List<List<double>> raw) {
  final clean = <List<double>>[];
  for (final p in raw) {
    final lng = p[0];
    final lat = p[1];
    if (!lng.isFinite || !lat.isFinite) continue;
    if (lng.abs() > 180 || lat.abs() > 90) continue;
    if (clean.isNotEmpty && _dist(clean.last, p) < kRouteArtMinStepM) continue;
    clean.add([lng, lat]);
  }
  if (clean.length < 2) {
    return const PreparedStroke._(rejection: StrokeRejection.tooShort);
  }
  final lengthM = polylineLengthM(clean);
  if (lengthM < kRouteArtMinStrokeM) {
    return const PreparedStroke._(rejection: StrokeRejection.tooShort);
  }
  if (lengthM > kRouteArtMaxStrokeM) {
    return const PreparedStroke._(rejection: StrokeRejection.tooLong);
  }

  final first = clean.first;
  final gap = _dist(first, clean.last);
  final closeWithin = _clamp(
    lengthM * kRouteArtCloseFraction,
    kRouteArtCloseMinM,
    kRouteArtCloseMaxM,
  );
  final closed = gap <= closeWithin;
  if (closed && gap > 0) {
    if (gap < kRouteArtMinStepM) {
      clean[clean.length - 1] = [first[0], first[1]];
    } else {
      clean.add([first[0], first[1]]);
    }
  }

  final asTrack = [for (final p in clean) Waypoint(lat: p[1], lng: p[0])];
  var spacingM = kRouteArtSpacingM;
  for (var attempt = 0; attempt < _budgetAttempts; attempt++) {
    final simplified = [
      for (final w in simplifyTrack(asTrack, epsilonMetres: spacingM / 4))
        [w.lng, w.lat],
    ];
    final points = densifyLine(simplified, spacingM);
    if (points.length <= kRouteArtMaxPoints) {
      return PreparedStroke._(
        points: points,
        lengthM: lengthM,
        closed: closed,
        spacingM: spacingM,
      );
    }
    spacingM *= _budgetGrowth;
  }
  return const PreparedStroke._(rejection: StrokeRejection.tooComplex);
}

/// One routing call: inclusive indices; the next call starts on [end].
class RouteBatch {
  const RouteBatch(this.start, this.end);

  final int start;
  final int end;

  @override
  bool operator ==(Object other) =>
      other is RouteBatch && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'RouteBatch($start, $end)';
}

/// Split [count] points into calls of at most [maxPerCall] coordinates. Each
/// call starts on the previous call's last point so the stitched route has
/// no gap at a seam.
List<RouteBatch> planRouteBatches(
  int count, [
  int maxPerCall = kRouteArtMaxCoordsPerCall,
]) {
  if (count < 2 || maxPerCall < 2) return const [];
  final out = <RouteBatch>[];
  var start = 0;
  while (start < count - 1) {
    final end = math.min(start + maxPerCall - 1, count - 1);
    out.add(RouteBatch(start, end));
    start = end;
  }
  return out;
}

/// The OSRM-shaped path for one call: every point is a waypoint the route
/// must pass, each allowed [radiusM] to find a way.
String routeArtBatchPath(
  List<List<double>> points,
  String profile,
  int radiusM,
) {
  final coords = points.map((p) => '${p[0]},${p[1]}').join(';');
  final radiuses = points.map((_) => '$radiusM').join(';');
  return '/route/v1/$profile/$coords'
      '?overview=full&geometries=geojson&radiuses=$radiuses';
}

/// Join per-call polylines, dropping a seam point the previous call ended on.
List<List<double>> stitchPolylines(List<List<List<double>>> parts) {
  final out = <List<double>>[];
  for (final part in parts) {
    for (var i = 0; i < part.length; i++) {
      if (i == 0 && out.isNotEmpty && _dist(out.last, part[0]) < _seamDedupeM) {
        continue;
      }
      out.add([part[i][0], part[i][1]]);
    }
  }
  return out;
}

/// [count] points at evenly spaced distances along [line], both ends
/// included.
List<List<double>> sampleAlong(List<List<double>> line, int count) {
  if (line.isEmpty || count < 1) return const [];
  final total = polylineLengthM(line);
  if (count == 1 || total <= 0 || line.length == 1) {
    return [
      for (var k = 0; k < count; k++) [line[0][0], line[0][1]],
    ];
  }
  final out = <List<double>>[];
  var seg = 0;
  var segStart = 0.0;
  var segLen = _dist(line[0], line[1]);
  for (var k = 0; k < count; k++) {
    final target = (total * k) / (count - 1);
    while (seg < line.length - 2 && segStart + segLen < target) {
      segStart += segLen;
      seg++;
      segLen = _dist(line[seg], line[seg + 1]);
    }
    final f = segLen > 0 ? _clamp((target - segStart) / segLen, 0, 1) : 0.0;
    out.add(_lerp(line[seg], line[seg + 1], f));
  }
  return out;
}

/// How far "close" reaches for this drawing: a share of its size, clamped.
double fidelityToleranceM(List<List<double>> drawn) {
  if (drawn.isEmpty) return kRouteArtToleranceMinM;
  final ref = drawn[0][0];
  var minLng = double.infinity;
  var maxLng = double.negativeInfinity;
  var minLat = double.infinity;
  var maxLat = double.negativeInfinity;
  for (final p in drawn) {
    final u = unwrapLonDeg(ref, p[0]);
    if (u < minLng) minLng = u;
    if (u > maxLng) maxLng = u;
    if (p[1] < minLat) minLat = p[1];
    if (p[1] > maxLat) maxLat = p[1];
  }
  final diag = haversineMetres(minLat, minLng, maxLat, maxLng);
  return _clamp(
    diag * kRouteArtToleranceFraction,
    kRouteArtToleranceMinM,
    kRouteArtToleranceMaxM,
  );
}

enum FidelityVerdict { close, rough, poor }

class ArtFidelity {
  const ArtFidelity({
    required this.score,
    required this.coverage,
    required this.precision,
    required this.meanOffsetM,
    required this.maxOffsetM,
    required this.toleranceM,
    required this.lengthRatio,
    required this.verdict,
  });

  /// 0-100: the worse of coverage and precision, as a percentage.
  final int score;

  /// Share of the drawing within tolerance of the route.
  final double coverage;

  /// Share of the route within tolerance of the drawing.
  final double precision;

  /// Mean distance from the drawing to the route, metres.
  final double meanOffsetM;

  /// Largest distance either way, metres.
  final double maxOffsetM;
  final double toleranceM;

  /// Route length over drawing length.
  final double lengthRatio;
  final FidelityVerdict verdict;
}

FidelityVerdict fidelityVerdict(int score) {
  if (score >= kRouteArtCloseScore) return FidelityVerdict.close;
  if (score >= kRouteArtMinScore) return FidelityVerdict.rough;
  return FidelityVerdict.poor;
}

double _offsetM(List<double> p, List<List<double>> line) =>
    snapToPolyline((lng: p[0], lat: p[1]), line)?.offsetM ?? double.infinity;

/// Grade a matched route against the drawing. Coverage asks whether every
/// part of the drawing was reached; precision asks whether the route wandered
/// off it. The score is the worse of the two, because either failure alone
/// draws a different picture: a route that covers the shape plus a long
/// detour, or one that stays on the shape but skips half of it.
ArtFidelity? drawingFidelity(
  List<List<double>> drawn,
  List<List<double>> matched,
) {
  if (drawn.length < 2 || matched.length < 2) return null;
  final drawnLen = polylineLengthM(drawn);
  final matchedLen = polylineLengthM(matched);
  if (drawnLen <= 0 || matchedLen <= 0) return null;

  final toleranceM = fidelityToleranceM(drawn);
  var covered = 0;
  var sumOffset = 0.0;
  var maxOffsetM = 0.0;
  for (final p in sampleAlong(drawn, kRouteArtSamples)) {
    final d = _offsetM(p, matched);
    sumOffset += d;
    if (d > maxOffsetM) maxOffsetM = d;
    if (d <= toleranceM) covered++;
  }
  var precise = 0;
  for (final p in sampleAlong(matched, kRouteArtSamples)) {
    final d = _offsetM(p, drawn);
    if (d > maxOffsetM) maxOffsetM = d;
    if (d <= toleranceM) precise++;
  }
  final coverage = covered / kRouteArtSamples;
  final precision = precise / kRouteArtSamples;
  final score = (100 * math.min(coverage, precision)).round();
  return ArtFidelity(
    score: score,
    coverage: coverage,
    precision: precision,
    meanOffsetM: sumOffset / kRouteArtSamples,
    maxOffsetM: maxOffsetM,
    toleranceM: toleranceM,
    lengthRatio: matchedLen / drawnLen,
    verdict: fidelityVerdict(score),
  );
}

/// Indices of the pins left on a matched drawing: both ends, plus one each
/// time the route passes another `step` metres, with `step` widened so the
/// count never exceeds [maxAnchors].
List<int> artAnchorIndices(
  List<List<double>> line, [
  double spacingM = kRouteArtAnchorSpacingM,
  int maxAnchors = kRouteArtMaxAnchors,
]) {
  if (line.isEmpty) return const [];
  if (line.length == 1) return const [0];
  final total = polylineLengthM(line);
  final step = math.max(spacingM, total / math.max(1, maxAnchors - 1));
  final out = <int>[0];
  var along = 0.0;
  var next = step;
  for (var i = 1; i < line.length - 1; i++) {
    along += _dist(line[i - 1], line[i]);
    if (along >= next && total - along >= step / 2) {
      out.add(i);
      while (next <= along) {
        next += step;
      }
    }
  }
  out.add(line.length - 1);
  return out;
}

/// The slices of [line] between consecutive anchors, seam points shared.
List<List<List<double>>> sliceAtAnchors(
  List<List<double>> line,
  List<int> anchors,
) {
  return [
    for (var j = 0; j < anchors.length - 1; j++)
      [
        for (final p in line.sublist(anchors[j], anchors[j + 1] + 1))
          [p[0], p[1]],
      ],
  ];
}
