/// Course start and finish lines (#1305, timing lines phase 2, decisions
/// § 2390): reading a course's lines off its row, the geometry the maps draw,
/// the inline warnings, and the Arm preflight. Pure: no Flutter, no I/O.
///
/// Web twin: `apps/web/src/lib/races/course_gates.ts` (the `course_gates`
/// pair in `docs/architecture/parity_pairs.md`). Both read
/// `fixtures/course_gates_cases.json`, so a rule changes there or nowhere.
library;

import 'dart:math' as math;

import 'gate_crossing.dart';

/// Mirrors the event_courses half-width CHECK (5-100 m).
const double kCourseGateHalfWidthMinM = 5;
const double kCourseGateHalfWidthMaxM = 100;

/// The width a derived line and a newly placed one get (§ 2377).
const double kCourseGateDefaultHalfWidthM = kGateHalfWidthRaceM;

/// A line further than this from the course route is probably misplaced.
const double kCourseGateRouteWarnM = 100;

/// A line facing more than this away from the route's direction faces
/// against it.
const double kCourseGateAgainstRouteDeg = 90;

enum GateWhich { start, finish }

/// Where a line came from: derived from the route, or placed by an organiser.
/// The wire values are the event_courses `*_gate_source` CHECK's.
enum GateSource { derived, organiser }

class CourseGate extends Gate {
  const CourseGate({
    required super.lat,
    required super.lng,
    required super.bearingDeg,
    required super.halfWidthM,
    required this.source,
  });

  final GateSource source;
}

class GatePoint {
  const GatePoint(this.lat, this.lng);

  final double lat;
  final double lng;
}

double? _finite(Object? v) =>
    v is num && v.toDouble().isFinite ? v.toDouble() : null;

/// One line of an event_courses or race_session_courses row, or null when the
/// row has none. A frozen copy carries no source, so it reads as `derived`;
/// nothing that reads a frozen copy edits it.
CourseGate? courseGate(Map<String, dynamic> row, GateWhich which) {
  final p = which == GateWhich.start ? 'start_gate' : 'finish_gate';
  final lat = _finite(row['${p}_lat']);
  final lng = _finite(row['${p}_lng']);
  final bearing = _finite(row['${p}_bearing_deg']);
  final halfWidth = _finite(row['${p}_half_width_m']);
  if (lat == null || lng == null || bearing == null || halfWidth == null) {
    return null;
  }
  return CourseGate(
    lat: lat,
    lng: lng,
    bearingDeg: bearing,
    halfWidthM: halfWidth,
    source: row['${p}_source'] == 'organiser'
        ? GateSource.organiser
        : GateSource.derived,
  );
}

/// Any finite bearing into [0, 360).
double normalizeBearing(double deg) {
  final b = ((deg % 360) + 360) % 360;
  return b >= 360 ? 0 : b;
}

/// A half-width held to the CHECK's range, rounded to the metre.
double clampHalfWidth(double m) {
  if (!m.isFinite) return kCourseGateDefaultHalfWidthM;
  return math.min(kCourseGateHalfWidthMaxM,
      math.max(kCourseGateHalfWidthMinM, m.roundToDouble()));
}

double _rad(double deg) => deg * math.pi / 180;
double _deg(double r) => r * 180 / math.pi;

double _wrapLng(double d) {
  if (d >= 180) return d - 360;
  if (d < -180) return d + 360;
  return d;
}

/// ([p]) on the tangent plane at [origin]: metres east (x) and north (y).
({double x, double y}) planeXY(GatePoint origin, GatePoint p) => (
      x: _rad(_wrapLng(p.lng - origin.lng)) *
          kGateEarthRadiusM *
          math.cos(_rad(origin.lat)),
      y: _rad(p.lat - origin.lat) * kGateEarthRadiusM,
    );

/// The inverse of [planeXY].
GatePoint fromPlane(GatePoint origin, double x, double y) => GatePoint(
      origin.lat + _deg(y / kGateEarthRadiusM),
      _wrapLng(origin.lng +
          _deg(x / (kGateEarthRadiusM * math.cos(_rad(origin.lat))))),
    );

