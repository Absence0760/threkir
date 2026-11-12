import 'dart:convert';
import 'dart:io';

import 'package:core_models/core_models.dart' show Waypoint;
import 'package:flutter_test/flutter_test.dart';
import '../lib/race_phases.dart';

/// The Dart reader of `fixtures/race_phase_vectors.json`, the [gradePhases]
/// vectors generated from web's `gradePhases` and replayed by
/// `apps/web/src/lib/runs/race_phase_vectors.test.ts` (decisions § 1915). The
/// fixture's keys are web's field names and wire strings, so every Dart enum is
/// compared through the wire string web would have written.
String _snake(String camel) => camel.replaceAllMapped(
    RegExp('[A-Z]'), (m) => '_${m.group(0)!.toLowerCase()}');

Object? _strategyJson(PacingStrategy? s) => s == null
    ? null
    : {
        'preset': s.preset.wire,
        'distanceM': s.distanceM,
        'goalTimeS': s.goalTimeS,
      };

Map<String, Object?> _reviewJson(PhaseReview r) => {
      'strategy': _strategyJson(r.strategy),
      'basis': r.basis.name,
      'basisPaceSecPerKm': r.basisPaceSecPerKm,
      'trackDistanceM': r.trackDistanceM,
      'completed': r.completed,
      'verdict': _snake(r.verdict.name),
      'ungradedReason':
          r.ungradedReason == null ? null : _snake(r.ungradedReason!.name),
      'phases': [
        for (final p in r.phases)
          {
            'intent': p.intent.wire,
            'paceFactor': p.paceFactor,
            'startM': p.startM,
            'endM': p.endM,
            'coverage': _snake(p.coverage.name),
            'coveredM': p.coveredM,
            'movingS': p.movingS,
            'movingM': p.movingM,
            'actualPaceSecPerKm': p.actualPaceSecPerKm,
            'targetPaceSecPerKm': p.targetPaceSecPerKm,
            'gapSecPerKm': p.gapSecPerKm,
            'grade': p.grade == null ? null : _snake(p.grade!.name),
          }
      ],
    };

void _expectClose(Object? got, Object? want, String path) {
  if (want is num && got is num) {
    final tol = 1e-6 * (want.abs() > 1 ? want.abs() : 1);
    expect((got - want).abs() <= tol, isTrue, reason: '$path: $got != $want');
    return;
  }
  if (want is Map) {
    expect(got, isA<Map>(), reason: '$path: expected an object');
    final g = got as Map;
    expect(g.keys.toSet(), want.keys.toSet(), reason: '$path: keys');
    for (final k in want.keys) {
      _expectClose(g[k], want[k], '$path.$k');
    }
    return;
  }
  if (want is List) {
    expect(got, isA<List>(), reason: '$path: expected a list');
    final g = got as List;
    expect(g.length, want.length, reason: '$path: length');
    for (var i = 0; i < want.length; i++) {
      _expectClose(g[i], want[i], '$path[$i]');
    }
    return;
  }
  expect(got, want, reason: path);
}

List<Waypoint>? _track(Object? raw) {
  if (raw == null) return null;
  return [
    for (final p in (raw as List).cast<List<dynamic>>())
      Waypoint(
        lat: (p[0] as num).toDouble(),
        lng: (p[1] as num).toDouble(),
        timestamp: p[2] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch((p[2] as num).toInt(),
                isUtc: true),
      ),
  ];
}

void main() {
  final fixture = jsonDecode(
          File('../../fixtures/race_phase_vectors.json').readAsStringSync())
      as Map<String, dynamic>;

  test('race phase vectors: parsePacingStrategy reads every fixture bag as recorded', () {
    final cases = (fixture['parse_cases'] as List).cast<Map<String, dynamic>>();
    expect(cases.length, greaterThanOrEqualTo(5));
    for (final p in cases) {
      _expectClose(_strategyJson(parsePacingStrategy(p['raw'])), p['expected'],
          p['name'] as String);
    }
  });

  test('race phase vectors: gradePhases reproduces every fixture review', () {
    final cases = (fixture['cases'] as List).cast<Map<String, dynamic>>();
    expect(cases.length, greaterThanOrEqualTo(8));
    for (final c in cases) {
      final name = c['name'] as String;
      final strategy = parsePacingStrategy(c['strategy']);
      expect(strategy, isNotNull, reason: '$name: the fixture strategy must parse');
      final r = gradePhases(_track(c['track']), strategy!);
      expect(_snake(r.verdict.name), c['expect_verdict'], reason: '$name: verdict');
      _expectClose(_reviewJson(r), c['expected'], name);
    }
  });

  test('race phase vectors: every verdict and ungraded reason is exercised', () {
    final cases = (fixture['cases'] as List).cast<Map<String, dynamic>>();
    final verdicts = {
      for (final c in cases) (c['expected'] as Map<String, dynamic>)['verdict']
    };
    for (final v in PhaseReviewVerdict.values) {
      expect(verdicts.contains(_snake(v.name)), isTrue, reason: 'no case reaches $v');
    }
    final reasons = {
      for (final c in cases)
        (c['expected'] as Map<String, dynamic>)['ungradedReason']
    };
    for (final r in PhaseUngradedReason.values) {
      expect(reasons.contains(_snake(r.name)), isTrue, reason: 'no case reaches $r');
    }
  });
}
