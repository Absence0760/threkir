/**
 * Meal plan — which plan governs a diary day, and the targets it prescribes
 * there (docs/features/nutrition_programming.md, P1).
 *
 * Pure functions, no Supabase / runes. TS↔Dart parity pair with
 * `apps/mobile_android/lib/meal_plan.dart` — keep the algorithm, constants,
 * edge cases, and test counts in lockstep.
 *
 * - **`prescribedTargets`** replaces `computeNutritionTargets` on a day a plan
 *   governs. The training-day override applies only to the two columns that
 *   carry one (calories, carbs); protein and fat are the same every day.
 *   Calories clamp to `MIN_CALORIE_TARGET`, the app's soft floor, because the
 *   column only rejects the absurd (< 1000).
 * - **`activeAssignmentForDate`** resolves overlapping assignments newest
 *   `start_date` first, then newest `created_at`, then id, so a stale overlap
 *   degrades to "the newest plan governs" and both platforms pick the same
 *   row. An `ended` assignment still governs the days inside its explicit
 *   range — that is what makes a past day reviewable against the plan it was
 *   lived under — and an `ended` row with no `end_date` governs nothing.
 * - **`stopFollowingAction`** ends an assignment so that today reverts to the
 *   computed target: the range closes on yesterday, and an assignment that
 *   started today never governed a finished day, so it is deleted instead.
 * - **`goalPhaseToWeightGoal`** maps the plan's richer phase onto the shipped
 *   `WeightGoal` vocabulary rather than forking a second one.
 *
 * Dates are `YYYY-MM-DD` calendar strings; "today" is always passed in.
 */

import {
	computeNutritionTargets,
	MIN_CALORIE_TARGET,
	type BodyMetricsInput,
	type WeightGoal,
} from './nutrition_targets';
import type {
	NutritionAssignmentStatus as AssignmentStatus,
	NutritionGoalPhase as GoalPhase,
} from '../types';

export type { AssignmentStatus, GoalPhase };

/// Display order for the editor's phase picker.
export const GOAL_PHASES: GoalPhase[] = ['cut', 'maintain', 'build', 'recomp'];

/// The prescription columns of a `nutrition_plans` row.
export interface PlanTargets {
	targetCalories: number;
	targetProteinG: number | null;
	targetCarbsG: number | null;
	targetFatG: number | null;
	trainingCalories: number | null;
	trainingCarbsG: number | null;
}

/// What a governed day is measured against. A null macro is unprescribed.
export interface PrescribedDay {
	calories: number;
	proteinG: number | null;
	carbsG: number | null;
	fatG: number | null;
	isTrainingDay: boolean;
}

export interface PlanAssignment {
	id: string;
	planId: string;
	startDate: string;
	endDate: string | null;
	status: AssignmentStatus;
	createdAt: string;
}

export type StopFollowingAction = { kind: 'end'; endDate: string } | { kind: 'delete' };

/// A plan draft seeded from the computed rest-day target ("Save as plan").
export interface PlanDraft {
	goalPhase: GoalPhase;
	targetCalories: number;
	targetProteinG: number;
	targetCarbsG: number;
	targetFatG: number;
}

function finiteOrNull(v: number | null | undefined): number | null {
	return typeof v === 'number' && Number.isFinite(v) && v >= 0 ? v : null;
}

/// The targets `plan` prescribes on a day, or null when its calorie spine is
/// missing or non-finite. Whole kcal / whole grams, matching the rings.
export function prescribedTargets(plan: PlanTargets, isTrainingDay: boolean): PrescribedDay | null {
	const restCalories = finiteOrNull(plan.targetCalories);
	if (restCalories === null) return null;
	const trainingCalories = isTrainingDay ? finiteOrNull(plan.trainingCalories) : null;
	const trainingCarbs = isTrainingDay ? finiteOrNull(plan.trainingCarbsG) : null;
	const round = (v: number | null) => (v === null ? null : Math.round(v));
	return {
		calories: Math.max(MIN_CALORIE_TARGET, Math.round(trainingCalories ?? restCalories)),
		proteinG: round(finiteOrNull(plan.targetProteinG)),
		carbsG: round(trainingCarbs ?? finiteOrNull(plan.targetCarbsG)),
		fatG: round(finiteOrNull(plan.targetFatG)),
		isTrainingDay,
	};
}

/// Whether `a` governs the calendar day `date`.
export function assignmentGoverns(a: PlanAssignment, date: string): boolean {
	if (date < a.startDate) return false;
	if (a.endDate === null) return a.status === 'active';
	return date <= a.endDate;
}

/// The assignment governing `date`, or null when none does.
export function activeAssignmentForDate(
	assignments: readonly PlanAssignment[],
	date: string,
): PlanAssignment | null {
	let best: PlanAssignment | null = null;
	for (const a of assignments) {
		if (!assignmentGoverns(a, date)) continue;
		if (best === null || newer(a, best)) best = a;
	}
	return best;
}

function newer(a: PlanAssignment, b: PlanAssignment): boolean {
	if (a.startDate !== b.startDate) return a.startDate > b.startDate;
	if (a.createdAt !== b.createdAt) return a.createdAt > b.createdAt;
	return a.id > b.id;
}

/// The calendar day before `iso`, stepped through the calendar.
export function dayBefore(iso: string): string {
	const [y, m, d] = iso.split('-').map(Number);
	const prev = new Date(Date.UTC(y, m - 1, d - 1));
	const mm = String(prev.getUTCMonth() + 1).padStart(2, '0');
	const dd = String(prev.getUTCDate()).padStart(2, '0');
	return `${prev.getUTCFullYear()}-${mm}-${dd}`;
}

/// How to stop following `a` so that `today` is no longer governed by it.
export function stopFollowingAction(a: PlanAssignment, today: string): StopFollowingAction {
	if (a.startDate >= today) return { kind: 'delete' };
	const yesterday = dayBefore(today);
	const endDate = a.endDate !== null && a.endDate < yesterday ? a.endDate : yesterday;
	return { kind: 'end', endDate };
}

/// Every assignment `follow`-ing a new plan from `today` must end so the new
/// one is the only plan governing today onward.
export function assignmentsToEnd(
	assignments: readonly PlanAssignment[],
	today: string,
): PlanAssignment[] {
	return assignments.filter(
		(a) => a.status === 'active' && (a.endDate === null || a.endDate >= today),
	);
}

export function goalPhaseToWeightGoal(phase: string): WeightGoal {
	switch (phase) {
		case 'cut':
			return 'lose';
		case 'build':
			return 'gain';
		default:
			return 'maintain';
	}
}

export function weightGoalToGoalPhase(goal: string): GoalPhase {
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
export function planDraftFromTargets(input: BodyMetricsInput): PlanDraft | null {
	const rest = computeNutritionTargets({ ...input, exerciseKcal: 0 });
	if (rest === null) return null;
	return {
		goalPhase: weightGoalToGoalPhase(input.goal),
		targetCalories: rest.calories,
		targetProteinG: rest.proteinG,
		targetCarbsG: rest.carbsG,
		targetFatG: rest.fatG,
	};
}
