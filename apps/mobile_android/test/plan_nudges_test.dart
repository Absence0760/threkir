import 'package:flutter_test/flutter_test.dart';
import '../lib/plan_nudges.dart';

NudgeInputWorkout _wo(
  String id,
  String scheduledDate,
  String kind,
  double? targetDistanceM, {
  bool completed = false,
  bool skipped = false,
}) =>
    NudgeInputWorkout(
      id: id,
      scheduledDate: scheduledDate,
      kind: kind,
      targetDistanceM: targetDistanceM,
      completed: completed,
      skipped: skipped,
    );

NudgeInputRun _run(String date, double distanceM) =>
    NudgeInputRun(date: date, distanceM: distanceM);

/// Plan starting Monday 2026-06-01: weeks 0-2 complete on 2026-06-24, week 3
/// current (06-22..06-28), week 4 ahead with a long run.
const _start = '2026-06-01';
const _today = '2026-06-24';

List<NudgeInputWeek> _plan(
  List<double> volumes, {
  List<NudgeInputWorkout>? week0Workouts,
}) =>
    [
      NudgeInputWeek(
        weekIndex: 0,
        phase: 'build',
        targetVolumeM: volumes[0],
        workouts: week0Workouts ??
            [
              _wo('l0', '2026-06-07', 'long', 26000),
              _wo('e0', '2026-06-02', 'easy', 8000),
            ],
      ),
      NudgeInputWeek(
        weekIndex: 1,
        phase: 'build',
        targetVolumeM: volumes[1],
        workouts: [
          _wo('l1', '2026-06-14', 'long', 20000, completed: true),
          _wo('e1', '2026-06-09', 'easy', 8000),
        ],
      ),
      NudgeInputWeek(
        weekIndex: 2,
        phase: 'build',
        targetVolumeM: volumes[2],
        workouts: [
          _wo('l2', '2026-06-21', 'long', 20000, completed: true),
          _wo('e2', '2026-06-16', 'easy', 8000),
        ],
      ),
      NudgeInputWeek(
        weekIndex: 3,
        phase: 'build',
        targetVolumeM: 40000,
        workouts: [
          _wo('e3', '2026-06-25', 'easy', 8000),
          _wo('l3', '2026-06-28', 'long', 22000),
        ],
      ),
      NudgeInputWeek(
        weekIndex: 4,
        phase: 'build',
        targetVolumeM: 40000,
        workouts: [
          _wo('e4', '2026-06-30', 'easy', 10000),
          _wo('l4', '2026-07-05', 'long', 22000),
        ],
      ),
    ];

PlanNudge? _nudge(
  List<NudgeInputWeek> weeks,
  List<NudgeInputRun> runs, {
  String status = 'active',
  bool isTemplate = false,
  String startDate = _start,
  String endDate = '2026-08-30',
  String today = _today,
  List<String> dismissed = const [],
  String? breakFromIso,
  String? breakUntilIso,
}) =>
    planNudge(
      planId: 'p',
      status: status,
      isTemplate: isTemplate,
      startDate: startDate,
      endDate: endDate,
      today: today,
      weeks: buildReplanWeeks(
          startDate: _start, today: today, weeks: weeks, runs: runs),
      runDates: runs.map((r) => r.date).toList(),
      dismissed: dismissed,
      breakFromIso: breakFromIso,
      breakUntilIso: breakUntilIso,
    );

