/**
 * "Too hard? Repeat this week": run this week, or the week that just finished,
 * again next week, and push every later week back one. `repeat_plan_week`
 * applies the result in one transaction and re-checks every choice.
 *
 * The copy goes in at the current week + 1, each workout on its weekday. A
 * plan that ends on a race keeps its race day: one pre-taper week that has not
 * started is dropped instead (build first, then base, then peak, the latest of
 * each first), as `change_plan_race_date` and the break reschedule drop them.
 * A plan without a race ends a week later. The taper and race weeks never run
 * again, and nothing done and no other race moves.
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

const TAPER = new Set(['taper', 'race']);
const DROP_RANK: Record<string, number> = { build: 0, base: 1, peak: 2 };

function blocks(w: RaceDateWorkout): boolean {
	return w.kind === 'race' || w.completed_run_id != null || w.manually_completed;
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
	if (!week || week.week_index > current || week.week_index < current - 1 || TAPER.has(week.phase)) {
		return { ok: false, reason: 'not_repeatable' };
	}
	const sorted = [...weeks].sort((a, b) => a.week_index - b.week_index);
	if (sorted[sorted.length - 1].week_index <= current) return { ok: false, reason: 'last_week' };

	const byWeek = new Map<string, RaceDateWorkout[]>();
	for (const w of workouts) {
		const list = byWeek.get(w.week_id) ?? [];
		list.push(w);
		byWeek.set(w.week_id, list);
	}
	const holds = (w: RaceDateWeek) => (byWeek.get(w.id) ?? []).some(blocks);

	const raceDate = planRaceDate(plan, weeks);
	let drop: RaceDateWeek | null = null;
	if (raceDate) {
		drop =
			sorted
				.filter((w) => w.week_index > current && !TAPER.has(w.phase) && !holds(w))
				.sort(
					(a, b) =>
						(DROP_RANK[a.phase] ?? 3) - (DROP_RANK[b.phase] ?? 3) || b.week_index - a.week_index
				)[0] ?? null;
		if (!drop) return { ok: false, reason: 'no_room' };
	}
	const moving = sorted.filter(
		(w) => w.week_index > current && (drop == null || w.week_index < drop.week_index)
	);
	if (moving.some(holds)) return { ok: false, reason: 'in_the_way' };

	return {
		ok: true,
		change: {
			weekId,
			copyIndex: current + 1,
			copyStartIso: shiftIsoDate(plan.start_date, 7 * (current + 1)),
			dropWeekId: drop?.id ?? null,
			dropWeekIndex: drop?.week_index ?? null,
			endIso: raceDate ? plan.end_date : shiftIsoDate(plan.end_date, 7),
			raceDateIso: raceDate
		}
	};
}
