/**
 * Running weeks of a plan again from next week, and pushing every later week
 * back by as many whole weeks. "Too hard? Repeat this week" runs one week
 * again (this week, or the week that just finished); the break offer
 * (`plan_break.ts`) runs the latest N weeks again. Both share `rerunFrame` and
 * `rerunPlacement`, as `repeat_plan_week` and `reschedule_plan_after_break`
 * share `private.repeat_plan_weeks`, which applies the change in one
 * transaction and re-checks every choice.
 *
 * Copies go in at the current week + 1, each workout on its weekday. A plan
 * that ends on a race keeps its race day: as many pre-taper weeks that have
 * not started are dropped instead (build first, then base, then peak, the
 * latest of each first), as `change_plan_race_date` drops them. A plan
 * without a race ends that many weeks later. The taper and race weeks never
 * run again, and nothing done and no other race moves.
 */

import { daysBetweenIso } from './cycle_plan.ts';
import { shiftIsoDate } from './plan_bulk_ops.ts';
import {
	planRaceDate,
	type RaceDatePlan,
	type RaceDateWeek,
	type RaceDateWorkout
} from './plan_race_date.ts';

export type RepeatWeekRefusal =
	/// Not an active plan of the runner's that is under way.
	| 'not_active'
	/// Not this week or last week, or a taper or race week.
	| 'not_repeatable'
	/// There is no week after this one to push back.
	| 'last_week'
	/// A race plan with no pre-taper week left that could make room.
	| 'no_room'
	/// A week that would move holds another race or a completed workout.
	| 'in_the_way';

export type RepeatWeekChange = {
	weekId: string;
	/// The week index the copy goes in at: the current week + 1.
	copyIndex: number;
	/// The first day of the copy's week.
	copyStartIso: string;
	dropWeekId: string | null;
	dropWeekIndex: number | null;
	/// The plan's end date afterwards.
	endIso: string;
	/// The race day the plan keeps, or null for a plan without one.
	raceDateIso: string | null;
};

export type RepeatWeekResult =
	| { ok: true; change: RepeatWeekChange }
	| { ok: false; reason: RepeatWeekRefusal };

export type RerunFrame = {
	current: number;
	sorted: RaceDateWeek[];
	byWeek: Map<string, RaceDateWorkout[]>;
	/// The race day the plan keeps, or null for a plan without one.
	raceDate: string | null;
	/// The weeks a race plan may drop, in the order it drops them.
	drops: RaceDateWeek[];
};

export type RerunPlacement =
	| { ok: true; drops: RaceDateWeek[]; endIso: string }
	| { ok: false; reason: 'no_room' | 'in_the_way' };

export const RERUN_TAPER_PHASES: ReadonlySet<string> = new Set(['taper', 'race']);
const DROP_RANK: Record<string, number> = { build: 0, base: 1, peak: 2 };

function holdsSomething(w: RaceDateWorkout): boolean {
	return w.kind === 'race' || w.completed_run_id != null || w.manually_completed;
}

/// The plan as a rerun sees it, or null when it is not an active plan that is
/// under way with a week after the current one.
export function rerunFrame(
	plan: RaceDatePlan,
	weeks: RaceDateWeek[],
	workouts: RaceDateWorkout[],
	todayIso: string
): RerunFrame | null {
	if (plan.is_template || plan.trimmed_at || plan.status !== 'active') return null;
	if (weeks.length === 0 || todayIso > plan.end_date) return null;
	const toToday = daysBetweenIso(plan.start_date, todayIso);
	if (toToday == null || toToday < 0) return null;
	const current = Math.floor(toToday / 7);
	const sorted = [...weeks].sort((a, b) => a.week_index - b.week_index);
	if (sorted[sorted.length - 1].week_index <= current) return null;

	const byWeek = new Map<string, RaceDateWorkout[]>();
	for (const w of workouts) {
		const list = byWeek.get(w.week_id) ?? [];
		list.push(w);
		byWeek.set(w.week_id, list);
	}
	const raceDate = planRaceDate(plan, weeks);
	const drops = raceDate
		? sorted
				.filter(
					(w) =>
						w.week_index > current &&
						!RERUN_TAPER_PHASES.has(w.phase) &&
						!(byWeek.get(w.id) ?? []).some(holdsSomething)
				)
				.sort(
					(a, b) =>
						(DROP_RANK[a.phase] ?? 3) - (DROP_RANK[b.phase] ?? 3) || b.week_index - a.week_index
				)
		: [];
	return { current, sorted, byWeek, raceDate, drops };
}

/// Where `k` copies would leave the rest of the plan: the weeks a race plan
/// drops and the end date afterwards, or why it cannot.
export function rerunPlacement(frame: RerunFrame, plan: RaceDatePlan, k: number): RerunPlacement {
	if (frame.raceDate && k > frame.drops.length) return { ok: false, reason: 'no_room' };
	const drops = frame.raceDate ? frame.drops.slice(0, k) : [];
	const dropped = new Set(drops.map((w) => w.id));
	for (const w of frame.sorted) {
		if (w.week_index <= frame.current || dropped.has(w.id)) continue;
		const below = drops.filter((d) => d.week_index < w.week_index).length;
		if (k - below === 0) continue;
		if ((frame.byWeek.get(w.id) ?? []).some(holdsSomething)) return { ok: false, reason: 'in_the_way' };
	}
	return {
		ok: true,
		drops,
		endIso: frame.raceDate ? plan.end_date : shiftIsoDate(plan.end_date, 7 * k)
	};
}

export function repeatWeekChange(input: {
	plan: RaceDatePlan;
	weeks: RaceDateWeek[];
	workouts: RaceDateWorkout[];
	weekId: string;
	todayIso: string;
}): RepeatWeekResult {
	const { plan, weeks, workouts, weekId, todayIso } = input;
	if (plan.is_template || plan.trimmed_at || plan.status !== 'active' || weeks.length === 0) {
		return { ok: false, reason: 'not_active' };
	}
	const toToday = daysBetweenIso(plan.start_date, todayIso);
	if (toToday == null || toToday < 0 || todayIso > plan.end_date) {
		return { ok: false, reason: 'not_active' };
	}
	const current = Math.floor(toToday / 7);
	const week = weeks.find((w) => w.id === weekId);
	if (
		!week ||
		week.week_index > current ||
		week.week_index < current - 1 ||
		RERUN_TAPER_PHASES.has(week.phase)
	) {
		return { ok: false, reason: 'not_repeatable' };
	}
	const frame = rerunFrame(plan, weeks, workouts, todayIso);
	if (!frame) return { ok: false, reason: 'last_week' };
	const placed = rerunPlacement(frame, plan, 1);
	if (!placed.ok) return placed;
	const drop = placed.drops[0] ?? null;
	return {
		ok: true,
		change: {
			weekId,
			copyIndex: current + 1,
			copyStartIso: shiftIsoDate(plan.start_date, 7 * (current + 1)),
			dropWeekId: drop?.id ?? null,
			dropWeekIndex: drop?.week_index ?? null,
			endIso: placed.endIso,
			raceDateIso: frame.raceDate
		}
	};
}
