import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../lib/course_gates.dart';

/// The Dart reader of `fixtures/course_gates_cases.json`, the case table the
/// `course_gates` pair shares with web's `course_gates.test.ts`. The file's
/// own `schema` block says what each section means.
final Map<String, dynamic> _fixture = jsonDecode(
        File('../../fixtures/course_gates_cases.json').readAsStringSync())
    as Map<String, dynamic>;

const _sections = [
  'normalizeBearing',
  'clampHalfWidth',
  'courseGate',
  'bearingTo',
  'lineEnds',
  'arrowTip',
  'routeRelation',
  'warnings',
  'preflight',
];
const _metaKeys = {
  'spec',
  'reference',
  'readers',
  'schema',
  'constants',
  'degreeTolerance',
  'bearingTolerance',
  'distanceToleranceM',
};

List<Map<String, dynamic>> _section(String name) =>
    (_fixture[name] as List).cast<Map<String, dynamic>>();

double _num(Object? v) => switch (v) {
      'NaN' => double.nan,
      num n => n.toDouble(),
      _ => throw FormatException('not a fixture number: $v'),
    };

final double _degTol = _num(_fixture['degreeTolerance']);
final double _bearingTol = _num(_fixture['bearingTolerance']);
final double _distTol = _num(_fixture['distanceToleranceM']);

GatePoint _point(Object? o) {
  final m = o as Map<String, dynamic>;
  return GatePoint(_num(m['lat']), _num(m['lng']));
}

CourseGate _gate(Object? o) {
  final m = o as Map<String, dynamic>;
  return CourseGate(
    lat: _num(m['lat']),
    lng: _num(m['lng']),
    bearingDeg: _num(m['bearingDeg']),
    halfWidthM: _num(m['halfWidthM']),
    source: m['source'] == 'organiser' ? GateSource.organiser : GateSource.derived,
  );
}

List<GatePoint>? _route(Object? v) =>
    v == null ? null : (v as List).map(_point).toList();

void _nearPoint(GatePoint actual, Object? expected, String what) {
  final e = _point(expected);
  expect((actual.lat - e.lat).abs(), lessThanOrEqualTo(_degTol),
      reason: '$what lat');
  expect((actual.lng - e.lng).abs(), lessThanOrEqualTo(_degTol),
      reason: '$what lng');
}

void _nearBearing(double actual, double expected, String what) {
  final d = (actual - expected).abs();
  expect(d < 360 - d ? d : 360 - d, lessThanOrEqualTo(_bearingTol),
      reason: '$what: $actual vs $expected');
}

const _which = {'start': GateWhich.start, 'finish': GateWhich.finish};
const _modes = {
  'host_go': SessionStartMode.hostGo,
  'scheduled_go': SessionStartMode.scheduledGo,
  'self_timed': SessionStartMode.selfTimed,
};
const _warningWire = {
  CourseGateWarning.farFromRoute: 'far_from_route',
  CourseGateWarning.againstRoute: 'against_route',
  CourseGateWarning.selfCross: 'self_cross',
  CourseGateWarning.startRequired: 'start_required',
};
const _codeWire = {
  PreflightCode.noFinish: 'no_finish',
  PreflightCode.noStart: 'no_start',
  PreflightCode.selfCross: 'self_cross',
  PreflightCode.gateFarFromRoute: 'gate_far_from_route',
};

