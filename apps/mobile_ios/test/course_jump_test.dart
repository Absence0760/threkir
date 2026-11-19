import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../lib/course_gates.dart';
import '../lib/course_jump.dart';
import '../lib/gate_crossing.dart' show Gate;

/// The Dart reader of `fixtures/course_jump_cases.json`, the case table the
/// `course_jump` pair shares with web's `course_jump.test.ts`.
final List<Map<String, dynamic>> _cases = [
  for (final c
      in (jsonDecode(
                File(
                  '../../fixtures/course_jump_cases.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>)['cases']
          as List)
    c as Map<String, dynamic>,
];

Gate _gate(Map<String, dynamic> g) => Gate(
  lat: (g['lat'] as num).toDouble(),
  lng: (g['lng'] as num).toDouble(),
  bearingDeg: (g['bearingDeg'] as num).toDouble(),
  halfWidthM: (g['halfWidthM'] as num).toDouble(),
);

List<CourseJump> _run(Map<String, dynamic> c) {
  final g = c['gates'] as Map<String, dynamic>?;
  return courseJumps(
    gates: g == null
        ? null
        : (
            start: _gate(g['start'] as Map<String, dynamic>),
            finish: _gate(g['finish'] as Map<String, dynamic>),
          ),
    line: [
      for (final p in c['line'] as List)
        GatePoint(
          ((p as Map<String, dynamic>)['lat'] as num?)?.toDouble() ??
              double.nan,
          (p['lng'] as num).toDouble(),
        ),
    ],
    endsShared: c['endsShared'] as bool,
  );
}

void main() {
  for (final c in _cases) {
    test(c['name'] as String, () {
      final got = _run(c);
      final want = c['jumps'] as List;
      expect(got.map((j) => j.target.name).toList(), [
        for (final j in want) (j as Map<String, dynamic>)['target'],
      ]);
      for (var i = 0; i < got.length; i++) {
        final b =
            (want[i] as Map<String, dynamic>)['bounds'] as Map<String, dynamic>;
        final g = got[i].bounds;
        expect(g.south, closeTo((b['south'] as num).toDouble(), 1e-9));
        expect(g.west, closeTo((b['west'] as num).toDouble(), 1e-9));
        expect(g.north, closeTo((b['north'] as num).toDouble(), 1e-9));
        expect(g.east, closeTo((b['east'] as num).toDouble(), 1e-9));
      }
    });
  }

  test('every start or finish jump shows at least the least span each way', () {
    for (final c in _cases) {
      for (final j in _run(c)) {
        if (j.target == CourseJumpTarget.course) continue;
        final d = planeXY(
          GatePoint(j.bounds.south, j.bounds.west),
          GatePoint(j.bounds.north, j.bounds.east),
        );
        expect(d.x, greaterThanOrEqualTo(kCourseJumpMinSpanM - 0.5));
        expect(d.y, greaterThanOrEqualTo(kCourseJumpMinSpanM - 0.5));
      }
    }
  });
}
