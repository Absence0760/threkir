import 'package:flutter_test/flutter_test.dart';
import '../lib/route_history.dart';

var _seq = 0;

const _unset = Object();

RouteHistoryRun baseRun({
  String? id,
  Object? routeId = _unset,
  double distanceM = 5000,
  int durationS = 1500,
  String? activityType,
}) =>
    RouteHistoryRun(
      id: id ?? 'run-${_seq++}',
      routeId: identical(routeId, _unset) ? 'route-1' : routeId as String?,
      distanceM: distanceM,
      durationS: durationS,
      activityType: activityType,
    );

void main() {
  test('qualifyingAttempts excludes runs without a route_id', () {
    final me = baseRun(id: 'me', routeId: null);
    final others = [baseRun(id: 'a'), baseRun(id: 'b')];
    expect(qualifyingAttempts(me, others), isEmpty);
  });

  test('qualifyingAttempts treats an empty route_id as no route', () {
    final me = baseRun(id: 'me', routeId: '');
    final others = [baseRun(id: 'a', routeId: ''), baseRun(id: 'b', routeId: '')];
    expect(qualifyingAttempts(me, others), isEmpty);
  });

  test('qualifyingAttempts filters to same route_id', () {
    final me = baseRun(id: 'me', routeId: 'route-1');
    final others = [
      baseRun(id: 'same', routeId: 'route-1'),
      baseRun(id: 'different', routeId: 'route-2'),
    ];
    final got = qualifyingAttempts(me, others);
    expect(got.length, 1);
    expect(got[0].id, 'same');
  });

  test('qualifyingAttempts excludes runs under 100 m', () {
    final me = baseRun(id: 'me');
    final others = [
      baseRun(id: 'long', distanceM: 5000),
      baseRun(id: 'tiny', distanceM: 50),
    ];
    final got = qualifyingAttempts(me, others);
    expect(got.length, 1);
    expect(got[0].id, 'long');
  });

  test('qualifyingAttempts filters by activity_type (defaulting to run)', () {
    final me = baseRun(id: 'me');
    final others = [
      baseRun(id: 'run', activityType: 'run'),
      baseRun(id: 'walk', activityType: 'walk'),
      baseRun(id: 'undef'),
    ];
    final got = qualifyingAttempts(me, others);
    expect(got.map((r) => r.id).toList()..sort(), ['run', 'undef']);
  });

  test(
      'qualifyingAttempts leaves out a run holding the ten-day repair placeholder',
      () {
    final me = baseRun(id: 'me', durationS: 1500);
    final others = [
      me,
      baseRun(id: 'capped', durationS: 864000),
      baseRun(id: 'slow', durationS: 863999),
    ];
    expect(qualifyingAttempts(me, others).map((r) => r.id).toList(),
        ['me', 'slow']);
    final capped = others[1];
    expect(summariseHistory(capped.id, qualifyingAttempts(capped, others)),
        isNull);
  });

  test('qualifyingAttempts leaves out a run with distance and no time', () {
    final me = baseRun(id: 'me', durationS: 1500);
    final others = [me, baseRun(id: 'untimed', durationS: 0)];
    expect(qualifyingAttempts(me, others).map((r) => r.id).toList(), ['me']);
  });

  test('qualifyingAttempts sorts by duration ascending', () {
    final me = baseRun(id: 'me');
    final others = [
      baseRun(id: 'slow', durationS: 2000),
      baseRun(id: 'fast', durationS: 1200),
      baseRun(id: 'medium', durationS: 1600),
    ];
    final got = qualifyingAttempts(me, others);
    expect(got.map((r) => r.id).toList(), ['fast', 'medium', 'slow']);
  });

  test('summariseHistory returns null for fewer than 2 attempts', () {
    final only = [baseRun(id: 'me', durationS: 1500)];
    expect(summariseHistory('me', only), isNull);
  });

  test('summariseHistory marks PB correctly', () {
    final attempts = [
      baseRun(id: 'me', durationS: 1200),
      baseRun(id: 'old', durationS: 1500),
    ];
    final s = summariseHistory('me', attempts)!;
    expect(s.isPb, true);
    expect(s.rank, 1);
    expect(s.total, 2);
    expect(s.deltaSeconds, 0);
  });

  test('summariseHistory computes delta and rank for non-PB run', () {
    final attempts = [
      baseRun(id: 'pb', durationS: 1200),
      baseRun(id: 'me', durationS: 1283),
      baseRun(id: 'slow', durationS: 1500),
    ];
    final s = summariseHistory('me', attempts)!;
    expect(s.isPb, false);
    expect(s.rank, 2);
    expect(s.total, 3);
    expect(s.deltaSeconds, 83);
    expect(s.pb.id, 'pb');
  });

  test('summariseHistory makes a run tied with the fastest time a PB too', () {
    for (final order in [
      ['first', 'me'],
      ['me', 'first'],
    ]) {
      final attempts = [
        for (final id in order) baseRun(id: id, durationS: 1200),
        baseRun(id: 'slow', durationS: 1500),
      ];
      final s = summariseHistory('me', attempts)!;
      expect(s.isPb, true);
      expect(s.rank, 1);
      expect(s.deltaSeconds, 0);
    }
  });

  test('summariseHistory gives tied times the same competition rank', () {
    final attempts = [
      baseRun(id: 'a', durationS: 1500),
      baseRun(id: 'b', durationS: 1600),
      baseRun(id: 'c', durationS: 1600),
      baseRun(id: 'd', durationS: 1700),
    ];
    expect(
        ['a', 'b', 'c', 'd']
            .map((id) => summariseHistory(id, attempts)!.rank)
            .toList(),
        [1, 2, 2, 4]);
    expect(summariseHistory('c', attempts)!.isPb, false);
  });

  test('summariseHistory returns null when current run is not in attempts list',
      () {
    final attempts = [
      baseRun(id: 'a', durationS: 1200),
      baseRun(id: 'b', durationS: 1500),
    ];
    expect(summariseHistory('not-in-list', attempts), isNull);
  });

  test('formatSignedDelta renders signs and unit boundaries', () {
    expect(formatSignedDelta(0), '0:00');
    expect(formatSignedDelta(5), '+0:05');
    expect(formatSignedDelta(-5), '\u22120:05');
    expect(formatSignedDelta(83), '+1:23');
    expect(formatSignedDelta(-3725), '\u22121:02:05');
  });
}
