// Twin of apps/web/src/lib/training/plan_break.test.ts — same cases.

import 'package:flutter_test/flutter_test.dart';

import '../lib/plan_break.dart';
import '../lib/plan_bulk_ops.dart';
import '../lib/plan_race_date.dart';

// A ten-week half plan from Sunday 2026-06-07: base 0-1, build 2-5, peak 6-7,
// taper 8, race 9 (the race on week 9's Sunday, the plan's end date). A long
// run every Sunday and an easy run every Wednesday. Week 1's long run was the
// last thing done; today is week 4's Tuesday, 22 quiet days later.
const _s = '2026-06-07';
final _today = shiftIsoDate(_s, 30);
const _racePhases = [
  'base', 'base', 'build', 'build', 'build', 'build', 'peak', 'peak', 'taper', 'race'
];
const _walkPhases = [
  'base', 'base', 'build', 'build', 'build', 'build', 'build', 'build', 'build', 'build'
];

RaceDatePlan _plan(
        {String? endDate,
        String status = 'active',
        String? trimmedAt,
        bool isTemplate = false}) =>
    RaceDatePlan(
      startDate: _s,
      endDate: endDate ?? shiftIsoDate(_s, 63),
      trimmedAt: trimmedAt,
      status: status,
      isTemplate: isTemplate,
    );

List<RaceDateWeek> _weeks([List<String> phases = _racePhases]) => [
      for (var i = 0; i < phases.length; i++)
        RaceDateWeek(id: 'w$i', weekIndex: i, phase: phases[i])
    ];

List<RaceDateWorkout> _workouts([List<String> phases = _racePhases]) {
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
        manuallyCompleted: i == 0,
      ));
    }
  }
  return out;
}

RaceDateWorkout _with(RaceDateWorkout w,
        {String? kind, bool? manuallyCompleted, String? completedRunId}) =>
    RaceDateWorkout(
      id: w.id,
      weekId: w.weekId,
      scheduledDate: w.scheduledDate,
      kind: kind ?? w.kind,
      completedRunId: completedRunId ?? w.completedRunId,
      manuallyCompleted: manuallyCompleted ?? w.manuallyCompleted,
    );

PlanBreak? _detect({
  RaceDatePlan? plan,
  List<RaceDateWeek>? weeks,
  List<RaceDateWorkout>? workouts,
  List<String> runDatesIso = const [],
  String? todayIso,
}) =>
    detectPlanBreak(
      plan: plan ?? _plan(),
      weeks: weeks ?? _weeks(),
      workouts: workouts ?? _workouts(),
      runDatesIso: runDatesIso,
      todayIso: todayIso ?? _today,
    );

BreakChange? _change(
  int k, {
  RaceDatePlan? plan,
  List<RaceDateWeek>? weeks,
  List<RaceDateWorkout>? workouts,
}) =>
    planBreakChange(
      plan: plan ?? _plan(),
      weeks: weeks ?? _weeks(),
      workouts: workouts ?? _workouts(),
      runDatesIso: const [],
      todayIso: _today,
      weeksToRepeat: k,
    );