/// Degrees clockwise from north, from [from] toward [to], in [0, 360).
double bearingTo(GatePoint from, GatePoint to) {
  final p = planeXY(from, to);
  return normalizeBearing(_deg(math.atan2(p.x, p.y)));
}

/// The point [distM] from [origin] along [bearingDeg].
GatePoint offsetPoint(GatePoint origin, double bearingDeg, double distM) =>
    fromPlane(origin, distM * math.sin(_rad(bearingDeg)),
        distM * math.cos(_rad(bearingDeg)));

GatePoint _centre(Gate g) => GatePoint(g.lat, g.lng);

/// The line's two ends, left of travel first, as gate_crossing measures it.
(GatePoint, GatePoint) gateLineEnds(Gate gate) {
  final b = _rad(gate.bearingDeg);
  final ex = gate.halfWidthM * math.cos(b);
  final ey = -gate.halfWidthM * math.sin(b);
  final c = _centre(gate);
  return (fromPlane(c, -ex, -ey), fromPlane(c, ex, ey));
}

/// Where the direction arrow ends: ahead of the centre by the half-width, at
/// least 20 m.
GatePoint gateArrowTip(Gate gate) => offsetPoint(
    _centre(gate), gate.bearingDeg, math.max(20, gate.halfWidthM));

/// How deep a drawn start or finish box is, from its line.
const double kCourseGateBoxDepthM = 10;

/// Start and finish lines whose centres sit this close, facing the same way
/// or opposite ways, sit at one spot.
const double kCourseGateSharedSpotM = 10;

/// How far from parallel (or from opposed) two lines may face and still share
/// a spot.
const double kCourseGateSharedSpotDeg = 20;

/// The point on the line at [f] of its half-width: -1 its left end, 0 the
/// centre, 1 its right end.
GatePoint gatePointAlong(Gate gate, double f) {
  final b = _rad(gate.bearingDeg);
  return fromPlane(_centre(gate), f * gate.halfWidthM * math.cos(b),
      -f * gate.halfWidthM * math.sin(b));
}

/// Which side of its line a box sits: behind it (where a runner waits to
/// start), ahead (where one stops), or centred on it (a start and finish at
/// one spot, half behind and half ahead).
enum GateBoxSide { behind, ahead, centred }

/// The box on one side of a line, [depthM] deep, from [from] to [to] along
/// the line (as [gatePointAlong]). Corners: the near edge first, its left end
/// then its right (left of travel), then the far right and far left corners.
/// For `behind` and `ahead` the near edge is on the line, and leaving a
/// `behind` box through it, or entering an `ahead` one, is crossing the
/// line. A `centred` box runs from `depthM / 2` behind the line to
/// `depthM / 2` ahead, its near edge the one behind, so the line crosses its
/// middle.
List<GatePoint> gateBox(Gate gate, double depthM, GateBoxSide side,
    {double from = -1, double to = 1}) {
  final b = _rad(gate.bearingDeg);
  final ax = gate.halfWidthM * math.cos(b);
  final ay = -gate.halfWidthM * math.sin(b);
  final (near, far) = switch (side) {
    GateBoxSide.ahead => (0.0, depthM),
    GateBoxSide.behind => (0.0, -depthM),
    GateBoxSide.centred => (-depthM / 2, depthM / 2),
  };
  final c = _centre(gate);
  GatePoint at(double f, double k) => fromPlane(
      c, f * ax + k * math.sin(b), f * ay + k * math.cos(b));
  return [at(from, near), at(to, near), at(to, far), at(from, far)];
}

/// Whether a start line and a finish line sit at one spot: an
/// out-and-back's or a loop's.
bool gatesShareSpot(Gate start, Gate finish) {
  final p = planeXY(_centre(start), _centre(finish));
  if (math.sqrt(p.x * p.x + p.y * p.y) > kCourseGateSharedSpotM) return false;
  final d = bearingDelta(start.bearingDeg, finish.bearingDeg);
  return d <= kCourseGateSharedSpotDeg || d >= 180 - kCourseGateSharedSpotDeg;
}

