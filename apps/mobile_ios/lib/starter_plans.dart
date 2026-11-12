/// Built-in starter training plans (Training Phase-3). A starter is just a
/// preset set of [generatePlan] inputs — instantiating one produces a
/// [GeneratedPlan] that flows through the same createPlan path the wizard uses
/// (no RPC, no schema, no DB template row). Distinct from club templates, which
/// are DB-owned rows cloned via clone_plan_template.
///
/// Dart twin of `apps/web/src/lib/training/starter_plans.ts` — keep in lockstep
/// (equal test counts).
library;

import 'training.dart';

class StarterPlan {
  /// Stable id; also the ARB key suffix (plansNewStarter<Id>Name / ...Hint).
  final String id;
  final GoalEvent goalEvent;
  final int weeks;
  final int daysPerWeek;

  /// C25K-style walk-run beginner plan.
  final bool beginnerWalkRun;

  const StarterPlan({
    required this.id,
    required this.goalEvent,
    required this.weeks,
    required this.daysPerWeek,
    this.beginnerWalkRun = false,
  });
}

/// The catalogue. Order is the display order on the picker. Not `const` because
/// C25K's week count comes from the runtime [walkRunDefaultWeeks].
final List<StarterPlan> starterPlans = [
  // C25K: weeks MUST be walkRunDefaultWeeks() or the graduation week truncates.
  StarterPlan(
    id: 'c25k',
    goalEvent: GoalEvent.distance5k,
    weeks: walkRunDefaultWeeks(),
    daysPerWeek: 3,
    beginnerWalkRun: true,
  ),
  const StarterPlan(id: 'half_12wk', goalEvent: GoalEvent.distanceHalf, weeks: 12, daysPerWeek: 4),
  const StarterPlan(id: 'marathon_16wk', goalEvent: GoalEvent.distanceFull, weeks: 16, daysPerWeek: 5),
];

StarterPlan? starterById(String id) {
  for (final s in starterPlans) {
    if (s.id == id) return s;
  }
  return null;
}

/// Instantiate a starter into a [GeneratedPlan] anchored at [startDate],
/// delegating to [generatePlan]. Returns null for an unknown id. No goal time /
/// recent-5k is supplied, so paces come back as the conservative fallback —
/// the caller discloses that, same as the wizard.
GeneratedPlan? instantiateStarter(String id, DateTime startDate,
    {int? age, bool extraRecovery = false}) {
  final starter = starterById(id);
  if (starter == null) return null;
  return generatePlan(GeneratePlanInput(
    goalEvent: starter.goalEvent,
    startDate: startDate,
    daysPerWeek: starter.daysPerWeek,
    weeks: starter.weeks,
    beginnerWalkRun: starter.beginnerWalkRun,
    age: age,
    extraRecovery: extraRecovery,
  ));
}

/// What a starter asks of the runner, for the line under its name.
class StarterSummary {
  final int weeks;
  final int daysPerWeek;

  /// The shortest and longest session, in whole minutes rounded to the nearest
  /// 5, for a starter whose sessions are timed (walk-run). Null for a
  /// distance-based starter, whose session length depends on the runner's
  /// pace; for the same reason the walk-run graduation 5K is left out.
  final ({int min, int max})? sessionMinutes;

  const StarterSummary({
    required this.weeks,
    required this.daysPerWeek,
    required this.sessionMinutes,
  });
}

/// Read off the plan [instantiateStarter] actually builds, so the line cannot
/// drift from the schedule. Session lengths do not depend on the start date;
/// the fixed Sunday below only gives the generator a valid day 0. Mirrors
/// `starterSummary` in starter_plans.ts.
StarterSummary? starterSummary(String id) {
  final starter = starterById(id);
  final plan = instantiateStarter(id, DateTime(2026, 1, 4));
  if (starter == null || plan == null) return null;
  ({int min, int max})? sessionMinutes;
  if (starter.beginnerWalkRun) {
    final seconds = [
      for (final w in plan.weeks)
        for (final wo in w.workouts)
          if (wo.kind == WorkoutKind.walkRun &&
              wo.targetDurationSeconds != null &&
              wo.structure?.repeats?['distance_m'] == null)
            wo.targetDurationSeconds!,
    ];
    if (seconds.isNotEmpty) {
      int toFive(int s) => (s / 300).round() * 5;
      sessionMinutes = (
        min: toFive(seconds.reduce((a, b) => a < b ? a : b)),
        max: toFive(seconds.reduce((a, b) => a > b ? a : b)),
      );
    }
  }
  return StarterSummary(
    weeks: plan.weeks.length,
    daysPerWeek: starter.daysPerWeek,
    sessionMinutes: sessionMinutes,
  );
}
