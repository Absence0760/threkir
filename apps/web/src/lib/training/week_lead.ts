/**
 * The dashboard's opening card for an account that has runs: how this
 * calendar week is going, what it is measured against, and the next session
 * the active plan has scheduled (#905 workstream 3).
 *
 * The week is the runner's calendar week on their `week_start` pref, the same
 * window the "This Week" stat card and `ThisWeekStrip` use, so the three never
 * disagree about what "this week" holds. Plan workouts marked done without a
 * linked run count toward it through `markedDoneTally`, the same tally the
 * stat card and the Goals section take, so a run-count goal reads the same
 * number here and on its ring (decisions § 1813).
 *
 * The yardstick is, in order: the plan's distance for the same calendar week,
 * the runner's own weekly goal (distance, then run count), and otherwise their
 * average over the weeks before this one. The plan wins over a standing goal
 * because it is written for this particular week — a taper or a cutback week
 * set against a flat weekly goal would read as falling short on purpose. A week with no activity inside the average window is a real zero,
 * but weeks before the runner's first activity are not weeks they missed, so
 * the window is shortened to their history rather than diluted by it.
 *
 * Web half of a registered parity pair with the Dart twin
 * `apps/mobile_android/lib/week_lead.dart`. Keep the algorithm, edge cases,
 * outputs, and test counts in lockstep.
 */

import type { WeekStart } from './current_week';
import { markedDoneTally, weekStartLocal, type PlanCompletion, type RunGoal } from './goals';

export interface LeadActivity {
	started_at: string;
	distance_m: number;
}

export interface LeadPlanWorkout extends PlanCompletion {
	kind: string;
	skipped_at: string | null;
}

export const RECENT_AVERAGE_WEEKS = 4;

export type WeekComparison =
	| { kind: 'plan'; targetM: number }
	| { kind: 'goal'; targetM: number }
	| { kind: 'goalRuns'; targetCount: number }
	| { kind: 'average'; averageM: number; weeks: number };

export interface WeekLead<W extends LeadPlanWorkout> {
	distanceM: number;
	count: number;
	comparison: WeekComparison | null;
	next: W | null;
	/// Whole calendar days from today to `next` — 0 is today, 1 tomorrow.
	nextInDays: number | null;
}

function localIso(d: Date): string {
	const y = d.getFullYear();
	const mo = String(d.getMonth() + 1).padStart(2, '0');
	const da = String(d.getDate()).padStart(2, '0');
	return `${y}-${mo}-${da}`;
}

function isoToEpochDay(iso: string): number {
	const [y, m, d] = iso.split('-').map((n) => parseInt(n, 10));
	return Math.floor(Date.UTC(y, m - 1, d) / 86_400_000);
}

function addDays(d: Date, days: number): Date {
	const out = new Date(d);
	out.setDate(d.getDate() + days);
	return out;
}

function isDone(w: LeadPlanWorkout): boolean {
	return w.manually_completed === true || w.completed_run_id != null;
}

export function recentWeeklyAverage(
	activities: LeadActivity[],
	thisWeekStart: Date,
	weeks: number = RECENT_AVERAGE_WEEKS,
): { averageM: number; weeks: number } | null {
	const windowStart = addDays(thisWeekStart, -7 * weeks);
	let earliest: number | null = null;
	let totalM = 0;
	for (const a of activities) {
		const t = new Date(a.started_at).getTime();
		if (Number.isNaN(t)) continue;
		if (earliest == null || t < earliest) earliest = t;
		if (t >= windowStart.getTime() && t < thisWeekStart.getTime() && a.distance_m > 0) {
			totalM += a.distance_m;
		}
	}
	if (earliest == null || earliest >= thisWeekStart.getTime()) return null;
	let span = weeks;
	while (span > 1 && earliest >= addDays(thisWeekStart, -7 * (span - 1)).getTime()) span -= 1;
	return { averageM: totalM / span, weeks: span };
}

export interface WeeklyGoalTarget {
	distanceM: number | null;
	runCount: number | null;
}

/// The week-period targets among the dashboard's goals: the first distance
/// target and the first run-count target, which need not be the same goal.
/// The dashboard's own list already drops the settings-backed weekly mileage
/// goal when the runner has a weekly distance goal of their own, so the first
/// match is the one the Goals section shows.
export function weeklyGoalTarget(goals: RunGoal[]): WeeklyGoalTarget | null {
	let distanceM: number | null = null;
	let runCount: number | null = null;
	for (const g of goals) {
		if (g.period !== 'week') continue;
		if (distanceM == null && g.distanceMetres != null && g.distanceMetres > 0) distanceM = g.distanceMetres;
		if (runCount == null && g.runCount != null && g.runCount > 0) runCount = g.runCount;
	}
	return distanceM == null && runCount == null ? null : { distanceM, runCount };
}

export function plannedDistanceForWeek(
	workouts: LeadPlanWorkout[],
	thisWeekStart: Date,
): number {
	const first = localIso(thisWeekStart);
	const last = localIso(addDays(thisWeekStart, 6));
	let total = 0;
	for (const w of workouts) {
		if (w.kind === 'rest') continue;
		if (w.scheduled_date < first || w.scheduled_date > last) continue;
		total += w.target_distance_m ?? 0;
	}
	return total;
}

export function nextPlanSession<W extends LeadPlanWorkout>(workouts: W[], todayIso: string): W | null {
	let best: W | null = null;
	for (const w of workouts) {
		if (w.kind === 'rest' || isDone(w) || w.skipped_at != null) continue;
		if (w.scheduled_date < todayIso) continue;
		if (best == null || w.scheduled_date < best.scheduled_date) best = w;
	}
	return best;
}

export function weekLead<W extends LeadPlanWorkout>(input: {
	activities: LeadActivity[];
	planWorkouts: W[] | null;
	weeklyGoal?: WeeklyGoalTarget | null;
	weekStart: WeekStart;
	now: Date;
}): WeekLead<W> {
	const start = weekStartLocal(input.now, input.weekStart);
	const todayIso = localIso(input.now);

	let distanceM = 0;
	let count = 0;
	for (const a of input.activities) {
		const t = new Date(a.started_at).getTime();
		if (Number.isNaN(t) || t < start.getTime()) continue;
		distanceM += a.distance_m > 0 ? a.distance_m : 0;
		count += 1;
	}

	const workouts = input.planWorkouts ?? [];
	const marked = markedDoneTally(workouts, start, input.now);
	distanceM += marked.distanceM;
	count += marked.count;

	let comparison: WeekComparison | null = null;
	const planned = input.planWorkouts ? plannedDistanceForWeek(workouts, start) : 0;
	const goal = input.weeklyGoal ?? null;
	if (planned > 0) {
		comparison = { kind: 'plan', targetM: planned };
	} else if (goal?.distanceM != null && goal.distanceM > 0) {
		comparison = { kind: 'goal', targetM: goal.distanceM };
	} else if (goal?.runCount != null && goal.runCount > 0) {
		comparison = { kind: 'goalRuns', targetCount: goal.runCount };
	} else {
		const avg = recentWeeklyAverage(input.activities, start);
		if (avg && avg.averageM > 0) comparison = { kind: 'average', ...avg };
	}

	const next = input.planWorkouts ? nextPlanSession(workouts, todayIso) : null;
	const nextInDays = next ? isoToEpochDay(next.scheduled_date) - isoToEpochDay(todayIso) : null;

	return { distanceM, count, comparison, next, nextInDays };
}
