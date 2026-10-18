/**
 * A break of a week or more inside an active plan: whether the runner is on
 * one, and what re-running the missed weeks would change.
 * `reschedule_plan_after_break` applies a change in one transaction and
 * re-checks every choice.
 *
 * A break is BREAK_MIN_DAYS or more of the runner's local days, up to
 * yesterday, with no run of any kind and no plan workout done. A run today
 * does not end it, so the offer is still there on the day the runner comes
 * back.
 *
 * The change runs the latest `weeks` weeks up to the current one again, from
 * next week, and everything after them moves back by that many whole weeks.
 * A plan that ends on a race keeps its race day: the same number of pre-taper
 * weeks that have not started are dropped (build first, then base, then peak,
 * the latest of each first), as `change_plan_race_date` drops them. The
 * taper, anything that has started and anything done never move.
 */

import { daysBetweenIso } from './cycle_plan.ts';
import { shiftIsoDate } from './plan_bulk_ops.ts';
import {
	planRaceDate,
	type RaceDatePlan,
	type RaceDateWeek,
	type RaceDateWorkout
} from './plan_race_date.ts';

export const BREAK_MIN_DAYS = 7;
export const BREAK_MAX_WEEKS = 52;

export type BreakPlan = RaceDatePlan;
export type BreakWeek = RaceDateWeek;
export type BreakWorkout = RaceDateWorkout;

export type BreakInput = {
	plan: BreakPlan;
	weeks: BreakWeek[];
	workouts: BreakWorkout[];
	/// The runner's local dates of their latest runs; any order, any count.
	runDatesIso: string[];
	todayIso: string;
};

export type PlanBreak = {
	/// The first day of the break.
	fromIso: string;
	/// Days without a run or a done workout, today not counted.
	days: number;
	/// The race day the plan keeps, or null for a plan without one.
	raceDateIso: string | null;
	/// The most weeks a change can run again; at least 1.
	maxWeeks: number;
};

export type BreakChange = {
	weeks: number;
	/// The weeks run again, oldest first; copies go in at the current week + 1.
	repeatWeekIds: string[];
	dropWeekIds: string[];
	endIso: string;
};

const TAPER = new Set(['taper', 'race']);
const DROP_RANK: Record<string, number> = { build: 0, base: 1, peak: 2 };

function isDone(w: BreakWorkout): boolean {
	return w.completed_run_id != null || w.manually_completed;
}

type Shape = {
	from: string;
	days: number;
	current: number;
	raceDate: string | null;
	sources: BreakWeek[];
	drops: BreakWeek[];
	sorted: BreakWeek[];
	byWeek: Map<string, BreakWorkout[]>;
};

function shape(input: BreakInput): Shape | null {
	const { plan, weeks, workouts, runDatesIso, todayIso } = input;
	if (plan.is_template || plan.trimmed_at || plan.status !== 'active') return null;
	if (weeks.length === 0 || todayIso > plan.end_date) return null;
	const toToday = daysBetweenIso(plan.start_date, todayIso);
	if (toToday == null || toToday < 0) return null;
	const current = Math.floor(toToday / 7);
	const sorted = [...weeks].sort((a, b) => a.week_index - b.week_index);
	if (sorted[sorted.length - 1].week_index <= current) return null;

	let last: string | null = null;
	for (const d of runDatesIso) if (d < todayIso && (last == null || d > last)) last = d;
	for (const w of workouts) {
		if (isDone(w) && w.scheduled_date < todayIso && (last == null || w.scheduled_date > last)) {
			last = w.scheduled_date;
		}
	}
	const afterLast = last == null ? plan.start_date : shiftIsoDate(last, 1);
	const from = afterLast > plan.start_date ? afterLast : plan.start_date;
	const days = daysBetweenIso(from, todayIso);
	if (days == null || days < BREAK_MIN_DAYS) return null;
	if (!workouts.some((w) => w.kind !== 'rest' && w.scheduled_date >= from && w.scheduled_date < todayIso)) {
		return null;
	}

	const byWeek = new Map<string, BreakWorkout[]>();
	for (const w of workouts) {
		const list = byWeek.get(w.week_id) ?? [];
		list.push(w);
		byWeek.set(w.week_id, list);
	}
	const of = (week: BreakWeek) => byWeek.get(week.id) ?? [];

	const sources: BreakWeek[] = [];
	for (const w of [...sorted].reverse()) {
		if (w.week_index > current) continue;
		if (TAPER.has(w.phase)) break;
		sources.push(w);
	}
	const raceDate = planRaceDate(plan, weeks);
	const drops = raceDate
		? sorted
				.filter(
					(w) =>
						w.week_index > current &&
						!TAPER.has(w.phase) &&
						!of(w).some((x) => x.kind === 'race' || isDone(x))
				)
				.sort(
					(a, b) =>
						(DROP_RANK[a.phase] ?? 3) - (DROP_RANK[b.phase] ?? 3) || b.week_index - a.week_index
				)
		: [];
	return { from, days, current, raceDate, sources, drops, sorted, byWeek };
}

