// The "jump to" buttons over a park course map: which ones a course gets and
// where each one takes the map. Start and Finish on a point-to-point, one
// Start and finish where they share a spot (as the map draws one box there,
// decisions § 2582), and Whole course always. Pure.
//
// Parity pair with apps/web/src/lib/parks/course_jump.ts. Both read
// fixtures/course_jump_cases.json.

import 'dart:math' as math;

import 'course_gates.dart';
import 'gate_crossing.dart' show Gate;

/// A jump to a start or finish shows at least this much ground across, so it
/// is never absurdly close.
const double kCourseJumpMinSpanM = 120;

/// The closest a jump zooms, whatever the box.
const double kCourseJumpMaxZoom = 18;

enum CourseJumpTarget { start, finish, startFinish, course }

class JumpBounds {
  const JumpBounds({
    required this.south,
    required this.west,
    required this.north,
    required this.east,
  });

  final double south;
  final double west;
  final double north;
  final double east;
}

class CourseJump {
  const CourseJump({required this.target, required this.bounds});

  final CourseJumpTarget target;
  final JumpBounds bounds;
}

JumpBounds _boundsOf(List<GatePoint> points) {
  var south = double.infinity;
  var west = double.infinity;
  var north = double.negativeInfinity;
  var east = double.negativeInfinity;
  for (final p in points) {
    south = math.min(south, p.lat);
    north = math.max(north, p.lat);
    west = math.min(west, p.lng);
    east = math.max(east, p.lng);
  }
  return JumpBounds(south: south, west: west, north: north, east: east);
}

/// The bounds of [points], widened about their centre to at least
/// [kCourseJumpMinSpanM] each way.
JumpBounds _closeBounds(List<GatePoint> points) {
  final b = _boundsOf(points);
  final centre = GatePoint((b.south + b.north) / 2, (b.west + b.east) / 2);
  final corner = planeXY(centre, GatePoint(b.north, b.east));
  final hx = math.max(corner.x.abs(), kCourseJumpMinSpanM / 2);
  final hy = math.max(corner.y.abs(), kCourseJumpMinSpanM / 2);
  final sw = fromPlane(centre, -hx, -hy);
  final ne = fromPlane(centre, hx, hy);
  return JumpBounds(south: sw.lat, west: sw.lng, north: ne.lat, east: ne.lng);
}

/// The buttons a course map shows, in order. With [gates] each jump fits its
/// box (the one box a shared start and finish make); without, the line's
/// first and last points, one jump when [endsShared] says the map draws one
/// pin for both. Empty for a line the map does not draw.
List<CourseJump> courseJumps({
  required ({Gate start, Gate finish})? gates,
  required List<GatePoint> line,
  required bool endsShared,
}) {
  final pts = [
    for (final p in line)
      if (p.lat.isFinite && p.lng.isFinite) p,
  ];
  if (pts.length < 2) return const [];
  final out = <CourseJump>[];
  if (gates != null) {
    for (final part in gateBoxParts(gates.start, gates.finish).parts) {
      final target = switch (part.which) {
        null => CourseJumpTarget.startFinish,
        GateWhich.start => CourseJumpTarget.start,
        GateWhich.finish => CourseJumpTarget.finish,
      };
      out.add(
        CourseJump(
          target: target,
          bounds: _closeBounds([...part.box, part.line.$1, part.line.$2]),
        ),
      );
    }
  } else if (endsShared) {
    out.add(
      CourseJump(
        target: CourseJumpTarget.startFinish,
        bounds: _closeBounds([pts.first]),
      ),
    );
  } else {
    out.add(
      CourseJump(
        target: CourseJumpTarget.start,
        bounds: _closeBounds([pts.first]),
      ),
    );
    out.add(
      CourseJump(
        target: CourseJumpTarget.finish,
        bounds: _closeBounds([pts.last]),
      ),
    );
  }
  out.add(CourseJump(target: CourseJumpTarget.course, bounds: _boundsOf(pts)));
  return out;
}
