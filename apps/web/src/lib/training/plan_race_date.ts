/**
 * Changing a plan's race date mid-plan (issue #1186, decisions § 2120): which
 * weeks to drop or repeat so the plan ends on the new race day with its taper
 * whole. `change_plan_race_date` applies the result in one transaction and
 * re-checks every choice.
 *
 * Whole weeks, so every workout keeps its weekday role and stays inside the
 * week window both clients derive from start_date + 7 * week_index. An earlier
 * race drops pre-taper weeks that have not started (build first, then base,
 * then peak, the latest of each first); a later race repeats the last base or
 * build week before the peak, or before the taper once the peak has started.
 * The taper and race weeks are never dropped, and nothing that has started,
 * nothing completed and no other race moves.
 *
 * Dart twin: apps/mobile_android/lib/plan_race_date.dart.
 */

import { daysBetweenIso } from './cycle_plan.ts';
import { shiftIsoDate } from './plan_bulk_ops.ts';
import { racePlanPreset } from './race_plan_preset.ts';

export const RACE_DATE_MAX_ADDED_WEEKS = 52;

export type RaceDatePlan = {
	start_date: string;
	end_date: string;
	trimmed_at: string | null;
	status: string;
	is_template?: boolean;
};

export type RaceDateWeek = { id: string; week_index: number; phase: string };

export type RaceDateWorkout = {
	id: string;
	week_id: string;
	scheduled_date: string;
	kind: string;
	race_priority?: string | null;
	completed_run_id: string | null;
	manually_completed: boolean;
};

export type RaceDateRefusal =
	/// Not a usable date.
	| 'invalid'
	/// Today or earlier.
	| 'past'
	/// The race is already on that day.
	| 'unchanged'
	/// The plan has no race still ahead to move.
	| 'no_race'
	/// Race week has started, so no week can be added in front of it.
	| 'race_week_started'
	/// Even with every pre-taper week that has not started cut, the taper
	/// cannot end on that day. `earliestIso` says the first day it can.
	| 'too_soon'
	/// More than RACE_DATE_MAX_ADDED_WEEKS weeks later.
	| 'too_far'
	/// No base or build week to repeat.
	| 'no_build_week'
	/// A week that would move or go holds another race or a completed workout.
	| 'in_the_way';

export type RaceDateChange = {
	raceDateIso: string;
	/// Weeks added (positive) or removed (negative).
	weekDelta: number;
	dropWeekIds: string[];
	/// The week index the repeated weeks are inserted at, or null.
	insertAt: number | null;
	insertCount: number;
	repeatWeekId: string | null;
	/// The race workout that moves onto the new day, or null when the plan's
	/// race is only its end date.
	raceWorkoutId: string | null;
};

export type RaceDateResult =
	| { ok: true; change: RaceDateChange }
	| { ok: false; reason: RaceDateRefusal; earliestIso?: string };

const TAPER = new Set(['taper', 'race']);
const LATE = new Set(['peak', 'taper', 'race']);
const DROP_RANK: Record<string, number> = { build: 0, base: 1, peak: 2 };

function isDone(w: RaceDateWorkout): boolean {
	return w.completed_run_id != null || w.manually_completed;
}

/// The race day a plan can move: its end date, when the plan is the runner's
/// own active or paused plan, was not ended early, and its last week is a race
/// week. Null for a walk-run plan, a trimmed plan or a template.
export function planRaceDate(plan: RaceDatePlan, weeks: RaceDateWeek[]): string | null {
	if (plan.is_template || plan.trimmed_at) return null;
	if (plan.status !== 'active' && plan.status !== 'paused') return null;
	if (weeks.length === 0) return null;
	const last = weeks.reduce((a, b) => (b.week_index > a.week_index ? b : a));
	return last.phase === 'race' ? plan.end_date : null;
}

/// Index of the first week of the run of trailing weeks whose phase is in
/// `phases`, or one past the last week when the last week is not.
function trailingStart(sorted: RaceDateWeek[], phases: Set<string>): number {
	let start = sorted[sorted.length - 1].week_index + 1;
	for (let i = sorted.length - 1; i >= 0 && phases.has(sorted[i].phase); i--) {
		start = sorted[i].week_index;
	}
	return start;
}

