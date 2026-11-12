// Mirrors apps/web/src/lib/training/plan_advice.test.ts — keep in lockstep.
import 'package:flutter_test/flutter_test.dart';

import '../lib/plan_advice.dart';
import '../lib/training.dart';

void main() {
  test('weekAdviceKind: race, taper and graduation weeks read their phase', () {
    expect(weekAdviceKind('race', ['race']), WeekAdviceKind.race);
    expect(weekAdviceKind('taper', ['long']), WeekAdviceKind.taper);
    expect(weekAdviceKind('graduation', ['walk_run']), WeekAdviceKind.graduation);
  });

  test('weekAdviceKind: a walk-run week asks the runner to take the walk breaks',
      () {
    expect(weekAdviceKind('build', ['walk_run', 'rest']),
        WeekAdviceKind.walkBreaks);
  });

  test('weekAdviceKind: a week holding two long runs is a back-to-back weekend',
      () {
    expect(weekAdviceKind('build', ['long', 'easy', 'long']),
        WeekAdviceKind.backToBack);
    expect(weekAdviceKind('peak', ['long', 'long']), WeekAdviceKind.backToBack);
  });

  test('weekAdviceKind: an ordinary build week has no advice', () {
    expect(weekAdviceKind('build', ['long', 'easy']), isNull);
    expect(weekAdviceKind('base', ['easy']), isNull);
    expect(weekAdviceKind('peak', const <String>[]), isNull);
  });

  test('workoutAdviceKind: a long run set by time with no pace is time on feet',
      () {
    expect(
        workoutAdviceKind(
            kind: 'long', targetDistanceM: 20000, targetDurationSeconds: 10800),
        WorkoutAdviceKind.timeOnFeet);
    expect(
        workoutAdviceKind(
            kind: 'long',
            targetDistanceM: 20000,
            targetDurationSeconds: 10800,
            targetPaceSecPerKm: 360),
        WorkoutAdviceKind.long);
    expect(workoutAdviceKind(kind: 'long', targetDistanceM: 20000),
        WorkoutAdviceKind.long);
  });

  test('workoutAdviceKind: a race past the marathon is an ultra race', () {
    expect(workoutAdviceKind(kind: 'race', targetDistanceM: 50000),
        WorkoutAdviceKind.ultraRace);
    expect(workoutAdviceKind(kind: 'race', targetDistanceM: 42195),
        WorkoutAdviceKind.race);
    expect(workoutAdviceKind(kind: 'race'), WorkoutAdviceKind.race);
  });

  test(
      'workoutAdviceKind: the other kinds keep their own advice, recovery reads as easy',
      () {
    expect(workoutAdviceKind(kind: 'recovery'), WorkoutAdviceKind.easy);
    expect(workoutAdviceKind(kind: 'easy'), WorkoutAdviceKind.easy);
    expect(workoutAdviceKind(kind: 'tempo'), WorkoutAdviceKind.tempo);
    expect(workoutAdviceKind(kind: 'interval'), WorkoutAdviceKind.interval);
    expect(workoutAdviceKind(kind: 'marathon_pace'),
        WorkoutAdviceKind.marathonPace);
    expect(workoutAdviceKind(kind: 'walk_run'), WorkoutAdviceKind.walkRun);
    expect(workoutAdviceKind(kind: 'rest'), WorkoutAdviceKind.rest);
  });

  test(
      'generatePlan: an ultra plan reads back-to-back weekends and time-on-feet long runs from its rows',
      () {
    final plan = generatePlan(GeneratePlanInput(
      goalEvent: GoalEvent.custom,
      goalDistanceM: 100000,
      startDate: DateTime(2026, 11, 1),
      daysPerWeek: 5,
      recent5kSec: 1500,
    ));
    final kinds = [
      for (final w in plan.weeks)
        weekAdviceKind(planPhaseDbValue(w.phase),
            [for (final x in w.workouts) workoutKindDbValue(x.kind)]),
    ];
    expect(kinds, contains(WeekAdviceKind.backToBack));
    expect(kinds.last, WeekAdviceKind.race);
    WorkoutAdviceKind adviceOf(GeneratedWorkout x) => workoutAdviceKind(
          kind: workoutKindDbValue(x.kind),
          targetDistanceM: x.targetDistanceM,
          targetDurationSeconds: x.targetDurationSeconds,
          targetPaceSecPerKm: x.targetPaceSecPerKm,
        );
    final all = plan.weeks.expand((w) => w.workouts);
    expect(adviceOf(all.firstWhere((x) => x.kind == WorkoutKind.long)),
        WorkoutAdviceKind.timeOnFeet);
    expect(adviceOf(all.firstWhere((x) => x.kind == WorkoutKind.race)),
        WorkoutAdviceKind.ultraRace);
  });
}
