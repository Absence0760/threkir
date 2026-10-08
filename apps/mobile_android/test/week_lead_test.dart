import 'package:core_models/core_models.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/current_week.dart';
import '../lib/goals.dart';
import '../lib/week_lead.dart';

// Dart twin of apps/web/src/lib/training/week_lead.test.ts — one case per
// web case, same inputs, same expectations.

// 2026-06-10 is a Wednesday; the Monday-start week runs 06-08..06-14.
final _wed = DateTime(2026, 6, 10, 12);
final _mon = DateTime(2026, 6, 8);

String _at(int y, int mo, int d, [int h = 9]) =>
    DateTime(y, mo, d, h).toUtc().toIso8601String();

LeadActivity _act(String startedAt, double distanceM) =>
    LeadActivity(startedAt: startedAt, distanceM: distanceM);

LeadPlanWorkout _wo(
  String date, {
  String kind = 'easy',
  double? targetDistanceM = 5000,
  bool manuallyCompleted = false,
  String? completedRunId,
  String? skippedAt,
}) =>
    LeadPlanWorkout(
      scheduledDate: date,
      kind: kind,
      targetDistanceM: targetDistanceM,
      manuallyCompleted: manuallyCompleted,
      completedRunId: completedRunId,
      skippedAt: skippedAt,
    );

