// Mirror of apps/web/src/lib/training/plan_restart.test.ts.

import 'package:flutter_test/flutter_test.dart';

import '../lib/plan_restart.dart';

RestartWorkout _wo(String kind, String date) =>
    RestartWorkout(kind: kind, scheduledDate: date);

void main() {
  test('isWalkRunPlan: walk-run, rest and race days with a walk-run', () {
    expect(
        isWalkRunPlan([
          _wo('walk_run', '2026-01-01'),
          _wo('rest', '2026-01-02'),
          _wo('race', '2026-01-03'),
        ]),
        isTrue);
  });
  test('isWalkRunPlan: false with any other kind', () {
    expect(
        isWalkRunPlan(
            [_wo('walk_run', '2026-01-01'), _wo('easy', '2026-01-02')]),
        isFalse);
  });
  test('isWalkRunPlan: false with no walk-run at all', () {
    expect(isWalkRunPlan([_wo('rest', '2026-01-01')]), isFalse);
  });

  test('upcomingRaceIso: null when every race is behind', () {
    expect(
        upcomingRaceIso(
            [_wo('race', '2026-10-01'), _wo('easy', '2026-11-01')],
            '2026-10-18'),
        isNull);
  });
  test('upcomingRaceIso: a race today is ahead', () {
    expect(upcomingRaceIso([_wo('race', '2026-10-18')], '2026-10-18'),
        '2026-10-18');
  });
  test('upcomingRaceIso: the earliest race ahead', () {
    expect(
        upcomingRaceIso([
          _wo('race', '2026-12-01'),
          _wo('race', '2026-11-01'),
          _wo('race', '2026-09-01'),
        ], '2026-10-18'),
        '2026-11-01');
  });
  test('upcomingRaceIso: an unreadable date is ignored', () {
    expect(upcomingRaceIso([_wo('race', 'soon')], '2026-10-18'), isNull);
  });

  test('alignRestartStartIso: a date on the source weekday stays', () {
    expect(alignRestartStartIso('2026-10-25', '2026-03-01', false),
        '2026-10-25');
  });
  test('alignRestartStartIso: snaps forward to the source weekday', () {
    expect(alignRestartStartIso('2026-10-20', '2026-03-01', false),
        '2026-10-25');
  });
  test('alignRestartStartIso: a walk-run plan is left alone', () {
    expect(alignRestartStartIso('2026-10-20', '2026-03-01', true),
        '2026-10-20');
  });
  test('alignRestartStartIso: a source after the picked date', () {
    expect(alignRestartStartIso('2026-10-20', '2027-01-06', false),
        '2026-10-21');
  });

  test('defaultRestartStartIso: the source weekday at least a week out', () {
    expect(defaultRestartStartIso('2026-03-01', '2026-10-18', false),
        '2026-10-25');
    expect(defaultRestartStartIso('2026-03-01', '2026-10-19', false),
        '2026-11-01');
  });
  test('defaultRestartStartIso: a Wednesday-anchored plan', () {
    expect(defaultRestartStartIso('2026-03-04', '2026-10-18', false),
        '2026-10-28');
  });
  test('defaultRestartStartIso: tomorrow for a walk-run plan', () {
    expect(defaultRestartStartIso('2026-03-04', '2026-10-18', true),
        '2026-10-19');
  });

  test('restartStartAllowed: refuses a date before today', () {
    expect(restartStartAllowed('2026-10-11', '2026-03-01', '2026-10-18', false),
        isFalse);
  });
  test('restartStartAllowed: today on the source weekday', () {
    expect(restartStartAllowed('2026-10-18', '2026-03-01', '2026-10-18', false),
        isTrue);
  });
  test('restartStartAllowed: another weekday only for walk-run', () {
    expect(restartStartAllowed('2026-10-20', '2026-03-01', '2026-10-18', false),
        isFalse);
    expect(restartStartAllowed('2026-10-20', '2026-03-01', '2026-10-18', true),
        isTrue);
  });
  test('restartStartAllowed: refuses an unreadable date', () {
    expect(
        restartStartAllowed('', '2026-03-01', '2026-10-18', true), isFalse);
  });

  test('restartedDateIso: moves a date by the start offset', () {
    expect(restartedDateIso('2026-05-24', '2026-03-01', '2026-10-25'),
        '2027-01-17');
  });
  test('restartedDateIso: an unreadable start keeps the date', () {
    expect(restartedDateIso('2026-05-24', 'x', '2026-10-25'), '2026-05-24');
  });
}