void main() {
  test('22 quiet days in a race plan offer up to three weeks, kept to race day',
      () {
    final r = _detect()!;
    expect(r.fromIso, shiftIsoDate(_s, 8));
    expect(r.days, 22);
    expect(r.raceDateIso, shiftIsoDate(_s, 63));
    expect(r.maxWeeks, 3);
  });

  test('repeating one week runs this week again and drops the latest build week',
      () {
    final c = _change(1)!;
    expect(c.weeks, 1);
    expect(c.repeatWeekIds, ['w4']);
    expect(c.dropWeekIds, ['w5']);
    expect(c.endIso, shiftIsoDate(_s, 63));
  });

  test('once the build runs out the peak goes, latest first, never the taper',
      () {
    expect(_change(2)!.dropWeekIds, ['w5', 'w7']);
    final c = _change(3)!;
    expect(c.weeks, 3);
    expect(c.repeatWeekIds, ['w2', 'w3', 'w4']);
    expect(c.dropWeekIds, ['w5', 'w6', 'w7']);
    expect(c.endIso, shiftIsoDate(_s, 63));
  });

  test('a plan without a race pushes its end back and drops nothing', () {
    final plan = _plan(endDate: shiftIsoDate(_s, 69));
    final weeks = _weeks(_walkPhases);
    final workouts = _workouts(_walkPhases);
    final r = _detect(plan: plan, weeks: weeks, workouts: workouts)!;
    expect(r.raceDateIso, isNull);
    expect(r.maxWeeks, 3);
    final c = _change(2, plan: plan, weeks: weeks, workouts: workouts)!;
    expect(c.weeks, 2);
    expect(c.repeatWeekIds, ['w3', 'w4']);
    expect(c.dropWeekIds, isEmpty);
    expect(c.endIso, shiftIsoDate(_s, 83));
  });

  test('a run before today ends the break; a run today does not', () {
    expect(_detect(runDatesIso: [shiftIsoDate(_s, 25)]), isNull);
    expect(_detect(runDatesIso: [_today, shiftIsoDate(_s, 2)])!.days, 22);
  });

  test('the break needs kBreakMinDays quiet days', () {
    final sixDays = shiftIsoDate(_today, -kBreakMinDays + 1);
    expect(_detect(runDatesIso: [shiftIsoDate(sixDays, -1)]), isNull);
    expect(_detect(runDatesIso: [shiftIsoDate(sixDays, -2)])!.days, 7);
  });

  test('nothing done since the start counts from the start date', () {
    final none =
        _workouts().map((w) => _with(w, manuallyCompleted: false)).toList();
    final r = _detect(workouts: none, todayIso: shiftIsoDate(_s, 10))!;
    expect(r.fromIso, _s);
    expect(r.days, 10);
    expect(r.raceDateIso, shiftIsoDate(_s, 63));
    expect(r.maxWeeks, 1);
  });

  test('only rest days in the quiet stretch is no break', () {
    final rest = _workouts()
        .map((w) => w.scheduledDate.compareTo(shiftIsoDate(_s, 7)) > 0 &&
                w.scheduledDate.compareTo(_today) < 0
            ? _with(w, kind: 'rest')
            : w)
        .toList();
    expect(_detect(workouts: rest), isNull);
  });

  test('a paused, ended-early, template or finished plan offers nothing', () {
    expect(_detect(plan: _plan(status: 'paused')), isNull);
    expect(_detect(plan: _plan(trimmedAt: '2026-06-20T00:00:00Z')), isNull);
    expect(_detect(plan: _plan(isTemplate: true)), isNull);
    expect(_detect(todayIso: shiftIsoDate(_s, 64)), isNull);
  });

  test('before the start or in the last week there is nothing to move', () {
    expect(_detect(todayIso: shiftIsoDate(_s, -1)), isNull);
    expect(_detect(todayIso: shiftIsoDate(_s, 63)), isNull);
  });

  test('a break that reaches the taper offers nothing to run again', () {
    expect(_detect(todayIso: shiftIsoDate(_s, 58)), isNull);
  });

  test('a race or a done workout in a week that would move refuses the change',
      () {
    final plan = _plan(endDate: shiftIsoDate(_s, 69));
    final weeks = _weeks(_walkPhases);
    final bRace = _workouts(_walkPhases)
        .map((w) => w.id == 'long7' ? _with(w, kind: 'race') : w)
        .toList();
    expect(_detect(plan: plan, weeks: weeks, workouts: bRace), isNull);
    final doneAhead = _workouts(_walkPhases)
        .map((w) => w.id == 'easy8' ? _with(w, completedRunId: 'r') : w)
        .toList();
    expect(_detect(plan: plan, weeks: weeks, workouts: doneAhead), isNull);
  });

  test('a B race mid-block is neither dropped nor moved off its day', () {
    final bRace = _workouts()
        .map((w) => w.id == 'long6' ? _with(w, kind: 'race') : w)
        .toList();
    expect(_detect(workouts: bRace)!.maxWeeks, 1);
    expect(_change(1, workouts: bRace)!.dropWeekIds, ['w5']);
    expect(_change(2, workouts: bRace), isNull);
  });

  test('weeks outside 1..maxWeeks are refused', () {
    expect(_change(0), isNull);
    expect(_change(4), isNull);
    expect(_change(-1), isNull);
  });

  test('a dismissal answers only the same plan and the same break', () {
    const pref = {'plan_id': 'p', 'from': '2026-06-15'};
    expect(isBreakDismissed(pref, 'p', '2026-06-15'), isTrue);
    expect(isBreakDismissed(pref, 'p', '2026-07-01'), isFalse);
    expect(isBreakDismissed(pref, 'q', '2026-06-15'), isFalse);
    expect(isBreakDismissed(null, 'p', '2026-06-15'), isFalse);
    expect(isBreakDismissed('p', 'p', '2026-06-15'), isFalse);
    expect(isBreakDismissed([pref], 'p', '2026-06-15'), isFalse);
  });

  test('the offer shows for a break nobody answered, and only then', () {
    final found = _detect();
    expect(breakOfferShowing(found, null, 'p'), isTrue);
    expect(
        breakOfferShowing(
            found, {'plan_id': 'p', 'from': shiftIsoDate(_s, 8)}, 'p'),
        isFalse);
    expect(
        breakOfferShowing(
            found, {'plan_id': 'q', 'from': shiftIsoDate(_s, 8)}, 'p'),
        isTrue);
    expect(breakOfferShowing(null, null, 'p'), isFalse);
  });

  test('the break window is the break on now, else the last one answered in this plan',
      () {
    final found = _detect();
    const answered = {'plan_id': 'p', 'from': '2026-05-01', 'until': '2026-05-20'};
    expect(breakWindow(found, answered, 'p', _today),
        (fromIso: shiftIsoDate(_s, 8), untilIso: _today));
    expect(breakWindow(null, answered, 'p', _today),
        (fromIso: '2026-05-01', untilIso: '2026-05-20'));
    expect(breakWindow(null, answered, 'q', _today), isNull);
    expect(breakWindow(null, {'plan_id': 'p', 'from': '2026-05-01'}, 'p', _today),
        isNull);
    expect(breakWindow(null, null, 'p', _today), isNull);
  });
}
