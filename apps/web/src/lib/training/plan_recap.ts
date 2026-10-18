// The end-of-plan recap (issue #1186): what the block added up to, read off the
// plan, its workouts and the runner's runs and records inside its window, and
// what comes after it. Pure: every date is a local `yyyy-mm-dd` the caller has
// already put in the runner's zone, so nothing here reads a clock or a zone.
//
// Dart twin: `apps/mobile_android/lib/plan_recap.dart`.

import { shiftIsoDate } from './plan_bulk_ops.ts';
import { isWorkoutMissed } from './plan_current.ts';
import { longestCompletedLongRunMetres, planDistanceBanked, planWorkoutProgress } from './plan_progress.ts';
import { planRaces, type PlanRace, type RacePriority } from './plan_races.ts';
import { isWalkRunPlan } from './plan_restart.ts';
import { defaultPlanStartIso, nextSundayIso } from './plan_start.ts';
import { isPlausibleRecent5k, RECENT_5K_WINDOW_DAYS } from './recent_5k_suggestion.ts';
import { seasonRecoveryDays } from './season_plan.ts';
import { vdotFromRace } from './training.ts';

/// The share of a race's distance a run on race day must cover to stand for a
/// race the plan has no workout row for: the run-to-workout matcher's own
/// lower bound (decisions § 2079), so a shakeout jog is never read as the race.
export const RECAP_RACE_RUN_MIN_SHARE = 0.75;

/// The distances Daniels' VDOT formula is calibrated over: 1500 m to the
/// marathon, with 5% of headroom for a GPS trace that over-measures the
/// course. An ultra's time says nothing about a 5K, so it seeds no plan.
export const RECAP_VDOT_MIN_M = 1500;
export const RECAP_VDOT_MAX_M = 42_195 * 1.05;

export interface RecapPlan {
	start_date: string;
	end_date: string;
	goal_distance_m: number;
	goal_time_seconds: number | null;
	trimmed_at: string | null;
}

export interface RecapWorkout {
	id: string;
	scheduled_date: string;
	kind: string;
	target_distance_m: number | null;
	target_duration_seconds: number | null;
	completed_run_id?: string | null;
	manually_completed?: boolean | null;
	skipped_at?: string | null;
	missed_ack_at?: string | null;
	race_name?: string | null;
	race_priority?: string | null;
}

export interface PlanRecapRun {
	id: string;
	/// The local day the run started on.
	date: string;
	distanceM: number | null;
	durationS: number | null;
	activityType: string | null;
	isDnf: boolean | null;
}

/// A `personal_records` row: the best time the runner holds for a bracket.
export interface PlanRecapRecord {
	distance: string;
	timeS: number;
	/// The local day the record was set.
	date: string;
	runId: string | null;
}

export interface PlanRecapInput {
	plan: RecapPlan;
	workouts: RecapWorkout[];
	/// The runner's runs around the plan window; linked runs are found by id.
	runs: PlanRecapRun[];
	records: PlanRecapRecord[];
	todayIso: string;
}

export type RecapVolumeBasis = 'distance' | 'time';

export interface PlanRecapRaceRun {
	id: string;
	distanceM: number | null;
	durationS: number | null;
	isDnf: boolean;
}

export interface RecapRace {
	date: string;
	name: string | null;
	priority: RacePriority;
	distanceM: number | null;
	goalTimeSec: number | null;
	run: PlanRecapRaceRun | null;
	/// The race was run: a run stands for it, or its workout was ticked done.
	raced: boolean;
	/// VDOT of the race run, one decimal. Null for a DNF, a non-run, a distance
	/// outside the formula's range or a run with no time.
	vdot: number | null;
}

export interface RecapNext {
	/// Easy days still owed to the race, through `untilIso`. Null when nothing
	/// was raced or the recovery is already behind the runner.
	recovery: { days: number; untilIso: string } | null;
	/// The Sunday the next plan should start: the wizard's default, or the
	/// first Sunday after the recovery when that is later.
	startIso: string;
	/// The 5K time at the race's VDOT, to seed the next plan's paces with. Null
	/// without a VDOT, when the race is older than the recent-5K window, or when
	/// the time falls outside what the wizard's field takes.
	seed5kSec: number | null;
}

export interface RecapLongRuns {
	/// Long runs done, of those still on the books (skipped ones leave both).
	done: number;
	planned: number;
	/// The earliest-dated long run done, and the longest: the block's
	/// progression. Each is the linked run's distance, else the target.
	first: number | null;
	longest: number | null;
}