/// One box on a course map.
class GateBoxPart {
  const GateBoxPart({
    required this.which,
    required this.box,
    required this.line,
  });

  /// The line it belongs to, or null for the one box a start and finish at
  /// one spot share (web's `'both'`).
  final GateWhich? which;

  /// As [gateBox] gives it: behind the start line, ahead of the finish line,
  /// centred on a shared one.
  final List<GatePoint> box;

  /// The timing line across the box: the stretch of the stored line it
  /// covers.
  final (GatePoint, GatePoint) line;
}

/// How a course's start and finish boxes lie. Twin of web's `GateBoxLayout`:
/// [apart], two boxes in two places, the start box behind its line and the
/// finish box ahead of its own; [shared], the lines sit at one spot (a loop,
/// or an out-and-back), so it is one box in one colour, centred on the start
/// line, which crosses its middle. Never two colours at one spot: a runner
/// would read half of it as the start and half as the finish (decisions
/// § 2582).
enum GateBoxLayout { apart, shared }

/// Where a box's flag and name go: the middle of the box's far side, so at
/// a close zoom it sits beside the box rather than over the line. One for a
/// box the start and finish share ([which] null).
class GateBoxMarker {
  const GateBoxMarker({required this.which, required this.at});

  /// The line the box belongs to, or null for a box both share.
  final GateWhich? which;
  final GatePoint at;
}

/// The start and finish boxes a course map draws (decisions § 2582).
({GateBoxLayout layout, List<GateBoxPart> parts, List<GateBoxMarker> markers})
    gateBoxParts(
  Gate? start,
  Gate? finish, {
  double depthM = kCourseGateBoxDepthM,
}) {
  GateBoxPart part(GateWhich? which, Gate gate) => GateBoxPart(
        which: which,
        box: gateBox(
            gate,
            depthM,
            switch (which) {
              null => GateBoxSide.centred,
              GateWhich.start => GateBoxSide.behind,
              GateWhich.finish => GateBoxSide.ahead,
            }),
        line: gateLineEnds(gate),
      );

  GateBoxMarker marker(GateWhich? which, Gate gate, double away, double distM) =>
      GateBoxMarker(which: which, at: offsetPoint(_centre(gate), away, distM));
  double back(Gate g) => g.bearingDeg + 180;

  if (start != null && finish != null && gatesShareSpot(start, finish)) {
    return (
      layout: GateBoxLayout.shared,
      parts: [part(null, start)],
      markers: [marker(null, start, back(start), depthM / 2)],
    );
  }
  return (
    layout: GateBoxLayout.apart,
    parts: [
      if (start != null) part(GateWhich.start, start),
      if (finish != null) part(GateWhich.finish, finish),
    ],
    markers: [
      if (start != null) marker(GateWhich.start, start, back(start), depthM),
      if (finish != null)
        marker(GateWhich.finish, finish, finish.bearingDeg, depthM),
    ],
  );
}

/// The edges a course is timed by, read off the boxes [gateBoxParts] draws
/// (decisions § 2583): leaving the start box forward is a forward crossing of
/// [startExit], with the box behind it; entering the finish box is a forward
/// crossing of [finishEntry], with the box [depthM] ahead of it. Apart, they
/// are the start and finish lines themselves. At a shared spot, the exit is
/// the box's far edge and the entry is its near edge on a loop, or its far
/// edge facing back on an out-and-back, so the timed stretch is [depthM]
/// shorter than line to line. Twin of web's `GateTimingEdges`.
class GateTimingEdges {
  const GateTimingEdges({
    required this.layout,
    required this.startExit,
    required this.finishEntry,
    required this.depthM,
  });

  final GateBoxLayout layout;
  final Gate startExit;
  final Gate finishEntry;
  final double depthM;
}

