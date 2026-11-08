import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import '../lib/gate_crossing.dart';

/// The Dart reader of `fixtures/gate_crossing_cases.json`, the case table the
/// `gate_crossing` pairs share with web's `gate_crossing.test.ts` and Wear's
/// `GateCrossingTest.kt`. The file's own `schema` block says what each
/// section means; a case changes there, for every port at once, or not at all.
final Map<String, dynamic> _fixture = jsonDecode(
        File('../../fixtures/gate_crossing_cases.json').readAsStringSync())
    as Map<String, dynamic>;

const _sections = ['projection', 'crossings'];
const _metaKeys = {
  'spec',
  'reference',
  'readers',
  'schema',
  'constants',
  't0EpochMs',
  'distanceToleranceM',
  'timeToleranceS',
  'fractionTolerance',
};

List<Map<String, dynamic>> _section(String name) =>
    (_fixture[name] as List).cast<Map<String, dynamic>>();

double _num(Object? v) => switch (v) {
      'NaN' => double.nan,
      'Infinity' => double.infinity,
      '-Infinity' => double.negativeInfinity,
      num n => n.toDouble(),
      _ => throw FormatException('not a fixture number: $v'),
    };

Object? _req(Map<String, dynamic> o, String key) {
  if (!o.containsKey(key)) {
    throw StateError(
        "case ${o['name']} has no '$key' (nullable fields are explicit)");
  }
  return o[key];
}

final Map<String, dynamic> _constants =
    _fixture['constants'] as Map<String, dynamic>;
final double _t0 = _num(_fixture['t0EpochMs']);
final double _distTol = _num(_fixture['distanceToleranceM']);
final double _timeTol = _num(_fixture['timeToleranceS']);
final double _fracTol = _num(_fixture['fractionTolerance']);
final double _k = _num(_constants['EARTH_RADIUS_M']) * math.pi / 180;

Gate _gate(Map<String, dynamic> o) => Gate(
      lat: _num(o['lat']),
      lng: _num(o['lng']),
      bearingDeg: _num(o['bearingDeg']),
      halfWidthM: _num(o['halfWidthM']),
    );

({double lat, double lng}) _position(Gate gate, Map<String, dynamic> o) {
  if (o.containsKey('lat')) return (lat: _num(o['lat']), lng: _num(o['lng']));
  return (
    lat: gate.lat + _num(o['northM']) / _k,
    lng: gate.lng +
        _num(o['eastM']) / (_k * math.cos(gate.lat * math.pi / 180)),
  );
}

GateFix _fix(Gate gate, Map<String, dynamic> o) {
  final p = _position(gate, o);
  return GateFix(
    lat: p.lat,
    lng: p.lng,
    tMs: _t0 + _num(o['atS']) * 1000,
    coveredM: _num(o['coveredM']),
  );
}

GateCrossingOptions _options(Object? o) {
  if (o == null) return const GateCrossingOptions();
  final p = o as Map<String, dynamic>;
  return GateCrossingOptions(
    maxGapS: _num(p['maxGapS']),
    maxHopM: _num(p['maxHopM']),
    rejectGapS: _num(p['rejectGapS']),
  );
}

void _expectCrossing(GateCrossing actual, Map<String, dynamic> e, String at) {
  expect(actual.direction.name, e['direction'], reason: '$at direction');
  expect(actual.gapped, e['gapped'], reason: '$at gapped');
  expect(actual.fraction, closeTo(_num(e['fraction']), _fracTol),
      reason: '$at fraction');
  expect((actual.tMs - _t0) / 1000, closeTo(_num(e['atS']), _timeTol),
      reason: '$at atS');
  expect(actual.coveredM, closeTo(_num(e['coveredM']), _distTol),
      reason: '$at coveredM');
  expect(actual.offsetM, closeTo(_num(e['offsetM']), _distTol),
      reason: '$at offsetM');
}

void main() {
  test('every section in the file is one this reader runs', () {
    final unknown = _fixture.keys
        .where((k) => !_metaKeys.contains(k) && !_sections.contains(k))
        .toList();
    expect(unknown, isEmpty);
    final schemaSections = (_fixture['schema'] as Map<String, dynamic>)
        .keys
        .where((k) => !const {'general', 'constants', 'gate', 'position'}
            .contains(k))
        .toSet();
    expect(schemaSections, _sections.toSet());
    for (final s in _sections) {
      expect(_section(s), isNotEmpty, reason: 'section $s is empty');
    }
  });

  test('the constants match the file', () {
    expect(kGateEarthRadiusM, _num(_constants['EARTH_RADIUS_M']));
    expect(kGateMaxGapS, _num(_constants['MAX_GAP_S']));
    expect(kGateMaxHopM, _num(_constants['MAX_HOP_M']));
    expect(kGateRejectGapS, _num(_constants['REJECT_GAP_S']));
    expect(kGateHalfWidthRaceM, _num(_constants['HALF_WIDTH_RACE_M']));
    expect(kGateHalfWidthSegmentM, _num(_constants['HALF_WIDTH_SEGMENT_M']));
  });

  group('projection', () {
    for (final c in _section('projection')) {
      test(c['name'], () {
        final gate = _gate(c['gate'] as Map<String, dynamic>);
        final p = _position(gate, c['point'] as Map<String, dynamic>);
        final got = gateProjection(gate, p.lat, p.lng);
        final e = c['expect'] as Map<String, dynamic>;
        expect(got.s, closeTo(_num(e['s']), _distTol), reason: 's');
        expect(got.u, closeTo(_num(e['u']), _distTol), reason: 'u');
      });
    }
  });

  group('crossings', () {
    for (final c in _section('crossings')) {
      test(c['name'], () {
        final gate = _gate(c['gate'] as Map<String, dynamic>);
        final options = _options(_req(c, 'options'));
        final fixes = (c['fixes'] as List)
            .cast<Map<String, dynamic>>()
            .map((f) => _fix(gate, f))
            .toList();
        final expected = (c['expect'] as List).cast<Map<String, dynamic>>();

        final detector = GateCrossingDetector(gate, options);
        for (var i = 0; i < fixes.length; i++) {
          final got = detector.offer(fixes[i]);
          final e =
              expected.where((x) => _num(x['afterFix']) == i).firstOrNull;
          if (e == null) {
            expect(got, isNull, reason: 'offer(fixes[$i]) should be null');
          } else {
            expect(got, isNotNull,
                reason: 'offer(fixes[$i]) should return a crossing');
            _expectCrossing(got!, e, 'offer(fixes[$i])');
          }
        }

        final settled = detector.settle();
        expect(settled, hasLength(expected.length), reason: 'settle() count');
        for (var i = 0; i < settled.length; i++) {
          _expectCrossing(settled[i], expected[i], 'settle()[$i]');
        }

        final after = _req(c, 'fixesAfterSettle') as List?;
        for (final f in (after ?? const []).cast<Map<String, dynamic>>()) {
          expect(detector.offer(_fix(gate, f)), isNull,
              reason: 'offer after settle');
        }
        expect(detector.settle(), hasLength(expected.length),
            reason: 'settle() unchanged');

        final batch = crossingsOf(fixes, gate, options);
        expect(batch, hasLength(expected.length), reason: 'crossingsOf count');
        for (var i = 0; i < batch.length; i++) {
          _expectCrossing(batch[i], expected[i], 'crossingsOf[$i]');
        }
      });
    }
  });
}
