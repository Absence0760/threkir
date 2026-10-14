import 'package:flutter_test/flutter_test.dart';

import '../lib/meal_plan.dart';
import '../lib/nutrition_targets.dart';

PlanTargets plan({
  double targetCalories = 2200,
  double? targetProteinG = 140,
  double? targetCarbsG = 250,
  double? targetFatG = 70,
  double? trainingCalories,
  double? trainingCarbsG,
}) =>
    PlanTargets(
      targetCalories: targetCalories,
      targetProteinG: targetProteinG,
      targetCarbsG: targetCarbsG,
      targetFatG: targetFatG,
      trainingCalories: trainingCalories,
      trainingCarbsG: trainingCarbsG,
    );

PlanAssignment assignment(
  String id, {
  String startDate = '2027-03-01',
  String? endDate,
  String status = 'active',
  String createdAt = '2027-03-01T08:00:00Z',
}) =>
    PlanAssignment(
      id: id,
      planId: 'plan-$id',
      startDate: startDate,
      endDate: endDate,
      status: status,
      createdAt: createdAt,
    );

List<Object?> shape(PrescribedDay? d) => d == null
    ? [null]
    : [d.calories, d.proteinG, d.carbsG, d.fatG, d.isTrainingDay];

void main() {
  // ── prescribedTargets ─────────────────────────────────────────────────────

  test('prescribedTargets returns the rest-day targets on a rest day', () {
    expect(shape(prescribedTargets(plan(), false)), [2200, 140, 250, 70, false]);
  });

  test('prescribedTargets applies the training override to calories and carbs only', () {
    final d = prescribedTargets(
        plan(trainingCalories: 2600, trainingCarbsG: 340), true);
    expect(shape(d), [2600, 140, 340, 70, true]);
  });

  test('prescribedTargets ignores the training override on a rest day', () {
    final d = prescribedTargets(
        plan(trainingCalories: 2600, trainingCarbsG: 340), false);
    expect(d?.calories, 2200);
    expect(d?.carbsG, 250);
  });

  test('prescribedTargets falls back to rest-day values when a training day has no override', () {
    final d = prescribedTargets(plan(trainingCalories: 2600), true);
    expect(d?.calories, 2600);
    expect(d?.carbsG, 250);
  });

  test('prescribedTargets keeps a kcal-only plan kcal-only', () {
    final d = prescribedTargets(
        plan(targetProteinG: null, targetCarbsG: null, targetFatG: null), false);
    expect(shape(d), [2200, null, null, null, false]);
  });

  test('prescribedTargets clamps calories to the app soft floor', () {
    expect(prescribedTargets(plan(targetCalories: 1050), false)?.calories,
        minCalorieTarget);
    expect(prescribedTargets(plan(trainingCalories: 1100), true)?.calories,
        minCalorieTarget);
  });

  test('prescribedTargets rounds to whole kcal and grams', () {
    final d = prescribedTargets(
        plan(targetCalories: 2200.5, targetProteinG: 139.6, targetFatG: 70.4),
        false);
    expect(d?.calories, 2201);
    expect(d?.proteinG, 140);
    expect(d?.fatG, 70);
  });

  test('prescribedTargets returns null for a non-finite calorie spine', () {
    expect(prescribedTargets(plan(targetCalories: double.nan), false), isNull);
    expect(prescribedTargets(plan(targetCalories: double.infinity), false),
        isNull);
  });

  test('prescribedTargets treats a non-finite or negative macro as unprescribed', () {
    final d = prescribedTargets(
        plan(targetProteinG: double.nan, targetFatG: -5), false);
    expect(d?.proteinG, isNull);
    expect(d?.fatG, isNull);
    expect(d?.carbsG, 250);
  });

  // ── assignmentGoverns / activeAssignmentForDate ───────────────────────────

  test('an open-ended active assignment governs from its start onward', () {
    final a = assignment('a');
    expect(assignmentGoverns(a, '2027-02-28'), isFalse);
    expect(assignmentGoverns(a, '2027-03-01'), isTrue);
    expect(assignmentGoverns(a, '2028-01-01'), isTrue);
  });

  test('a bounded assignment governs its range inclusive, whatever its status', () {
    final a = assignment('a', endDate: '2027-03-10', status: 'ended');
    expect(assignmentGoverns(a, '2027-03-10'), isTrue);
    expect(assignmentGoverns(a, '2027-03-11'), isFalse);
    expect(
        assignmentGoverns(assignment('a', endDate: '2027-03-10'), '2027-03-05'),
        isTrue);
  });

  test('an ended assignment with no end date governs nothing', () {
    expect(assignmentGoverns(assignment('a', status: 'ended'), '2027-03-05'),
        isFalse);
  });

  test('activeAssignmentForDate returns null when nothing governs the day', () {
    expect(activeAssignmentForDate([], '2027-03-05'), isNull);
    expect(activeAssignmentForDate([assignment('a')], '2027-02-01'), isNull);
  });

  test('activeAssignmentForDate lets the newest start date win an overlap', () {
    final older = assignment('older', startDate: '2027-03-01');
    final newer = assignment('newer',
        startDate: '2027-03-05', createdAt: '2027-02-01T00:00:00Z');
    expect(activeAssignmentForDate([newer, older], '2027-03-06')?.id, 'newer');
    expect(activeAssignmentForDate([newer, older], '2027-03-04')?.id, 'older');
  });

  test('activeAssignmentForDate breaks a same-start tie on created_at, then id', () {
    final a = assignment('a', createdAt: '2027-03-01T08:00:00Z');
    final b = assignment('b', createdAt: '2027-03-01T09:00:00Z');
    expect(activeAssignmentForDate([b, a], '2027-03-02')?.id, 'b');
    final c = assignment('c', createdAt: '2027-03-01T08:00:00Z');
    expect(activeAssignmentForDate([c, a], '2027-03-02')?.id, 'c');
  });

  // ── stopping and switching ────────────────────────────────────────────────

  test('dayBefore steps through month and year boundaries', () {
    expect(dayBefore('2027-03-01'), '2027-02-28');
    expect(dayBefore('2028-03-01'), '2028-02-29');
    expect(dayBefore('2027-01-01'), '2026-12-31');
  });

  test('stopFollowingAction closes an older assignment on yesterday', () {
    final s = stopFollowingAction(assignment('a'), '2027-03-20');
    expect([s.kind, s.endDate], ['end', '2027-03-19']);
  });

  test('stopFollowingAction deletes an assignment that started today or later', () {
    final s =
        stopFollowingAction(assignment('a', startDate: '2027-03-20'), '2027-03-20');
    expect([s.kind, s.endDate], ['delete', null]);
  });

  test('stopFollowingAction never extends an end date that already closed', () {
    final s = stopFollowingAction(
        assignment('a', endDate: '2027-03-10'), '2027-03-20');
    expect([s.kind, s.endDate], ['end', '2027-03-10']);
  });

  test('assignmentsToEnd keeps only active rows still reaching today', () {
    final all = [
      assignment('open'),
      assignment('reaching', endDate: '2027-03-25'),
      assignment('past', endDate: '2027-03-10'),
      assignment('ended', status: 'ended', endDate: '2027-03-25'),
    ];
    expect(assignmentsToEnd(all, '2027-03-20').map((a) => a.id).toList(),
        ['open', 'reaching']);
  });

  // ── goal phase vocabulary ─────────────────────────────────────────────────

  test('goalPhaseToWeightGoal maps every phase onto a goalKcalDelta key', () {
    expect(goalPhases.map(goalPhaseToWeightGoal).toList(),
        ['lose', 'maintain', 'gain', 'maintain']);
    for (final p in goalPhases) {
      expect(goalKcalDelta.containsKey(goalPhaseToWeightGoal(p)), isTrue);
    }
    expect(goalPhaseToWeightGoal('bulk'), 'maintain');
  });

  test('weightGoalToGoalPhase is the inverse for the three weight goals', () {
    expect(['lose', 'maintain', 'gain', 'recomp'].map(weightGoalToGoalPhase).toList(),
        ['cut', 'maintain', 'build', 'maintain']);
  });

  // ── planDraftFromTargets ──────────────────────────────────────────────────

  test('planDraftFromTargets seeds the rest-day target, not the exercise-inflated one', () {
    final d = planDraftFromTargets(const BodyMetricsInput(
      weightKg: 70,
      heightCm: 175,
      ageYears: 30,
      sex: 'male',
      activityLevel: 'moderate',
      goal: 'lose',
      exerciseKcal: 600,
    ));
    expect([
      d?.goalPhase,
      d?.targetCalories,
      d?.targetProteinG,
      d?.targetCarbsG,
      d?.targetFatG,
    ], ['cut', 2060, 126, 234, 69]);
  });

  test('planDraftFromTargets returns null without body metrics', () {
    expect(
        planDraftFromTargets(const BodyMetricsInput(
          weightKg: null,
          heightCm: 175,
          ageYears: 30,
          sex: null,
          activityLevel: 'moderate',
          goal: 'maintain',
        )),
        isNull);
  });
}