/// A line along a drawn box edge from corner [a] to corner [b], facing
/// [bearingDeg].
Gate _edgeGate(GatePoint a, GatePoint b, double bearingDeg, double halfWidthM) {
  final p = planeXY(a, b);
  final mid = fromPlane(a, p.x / 2, p.y / 2);
  return Gate(
    lat: mid.lat,
    lng: mid.lng,
    bearingDeg: normalizeBearing(bearingDeg),
    halfWidthM: halfWidthM,
  );
}

/// The timing edges of a course with both lines (decisions § 2583). Twin of
/// web's `gateTimingEdges`.
GateTimingEdges gateTimingEdges(
  Gate start,
  Gate finish, {
  double depthM = kCourseGateBoxDepthM,
}) {
  final boxes = gateBoxParts(start, finish, depthM: depthM);
  if (boxes.layout == GateBoxLayout.shared) {
    final box = boxes.parts[0].box;
    final nearL = box[0];
    final nearR = box[1];
    final farR = box[2];
    final farL = box[3];
    final sameWay = bearingDelta(start.bearingDeg, finish.bearingDeg) <= 90;
    return GateTimingEdges(
      layout: boxes.layout,
      startExit: _edgeGate(farL, farR, start.bearingDeg, start.halfWidthM),
      finishEntry: sameWay
          ? _edgeGate(nearL, nearR, start.bearingDeg, start.halfWidthM)
          : _edgeGate(farR, farL, start.bearingDeg + 180, start.halfWidthM),
      depthM: depthM,
    );
  }
  final s = boxes.parts[0].box;
  final f = boxes.parts[1].box;
  return GateTimingEdges(
    layout: boxes.layout,
    startExit: _edgeGate(s[0], s[1], start.bearingDeg, start.halfWidthM),
    finishEntry: _edgeGate(f[0], f[1], finish.bearingDeg, finish.halfWidthM),
    depthM: depthM,
  );
}

class GateRouteRelation {
  const GateRouteRelation({
    required this.distanceM,
    required this.routeBearingDeg,
    required this.against,
  });

  /// Distance from the line's centre to the nearest point of the route.
  final double distanceM;

  /// The route's direction of travel at that point.
  final double routeBearingDeg;

  /// The line faces more than [kCourseGateAgainstRouteDeg] away from it.
  final bool against;
}

/// Smallest angle between two bearings, 0..180.
double bearingDelta(double a, double b) {
  final d = (normalizeBearing(a) - normalizeBearing(b)).abs();
  return d > 180 ? 360 - d : d;
}

/// How a line sits against a route, on the tangent plane at the line's
/// centre. Null for a route with fewer than two distinct points.
GateRouteRelation? gateRouteRelation(Gate gate, List<GatePoint> route) {
  double? bestD;
  double bestBearing = 0;
  ({double x, double y})? prev;
  final c = _centre(gate);
  for (final p in route) {
    if (!p.lat.isFinite || !p.lng.isFinite) continue;
    final cur = planeXY(c, p);
    if (prev != null) {
      final dx = cur.x - prev.x;
      final dy = cur.y - prev.y;
      final len2 = dx * dx + dy * dy;
      if (len2 > 0) {
        final t = math
            .max(0.0, math.min(1.0, -(prev.x * dx + prev.y * dy) / len2))
            .toDouble();
        final px = prev.x + t * dx;
        final py = prev.y + t * dy;
        final d = math.sqrt(px * px + py * py);
        if (bestD == null || d < bestD) {
          bestD = d;
          bestBearing = normalizeBearing(_deg(math.atan2(dx, dy)));
        }
      }
    }
    prev = cur;
  }
  if (bestD == null) return null;
  return GateRouteRelation(
    distanceM: bestD,
    routeBearingDeg: bestBearing,
    against:
        bearingDelta(gate.bearingDeg, bestBearing) > kCourseGateAgainstRouteDeg,
  );
}

/// How a race session starts its clock (#1306): the values of
/// `events.race_start_mode` and `race_sessions.start_mode`, snake_cased.
enum SessionStartMode { hostGo, scheduled, selfTimed }