void main() {
  test('workoutOverrunMetres: 3 km over a 10 km target is reported', () {
    expect(workoutOverrunMetres(10000, 13000), 3000);
  });

  test('workoutOverrunMetres: less than 1 km over is noise', () {
    expect(workoutOverrunMetres(5000, 5900), isNull);
  });

  test('workoutOverrunMetres: less than 10% over a long target is noise', () {
    expect(workoutOverrunMetres(30000, 32500), isNull);
    expect(workoutOverrunMetres(30000, 33000), 3000);
  });

  test('workoutOverrunMetres: a short run, or no target, is never an over-run',
      () {
    expect(workoutOverrunMetres(10000, 8000), isNull);
    expect(workoutOverrunMetres(null, 8000), isNull);
    expect(workoutOverrunMetres(0, 8000), isNull);
    expect(workoutOverrunMetres(10000, null), isNull);
  });

  test(
      'overrunDigits: whole units at ten or more, or when a decimal would read .0',
      () {
    expect(overrunDigits(3), 0);
    expect(overrunDigits(2.98), 0);
    expect(overrunDigits(1.9), 1);
    expect(overrunDigits(12.4), 0);
  });

  test(
      'parseDismissedNudges: keeps strings, reads anything else as nothing dismissed',
      () {
    expect(parseDismissedNudges(['a', 3, 'b']), ['a', 'b']);
    expect(parseDismissedNudges('a'), isEmpty);
    expect(parseDismissedNudges(null), isEmpty);
  });

  test('withDismissedNudge: appends once and keeps only the newest entries',
      () {
    expect(withDismissedNudge(['a', 'b'], 'a'), ['b', 'a']);
    final full = List.generate(dismissedNudgesCap, (i) => 'k$i');
    final next = withDismissedNudge(full, 'new');
    expect(next.length, dismissedNudgesCap);
    expect(next.first, 'k1');
    expect(next.last, 'new');
  });

  test(
      'buildReplanWeeks: falls back to the non-rest distances, sums runs by local day, closes weeks at their end',
      () {
    final weeks = buildReplanWeeks(
      startDate: _start,
      today: '2026-06-08',
      weeks: [
        NudgeInputWeek(weekIndex: 0, phase: 'build', targetVolumeM: null, workouts: [
          _wo('a', '2026-06-02', 'easy', 8000),
          _wo('r', '2026-06-03', 'rest', 5000),
        ]),
        NudgeInputWeek(
            weekIndex: 1,
            phase: 'build',
            targetVolumeM: 30000,
            workouts: [_wo('b', '2026-06-09', 'easy', 8000)]),
      ],
      runs: [
        _run('2026-06-01', 5000),
        _run('2026-06-07', 4000),
        _run('2026-06-08', 6000),
      ],
    );
    expect(weeks[0].plannedMetres, 8000);
    expect(weeks[0].actualMetres, 9000);
    expect(weeks[0].isComplete, isTrue);
    expect(weeks[0].workouts[0].isPast, isTrue);
    expect(weeks[1].actualMetres, 6000);
    expect(weeks[1].isComplete, isFalse);
    expect(weeks[1].workouts[0].isPast, isFalse);
  });

  test(
      'planNudge: under plan in 2 of the last 3 weeks with a missed long run proposes the adaptive review',
      () {
    final runs = [
      _run('2026-06-02', 8000),
      _run('2026-06-14', 20000),
      _run('2026-06-09', 8000),
      _run('2026-06-21', 20000),
      _run('2026-06-16', 8000),
    ];
    final n = _nudge(_plan([40000, 40000, 28000]), runs)!;
    expect(n.kind, PlanNudgeKind.adaptiveUnder);
    expect(n.weekIndex, 2);
    expect(n.key, 'p:adaptive_under:2');
    expect(n.weeks, 2);
    expect(n.ofWeeks, 3);
  });

  test('planNudge: an under-run trend with nothing safe to change says nothing',
      () {
    final weeks = _plan([40000, 40000, 28000],
        week0Workouts: [_wo('e0', '2026-06-02', 'easy', 8000)]);
    final runs = [_run('2026-06-14', 20000), _run('2026-06-21', 28000)];
    expect(_nudge(weeks, runs), isNull);
  });

  test('planNudge: one week more than 20% over plan proposes the ease-off', () {
    final runs = [
      _run('2026-06-07', 28000),
      _run('2026-06-14', 28000),
      _run('2026-06-21', 36000),
    ];
    final n = _nudge(_plan([28000, 28000, 28000]), runs);
    expect(n?.kind, PlanNudgeKind.easeOver);
    expect(n?.key, planNudgeKey('p', PlanNudgeKind.easeOver, 2));
    expect(n?.weeks, 1);
    expect(n?.ofWeeks, 1);
  });

  test(
      'planNudge: runs on rest days in 2 of the last 3 weeks get the rest-day note',
      () {
    final runs = [
      _run('2026-06-07', 20000),
      _run('2026-06-02', 8000),
      _run('2026-06-03', 4000),
      _run('2026-06-14', 20000),
      _run('2026-06-09', 4000),
      _run('2026-06-20', 4000),
      _run('2026-06-21', 20000),
      _run('2026-06-16', 12000),
    ];
    final n = _nudge(_plan([36000, 32000, 32000]), runs);
    expect(n?.kind, PlanNudgeKind.restDayRuns);
    expect(n?.weeks, 2);
    expect(n?.ofWeeks, 3);
  });

  test('planNudge: a rest-day run in only one week is not a habit', () {
    final runs = [
      _run('2026-06-07', 20000),
      _run('2026-06-02', 8000),
      _run('2026-06-03', 4000),
      _run('2026-06-14', 20000),
      _run('2026-06-09', 8000),
      _run('2026-06-21', 20000),
      _run('2026-06-16', 8000),
    ];
    expect(_nudge(_plan([32000, 28000, 28000]), runs), isNull);
  });

  test(
      'planNudge: a dismissed occurrence gives way to the next one, and a new week brings it back',
      () {
    final runs = [
      _run('2026-06-07', 28000),
      _run('2026-06-14', 28000),
      _run('2026-06-20', 8000),
      _run('2026-06-21', 28000),
      _run('2026-06-13', 8000),
    ];
    final weeks = _plan([28000, 28000, 28000]);
    expect(_nudge(weeks, runs)?.kind, PlanNudgeKind.easeOver);
    expect(_nudge(weeks, runs, dismissed: ['p:ease_over:2'])?.kind,
        PlanNudgeKind.restDayRuns);
    expect(
        _nudge(weeks, runs,
            dismissed: ['p:ease_over:2', 'p:rest_day_runs:2']),
        isNull);
    expect(_nudge(weeks, runs, dismissed: ['p:ease_over:1'])?.kind,
        PlanNudgeKind.easeOver);
  });

  test(
      'planNudge: nothing for a paused, finished, template or not-yet-started plan',
      () {
    final runs = [
      _run('2026-06-07', 28000),
      _run('2026-06-14', 28000),
      _run('2026-06-21', 36000),
    ];
    final weeks = _plan([28000, 28000, 28000]);
    expect(_nudge(weeks, runs, status: 'paused'), isNull);
    expect(_nudge(weeks, runs, status: 'completed'), isNull);
    expect(_nudge(weeks, runs, isTemplate: true), isNull);
    expect(_nudge(weeks, runs, endDate: '2026-06-23'), isNull);
    expect(_nudge(weeks, runs, startDate: '2026-06-25'), isNull);
  });

  test('planNudge: nothing before the first week has ended', () {
    final runs = [_run('2026-06-02', 30000)];
    expect(
        _nudge(_plan([28000, 28000, 28000]), runs, today: '2026-06-05'),
        isNull);
  });

  test(
      'planNudge: a judged week that overlaps a break says nothing, and a later one is judged again',
      () {
    final runs = [
      _run('2026-06-07', 28000),
      _run('2026-06-14', 28000),
      _run('2026-06-21', 36000),
    ];
    final weeks = _plan([28000, 28000, 28000]);
    expect(
        _nudge(weeks, runs,
            breakFromIso: '2026-06-21', breakUntilIso: '2026-06-24'),
        isNull);
    expect(
        _nudge(weeks, runs,
                breakFromIso: '2026-06-01', breakUntilIso: '2026-06-14')
            ?.kind,
        PlanNudgeKind.easeOver);
    expect(
        _nudge(weeks, runs,
                breakFromIso: '2026-06-22', breakUntilIso: '2026-06-24')
            ?.kind,
        PlanNudgeKind.easeOver);
  });
}
