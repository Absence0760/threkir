/// Meal plan — which plan governs a diary day, and the targets it prescribes
/// there (docs/features/nutrition_programming.md, P1).
///
/// Dart twin of `apps/web/src/lib/nutrition/meal_plan.ts` — keep the
/// algorithm, constants, edge cases, and test counts in lockstep. Read the
/// web module's header for the rules; the two halves state them once there.
///
/// Dates are `YYYY-MM-DD` calendar strings; "today" is always passed in.
library;

import 'nutrition_targets.dart';

/// Display order for the editor's phase picker.
const List<String> goalPhases = ['cut', 'maintain', 'build', 'recomp'];

/// The prescription columns of a `nutrition_plans` row.
class PlanTargets {
  const PlanTargets({
    required this.targetCalories,
    this.targetProteinG,
    this.targetCarbsG,
    this.targetFatG,
    this.trainingCalories,
    this.trainingCarbsG,
  });
  final double targetCalories;
  final double? targetProteinG;
  final double? targetCarbsG;
  final double? targetFatG;
  final double? trainingCalories;
  final double? trainingCarbsG;
}

/// What a governed day is measured against. A null macro is unprescribed.
class PrescribedDay {
  const PrescribedDay({
    required this.calories,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
    required this.isTrainingDay,
  });
  final int calories;
  final int? proteinG;
  final int? carbsG;
  final int? fatG;
  final bool isTrainingDay;
}

class PlanAssignment {
  const PlanAssignment({
    required this.id,
    required this.planId,
    required this.startDate,
    required this.endDate,
    required this.status,
    required this.createdAt,
  });
  final String id;
  final String planId;
  final String startDate;
  final String? endDate;
  final String status;
  final String createdAt;
}

/// `kind` is `'end'` (with [endDate]) or `'delete'`.
class StopFollowingAction {
  const StopFollowingAction.end(String this.endDate) : kind = 'end';
  const StopFollowingAction.delete()
      : kind = 'delete',
        endDate = null;
  final String kind;
  final String? endDate;
}

/// A plan draft seeded from the computed rest-day target ("Save as plan").
class PlanDraft {
  const PlanDraft({
    required this.goalPhase,
    required this.targetCalories,
    required this.targetProteinG,
    required this.targetCarbsG,
    required this.targetFatG,
  });
  final String goalPhase;
  final int targetCalories;
  final int targetProteinG;
  final int targetCarbsG;
  final int targetFatG;
}

double? _finiteOrNull(double? v) =>
    v != null && v.isFinite && v >= 0 ? v : null;

int? _round(double? v) => v?.round();

/// The targets [plan] prescribes on a day, or null when its calorie spine is
/// missing or non-finite. Whole kcal / whole grams, matching the rings.
PrescribedDay? prescribedTargets(PlanTargets plan, bool isTrainingDay) {
  final restCalories = _finiteOrNull(plan.targetCalories);
  if (restCalories == null) return null;
  final trainingCalories =
      isTrainingDay ? _finiteOrNull(plan.trainingCalories) : null;
  final trainingCarbs = isTrainingDay ? _finiteOrNull(plan.trainingCarbsG) : null;
  final calories = (trainingCalories ?? restCalories).round();
  return PrescribedDay(
    calories: calories < minCalorieTarget ? minCalorieTarget : calories,
    proteinG: _round(_finiteOrNull(plan.targetProteinG)),
    carbsG: _round(trainingCarbs ?? _finiteOrNull(plan.targetCarbsG)),
    fatG: _round(_finiteOrNull(plan.targetFatG)),
    isTrainingDay: isTrainingDay,
  );
}

/// Whether [a] governs the calendar day [date].
bool assignmentGoverns(PlanAssignment a, String date) {
  if (date.compareTo(a.startDate) < 0) return false;
  final end = a.endDate;
  if (end == null) return a.status == 'active';
  return date.compareTo(end) <= 0;
}

/// The assignment governing [date], or null when none does.
PlanAssignment? activeAssignmentForDate(
  List<PlanAssignment> assignments,
  String date,
) {
  PlanAssignment? best;
  for (final a in assignments) {
    if (!assignmentGoverns(a, date)) continue;
    if (best == null || _newer(a, best)) best = a;
  }
  return best;
}

bool _newer(PlanAssignment a, PlanAssignment b) {
  if (a.startDate != b.startDate) return a.startDate.compareTo(b.startDate) > 0;
  if (a.createdAt != b.createdAt) return a.createdAt.compareTo(b.createdAt) > 0;
  return a.id.compareTo(b.id) > 0;
}

String _pad2(int v) => v.toString().padLeft(2, '0');

/// The calendar day before [iso], stepped through the calendar.
String dayBefore(String iso) {
  final parts = iso.split('-').map(int.parse).toList();
  final prev = DateTime.utc(parts[0], parts[1], parts[2] - 1);
  return '${prev.year}-${_pad2(prev.month)}-${_pad2(prev.day)}';
}

/// How to stop following [a] so that [today] is no longer governed by it.
StopFollowingAction stopFollowingAction(PlanAssignment a, String today) {
  if (a.startDate.compareTo(today) >= 0) return const StopFollowingAction.delete();
  final yesterday = dayBefore(today);
  final end = a.endDate;
  return StopFollowingAction.end(
    end != null && end.compareTo(yesterday) < 0 ? end : yesterday,
  );
}

/// Every assignment following a new plan from [today] must end so the new
/// one is the only plan governing today onward.
List<PlanAssignment> assignmentsToEnd(
  List<PlanAssignment> assignments,
  String today,
) =>
    assignments
        .where((a) =>
            a.status == 'active' &&
            (a.endDate == null || a.endDate!.compareTo(today) >= 0))
        .toList();

String goalPhaseToWeightGoal(String phase) {
  switch (phase) {
    case 'cut':
      return 'lose';
    case 'build':
      return 'gain';
    default:
      return 'maintain';
  }
}

String weightGoalToGoalPhase(String goal) {
  switch (goal) {
    case 'lose':
      return 'cut';
    case 'gain':
      return 'build';
    default:
      return 'maintain';
  }
}

/// Seed a plan from the computed REST-day target, so promoting today's
/// numbers on a long-run day does not bake that day's exercise add-on into
/// every day the plan governs. Null when the target cannot be computed.
PlanDraft? planDraftFromTargets(BodyMetricsInput input) {
  final rest = computeNutritionTargets(BodyMetricsInput(
    weightKg: input.weightKg,
    heightCm: input.heightCm,
    ageYears: input.ageYears,
    sex: input.sex,
    activityLevel: input.activityLevel,
    goal: input.goal,
  ));
  if (rest == null) return null;
  return PlanDraft(
    goalPhase: weightGoalToGoalPhase(input.goal),
    targetCalories: rest.calories,
    targetProteinG: rest.proteinG,
    targetCarbsG: rest.carbsG,
    targetFatG: rest.fatG,
  );
}
