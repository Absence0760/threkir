/// Nutrition adherence — did a governed day land inside its prescription
/// (docs/features/nutrition_programming.md § Adherence)?
///
/// Dart twin of `apps/web/src/lib/nutrition/nutrition_adherence.ts` — keep
/// the algorithm, constants, edge cases, and test counts in lockstep. Read the
/// web module's header for the rules.
library;

import 'food_search.dart';
import 'meal_plan.dart';
import 'nutrition_budget.dart';

/// `met` / `under` / `over`.
typedef MacroVerdict = String;

/// `on_target` / `off_target` / `partial`.
typedef DayVerdict = String;

/// Allowed overshoot on a ceiling macro before it reads as `over`.
const ceilingTolerance = 0.1;

/// Allowed shortfall on a floor macro before it reads as `under`.
const floorTolerance = 0.1;

/// Below this share of prescribed calories the day reads as under-logged.
const partialLogFraction = 0.5;

class MacroAdherence {
  const MacroAdherence({
    required this.kind,
    required this.actual,
    required this.target,
    required this.verdict,
  });
  final MacroKind kind;
  final double actual;
  final int target;
  final MacroVerdict verdict;
}

class DayAdherence {
  const DayAdherence({required this.verdict, required this.perMacro});
  final DayVerdict verdict;
  final List<MacroAdherence> perMacro;
}

double _finiteOrZero(num v) => v.isFinite && v > 0 ? v.toDouble() : 0;

/// One macro's verdict against a positive target.
MacroVerdict macroVerdict(MacroKind kind, num actual, num target) {
  final a = _finiteOrZero(actual);
  if (macroIsCeiling[kind]!) {
    return a <= target * (1 + ceilingTolerance) ? 'met' : 'over';
  }
  return a >= target * (1 - floorTolerance) ? 'met' : 'under';
}

/// The day's adherence to [prescribed], or null when there is no positive
/// calorie prescription to judge against.
DayAdherence? nutritionAdherence(PrescribedDay? prescribed, FoodMacros consumed) {
  if (prescribed == null || !(prescribed.calories > 0)) return null;
  final targets = <MacroKind, int?>{
    MacroKind.calories: prescribed.calories,
    MacroKind.protein: prescribed.proteinG,
    MacroKind.carbs: prescribed.carbsG,
    MacroKind.fat: prescribed.fatG,
  };
  final actuals = <MacroKind, double>{
    MacroKind.calories: _finiteOrZero(consumed.calories),
    MacroKind.protein: _finiteOrZero(consumed.proteinG),
    MacroKind.carbs: _finiteOrZero(consumed.carbsG),
    MacroKind.fat: _finiteOrZero(consumed.fatG),
  };
  final perMacro = <MacroAdherence>[];
  for (final kind in MacroKind.values) {
    final target = targets[kind];
    if (target == null || !(target > 0)) continue;
    final actual = actuals[kind]!;
    perMacro.add(MacroAdherence(
      kind: kind,
      actual: actual,
      target: target,
      verdict: macroVerdict(kind, actual, target),
    ));
  }
  final DayVerdict verdict;
  if (actuals[MacroKind.calories]! < prescribed.calories * partialLogFraction) {
    verdict = 'partial';
  } else if (perMacro.every((m) => m.verdict == 'met')) {
    verdict = 'on_target';
  } else {
    verdict = 'off_target';
  }
  return DayAdherence(verdict: verdict, perMacro: perMacro);
}
