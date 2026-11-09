// A suggested change to a coach-assigned plan, read for display (issue #1215
// Phase 2, decisions § 2382). Parity pair with mobile `plan_change.dart`
// (docs/architecture/parity_pairs.md).
//
// A `plan_change_requests` row stores the apply_ai_plan_edits payload: a list
// of workout changes (`id` plus the fields it changes) and a list of week
// target changes. Both clients show it as before → after lines, with "before"
// read from the plan rows as they are now, so the card describes what an
// approval would write rather than what the athlete's screen showed.

export const PLAN_CHANGE_STATUSES = ['pending', 'approved', 'declined', 'withdrawn', 'overridden'] as const;
export type PlanChangeStatus = (typeof PLAN_CHANGE_STATUSES)[number];

export function parsePlanChangeStatus(raw: unknown): PlanChangeStatus | null {
	return (PLAN_CHANGE_STATUSES as readonly unknown[]).includes(raw) ? (raw as PlanChangeStatus) : null;
}

export interface PlanChangeWorkoutRow {
	id: string;
	scheduled_date: string;
	kind: string;
	target_distance_m: number | null;
	target_duration_seconds: number | null;
	skipped_at: string | null;
}

export interface PlanChangeWeekRow {
	id: string;
	week_index: number;
	target_volume_m: number | null;
}

export interface PlanChangeWorkoutState {
	scheduledDate: string;
	kind: string;
	distanceM: number | null;
	durationS: number | null;
	skipped: boolean;
}

export interface PlanChangeWorkoutLine {
	workoutId: string;
	before: PlanChangeWorkoutState;
	after: PlanChangeWorkoutState;
}

export interface PlanChangeWeekLine {
	weekId: string;
	weekIndex: number;
	beforeM: number | null;
	afterM: number | null;
}

export interface PlanChangeLines {
	workouts: PlanChangeWorkoutLine[];
	weeks: PlanChangeWeekLine[];
	/// Changes whose row the viewer can no longer read (deleted, or the link
	/// ended): counted, never guessed at.
	unreadable: number;
}

type Change = { id: string } & Record<string, unknown>;

/// The well-formed changes of a stored list: objects with a string id.
export function parseChangeList(raw: unknown): Change[] {
	if (!Array.isArray(raw)) return [];
	return raw.filter(
		(c): c is Change =>
			c !== null && typeof c === 'object' && !Array.isArray(c) && typeof (c as { id?: unknown }).id === 'string',
	);
}

export function planChangeIds(workouts: unknown, weeks: unknown): { workoutIds: string[]; weekIds: string[] } {
	return {
		workoutIds: parseChangeList(workouts).map((c) => c.id),
		weekIds: parseChangeList(weeks).map((c) => c.id),
	};
}

function numberOrNull(v: unknown, fallback: number | null): number | null {
	if (v === null) return null;
	return typeof v === 'number' && Number.isFinite(v) ? v : fallback;
}

export function planChangeLines(
	workouts: unknown,
	weeks: unknown,
	workoutRows: PlanChangeWorkoutRow[],
	weekRows: PlanChangeWeekRow[],
): PlanChangeLines {
	const byWorkout = new Map(workoutRows.map((r) => [r.id, r]));
	const byWeek = new Map(weekRows.map((r) => [r.id, r]));
	let unreadable = 0;

	const workoutLines: PlanChangeWorkoutLine[] = [];
	for (const c of parseChangeList(workouts)) {
		const row = byWorkout.get(c.id);
		if (!row) {
			unreadable++;
			continue;
		}
		const before: PlanChangeWorkoutState = {
			scheduledDate: row.scheduled_date,
			kind: row.kind,
			distanceM: row.target_distance_m,
			durationS: row.target_duration_seconds,
			skipped: row.skipped_at !== null,
		};
		const after: PlanChangeWorkoutState = {
			scheduledDate: typeof c.scheduled_date === 'string' ? c.scheduled_date : before.scheduledDate,
			kind: typeof c.kind === 'string' ? c.kind : before.kind,
			distanceM: 'target_distance_m' in c ? numberOrNull(c.target_distance_m, before.distanceM) : before.distanceM,
			durationS:
				'target_duration_seconds' in c
					? numberOrNull(c.target_duration_seconds, before.durationS)
					: before.durationS,
			skipped: c.skip === true || before.skipped,
		};
		workoutLines.push({ workoutId: c.id, before, after });
	}
	workoutLines.sort((a, b) =>
		a.before.scheduledDate === b.before.scheduledDate
			? a.workoutId < b.workoutId
				? -1
				: a.workoutId > b.workoutId
					? 1
					: 0
			: a.before.scheduledDate < b.before.scheduledDate
				? -1
				: 1,
	);

	const weekLines: PlanChangeWeekLine[] = [];
	for (const c of parseChangeList(weeks)) {
		const row = byWeek.get(c.id);
		if (!row) {
			unreadable++;
			continue;
		}
		weekLines.push({
			weekId: c.id,
			weekIndex: row.week_index,
			beforeM: row.target_volume_m,
			afterM: numberOrNull(c.target_volume_m, row.target_volume_m),
		});
	}
	weekLines.sort((a, b) => a.weekIndex - b.weekIndex);

	return { workouts: workoutLines, weeks: weekLines, unreadable };
}
