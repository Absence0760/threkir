/// The weekly distance goal, typed in the runner's own unit. Shared with the
/// mobile twin (apps/mobile_android/lib/weekly_goal.dart); keep the two in
/// lockstep: algorithm, edge cases, outputs, and test counts must match.
///
/// `weekly_mileage_goal_m` is stored in metres, which is not what a person
/// types: nobody thinks of their week as `50000`. The field asks in km or mi
/// and converts at the boundary, the entry/exit split `challenge_goal` keeps
/// for a typed challenge distance.

import { MILE_METRES } from '../runs/race_day';

export const WEEKLY_GOAL_KEY = 'weekly_mileage_goal_m';

/// The range a typed goal must fall in, in the unit it is typed in.
export const WEEKLY_GOAL_MIN = 0.1;
export const WEEKLY_GOAL_MAX = 500;

function metresPerUnit(unit: 'km' | 'mi'): number {
	return unit === 'mi' ? MILE_METRES : 1000;
}

/// A stored goal as the field shows it: in `unit`, to one decimal place.
/// Null for an absent, non-numeric or non-positive stored value.
export function weeklyGoalToInput(metres: unknown, unit: 'km' | 'mi'): number | null {
	if (typeof metres !== 'number' || !Number.isFinite(metres) || metres <= 0) return null;
	return Math.round((metres / metresPerUnit(unit)) * 10) / 10;
}

/// Whether a typed goal is one the field accepts. Null (an empty field) is not
/// a goal; it clears one, and the caller handles it before asking.
export function isUsableWeeklyGoalInput(typed: number | null): boolean {
	return (
		typed !== null &&
		Number.isFinite(typed) &&
		typed >= WEEKLY_GOAL_MIN &&
		typed <= WEEKLY_GOAL_MAX
	);
}

/// The metres to store for a typed goal, or null to clear it. A non-positive
/// goal clears too, though the field refuses one before it gets here.
///
/// When the typed value is exactly what the field shows for the stored goal,
/// the stored metres come back unchanged: the display rounds to one decimal,
/// so converting it back would move a goal nobody edited (50000 m shows as
/// 31.1 mi, and 31.1 mi is 50051 m).
export function weeklyGoalFromInput(
	typed: number | null,
	unit: 'km' | 'mi',
	storedMetres: unknown,
): number | null {
	if (typed === null || !Number.isFinite(typed) || typed <= 0) return null;
	const shown = weeklyGoalToInput(storedMetres, unit);
	if (shown !== null && shown === typed) return storedMetres as number;
	return Math.round(typed * metresPerUnit(unit));
}