void main() {
  test('the reader knows every section the file holds', () {
    for (final key in _fixture.keys) {
      expect(_metaKeys.contains(key) || _sections.contains(key), isTrue,
          reason: 'unknown section $key');
    }
    for (final s in _sections) {
      expect(_section(s), isNotEmpty, reason: 'section $s is empty');
    }
    expect(_fixture['spec'], 'course_gates v1');
  });

  test('constants match the case table', () {
    final c = _fixture['constants'] as Map<String, dynamic>;
    expect(kCourseGateHalfWidthMinM, _num(c['halfWidthMinM']));
    expect(kCourseGateHalfWidthMaxM, _num(c['halfWidthMaxM']));
    expect(kCourseGateDefaultHalfWidthM, _num(c['defaultHalfWidthM']));
    expect(kCourseGateRouteWarnM, _num(c['routeWarnM']));
    expect(kCourseGateAgainstRouteDeg, _num(c['againstRouteDeg']));
  });

  test('normalizeBearing', () {
    for (final c in _section('normalizeBearing')) {
      expect(normalizeBearing(_num(c['in'])), _num(c['out']),
          reason: '${c['note']}');
    }
  });

  test('clampHalfWidth', () {
    for (final c in _section('clampHalfWidth')) {
      expect(clampHalfWidth(_num(c['in'])), _num(c['out']),
          reason: '${c['note']}');
    }
  });

  test('courseGate', () {
    for (final c in _section('courseGate')) {
      final got = courseGate(
          c['row'] as Map<String, dynamic>, _which[c['which']]!);
      final want = c['expected'] as Map<String, dynamic>?;
      if (want == null) {
        expect(got, isNull, reason: '${c['note']}');
        continue;
      }
      expect(got, isNotNull, reason: '${c['note']}');
      expect(got!.lat, _num(want['lat']));
      expect(got.lng, _num(want['lng']));
      expect(got.bearingDeg, _num(want['bearingDeg']));
      expect(got.halfWidthM, _num(want['halfWidthM']));
      expect(got.source.name, want['source'], reason: '${c['note']}');
    }
  });

  test('bearingTo', () {
    for (final c in _section('bearingTo')) {
      _nearBearing(bearingTo(_point(c['from']), _point(c['to'])),
          _num(c['bearingDeg']), '${c['note']}');
    }
  });

  test('gateLineEnds', () {
    for (final c in _section('lineEnds')) {
      final (left, right) = gateLineEnds(_gate(c['gate']));
      _nearPoint(left, c['left'], '${c['note']} left');
      _nearPoint(right, c['right'], '${c['note']} right');
    }
  });

  test('gateArrowTip', () {
    for (final c in _section('arrowTip')) {
      _nearPoint(gateArrowTip(_gate(c['gate'])), c['tip'], '${c['note']}');
    }
  });

  test('gateRouteRelation', () {
    for (final c in _section('routeRelation')) {
      final got = gateRouteRelation(_gate(c['gate']), _route(c['route'])!);
      final want = c['expected'] as Map<String, dynamic>?;
      if (want == null) {
        expect(got, isNull, reason: '${c['note']}');
        continue;
      }
      expect(got, isNotNull, reason: '${c['note']}');
      expect((got!.distanceM - _num(want['distanceM'])).abs(),
          lessThanOrEqualTo(_distTol),
          reason: '${c['note']} distance');
      _nearBearing(got.routeBearingDeg, _num(want['routeBearingDeg']),
          '${c['note']} bearing');
      expect(got.against, want['against'], reason: '${c['note']} against');
    }
  });

  test('gateWarnings', () {
    for (final c in _section('warnings')) {
      final got = gateWarnings(
        which: _which[c['which']]!,
        gate: c['gate'] == null ? null : _gate(c['gate']),
        route: _route(c['route']),
        selfCross: c['selfCross'] as bool,
        mode: _modes[c['mode']]!,
      );
      expect(got.map((w) => _warningWire[w]).toList(), c['expected'],
          reason: '${c['note']}');
    }
  });

  test('racePreflight and preflightBlocks', () {
    for (final c in _section('preflight')) {
      final courses = (c['courses'] as List)
          .cast<Map<String, dynamic>>()
          .map((o) => PreflightCourse(
                id: o['id'] as String,
                startGate: o['startGate'] == null ? null : _gate(o['startGate']),
                finishGate:
                    o['finishGate'] == null ? null : _gate(o['finishGate']),
                hasFinishPoint: o['hasFinishPoint'] as bool,
                selfCross: o['selfCross'] as bool,
                route: _route(o['route']),
              ))
          .toList();
      final issues = racePreflight(courses, _modes[c['mode']]!);
      final got = issues
          .map((i) => {
                'courseId': i.courseId,
                'code': _codeWire[i.code],
                'severity': i.severity.name,
                'which': i.which?.name,
              })
          .toList();
      expect(got, c['expected'], reason: '${c['note']}');
      expect(preflightBlocks(issues), c['blocks'], reason: '${c['note']}');
    }
  });
}
