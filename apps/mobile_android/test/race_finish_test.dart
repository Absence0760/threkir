import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import '../lib/gate_crossing.dart';
import '../lib/race_finish.dart';

/// The Dart reader of `fixtures/race_finish_cases.json`, the case table the
/// `race_finish` pair shares with Wear's `RaceFinishTest.kt`. The file's own
/// `schema` block says what each section means; a case changes there, for
/// both sides at once, or not at all.
final Map<String, dynamic> _fixture = jsonDecode(
        File('../../fixtures/race_finish_cases.json').readAsStringSync())
    as Map<String, dynamic>;

List<Map<String, dynamic>> _section(String name) =>
    (_fixture[name] as List).cast<Map<String, dynamic>>();

double _num(Object? v) => switch (v) {
      'NaN' => double.nan,
      'Infinity' => double.infinity,
      '-Infinity' => double.negativeInfinity,
      num n => n.toDouble(),
      _ => throw FormatException('not a fixture number: $v'),
    };

double? _numOrNull(Object? v) => v == null ? null : _num(v);

final DateTime _t0 = DateTime.fromMillisecondsSinceEpoch(
    _fixture['t0EpochMs'] as int,
    isUtc: true);

DateTime _ms(Object? v) => _t0.add(Duration(milliseconds: v as int));
DateTime? _msOrNull(Object? v) => v == null ? null : _ms(v);
DateTime _s(Object? v) => _t0.add(Duration(seconds: v as int));

final double _distanceTol = _num(_fixture['distanceToleranceM']);
final double _offsetTolMs = _num(_fixture['offsetToleranceMs']);

final Map<String, dynamic> _origin =
    _fixture['origin'] as Map<String, dynamic>;
final double _finishLat = _num(_origin['finishLat']);
final double _finishLng = _num(_origin['finishLng']);

RaceFix _fix(Map<String, dynamic> f) {
  final constants = _fixture['constants'] as Map<String, dynamic>;
  final mPerDegLat = _num(constants['EARTH_RADIUS_M']) * math.pi / 180;
  return RaceFix(
    lat: _finishLat + _num(f['northM']) / mPerDegLat,
    lng: _finishLng,
    at: _s(f['atS']),
    coveredM: _num(f['coveredM']),
  );
}

/// A nullable field must be present; a missing key is not a null.
Object? _req(Map<String, dynamic> o, String key) {
  if (!o.containsKey(key)) {
    throw StateError("case ${o['name']} has no '$key'");
  }
  return o[key];
}

final double _gateK = _num((_fixture['constants']
            as Map<String, dynamic>)['GATE_EARTH_RADIUS_M']) *
    math.pi /
    180;

({double lat, double lng}) _plane(Map<String, dynamic> o) => (
      lat: _finishLat + _num(o['northM']) / _gateK,
      lng: _finishLng +
          _num(o['eastM']) / (_gateK * math.cos(_finishLat * math.pi / 180)),
    );

Gate? _gate(Object? o) {
  if (o == null) return null;
  final g = o as Map<String, dynamic>;
  final p = _plane(g);
  return Gate(
    lat: p.lat,
    lng: p.lng,
    bearingDeg: _num(g['bearingDeg']),
    halfWidthM: _num(g['halfWidthM']),
  );
}

RaceFix _planeFix(Map<String, dynamic> f) {
  final p = _plane(f);
  return RaceFix(
      lat: p.lat, lng: p.lng, at: _s(f['atS']), coveredM: _num(f['coveredM']));
}

int _rel(DateTime at) => at.millisecondsSinceEpoch - _t0.millisecondsSinceEpoch;

void _expectStart(RaceStart? got, Object? want, String what) {
  if (want == null) {
    expect(got, isNull, reason: what);
    return;
  }
  final w = want as Map<String, dynamic>;
  expect(got, isNotNull, reason: what);
  expect(_rel(got!.at), w['atMs'], reason: '$what atMs');
  expect(got.coveredM, closeTo(_num(w['coveredM']), _distanceTol),
      reason: '$what coveredM');
  expect(got.kind.name, w['kind'], reason: '$what kind');
}