export interface PlanRecap {
	/// The ring's counts (`planWorkoutProgress`), plus the sessions it leaves
	/// out (skipped) and the ones it counts as not done whose day has passed
	/// (missed). An answered miss is still missed: answering it changes the
	/// plan ahead, not what was run.
	sessions: { completed: number; total: number; pct: number; skipped: number; missed: number };
	volume: { basis: RecapVolumeBasis; done: number; planned: number };
	longRuns: RecapLongRuns;
	records: PlanRecapRecord[];
	race: RecapRace | null;
	next: RecapNext;
}

/// The race the plan was built toward: the one on its end date, else its last
/// A race, else its last race. Expects `races` sorted, as `planRaces` returns.
export function recapGoalRace(races: PlanRace[], endDate: string): PlanRace | null {
	const onEnd = races.filter((r) => r.date === endDate);
	if (onEnd.length > 0) return onEnd[onEnd.length - 1];
	const a = races.filter((r) => r.priority === 'A');
	if (a.length > 0) return a[a.length - 1];
	return races.length > 0 ? races[races.length - 1] : null;
}

function isRunFamily(activityType: string | null): boolean {
	return activityType !== 'cycle';
}

function toRaceRun(r: PlanRecapRun): PlanRecapRaceRun {
	return { id: r.id, distanceM: r.distanceM, durationS: r.durationS, isDnf: r.isDnf === true };
}

/// The run that stands for the race. A race with a workout row answers with
/// that row's link and nothing else: the matcher already put the closest run
/// on it, and an unlinked race workout is one the runner did not race or took
/// a run off. A race the plan has no row for (the plan's goal on its end
/// date) takes the longest run-family run that day covering at least
/// `RECAP_RACE_RUN_MIN_SHARE` of its distance.
export function recapRaceRun(
	race: PlanRace,
	workouts: RecapWorkout[],
	runs: PlanRecapRun[],
): PlanRecapRaceRun | null {
	if (race.workoutId != null) {
		const w = workouts.find((x) => x.id === race.workoutId);
		const runId = w?.completed_run_id;
		if (runId == null) return null;
		const run = runs.find((r) => r.id === runId);
		return run ? toRaceRun(run) : null;
	}
	const floor = race.distanceM != null && race.distanceM > 0 ? race.distanceM * RECAP_RACE_RUN_MIN_SHARE : 0;
	let best: PlanRecapRun | null = null;
	for (const r of runs) {
		if (r.date !== race.date || !isRunFamily(r.activityType)) continue;
		const d = r.distanceM ?? 0;
		if (!(d > 0) || d < floor) continue;
		if (best === null || d > (best.distanceM ?? 0) || (d === best.distanceM && r.id < best.id)) best = r;
	}
	return best ? toRaceRun(best) : null;
}

/// VDOT of a race run, rounded to one decimal, or null when the formula does
/// not apply to it.
export function recapRaceVdot(run: PlanRecapRaceRun | null, activityType: string | null): number | null {
	if (run === null || run.isDnf) return null;
	if (activityType != null && activityType !== 'run') return null;
	const d = run.distanceM ?? 0;
	const t = run.durationS ?? 0;
	if (!(t > 0) || d < RECAP_VDOT_MIN_M || d > RECAP_VDOT_MAX_M) return null;
	const v = vdotFromRace(d, t);
	return Number.isFinite(v) && v > 0 ? Math.round(v * 10) / 10 : null;
}

/// The 5K time, in whole seconds, that `vdotFromRace` rates at `vdot`. Found
/// by bisection: the formula falls as the time grows, and has no closed form.
export function fiveKSecondsAtVdot(vdot: number): number | null {
	if (!Number.isFinite(vdot) || vdot <= 0) return null;
	let lo = 60;
	let hi = 4 * 60 * 60;
	if (vdotFromRace(5000, lo) < vdot || vdotFromRace(5000, hi) > vdot) return null;
	while (hi - lo > 1) {
		const mid = Math.floor((lo + hi) / 2);
		if (vdotFromRace(5000, mid) > vdot) lo = mid;
		else hi = mid;
	}
	return vdotFromRace(5000, lo) - vdot < vdot - vdotFromRace(5000, hi) ? lo : hi;
}

function longRunProgression(workouts: RecapWorkout[], distanceById: Map<string, number>): RecapLongRuns {
	let done = 0;
	let planned = 0;
	let firstDate: string | null = null;
	let first: number | null = null;
	for (const w of workouts) {
		if (w.kind !== 'long' || w.skipped_at != null) continue;
		planned += 1;
		if (w.manually_completed !== true && w.completed_run_id == null) continue;
		done += 1;
		const actual = w.completed_run_id != null ? distanceById.get(w.completed_run_id) : undefined;
		const d = actual != null && actual > 0 ? actual : (w.target_distance_m ?? 0);
		if (d > 0 && (firstDate === null || w.scheduled_date < firstDate)) {
			firstDate = w.scheduled_date;
			first = d;
		}
	}
	return { done, planned, first, longest: longestCompletedLongRunMetres(workouts, distanceById) };
}

