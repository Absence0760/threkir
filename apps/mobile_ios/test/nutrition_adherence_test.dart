import 'package:flutter_test/flutter_test.dart';

import '../lib/food_search.dart';
import '../lib/meal_plan.dart';
import '../lib/nutrition_adherence.dart';
import '../lib/nutrition_budget.dart';

PrescribedDay day({
  int calories = 2000,
  int? proteinG = 150,
  int? carbsG = 200,
  int? fatG = 70,
}) =>
    PrescribedDay(
      calories: calories,
      proteinG: proteinG,
      carbsG: carbsG,
      fatG: fatG,
      isTrainingDay: false,
    );

FoodMacros eaten(int calories, int proteinG, int carbsG, int fatG) =>
    FoodMacros(calories: calories, proteinG: proteinG, carbsG: carbsG, fatG: fatG);

void main() {
  test('tolerances and the partial threshold are the published values', () {
    expect(ceilingTolerance, 0.1);
    expect(floorTolerance, 0.1);
    expect(partialLogFraction, 0.5);
  });

  test('a ceiling macro is met up to 10% over and over past it', () {
    expect(macroVerdict(MacroKind.calories, 2200, 2000), 'met');
    expect(macroVerdict(MacroKind.calories, 2201, 2000), 'over');
    expect(macroVerdict(MacroKind.fat, 40, 70), 'met');
  });

  test('a floor macro is met from 10% under and under below it', () {
    expect(macroVerdict(MacroKind.protein, 135, 150), 'met');
    expect(macroVerdict(MacroKind.protein, 134, 150), 'under');
    expect(macroVerdict(MacroKind.carbs, 400, 200), 'met');
  });

  test('a non-finite or negative actual counts as nothing eaten', () {
    expect(macroVerdict(MacroKind.protein, double.nan, 150), 'under');
    expect(macroVerdict(MacroKind.calories, -50, 2000), 'met');
  });

  test('nutritionAdherence returns null without a prescription', () {
    expect(nutritionAdherence(null, eaten(1800, 150, 200, 60)), isNull);
    expect(nutritionAdherence(day(calories: 0), eaten(1800, 150, 200, 60)),
        isNull);
  });

  test('a day inside every band is on_target', () {
    final a = nutritionAdherence(day(), eaten(1950, 152, 190, 72));
    expect(a?.verdict, 'on_target');
    expect(a?.perMacro.map((m) => [m.kind, m.verdict]).toList(), [
      [MacroKind.calories, 'met'],
      [MacroKind.protein, 'met'],
      [MacroKind.carbs, 'met'],
      [MacroKind.fat, 'met'],
    ]);
  });

  test('an off_target day names which macro missed and in which direction', () {
    final a = nutritionAdherence(day(), eaten(2100, 110, 210, 95));
    expect(a?.verdict, 'off_target');
    expect(
        a?.perMacro
            .where((m) => m.verdict != 'met')
            .map((m) => [m.kind, m.verdict, m.actual, m.target])
            .toList(),
        [
          [MacroKind.protein, 'under', 110, 150],
          [MacroKind.fat, 'over', 95, 70],
        ]);
  });

  test('a day under half the prescribed calories is partial, however it splits', () {
    expect(nutritionAdherence(day(), eaten(999, 150, 200, 10))?.verdict,
        'partial');
    expect(nutritionAdherence(day(), eaten(1000, 150, 200, 10))?.verdict,
        'on_target');
  });

  test('an empty day is partial', () {
    expect(nutritionAdherence(day(), eaten(0, 0, 0, 0))?.verdict, 'partial');
  });

  test('a kcal-only plan is judged on calories alone', () {
    final a = nutritionAdherence(
        day(proteinG: null, carbsG: null, fatG: null), eaten(1900, 20, 400, 120));
    expect(a?.verdict, 'on_target');
    expect(a?.perMacro.map((m) => m.kind).toList(), [MacroKind.calories]);
  });

  test('an over-the-ceiling calorie day is off_target even with the macros met', () {
    expect(nutritionAdherence(day(), eaten(2300, 160, 220, 70))?.verdict,
        'off_target');
  });

  test('a negative consumed total is read as zero, never propagated', () {
    final a = nutritionAdherence(day(), eaten(-50, 150, 200, 70));
    expect(a?.verdict, 'partial');
    expect(a?.perMacro[0].actual, 0);
  });
}