void _expectFinish(RaceFinish? got, Object? want, String what) {
  if (want == null) {
    expect(got, isNull, reason: what);
    return;
  }
  final w = want as Map<String, dynamic>;
  expect(got, isNotNull, reason: what);
  expect(_rel(got!.at), w['atMs'], reason: '$what atMs');
  expect(got.coveredM, closeTo(_num(w['coveredM']), _distanceTol),
      reason: '$what coveredM');
  expect(got.distanceToFinishM,
      closeTo(_num(w['distanceToFinishM']), _distanceTol),
      reason: '$what distanceToFinishM');
  expect(got.detection.wire, w['detection'], reason: '$what detection');
  expect(got.gapped, w['gapped'], reason: '$what gapped');
  _expectStart(got.start, _req(w, 'start'), '$what start');
}

RaceFinishMethod? _method(Object? wire) => wire == null
    ? null
    : RaceFinishMethod.values.firstWhere((m) => m.wire == wire);

void main() {
  test('the constants match the shared case table', () {
    final c = _fixture['constants'] as Map<String, dynamic>;
    expect(kRaceFinishZoneM, _num(c['FINISH_ZONE_M']));
    expect(kRaceFinishMinCoverage, _num(c['MIN_COVERAGE']));
    expect(kRaceFinishMinCoverageWithStart,
        _num(c['MIN_COVERAGE_WITH_START']));
    expect(kRaceStartCommitM, _num(c['START_COMMIT_M']));
    expect(kRaceLapShortShare, _num(c['LAP_SHORT_SHARE']));
    expect(kGateEarthRadiusM, _num(c['GATE_EARTH_RADIUS_M']));
    expect(kRaceLateStartAfter.inMilliseconds, c['LATE_START_AFTER_MS']);
    expect(kRaceLateStartFarM, _num(c['LATE_START_FAR_M']));
  });

  group('raceDistanceM', () {
    for (final c in _section('distance')) {
      test(c['name'], () {
        final a = (c['a'] as List).map(_num).toList();
        final b = (c['b'] as List).map(_num).toList();
        expect(raceDistanceM(a[0], a[1], b[0], b[1]),
            closeTo(_num(c['expectM']), _distanceTol));
      });
    }
  });

  group('raceInFinishZone', () {
    for (final c in _section('zone')) {
      test(c['name'], () {
        expect(raceInFinishZone(_num(c['distanceM'])), c['inZone']);
      });
    }
  });

  group('raceCoverageMet', () {
    for (final c in _section('coverage')) {
      test(c['name'], () {
        expect(
            raceCoverageMet(
                _num(c['coveredM']), _numOrNull(c['courseDistanceM'])),
            c['met']);
      });
    }
  });

  group('RaceFinishDetector', () {
    for (final c in _section('detector')) {
      test(c['name'], () {
        final expected = c['expect'] as Map<String, dynamic>;
        final d = RaceFinishDetector(
          finishLat: _finishLat,
          finishLng: _finishLng,
          courseDistanceM: _num(c['courseDistanceM']),
        );
        int? finalisedAt;
        RaceFinish? finish;
        final fixes = (c['fixes'] as List).cast<Map<String, dynamic>>();
        for (var i = 0; i < fixes.length; i++) {
          final r = d.offer(_fix(fixes[i]));
          if (r == null) continue;
          expect(finalisedAt, isNull,
              reason: 'a detector finalises exactly once');
          finalisedAt = i;
          finish = r;
        }
        expect(finalisedAt, expected['finalisesAtFix']);
        final want = expected['finish'] as Map<String, dynamic>?;
        if (want == null) {
          expect(finish, isNull);
        } else {
          expect(finish!.at, _s(want['atS']));
          expect(finish.distanceToFinishM,
              closeTo(_num(want['distanceToFinishM']), _distanceTol));
          expect(finish.coveredM, _num(want['coveredM']));
          expect(d.result, same(finish));
        }
        final candidateAtS = expected['candidateAtS'];
        expect(d.candidate?.at, candidateAtS == null ? null : _s(candidateAtS));

        final settled = d.settle();
        final settleAtS = expected['settleAtS'];
        expect(settled?.at, settleAtS == null ? null : _s(settleAtS));
        expect(d.candidate, isNull, reason: 'settle closes the approach');

        final after = (c['fixesAfterSettle'] as List?)
                ?.cast<Map<String, dynamic>>() ??
            const <Map<String, dynamic>>[];
        for (final f in after) {
          expect(d.offer(_fix(f)), isNull);
          expect(d.result, same(settled));
        }
      });
    }
  });

  group('raceStartFlagged', () {
    for (final c in _section('startFlag')) {
      test(c['name'], () {
        expect(
            raceStartFlagged(
              gunAt: _ms(c['gunMs']),
              recordingStartedAt: _ms(c['recordingStartedMs']),
              firstFixFromStartM: _numOrNull(c['firstFixFromStartM']),
            ),
            c['flagged']);
      });
    }
  });

  group('ServerClockOffset', () {
    for (final c in _section('clockOffset')) {
      test(c['name'], () {
        final expected = c['expect'] as Map<String, dynamic>;
        final offset = ServerClockOffset();
        for (final s in (c['samples'] as List).cast<Map<String, dynamic>>()) {
          offset.addSample(
            sentAt: _ms(s['sentMs']),
            receivedAt: _ms(s['receivedMs']),
            serverAt: _ms(s['serverMs']),
          );
        }
        expect(offset.known, expected['known']);
        expect(offset.offset.inMicroseconds / 1000,
            closeTo(_num(expected['offsetMs']), _offsetTolMs));
      });
    }

    test('toServer moves a device instant by the offset', () {
      final c = ServerClockOffset()
        ..addSample(
          sentAt: _t0,
          receivedAt: _t0.add(const Duration(milliseconds: 400)),
          serverAt: _t0.add(const Duration(seconds: 3, milliseconds: 200)),
        );
      expect(c.toServer(_t0), _t0.add(const Duration(seconds: 3)));
    });
  });

  group('raceGunTimeS', () {
    for (final c in _section('gunTime')) {
      test(c['name'], () {
        expect(
            raceGunTimeS(
              finishAtDevice: _ms(c['finishMs']),
              gunAt: _ms(c['gunMs']),
              clockOffset: Duration(milliseconds: c['offsetMs'] as int),
            ),
            c['gunTimeS']);
      });
    }
  });

  group('raceChipTimeS', () {
    for (final c in _section('chipTime')) {
      test(c['name'], () {
        expect(
            raceChipTimeS(
              finishAtDevice: _ms(c['finishMs']),
              recordingStartedAt: _ms(c['startMs']),
            ),
            c['chipTimeS']);
      });
    }
  });

  group('raceStopOutcome', () {
    for (final c in _section('stopOutcome')) {
      test(c['name'], () {
        final expected = c['expect'] as Map<String, dynamic>;
        final cand = c['candidate'] as Map<String, dynamic>?;
        final o = raceStopOutcome(
          candidate: cand == null
              ? null
              : RaceFinish(
                  at: _ms(cand['atMs']),
                  distanceToFinishM: _num(cand['distanceToFinishM']),
                  coveredM: _num(cand['coveredM']),
                ),
          coveredM: _num(c['coveredM']),
          courseDistanceM: _numOrNull(c['courseDistanceM']),
          now: _ms(c['nowMs']),
          lapsMet: _req(c, 'lapsMet') as bool?,
        );
        expect(o.finisherStatus, expected['finisherStatus']);
        expect(o.method?.wire, expected['method']);
        expect(o.finishAt, _msOrNull(expected['finishAtMs']));
      });
    }

    test('the method wire values match the result CHECK', () {
      expect(RaceFinishMethod.values.map((m) => m.wire),
          ['auto', 'manual', 'host']);
    });
  });

  group('raceResultTiming', () {
    for (final c in _section('resultTiming')) {
      test(c['name'], () {
        final expected = c['expect'] as Map<String, dynamic>;
        final outcome = c['outcome'] as Map<String, dynamic>;
        final t = raceResultTiming(
          outcome: RaceOutcome(
            finisherStatus: outcome['finisherStatus'] as String,
            method: _method(outcome['method']),
            finishAt: _msOrNull(outcome['finishAtMs']),
          ),
          gunAt: _msOrNull(c['gunMs']),
          clockOffset: Duration(milliseconds: c['offsetMs'] as int),
          recordingStartedAt: _msOrNull(c['recordingStartedMs']),
          startAt: _msOrNull(_req(c, 'startMs')),
          elapsedS: c['elapsedS'] as int,
        );
        expect(t.durationS, expected['durationS']);
        expect(t.gunTimeS, expected['gunTimeS']);
        expect(t.chipTimeS, expected['chipTimeS']);
      });
    }
  });

  group('RaceFinishDetector with lines (race_finish v3)', () {
    for (final c in _section('lines')) {
      test(c['name'], () {
        final expected = c['expect'] as Map<String, dynamic>;
        final goS = _req(c, 'goS') as int?;
        final goAfter = _req(c, 'goSetAfterFix') as int?;
        final d = RaceFinishDetector(
          finishLat: _finishLat,
          finishLng: _finishLng,
          courseDistanceM: _num(c['courseDistanceM']),
          startGate: _gate(_req(c, 'startGate')),
          finishGate: _gate(_req(c, 'finishGate')),
          mode: c['mode'] == 'selfTimed'
              ? RaceStartMode.selfTimed
              : RaceStartMode.gun,
          goAt: goS != null && goAfter == null ? _s(goS) : null,
          lapCount: _req(c, 'lapCount') as int?,
        );
        int? finalisedAt;
        RaceFinish? finish;
        final fixes = (c['fixes'] as List).cast<Map<String, dynamic>>();
        for (var i = 0; i < fixes.length; i++) {
          var r = d.offer(_planeFix(fixes[i]));
          if (goAfter == i) r ??= d.setGo(_s(goS!));
          if (r == null || finalisedAt != null) continue;
          finalisedAt = i;
          finish = r;
        }
        expect(finalisedAt, expected['finalisesAtFix']);
        _expectFinish(finish, _req(expected, 'finish'), 'finish');
        _expectStart(d.start, _req(expected, 'start'), 'start');
        expect(d.lapsMet(_num(fixes.last['coveredM'])),
            _req(expected, 'lapsMet'),
            reason: 'lapsMet');
        final candidateAtS = _req(expected, 'candidateAtS');
        expect(d.candidate?.at, candidateAtS == null ? null : _s(candidateAtS));

        final settled = d.settle();
        _expectFinish(settled, _req(expected, 'settle'), 'settle');

        final timing = _req(expected, 'timing') as Map<String, dynamic>?;
        if (settled == null) {
          expect(timing, isNull);
          return;
        }
        final pressS = _req(c, 'pressS') as int?;
        final t = raceResultTiming(
          outcome: RaceOutcome(
            finisherStatus: 'finished',
            method: RaceFinishMethod.auto,
            finishAt: settled.at,
          ),
          gunAt: goS == null ? null : _s(goS),
          recordingStartedAt: pressS == null ? null : _s(pressS),
          startAt: settled.start?.at,
          elapsedS: 0,
        );
        expect(t.gunTimeS, timing!['gunTimeS']);
        expect(t.chipTimeS, timing['chipTimeS']);
        expect(t.durationS, timing['durationS']);
      });
    }

    test('an unusable line is no line', () {
      const ok = Gate(lat: 51.5, lng: -0.1, bearingDeg: 0, halfWidthM: 15);
      expect(raceLineUsable(ok), isTrue);
      expect(raceLineUsable(null), isFalse);
      expect(
          raceLineUsable(const Gate(
              lat: 51.5, lng: -0.1, bearingDeg: 0, halfWidthM: 0)),
          isFalse);
      expect(
          raceLineUsable(const Gate(
              lat: 51.5, lng: -0.1, bearingDeg: double.nan, halfWidthM: 15)),
          isFalse);
    });

    test('GO is fixed once set', () {
      final d = RaceFinishDetector(
        finishLat: _finishLat,
        finishLng: _finishLng,
        courseDistanceM: 1000,
        startGate:
            const Gate(lat: 51.5, lng: -0.1, bearingDeg: 0, halfWidthM: 15),
        goAt: _s(0),
      );
      expect(d.setGo(_s(100)), isNull);
      d.offer(RaceFix(lat: 51.5 + 10 / _gateK, lng: -0.1, at: _s(1), coveredM: 0));
      expect(d.start?.at, _s(0), reason: 'past the line at the first GO');
    });
  });

  test('every section of the case table is read', () {
    const read = {
      'spec', 'reference', 'readers', 'schema', 'constants', 't0EpochMs',
      'distanceToleranceM', 'offsetToleranceMs', 'origin', 'distance', 'zone',
      'coverage', 'detector', 'startFlag', 'clockOffset', 'gunTime',
      'chipTime', 'stopOutcome', 'resultTiming', 'lines',
    };
    expect(_fixture.keys.toSet(), read,
        reason: 'a section this reader skips is a rule Dart stops keeping');
    for (final s in [
      'distance', 'zone', 'coverage', 'detector', 'startFlag', 'clockOffset',
      'gunTime', 'chipTime', 'stopOutcome', 'resultTiming', 'lines',
    ]) {
      expect(_section(s), isNotEmpty, reason: '$s has no cases');
    }
  });
}