function changeFor(s: Shape, plan: BreakPlan, k: number): BreakChange | null {
	if (!Number.isInteger(k) || k < 1 || k > BREAK_MAX_WEEKS || k > s.sources.length) return null;
	if (s.raceDate && k > s.drops.length) return null;
	const drop = s.raceDate ? s.drops.slice(0, k) : [];
	const dropped = new Set(drop.map((w) => w.id));
	for (const w of s.sorted) {
		if (w.week_index <= s.current || dropped.has(w.id)) continue;
		const below = drop.filter((d) => d.week_index < w.week_index).length;
		if (k - below === 0) continue;
		if ((s.byWeek.get(w.id) ?? []).some((x) => x.kind === 'race' || isDone(x))) return null;
	}
	return {
		weeks: k,
		repeatWeekIds: s.sources
			.slice(0, k)
			.reverse()
			.map((w) => w.id),
		dropWeekIds: drop.map((w) => w.id).sort(),
		endIso: s.raceDate ? plan.end_date : shiftIsoDate(plan.end_date, 7 * k)
	};
}

/// The break the runner is on, or null when there is none to offer anything
/// for: not an active plan of their own, the plan has not started or has no
/// week after this one, fewer than BREAK_MIN_DAYS quiet days, no planned
/// workout fell in them, or no change can keep the taper and the race day.
export function detectPlanBreak(input: BreakInput): PlanBreak | null {
	const s = shape(input);
	if (!s) return null;
	const cap = Math.min(Math.floor(s.days / 7), BREAK_MAX_WEEKS);
	let maxWeeks = 0;
	while (maxWeeks < cap && changeFor(s, input.plan, maxWeeks + 1)) maxWeeks++;
	if (maxWeeks < 1) return null;
	return { fromIso: s.from, days: s.days, raceDateIso: s.raceDate, maxWeeks };
}

/// What running the latest `weeks` weeks again would change, or null when
/// there is no break or `weeks` is outside 1..maxWeeks.
export function planBreakChange(input: BreakInput, weeks: number): BreakChange | null {
	const found = detectPlanBreak(input);
	if (!found || weeks > found.maxWeeks) return null;
	const s = shape(input);
	return s ? changeFor(s, input.plan, weeks) : null;
}

/// Whether `user_settings.prefs.plan_break_dismissed` already answers this
/// break: the same plan and the same first day. A later break, or one in
/// another plan, is offered again; anything unreadable is not an answer.
export function isBreakDismissed(pref: unknown, planId: string, fromIso: string): boolean {
	if (pref == null || typeof pref !== 'object' || Array.isArray(pref)) return false;
	const p = pref as Record<string, unknown>;
	return p.plan_id === planId && p.from === fromIso;
}
