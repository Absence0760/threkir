import 'package:flutter_test/flutter_test.dart';
import '../lib/starter_plans.dart';
import '../lib/training.dart';

void main() {
  test('starterPlans catalogue has the expected presets', () {
    expect(starterPlans.map((s) => s.id).toList(),
        ['c25k', 'half_12wk', 'marathon_16wk']);
  });

  test('starterById finds a preset and returns null for an unknown id', () {
    expect(starterById('marathon_16wk')?.goalEvent, GoalEvent.distanceFull);
    expect(starterById('nope'), isNull);
  });

  test('instantiateStarter returns null for an unknown id', () {
    expect(instantiateStarter('nope', DateTime(2026, 7, 1)), isNull);
  });

  test('C25K starter is a walk-run plan over the full progression', () {
    final plan = instantiateStarter('c25k', DateTime(2026, 7, 1));
    expect(plan, isNotNull);
    expect(plan!.weeks.length, walkRunDefaultWeeks());
    expect(plan.goalDistanceM, kGoalDistancesM[GoalEvent.distance5k]);
    final kinds =
        plan.weeks.expand((w) => w.workouts.map((x) => x.kind)).toList();
    expect(kinds.contains(WorkoutKind.walkRun), isTrue,
        reason: 'C25K should produce walk_run workouts');
  });

  test('half-marathon starter is 12 weeks at the half distance', () {
    final plan = instantiateStarter('half_12wk', DateTime(2026, 7, 1));
    expect(plan, isNotNull);
    expect(plan!.weeks.length, 12);
    expect(plan.goalDistanceM, kGoalDistancesM[GoalEvent.distanceHalf]);
  });

  test('marathon starter is 16 weeks at the full distance', () {
    final plan = instantiateStarter('marathon_16wk', DateTime(2026, 7, 1));
    expect(plan, isNotNull);
    expect(plan!.weeks.length, 16);
    expect(plan.goalDistanceM, kGoalDistancesM[GoalEvent.distanceFull]);
  });

  test('an instantiated starter anchors at the given start date', () {
    final plan = instantiateStarter('half_12wk', DateTime(2026, 7, 1));
    expect(plan, isNotNull);
    expect(plan!.endDate.isAfter(DateTime(2026, 7, 1)), isTrue);
  });

  test(
      'an instantiated starter takes the masters schedule from extra recovery as it does from age',
      () {
    List<Object?> volumes(GeneratedPlan? p) =>
        [for (final w in p!.weeks) (w.targetVolumeM, w.notes)];
    final start = DateTime(2026, 7, 5);
    final masters = volumes(instantiateStarter('half_12wk', start, age: 60));
    expect(
        volumes(instantiateStarter('half_12wk', start, extraRecovery: true)),
        masters);
    expect(volumes(instantiateStarter('half_12wk', start)), isNot(masters));
  });

  test('starterSummary describes C25K as 9 weeks, 3 days a week, 30-45 minute sessions',
      () {
    // The shortest session is week 1 (28.5 min) and the longest week 7
    // (44 min), each rounded to the nearest 5. The graduation 5K lasts as
    // long as the runner takes, so it does not stretch the range.
    final s = starterSummary('c25k')!;
    expect(s.weeks, 9);
    expect(s.daysPerWeek, 3);
    expect(s.sessionMinutes, (min: 30, max: 45));
  });

  test('starterSummary gives a distance-based starter no session length', () {
    final s = starterSummary('half_12wk')!;
    expect(s.weeks, 12);
    expect(s.daysPerWeek, 4);
    expect(s.sessionMinutes, isNull);
    expect(starterSummary('nope'), isNull);
  });
}
