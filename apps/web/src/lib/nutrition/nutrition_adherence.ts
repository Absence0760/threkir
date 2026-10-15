/**
 * Nutrition adherence — did a governed day land inside its prescription
 * (docs/features/nutrition_programming.md § Adherence)?
 *
 * Pure functions, no Supabase / runes. TS↔Dart parity pair with
 * `apps/mobile_android/lib/nutrition_adherence.dart` — keep the algorithm,
 * constants, edge cases, and test counts in lockstep.
 *
 * Per macro and direction-aware, reusing `MACRO_IS_CEILING`:
 *
 * - a **ceiling** macro (calories, fat) is met at or below target × 1.10 and
 *   is otherwise `over`;
 * - a **floor** macro (protein, carbs) is met at or above target × 0.90 and is
 *   otherwise `under`.
 *
 * The day is `partial` when fewer than half the prescribed calories were
 * logged — a proxy for "did not finish logging", which cannot be told apart
 * from genuinely under-eating, so such a day is never judged. Otherwise it is
 * `on_target` when every prescribed macro is met and `off_target` with the
 * per-macro breakdown when one is not. An unprescribed macro is left out.
 *
 * Computed on read from the day's logged totals and never stored.
 */

import { MACRO_IS_CEILING, type MacroKind } from './nutrition_budget';
import type { FoodMacros } from './food_search';
import type { PrescribedDay } from './meal_plan';

export type MacroVerdict = 'met' | 'under' | 'over';
export type DayVerdict = 'on_target' | 'off_target' | 'partial';

/// Allowed overshoot on a ceiling macro before it reads as `over`.
export const CEILING_TOLERANCE = 0.1;
/// Allowed shortfall on a floor macro before it reads as `under`.
export const FLOOR_TOLERANCE = 0.1;
/// Below this share of prescribed calories the day reads as under-logged.
export const PARTIAL_LOG_FRACTION = 0.5;

export interface MacroAdherence {
	kind: MacroKind;
	actual: number;
	target: number;
	verdict: MacroVerdict;
}

export interface DayAdherence {
	verdict: DayVerdict;
	perMacro: MacroAdherence[];
}

const ORDER: MacroKind[] = ['calories', 'protein', 'carbs', 'fat'];

function finiteOrZero(v: number): number {
	return Number.isFinite(v) && v > 0 ? v : 0;
}

/// One macro's verdict against a positive target.
export function macroVerdict(kind: MacroKind, actual: number, target: number): MacroVerdict {
	const a = finiteOrZero(actual);
	if (MACRO_IS_CEILING[kind]) return a <= target * (1 + CEILING_TOLERANCE) ? 'met' : 'over';
	return a >= target * (1 - FLOOR_TOLERANCE) ? 'met' : 'under';
}

/// The day's adherence to `prescribed`, or null when there is no positive
/// calorie prescription to judge against.
export function nutritionAdherence(
	prescribed: PrescribedDay | null,
	consumed: FoodMacros,
): DayAdherence | null {
	if (prescribed === null || !(prescribed.calories > 0)) return null;
	const targets: Record<MacroKind, number | null> = {
		calories: prescribed.calories,
		protein: prescribed.proteinG,
		carbs: prescribed.carbsG,
		fat: prescribed.fatG,
	};
	const actuals: Record<MacroKind, number> = {
		calories: finiteOrZero(consumed.calories),
		protein: finiteOrZero(consumed.proteinG),
		carbs: finiteOrZero(consumed.carbsG),
		fat: finiteOrZero(consumed.fatG),
	};
	const perMacro: MacroAdherence[] = [];
	for (const kind of ORDER) {
		const target = targets[kind];
		if (target === null || !(target > 0)) continue;
		perMacro.push({ kind, actual: actuals[kind], target, verdict: macroVerdict(kind, actuals[kind], target) });
	}
	let verdict: DayVerdict;
	if (actuals.calories < prescribed.calories * PARTIAL_LOG_FRACTION) verdict = 'partial';
	else if (perMacro.every((m) => m.verdict === 'met')) verdict = 'on_target';
	else verdict = 'off_target';
	return { verdict, perMacro };
}
