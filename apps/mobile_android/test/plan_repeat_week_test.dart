// Twin of apps/web/src/lib/training/plan_repeat_week.test.ts — same cases.

import 'package:flutter_test/flutter_test.dart';

import '../lib/plan_bulk_ops.dart';
import '../lib/plan_race_date.dart';
import '../lib/plan_repeat_week.dart';

// A ten-week plan from Sunday 2026-06-07. The race plan: base 0-1, build 2-5,
// peak 6-7, taper 8, race 9 on its last Sunday, the end date. The walk-run
// plan: every week base, no race, ending on week 9's Saturday. A long run
// every Sunday and an easy run every Wednesday, weeks 0-1 done. Today is week
// 4's Tuesday.
const _s = '2026-06-07';
final _today = shiftIsoDate(_s, 30);
const _race = [
  'base', 'base', 'build', 'build', 'build', 'build', 'peak', 'peak', 'taper', 'race'
];
final _walk = List.filled(10, 'base');

RaceDatePlan _plan(List<String> phases,
        {String status = 'active', String? trimmedAt, bool isTemplate = false}) =>
    RaceDatePlan(
      startDate: _s,
      endDate: shiftIsoDate(_s, phases.last == 'race' ? 63 : 69),
      trimmedAt: trimmedAt,
      status: status,
      isTemplate: isTemplate,
    );

List<RaceDateWeek> _weeks(List<String> phases) => [
      for (var i = 0; i < phases.length; i++)
        RaceDateWeek(id: 'w$i', weekIndex: i, phase: phases[i])
    ];

List<RaceDateWorkout> _workouts(List<String> phases) {
  final out = <RaceDateWorkout>[];
  for (var i = 0; i < phases.length; i++) {
    final race = phases[i] == 'race';
    out.add(RaceDateWorkout(
      id: race ? 'race' : 'long$i',
      weekId: 'w$i',
      scheduledDate: shiftIsoDate(_s, 7 * i),
      kind: race ? 'race' : 'long',
      completedRunId: null,
      manuallyCompleted: i <= 1,
    ));
    if (!race) {
      out.add(RaceDateWorkout(
        id: 'easy$i',
        weekId: 'w$i',
        scheduledDate: shiftIsoDate(_s, 7 * i + 3),
        kind: 'easy',
        completedRunId: null,
        manuallyCompleted: i <= 1,
      ));
    }
  }
  return out;
}

RepeatWeekResult _run(List<String> phases, String weekId,
        {RaceDatePlan? plan, String? todayIso, List<RaceDateWorkout>? workouts}) =>
    repeatWeekChange(
      plan: plan ?? _plan(phases),
      weeks: _weeks(phases),
      workouts: workouts ?? _workouts(phases),
      weekId: weekId,
      todayIso: todayIso ?? _today,
    );

void main() {
  test('a walk-run plan repeats this week next week and ends a week later', () {
    final c = _run(_walk, 'w4').change!;
    expect(c.weekId, 'w4');
    expect(c.copyIndex, 5);
    expect(c.copyStartIso, shiftIsoDate(_s, 35));
    expect(c.dropWeekId, isNull);
    expect(c.endIso, shiftIsoDate(_s, 76));
    expect(c.raceDateIso, isNull);
  });

  test('last week runs again after this week, not inside it', () {
    final c = _run(_walk, 'w3').change!;
    expect(c.copyIndex, 5);
    expect(c.copyStartIso, shiftIsoDate(_s, 35));
  });

  test('a race plan keeps race day by dropping its latest build week', () {
    final c = _run(_race, 'w4').change!;
    expect(c.weekId, 'w4');
    expect(c.copyIndex, 5);
    expect(c.copyStartIso, shiftIsoDate(_s, 35));
    expect(c.dropWeekId, 'w5');
    expect(c.endIso, shiftIsoDate(_s, 63));
    expect(c.raceDateIso, shiftIsoDate(_s, 63));
  });

  test('with the build behind it, a race plan drops its latest peak week', () {
    final r = _run(_race, 'w6', todayIso: shiftIsoDate(_s, 44));
    expect(r.change!.dropWeekId, 'w7');
  });

  test('a race plan with no pre-taper week left to drop has no room', () {
    final r = _run(_race, 'w7', todayIso: shiftIsoDate(_s, 51));
    expect(r.reason, RepeatWeekRefusal.noRoom);
  });

  test('a week two back, or one not started, cannot run again', () {
    expect(_run(_walk, 'w2').reason, RepeatWeekRefusal.notRepeatable);
    expect(_run(_walk, 'w5').reason, RepeatWeekRefusal.notRepeatable);
    expect(_run(_walk, 'nope').reason, RepeatWeekRefusal.notRepeatable);
  });

  test('the taper never runs again', () {
    final r = _run(_race, 'w8', todayIso: shiftIsoDate(_s, 58));
    expect(r.reason, RepeatWeekRefusal.notRepeatable);
  });

  test('the last week has nothing after it to push back', () {
    final r = _run(_walk, 'w9', todayIso: shiftIsoDate(_s, 65));
    expect(r.reason, RepeatWeekRefusal.lastWeek);
  });

  test('a paused, template, trimmed, unstarted or finished plan is not active',
      () {
    for (final r in [
      _run(_walk, 'w4', plan: _plan(_walk, status: 'paused')),
      _run(_walk, 'w4', plan: _plan(_walk, isTemplate: true)),
      _run(_walk, 'w4',
          plan: _plan(_walk, trimmedAt: '2026-06-20T00:00:00Z')),
      _run(_walk, 'w4', todayIso: shiftIsoDate(_s, -1)),
      _run(_walk, 'w4', todayIso: shiftIsoDate(_s, 70)),
    ]) {
      expect(r.reason, RepeatWeekRefusal.notActive);
    }
  });

  test('a done workout or a B race in a week that would move is in the way',
      () {
    final done = [
      for (final w in _workouts(_walk))
        w.id == 'easy7' ? w.copyWith(manuallyCompleted: true) : w
    ];
    expect(_run(_walk, 'w4', workouts: done).reason, RepeatWeekRefusal.inTheWay);
    final bRace = [
      for (final w in _workouts(_race))
        w.id == 'long5' ? w.copyWith(kind: 'race') : w
    ];
    expect(_run(_race, 'w4', workouts: bRace).reason, RepeatWeekRefusal.inTheWay);
  });

  test(
      'the shared rerun drops as many weeks as it copies, build first, then the latest peak',
      () {
    final p = _plan(_race);
    final frame = rerunFrame(p, _weeks(_race), _workouts(_race), _today)!;
    expect(frame.drops.map((w) => w.id).toList(), ['w5', 'w7', 'w6']);
    final two = rerunPlacement(frame, p, 2);
    expect(two.ok, isTrue);
    expect(two.drops.map((w) => w.id).toList(), ['w5', 'w7']);
    expect(two.endIso, p.endDate);
    expect(rerunPlacement(frame, p, 4).reason, RepeatWeekRefusal.noRoom);
  });

  test('the shared rerun moves a plan without a race back by its copies', () {
    final p = _plan(_walk);
    final frame = rerunFrame(p, _weeks(_walk), _workouts(_walk), _today)!;
    expect(frame.current, 4);
    final three = rerunPlacement(frame, p, 3);
    expect(three.ok, isTrue);
    expect(three.drops, isEmpty);
    expect(three.endIso, shiftIsoDate(_s, 69 + 21));
    expect(
        rerunFrame(p, _weeks(_walk), _workouts(_walk), shiftIsoDate(_s, 65)),
        isNull);
  });
}
