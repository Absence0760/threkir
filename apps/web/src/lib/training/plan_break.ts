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
 * taper, anything that has started and anything done never move. The weeks
 * and drops come from `plan_repeat_week.ts`, which "Repeat this week" shares.
 */

import { daysBetweenIso } from './cycle_plan.ts';
import { shiftIsoDate } from './plan_bulk_ops.ts';
import type { RaceDatePlan, RaceDateWeek, RaceDateWorkout } from './plan_race_date.ts';
import { RERUN_TAPER_PHASES, rerunFrame, rerunPlacement, type RerunFrame } from './plan_repeat_week.ts';

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

function isDone(w: BreakWorkout): boolean {
	return w.completed_run_id != null || w.manually_completed;
}

type Shape = {
	from: string;
	days: number;
	frame: RerunFrame;
	sources: BreakWeek[];
};

function shape(input: BreakInput): Shape | null {
	const { plan, weeks, workouts, runDatesIso, todayIso } = input;
	const frame = rerunFrame(plan, weeks, workouts, todayIso);
	if (!frame) return null;

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

	const sources: BreakWeek[] = [];
	for (const w of [...frame.sorted].reverse()) {
		if (w.week_index > frame.current) continue;
		if (RERUN_TAPER_PHASES.has(w.phase)) break;
		sources.push(w);
	}
	return { from, days, frame, sources };
}

function changeFor(s: Shape, plan: BreakPlan, k: number): BreakChange | null {
	if (!Number.isInteger(k) || k < 1 || k > BREAK_MAX_WEEKS || k > s.sources.length) return null;
	const placed = rerunPlacement(s.frame, plan, k);
	if (!placed.ok) return null;
	return {
		weeks: k,
		repeatWeekIds: s.sources
			.slice(0, k)
			.reverse()
			.map((w) => w.id),
		dropWeekIds: placed.drops.map((w) => w.id).sort(),
		endIso: placed.endIso
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
	return { fromIso: s.from, days: s.days, raceDateIso: s.frame.raceDate, maxWeeks };
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

/// Whether the break offer is on screen: a break to offer that the runner has
/// not answered. While it is, a host shows neither the missed-workout prompt
/// nor the plan nudge card, and a make-up deep link only opens the plan: those
/// judge the missed weeks one workout or one week at a time, while the break
/// offer re-runs them whole.
export function breakOfferShowing(found: PlanBreak | null, dismissedPref: unknown, planId: string): boolean {
	return found != null && !isBreakDismissed(dismissedPref, planId, found.fromIso);
}

/// The days a break covered, for a judge that must not read them as missed
/// training: the break on now, from its first day to today, or else the last
/// one the runner answered in this plan (`plan_break_dismissed` with its
/// `until`). Null when there is neither.
export function breakWindow(
	found: PlanBreak | null,
	dismissedPref: unknown,
	planId: string,
	todayIso: string
): { fromIso: string; untilIso: string } | null {
	if (found) return { fromIso: found.fromIso, untilIso: todayIso };
	if (dismissedPref == null || typeof dismissedPref !== 'object' || Array.isArray(dismissedPref)) return null;
	const p = dismissedPref as Record<string, unknown>;
	if (p.plan_id !== planId || typeof p.from !== 'string' || typeof p.until !== 'string') return null;
	return { fromIso: p.from, untilIso: p.until };
}