enum CourseGateWarning { farFromRoute, againstRoute, selfCross, startRequired }

/// The inline warnings for one line. [route] is what the viewer can see of
/// the course route, or null when the course has none.
List<CourseGateWarning> gateWarnings({
  required GateWhich which,
  required Gate? gate,
  required List<GatePoint>? route,
  required bool selfCross,
  required SessionStartMode mode,
}) {
  final out = <CourseGateWarning>[];
  if (gate == null) {
    if (which == GateWhich.start && mode == SessionStartMode.selfTimed) {
      out.add(CourseGateWarning.startRequired);
    }
    return out;
  }
  final rel = route == null ? null : gateRouteRelation(gate, route);
  if (rel != null) {
    if (rel.distanceM > kCourseGateRouteWarnM) {
      out.add(CourseGateWarning.farFromRoute);
    } else if (rel.against) {
      out.add(CourseGateWarning.againstRoute);
    }
  }
  if (which == GateWhich.finish && selfCross) {
    out.add(CourseGateWarning.selfCross);
  }
  return out;
}

/// One course as the Arm preflight sees it.
class PreflightCourse {
  const PreflightCourse({
    required this.id,
    required this.startGate,
    required this.finishGate,
    required this.hasFinishPoint,
    required this.selfCross,
    required this.route,
  });

  final String id;
  final CourseGate? startGate;
  final CourseGate? finishGate;
  final bool hasFinishPoint;
  final bool selfCross;

  /// The course route as the viewer can see it, or null when unknown.
  final List<GatePoint>? route;
}

enum PreflightCode { noFinish, noStart, selfCross, gateFarFromRoute }

enum PreflightSeverity { warning, error }

class PreflightIssue {
  const PreflightIssue({
    required this.courseId,
    required this.code,
    required this.severity,
    this.which,
  });

  final String courseId;
  final PreflightCode code;
  final PreflightSeverity severity;

  /// For [PreflightCode.gateFarFromRoute]: which line.
  final GateWhich? which;
}

/// The Arm (or window-open) preflight, #1305's table:
///
///     condition                               gun modes   self-timed
///     no finish line and no finish point      warning     error
///     no start line                           -           error
///     finish_line_self_cross                  warning     error
///     organiser line > 100 m from the route   warning     warning
///
/// A course with no route has nothing to measure an organiser line against.
List<PreflightIssue> racePreflight(
    List<PreflightCourse> courses, SessionStartMode mode) {
  final selfTimed = mode == SessionStartMode.selfTimed;
  final hard = selfTimed ? PreflightSeverity.error : PreflightSeverity.warning;
  final out = <PreflightIssue>[];
  for (final c in courses) {
    if (c.finishGate == null && !c.hasFinishPoint) {
      out.add(PreflightIssue(
          courseId: c.id, code: PreflightCode.noFinish, severity: hard));
    }
    if (selfTimed && c.startGate == null) {
      out.add(PreflightIssue(
          courseId: c.id,
          code: PreflightCode.noStart,
          severity: PreflightSeverity.error));
    }
    if (c.selfCross) {
      out.add(PreflightIssue(
          courseId: c.id, code: PreflightCode.selfCross, severity: hard));
    }
    for (final which in GateWhich.values) {
      final gate = which == GateWhich.start ? c.startGate : c.finishGate;
      final route = c.route;
      if (gate == null || gate.source != GateSource.organiser || route == null) {
        continue;
      }
      final rel = gateRouteRelation(gate, route);
      if (rel != null && rel.distanceM > kCourseGateRouteWarnM) {
        out.add(PreflightIssue(
            courseId: c.id,
            code: PreflightCode.gateFarFromRoute,
            severity: PreflightSeverity.warning,
            which: which));
      }
    }
  }
  return out;
}

/// Whether any issue stops the race from being armed.
bool preflightBlocks(List<PreflightIssue> issues) =>
    issues.any((i) => i.severity == PreflightSeverity.error);
