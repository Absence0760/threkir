/**
 * "Restart this plan" (issue #1186, decisions § 2121): the dates a restart
 * offers and refuses. `restart_training_plan` copies the plan, moving every
 * workout by the offset between the old and new start dates.
 *
 * The start follows the creation wizard (`plan_start.ts`), generalised from
 * "a Sunday" to the source plan's own start weekday: day roles are offsets
 * from the start date, and a library or coach plan may be anchored on any
 * day. A walk-run plan has no weekday-bound role, so it may start any day
 * and defaults to tomorrow, as in the wizard.
 */

import { daysBetweenIso } from './cycle_plan.ts';
import { shiftIsoDate } from './plan_bulk_ops.ts';

export interface RestartWorkout {
	kind: string;
	scheduled_date: string;
}

/// The same test `create_training_plan` applies: every workout a walk-run,
/// rest or race day, and at least one walk-run.
export function isWalkRunPlan(workouts: readonly RestartWorkout[]): boolean {
	return (
		workouts.some((w) => w.kind === 'walk_run') &&
		workouts.every((w) => w.kind === 'walk_run' || w.kind === 'rest' || w.kind === 'race')
	);
}

/// The earliest race on or after `todayIso`, which blocks a restart: moving
/// the plan would move race day off the real date. Null when every race is
/// behind the runner, or the plan has none.
export function upcomingRaceIso(workouts: readonly RestartWorkout[], todayIso: string): string | null {
	let best: string | null = null;
	for (const w of workouts) {
		if (w.kind !== 'race') continue;
		const d = daysBetweenIso(todayIso, w.scheduled_date);
		if (d == null || d < 0) continue;
		if (best == null || w.scheduled_date < best) best = w.scheduled_date;
	}
	return best;
}

/// A picked date, snapped forward to the source plan's start weekday
/// (unchanged for a walk-run plan or an unreadable date).
export function alignRestartStartIso(iso: string, sourceStartIso: string, walkRun: boolean): string {
	if (walkRun) return iso;
	const d = daysBetweenIso(sourceStartIso, iso);
	if (d == null) return iso;
	return shiftIsoDate(iso, (((-d) % 7) + 7) % 7);
}

/// The start a restart offers first: tomorrow for a walk-run plan, otherwise
/// the source's start weekday at least a week out.
export function defaultRestartStartIso(sourceStartIso: string, todayIso: string, walkRun: boolean): string {
	if (walkRun) return shiftIsoDate(todayIso, 1);
	return alignRestartStartIso(shiftIsoDate(todayIso, 7), sourceStartIso, false);
}

/// Whether a restart may start on `iso`: not before today, and on the
/// source's start weekday unless it is a walk-run plan.
export function restartStartAllowed(
	iso: string,
	sourceStartIso: string,
	todayIso: string,
	walkRun: boolean
): boolean {
	const fromToday = daysBetweenIso(todayIso, iso);
	const fromSource = daysBetweenIso(sourceStartIso, iso);
	if (fromToday == null || fromSource == null || fromToday < 0) return false;
	return walkRun || fromSource % 7 === 0;
}

/// Where a date of the source plan lands in the copy.
export function restartedDateIso(dateIso: string, sourceStartIso: string, newStartIso: string): string {
	const offset = daysBetweenIso(sourceStartIso, newStartIso);
	return offset == null ? dateIso : shiftIsoDate(dateIso, offset);
}