function timeBanked(workouts: RecapWorkout[], durationById: Map<string, number>) {
	let done = 0;
	let planned = 0;
	for (const w of workouts) {
		if (w.kind === 'rest') continue;
		const target = w.target_duration_seconds ?? 0;
		if (w.skipped_at == null) planned += target;
		if (w.manually_completed === true || w.completed_run_id != null) {
			const actual = w.completed_run_id != null ? durationById.get(w.completed_run_id) : undefined;
			done += actual != null && actual > 0 ? actual : target;
		}
	}
	return { done, planned };
}

/// Assemble the recap. Sessions and distance reuse the plan page's own counts
/// (`planWorkoutProgress`, `planDistanceBanked`), so the recap never disagrees
/// with the ring above it; a walk-run plan, whose sessions are timed, reports
/// time instead of distance. Records are the `personal_records` rows set
/// inside the plan window — the cache holds only the best per bracket, so a
/// record set during the plan and beaten since is not listed.
export function assemblePlanRecap(input: PlanRecapInput): PlanRecap {
	const { plan, workouts, runs, records, todayIso } = input;

	const progress = planWorkoutProgress(workouts);
	let skipped = 0;
	let missed = 0;
	for (const w of workouts) {
		if (w.kind !== 'rest' && w.skipped_at != null) skipped += 1;
		const completed = w.manually_completed === true || w.completed_run_id != null;
		if (isWorkoutMissed({ ...w, completed, skipped: w.skipped_at != null }, todayIso)) missed += 1;
	}

	const distanceById = new Map<string, number>();
	const durationById = new Map<string, number>();
	for (const r of runs) {
		if (r.distanceM != null) distanceById.set(r.id, r.distanceM);
		if (r.durationS != null) durationById.set(r.id, r.durationS);
	}
	let volume: PlanRecap['volume'];
	if (isWalkRunPlan(workouts)) {
		volume = { basis: 'time', ...timeBanked(workouts, durationById) };
	} else {
		const d = planDistanceBanked(workouts, distanceById);
		volume = { basis: 'distance', done: d.completedMetres, planned: d.plannedMetres };
	}

	const inWindow = records
		.filter((r) => r.date >= plan.start_date && r.date <= plan.end_date)
		.sort((a, b) => (a.date !== b.date ? (a.date < b.date ? -1 : 1) : a.distance < b.distance ? -1 : a.distance > b.distance ? 1 : 0));

	const goal = recapGoalRace(planRaces(plan, [...workouts]), plan.end_date);
	let race: RecapRace | null = null;
	if (goal !== null) {
		const run = recapRaceRun(goal, workouts, runs);
		const runRow = run ? runs.find((r) => r.id === run.id) : undefined;
		const workout = goal.workoutId != null ? workouts.find((w) => w.id === goal.workoutId) : undefined;
		race = {
			date: goal.date,
			name: goal.name,
			priority: goal.priority,
			distanceM: goal.distanceM,
			goalTimeSec: goal.goalTimeSec,
			run,
			raced: run !== null || workout?.manually_completed === true,
			vdot: recapRaceVdot(run, runRow?.activityType ?? null),
		};
	}

	const defaultStart = defaultPlanStartIso(todayIso, false);
	let recovery: RecapNext['recovery'] = null;
	if (race !== null && race.raced && race.date <= todayIso) {
		const raced = race.run?.distanceM != null && race.run.distanceM > 0 ? race.run.distanceM : (race.distanceM ?? plan.goal_distance_m);
		const days = seasonRecoveryDays(raced);
		const untilIso = shiftIsoDate(race.date, days);
		if (untilIso >= todayIso) recovery = { days, untilIso };
	}
	const afterRecovery = recovery ? nextSundayIso(shiftIsoDate(recovery.untilIso, 1)) : defaultStart;
	const startIso = afterRecovery > defaultStart ? afterRecovery : defaultStart;

	let seed5kSec: number | null = null;
	if (race?.vdot != null && race.date <= todayIso && race.date >= shiftIsoDate(todayIso, -RECENT_5K_WINDOW_DAYS)) {
		const s = fiveKSecondsAtVdot(race.vdot);
		if (isPlausibleRecent5k(s)) seed5kSec = s;
	}

	return {
		sessions: { ...progress, skipped, missed },
		volume,
		longRuns: longRunProgression(workouts, distanceById),
		records: inWindow,
		race,
		next: { recovery, startIso, seed5kSec },
	};
}
