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

/// How a race session starts its clock (#1303; Scheduled GO and Self-timed
/// arrive with #1306).
enum SessionStartMode { hostGo, scheduledGo, selfTimed }

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
