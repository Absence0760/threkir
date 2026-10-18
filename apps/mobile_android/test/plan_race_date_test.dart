// Twin of apps/web/src/lib/training/plan_race_date.test.ts — same cases.

import 'package:flutter_test/flutter_test.dart';

import '../lib/plan_bulk_ops.dart';
import '../lib/plan_race_date.dart';

// A ten-week half plan from Sunday 2026-06-07: base 0-1, build 2-5, peak 6-7,
// taper 8, race 9. A long run every Sunday, the race on week 9's Sunday and
// six easy days after it, as the generator writes them. Today is in week 2.
const _s = '2026-06-07';
const _today = '2026-06-24';
const _phases = [
  'base', 'base', 'build', 'build', 'build', 'build', 'peak', 'peak', 'taper', 'race'
];
final _plan = RaceDatePlan(
    startDate: _s,
    endDate: shiftIsoDate(_s, 69),
    trimmedAt: null,
    status: 'active');
final _weeks = [
  for (var i = 0; i < _phases.length; i++)
    RaceDateWeek(id: 'w$i', weekIndex: i, phase: _phases[i])
];

List<RaceDateWorkout> _workouts() => [
      for (var i = 0; i < 10; i++)
        RaceDateWorkout(
          id: i == 9 ? 'race' : 'long$i',
          weekId: 'w$i',
          scheduledDate: shiftIsoDate(_s, 7 * i),
          kind: i == 9 ? 'race' : 'long',
          completedRunId: null,
          manuallyCompleted: i == 0,
        ),
      for (var d = 1; d <= 6; d++)
        RaceDateWorkout(
          id: 'easy$d',
          weekId: 'w9',
          scheduledDate: shiftIsoDate(_s, 63 + d),
          kind: 'easy',
          completedRunId: null,
          manuallyCompleted: false,
        ),
    ];

RaceDateResult _change(String raceDateIso,
        {String? todayIso, List<RaceDateWorkout>? workouts}) =>
    raceDateChange(
      plan: _plan,
      weeks: _weeks,
      workouts: workouts ?? _workouts(),
      raceDateIso: raceDateIso,
      todayIso: todayIso ?? _today,
    );

void main() {
  test('an earlier race drops the latest build weeks first and moves the race',
      () {
    final r = _change(shiftIsoDate(_s, 52));
    expect(r.ok, isTrue);
    final c = r.change!;
    expect(c.raceDateIso, shiftIsoDate(_s, 52));
    expect(c.weekDelta, -2);
    expect(c.dropWeekIds, ['w4', 'w5']);
    expect(c.insertAt, isNull);
    expect(c.insertCount, 0);
    expect(c.repeatWeekId, isNull);
    expect(c.raceWorkoutId, 'race');
  });

  test('once the build runs out the peak goes, never the taper', () {
    final r = _change(shiftIsoDate(_s, 35));
    expect(r.ok, isTrue);
    expect(r.change!.dropWeekIds, ['w3', 'w4', 'w5', 'w7']);
    expect(r.change!.weekDelta, -4);
  });

  test(
      'a race too close for the taper is refused with the earliest day it can keep',
      () {
    final r = _change(shiftIsoDate(_s, 21));
    expect(r.reason, RaceDateRefusal.tooSoon);
    expect(r.earliestIso, shiftIsoDate(_s, 28));
  });

  test('a later race repeats the last build week before the peak', () {
    final r = _change(shiftIsoDate(_s, 77));
    expect(r.ok, isTrue);
    final c = r.change!;
    expect(c.raceDateIso, shiftIsoDate(_s, 77));
    expect(c.weekDelta, 2);
    expect(c.dropWeekIds, isEmpty);
    expect(c.insertAt, 6);
    expect(c.insertCount, 2);
    expect(c.repeatWeekId, 'w5');
    expect(c.raceWorkoutId, 'race');
  });

  test('a later race once the peak has started goes in before the taper', () {
    final r = _change(shiftIsoDate(_s, 77), todayIso: shiftIsoDate(_s, 45));
    expect(r.ok, isTrue);
    expect(r.change!.insertAt, 7);
    expect(r.change!.repeatWeekId, 'w5');
  });

  test('a move inside race week changes no weeks', () {
    final r = _change(shiftIsoDate(_s, 67));
    expect(r.ok, isTrue);
    expect(r.change!.weekDelta, 0);
    expect(r.change!.dropWeekIds, isEmpty);
    expect(r.change!.insertAt, isNull);
  });

  test('race week under way cannot take a week in front of it', () {
    expect(_change(shiftIsoDate(_s, 75), todayIso: shiftIsoDate(_s, 64)).reason,
        RaceDateRefusal.raceWeekStarted);
  });

  test('another race in a week that would move is in the way', () {
    final wos = [
      for (final w in _workouts())
        w.id == 'long7' ? w.copyWith(kind: 'race', racePriority: 'B') : w
    ];
    expect(_change(shiftIsoDate(_s, 77), workouts: wos).reason,
        RaceDateRefusal.inTheWay);
  });

  test('a completed workout in a week that would move is in the way', () {
    final wos = [
      for (final w in _workouts())
        w.id == 'long6' ? w.copyWith(manuallyCompleted: true) : w
    ];
    expect(_change(shiftIsoDate(_s, 52), workouts: wos).reason,
        RaceDateRefusal.inTheWay);
  });

  test('past, invalid, unchanged and too-far dates are refused', () {
    expect(_change(_today).reason, RaceDateRefusal.past);
    expect(_change('2026-02-31').reason, RaceDateRefusal.invalid);
    expect(_change(_plan.endDate).reason, RaceDateRefusal.unchanged);
    expect(_change(shiftIsoDate(_s, 63 + 7 * 53)).reason, RaceDateRefusal.tooFar);
  });

  test('a plan with no race ahead offers nothing to move', () {
    expect(planRaceDate(_plan, _weeks), _plan.endDate);
    expect(
        planRaceDate(
            RaceDatePlan(
                startDate: _s,
                endDate: _plan.endDate,
                trimmedAt: '2026-06-20T00:00:00Z',
                status: 'active'),
            _weeks),
        isNull);
    expect(
        planRaceDate(
            RaceDatePlan(
                startDate: _s,
                endDate: _plan.endDate,
                trimmedAt: null,
                status: 'completed'),
            _weeks),
        isNull);
    expect(
        planRaceDate(_plan, [
          for (final w in _weeks)
            w.weekIndex == 9
                ? RaceDateWeek(id: w.id, weekIndex: 9, phase: 'graduation')
                : w
        ]),
        isNull);
    expect(_change(shiftIsoDate(_s, 80), todayIso: shiftIsoDate(_s, 70)).reason,
        RaceDateRefusal.noRace);
  });
}