export function raceDateChange(input: {
	plan: RaceDatePlan;
	weeks: RaceDateWeek[];
	workouts: RaceDateWorkout[];
	raceDateIso: string;
	todayIso: string;
}): RaceDateResult {
	const { plan, weeks, workouts, raceDateIso, todayIso } = input;
	const preset = racePlanPreset({ raceDateIso, todayIso });
	if (!preset.ok && preset.reason !== 'too_soon') return { ok: false, reason: preset.reason };
	const current = planRaceDate(plan, weeks);
	if (current == null || current < todayIso) return { ok: false, reason: 'no_race' };
	if (raceDateIso === current) return { ok: false, reason: 'unchanged' };

	const toRace = daysBetweenIso(plan.start_date, raceDateIso);
	const toToday = daysBetweenIso(plan.start_date, todayIso);
	if (toRace == null || toToday == null) return { ok: false, reason: 'invalid' };

	const sorted = [...weeks].sort((a, b) => a.week_index - b.week_index);
	const last = sorted[sorted.length - 1];
	const r = last.week_index;
	const c = Math.floor(toToday / 7);
	const k = Math.floor(toRace / 7) - r;

	const byWeek = new Map<string, RaceDateWorkout[]>();
	for (const w of workouts) {
		const list = byWeek.get(w.week_id) ?? [];
		list.push(w);
		byWeek.set(w.week_id, list);
	}
	const of = (week: RaceDateWeek) => byWeek.get(week.id) ?? [];
	const lastRows = of(last);
	const isARace = (w: RaceDateWorkout) =>
		w.kind === 'race' && (w.race_priority == null || w.race_priority === 'A') && !isDone(w);
	const raceWo =
		lastRows.find((w) => isARace(w) && w.scheduled_date === plan.end_date) ??
		lastRows
			.filter(isARace)
			.sort((a, b) => (a.scheduled_date < b.scheduled_date ? 1 : a.scheduled_date > b.scheduled_date ? -1 : 0))[0] ??
		null;
	const blocks = (w: RaceDateWorkout) => (w.kind === 'race' && w.id !== raceWo?.id) || isDone(w);
	const holdsRace = (week: RaceDateWeek) => of(week).some((w) => w.kind === 'race');

	let dropWeekIds: string[] = [];
	let insertAt: number | null = null;
	let repeatWeekId: string | null = null;
	let moving: RaceDateWeek[] = [];

	if (k < 0) {
		const candidates = sorted
			.filter((w) => w.week_index > c && !TAPER.has(w.phase) && !holdsRace(w) && !of(w).some(isDone))
			.sort(
				(a, b) =>
					(DROP_RANK[a.phase] ?? 3) - (DROP_RANK[b.phase] ?? 3) || b.week_index - a.week_index
			);
		if (candidates.length < -k) {
			const weekStart = shiftIsoDate(plan.start_date, 7 * (r - candidates.length));
			const tomorrow = shiftIsoDate(todayIso, 1);
			return { ok: false, reason: 'too_soon', earliestIso: weekStart > tomorrow ? weekStart : tomorrow };
		}
		const drop = candidates.slice(0, -k);
		dropWeekIds = drop.map((w) => w.id).sort();
		const firstDrop = Math.min(...drop.map((w) => w.week_index));
		const dropped = new Set(dropWeekIds);
		moving = sorted.filter((w) => w.week_index > firstDrop && !dropped.has(w.id));
	} else if (k > 0) {
		if (k > RACE_DATE_MAX_ADDED_WEEKS) return { ok: false, reason: 'too_far' };
		const p = Math.max(trailingStart(sorted, LATE), c + 1);
		if (p > r) return { ok: false, reason: 'race_week_started' };
		const before = sorted.filter((w) => w.week_index < p && !holdsRace(w)).reverse();
		const source =
			before.find((w) => w.phase === 'base' || w.phase === 'build') ??
			before.find((w) => !TAPER.has(w.phase)) ??
			null;
		if (!source) return { ok: false, reason: 'no_build_week' };
		insertAt = p;
		repeatWeekId = source.id;
		moving = sorted.filter((w) => w.week_index >= p);
	}

	if (moving.some((w) => of(w).some(blocks))) return { ok: false, reason: 'in_the_way' };

	for (const w of lastRows) {
		if (w.id === raceWo?.id) continue;
		const moved = shiftIsoDate(w.scheduled_date, 7 * k);
		const gone = moved > raceDateIso || (moved === raceDateIso && raceWo != null);
		if (gone && blocks(w)) return { ok: false, reason: 'in_the_way' };
	}

	return {
		ok: true,
		change: {
			raceDateIso,
			weekDelta: k,
			dropWeekIds,
			insertAt,
			insertCount: k > 0 ? k : 0,
			repeatWeekId,
			raceWorkoutId: raceWo?.id ?? null
		}
	};
}