void main() {
  test('weekLead: sums only this calendar week and counts every activity in it',
      () {
    final lead = weekLead(
      activities: [
        _act(_at(2026, 6, 7), 9000),
        _act(_at(2026, 6, 8), 5000),
        _act(_at(2026, 6, 10), 3000),
      ],
      planWorkouts: null,
      weekStart: WeekStart.monday,
      now: _wed,
    );
    expect(lead.distanceM, 8000);
    expect(lead.count, 2);
  });

  test(
      'weekLead: a sunday-start week takes in the sunday a monday-start week leaves out',
      () {
    final lead = weekLead(
      activities: [_act(_at(2026, 6, 7), 9000)],
      planWorkouts: null,
      weekStart: WeekStart.sunday,
      now: _wed,
    );
    expect(lead.distanceM, 9000);
  });

  test(
      'weekLead: a workout marked done without a run counts toward the week, a linked one does not',
      () {
    final lead = weekLead(
      activities: [_act(_at(2026, 6, 9), 4000)],
      planWorkouts: [
        _wo('2026-06-08', manuallyCompleted: true, targetDistanceM: 6000),
        _wo('2026-06-09', manuallyCompleted: true, completedRunId: 'r1'),
        _wo('2026-06-12', manuallyCompleted: true),
      ],
      weekStart: WeekStart.monday,
      now: _wed,
    );
    expect(lead.distanceM, 10000);
    expect(lead.count, 2);
  });

  test(
      'weekLead: compares against the plan when the plan puts distance in this week',
      () {
    final lead = weekLead(
      activities: [_act(_at(2026, 5, 20), 20000)],
      planWorkouts: [
        _wo('2026-06-09'),
        _wo('2026-06-11', targetDistanceM: 8000),
        _wo('2026-06-16'),
      ],
      weekStart: WeekStart.monday,
      now: _wed,
    );
    expect(lead.comparison, const WeekComparison.plan(13000));
  });

  test(
      'weekLead: falls back to the recent average when the plan has nothing this week',
      () {
    final lead = weekLead(
      activities: [
        _act(_at(2026, 5, 12), 8000),
        _act(_at(2026, 6, 2), 12000),
      ],
      planWorkouts: [_wo('2026-06-20')],
      weekStart: WeekStart.monday,
      now: _wed,
    );
    expect(lead.comparison, const WeekComparison.average(5000, 4));
  });

  test(
      'weekLead: a weekly distance goal is the yardstick when the plan puts no distance in this week',
      () {
    final history = [_act(_at(2026, 6, 2), 12000)];
    const goal = WeeklyGoalTarget(distanceM: 30000, runCount: 4);
    expect(
      weekLead(
        activities: history,
        planWorkouts: null,
        weeklyGoal: goal,
        weekStart: WeekStart.monday,
        now: _wed,
      ).comparison,
      const WeekComparison.goal(30000),
    );
    expect(
      weekLead(
        activities: history,
        planWorkouts: [_wo('2026-06-20')],
        weeklyGoal: goal,
        weekStart: WeekStart.monday,
        now: _wed,
      ).comparison,
      const WeekComparison.goal(30000),
    );
  });

  test(
      'weekLead: the plan outranks a weekly goal, since it is written for this particular week',
      () {
    final lead = weekLead(
      activities: const [],
      planWorkouts: [_wo('2026-06-11', targetDistanceM: 8000)],
      weeklyGoal: const WeeklyGoalTarget(distanceM: 40000),
      weekStart: WeekStart.monday,
      now: _wed,
    );
    expect(lead.comparison, const WeekComparison.plan(8000));
  });

  test(
      'weekLead: a run-count goal is the yardstick when there is no distance goal',
      () {
    final lead = weekLead(
      activities: [_act(_at(2026, 6, 2), 12000)],
      planWorkouts: null,
      weeklyGoal: const WeeklyGoalTarget(runCount: 3),
      weekStart: WeekStart.monday,
      now: _wed,
    );
    expect(lead.comparison, const WeekComparison.goalRuns(3));
  });

  test(
      'weekLead: a run-count goal reads the same count as its Goals ring in a '
      'plan week with no planned distance', () {
    const goal = RunGoal(id: 'g', period: GoalPeriod.week, runCount: 3);
    final runs = [
      Run(
        id: 'r',
        startedAt: DateTime(2026, 6, 9, 9),
        duration: const Duration(minutes: 30),
        distanceMetres: 5000,
        track: const [],
        source: RunSource.app,
      ),
    ];
    final planWorkouts = [
      _wo('2026-06-08', targetDistanceM: null, manuallyCompleted: true),
      _wo('2026-06-12', targetDistanceM: null),
    ];
    final lead = weekLead(
      activities: [
        for (final r in runs)
          _act(r.startedAt.toUtc().toIso8601String(), r.distanceMetres),
      ],
      planWorkouts: planWorkouts,
      weeklyGoal: weeklyGoalTarget([goal]),
      weekStart: WeekStart.monday,
      now: _wed,
    );
    final ring = evaluateGoal(goal, runs, _wed, planWorkouts: planWorkouts);
    expect(lead.comparison, const WeekComparison.goalRuns(3));
    expect(lead.count, 2);
    expect(ring.runCount, lead.count);
    expect(ring.targets.single.current, lead.count);
  });

  test(
      'weeklyGoalTarget: takes the first week-period distance and run-count targets, ignoring other periods',
      () {
    expect(weeklyGoalTarget(const []), isNull);
    expect(
      weeklyGoalTarget(const [
        RunGoal(id: 'm', period: GoalPeriod.month, distanceMetres: 100000),
      ]),
      isNull,
    );
    expect(
      weeklyGoalTarget(const [
        RunGoal(
            id: 'w', period: GoalPeriod.week, distanceMetres: 0, runCount: 0),
      ]),
      isNull,
    );
    expect(
      weeklyGoalTarget(const [
        RunGoal(
            id: 'm',
            period: GoalPeriod.month,
            distanceMetres: 100000,
            runCount: 12),
        RunGoal(id: 'a', period: GoalPeriod.week, runCount: 4),
        RunGoal(
            id: 'b',
            period: GoalPeriod.week,
            distanceMetres: 25000,
            runCount: 6),
        RunGoal(id: 'c', period: GoalPeriod.week, distanceMetres: 50000),
      ]),
      const WeeklyGoalTarget(distanceM: 25000, runCount: 4),
    );
  });

  test(
      'weekLead: no yardstick when there is no plan distance and no recent activity',
      () {
    final lead = weekLead(
      activities: [_act(_at(2025, 1, 5), 5000)],
      planWorkouts: null,
      weekStart: WeekStart.monday,
      now: _wed,
    );
    expect(lead.comparison, isNull);
    expect(lead.next, isNull);
    expect(lead.nextInDays, isNull);
  });

  test(
      'recentWeeklyAverage: a history shorter than the window averages over the weeks it has',
      () {
    final avg = recentWeeklyAverage([_act(_at(2026, 6, 2), 6000)], _mon);
    expect(avg, (averageM: 6000.0, weeks: 1));
    final two = recentWeeklyAverage(
      [
        _act(_at(2026, 5, 26), 4000),
        _act(_at(2026, 6, 3), 6000),
      ],
      _mon,
    );
    expect(two, (averageM: 5000.0, weeks: 2));
  });

  test(
      'recentWeeklyAverage: activity only in the current week is no history yet',
      () {
    expect(recentWeeklyAverage([_act(_at(2026, 6, 9), 5000)], _mon), isNull);
    expect(recentWeeklyAverage(const [], _mon), isNull);
  });

  test(
      'plannedDistanceForWeek: ignores rest days and workouts outside the calendar week',
      () {
    final total = plannedDistanceForWeek(
      [
        _wo('2026-06-07'),
        _wo('2026-06-08', targetDistanceM: 3000),
        _wo('2026-06-10', kind: 'rest', targetDistanceM: 9000),
        _wo('2026-06-14', targetDistanceM: null),
        _wo('2026-06-14', targetDistanceM: 12000),
        _wo('2026-06-15'),
      ],
      _mon,
    );
    expect(total, 15000);
  });

  test('nextPlanSession: the earliest open, non-rest session from today on', () {
    final next = nextPlanSession(
      [
        _wo('2026-06-14', kind: 'long'),
        _wo('2026-06-09'),
        _wo('2026-06-10', manuallyCompleted: true),
        _wo('2026-06-11', kind: 'rest'),
        _wo('2026-06-12', skippedAt: '2026-06-09T10:00:00Z'),
        _wo('2026-06-13', kind: 'tempo'),
      ],
      '2026-06-10',
    );
    expect(next?.scheduledDate, '2026-06-13');
    expect(next?.kind, 'tempo');
  });

  test('nextPlanSession: today counts while it is still open', () {
    expect(
      nextPlanSession([_wo('2026-06-12'), _wo('2026-06-10')], '2026-06-10')
          ?.scheduledDate,
      '2026-06-10',
    );
    expect(nextPlanSession([_wo('2026-06-01')], '2026-06-10'), isNull);
  });

  test('weekLead: nextInDays counts calendar days to the next session', () {
    final lead = weekLead(
      activities: const [],
      planWorkouts: [_wo('2026-06-11')],
      weekStart: WeekStart.monday,
      now: _wed,
    );
    expect(lead.next?.scheduledDate, '2026-06-11');
    expect(lead.nextInDays, 1);
  });
}
