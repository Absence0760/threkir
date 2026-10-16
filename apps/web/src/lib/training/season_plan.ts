// The season builder (issue #1181): a confirmed race list becomes one plan
// per A race, chained back to back with a recovery gap after each A race, and
// every B / C race written as a race workout into the plan whose window holds
// it. The generator still authors every training workout (decisions § 12,
// § 1930); this only sizes the windows and places the races.
//
// Dart twin `apps/mobile_android/lib/season_plan.dart` (parity pair: keep the
// rules, constants, refusals and test counts in lockstep).
//
// Dates are whole UTC epoch-days, as in `race_plan_preset.ts`, so a window that
// crosses a DST change is never a day short.

import {
	GOAL_DISTANCES_M,
	defaultPlanWeeks,
	generatePlan,
	type GeneratedPlan,
	type GeneratedWorkout,
	type GoalEvent,
	type TrainingGender,
} from './training';
import { RACE_PLAN_MIN_WEEKS, goalEventForDistance } from './race_plan_preset';
import type { SeasonRace, SeasonRacePriority } from './season_types';

/// The longest plan the season builder writes: the wizard's own `max` on the
/// week field. A gap longer than this between two A races leaves unplanned
/// weeks before the later plan rather than a block the generator was never
/// tuned for.
export const SEASON_MAX_PLAN_WEEKS = 24;
/// A race name becomes both the plan's name (`training_plans.name`, 80 chars)
/// and its race workout's `race_name` (120), so the tighter cap holds.
export const SEASON_RACE_NAME_MAX = 80;
/// Recovery after an A race before the next plan starts: one day per 3 km
/// raced, held to 3–28 days. That is half the density of the "a day per mile
/// raced" rule, because the next plan opens with its base phase (easy volume
/// at 0.6x peak) and so carries the back half of the recovery itself; it
/// lands where the published guidance does, a week after a half, two after a
/// marathon and two to four after an ultra (decisions § 2051 uses the same
/// per-3-km density for a B race's recovery inside a plan).
export const SEASON_RECOVERY_KM_PER_DAY = 3;
export const SEASON_RECOVERY_MIN_DAYS = 3;
export const SEASON_RECOVERY_MAX_DAYS = 28;

export type SeasonRefusal =
	/// No races to plan.
	| 'empty'
	/// A race has no name, a name over SEASON_RACE_NAME_MAX, an unusable date,
	/// a distance that is not positive or a goal time that is not.
	| 'invalid_race'
	/// A race is today or already past.
	| 'race_not_ahead'
	/// No race is marked A. Which race the season peaks for is the runner's
	/// call, so the builder does not promote one.
	| 'no_a_race'
	/// The first A race is fewer than RACE_PLAN_MIN_WEEKS weeks away.
	| 'first_too_soon'
	/// Two A races sit too close for the recovery after the first and a
	/// minimum-length plan before the second.
	| 'a_races_too_close';

/// Why a B / C race is in no plan. Plans never overlap and each ends on its A
/// race, so a race in a recovery gap or outside the season has no plan to
/// join without moving one; it is reported rather than silently dropped.
export type SeasonUnplacedReason =
	| 'before_first_plan'
	| 'between_plans'
	| 'after_last_plan'
	/// Same day as a race already placed in that plan.
	| 'same_day';

export interface SeasonPlanDraft {
	/// The plan name: the A race's name.
	name: string;
	race: SeasonRace;
	goalEvent: GoalEvent;
	goalDistanceM: number;
	goalTimeSec: number | null;
	/// ISO `yyyy-mm-dd`, always a Sunday (the generator's day 0 is the long run).
	startDate: string;
	/// The A race's date.
	endDate: string;
	weeks: number;
	daysPerWeek: number;
	/// The B / C races written into this plan, by date.
	races: SeasonRace[];
	/// What `createTrainingPlan` writes: `endDate` is the A race and every
	/// race is a `race` workout on its own date.
	generated: GeneratedPlan;
}

export interface SeasonGap {
	/// The A race the gap follows.
	afterRace: string;
	/// First and last day of the gap, ISO.
	from: string;
	to: string;
	days: number;
	/// What `seasonRecoveryDays` asked for; `days` is at least this, more when
	/// the next plan snaps to a Sunday or is capped at SEASON_MAX_PLAN_WEEKS.
	recoveryDays: number;
}

export interface SeasonUnplaced {
	race: SeasonRace;
	reason: SeasonUnplacedReason;
}

export type SeasonBuildResult =
	| { ok: true; plans: SeasonPlanDraft[]; gaps: SeasonGap[]; unplaced: SeasonUnplaced[] }
	| { ok: false; reason: SeasonRefusal; races: string[] };

export interface SeasonBuildInput {
	races: SeasonRace[];
	todayIso: string;
	daysPerWeek: number;
	recent5kSec?: number | null;
	gender?: TrainingGender;
	age?: number | null;
}

const ISO_DATE = /^\d{4}-\d{2}-\d{2}$/;
const PRIORITIES: readonly SeasonRacePriority[] = ['A', 'B', 'C'];

function epochDay(iso: string): number | null {
	if (!ISO_DATE.test(iso)) return null;
	const [y, m, d] = iso.split('-').map(Number);
	const ms = Date.UTC(y, m - 1, d);
	const back = new Date(ms);
	if (back.getUTCFullYear() !== y || back.getUTCMonth() !== m - 1 || back.getUTCDate() !== d) {
		return null;
	}
	return Math.floor(ms / 86_400_000);
}

function isoFromEpochDay(day: number): string {
	const d = new Date(day * 86_400_000);
	const pad = (n: number) => String(n).padStart(2, '0');
	return `${d.getUTCFullYear()}-${pad(d.getUTCMonth() + 1)}-${pad(d.getUTCDate())}`;
}

/// 0 = Sunday; epoch day 0 was a Thursday.
function dayOfWeek(day: number): number {
	return (((day + 4) % 7) + 7) % 7;
}

function sundayOnOrAfter(day: number): number {
	return day + ((7 - dayOfWeek(day)) % 7);
}

/// Days of recovery after an A race of `distanceM` before the next plan starts.
export function seasonRecoveryDays(distanceM: number): number {
	const days = Math.round(distanceM / 1000 / SEASON_RECOVERY_KM_PER_DAY);
	return Math.min(SEASON_RECOVERY_MAX_DAYS, Math.max(SEASON_RECOVERY_MIN_DAYS, days));
}

/// The generator goal for a race distance: a standard event when the distance
/// matches one within `goalEventForDistance`'s tolerance, else a custom goal at
/// the race's own distance.
export function seasonGoal(distanceM: number): { goalEvent: GoalEvent; goalDistanceM: number } {
	const event = goalEventForDistance(distanceM);
	if (event && event !== 'custom') {
		return { goalEvent: event, goalDistanceM: GOAL_DISTANCES_M[event] };
	}
	return { goalEvent: 'custom', goalDistanceM: distanceM };
}

function raceIsValid(r: SeasonRace): boolean {
	const name = r.name.trim();
	return (
		name.length > 0 &&
		name.length <= SEASON_RACE_NAME_MAX &&
		epochDay(r.date) !== null &&
		Number.isFinite(r.distanceM) &&
		r.distanceM > 0 &&
		PRIORITIES.includes(r.priority) &&
		(r.goalTimeSec === null || (Number.isInteger(r.goalTimeSec) && r.goalTimeSec > 0))
	);
}

function byDate(a: SeasonRace, b: SeasonRace): number {
	if (a.date !== b.date) return a.date < b.date ? -1 : 1;
	return a.name < b.name ? -1 : a.name > b.name ? 1 : 0;
}

function raceWorkout(date: string, race: SeasonRace, distanceM: number, pace: number | null): GeneratedWorkout {
	return {
		scheduled_date: date,
		kind: 'race',
		target_distance_m: distanceM,
		target_duration_seconds: race.goalTimeSec,
		target_pace_sec_per_km: pace,
		target_pace_tolerance_sec: pace === null ? null : 5,
		structure: null,
		notes: null,
		race_name: race.name.trim(),
		race_priority: race.priority,
	};
}

function restWorkout(date: string): GeneratedWorkout {
	return {
		scheduled_date: date,
		kind: 'rest',
		target_distance_m: null,
		target_duration_seconds: null,
		target_pace_sec_per_km: null,
		target_pace_tolerance_sec: null,
		structure: null,
		notes: null,
	};
}

/// Puts `workout` on its date, replacing whatever the generator put there.
function placeWorkout(plan: GeneratedPlan, workout: GeneratedWorkout): void {
	for (const week of plan.weeks) {
		const i = week.workouts.findIndex((w) => w.scheduled_date === workout.scheduled_date);
		if (i >= 0) {
			week.workouts[i] = workout;
			return;
		}
	}
	const target =
		[...plan.weeks].reverse().find((w) => (w.workouts[0]?.scheduled_date ?? '') <= workout.scheduled_date) ??
		plan.weeks[0];
	target.workouts.push(workout);
	target.workouts.sort((a, b) => (a.scheduled_date < b.scheduled_date ? -1 : a.scheduled_date > b.scheduled_date ? 1 : 0));
}

/// Ends the generated plan on the A race: the race workout moves from the race
/// week's Sunday to race day (the Sunday slot it leaves becomes rest), and the
/// days after race day are dropped.
function fitToARace(plan: GeneratedPlan, race: SeasonRace, goalDistanceM: number): void {
	let pace: number | null = null;
	for (const week of plan.weeks) {
		week.workouts = week.workouts
			.filter((w) => w.scheduled_date <= race.date)
			.map((w) => {
				if (w.kind !== 'race') return w;
				pace = w.target_pace_sec_per_km;
				return restWorkout(w.scheduled_date);
			});
	}
	plan.weeks = plan.weeks.filter((w) => w.workouts.length > 0);
	placeWorkout(plan, raceWorkout(race.date, race, goalDistanceM, pace));
	plan.endDate = race.date;
}

function restateVolumes(plan: GeneratedPlan): void {
	for (const week of plan.weeks) {
		week.target_volume_m = week.workouts.reduce((s, w) => s + (w.target_distance_m ?? 0), 0);
	}
}

export function buildSeason(input: SeasonBuildInput): SeasonBuildResult {
	if (input.races.length === 0) return { ok: false, reason: 'empty', races: [] };
	const invalid = input.races.filter((r) => !raceIsValid(r));
	if (invalid.length > 0) {
		return { ok: false, reason: 'invalid_race', races: invalid.map((r) => r.name.trim()) };
	}
	const today = epochDay(input.todayIso);
	if (today === null) return { ok: false, reason: 'invalid_race', races: [] };
	const past = input.races.filter((r) => epochDay(r.date)! <= today);
	if (past.length > 0) {
		return { ok: false, reason: 'race_not_ahead', races: past.map((r) => r.name.trim()) };
	}

	const sorted = [...input.races].sort(byDate);
	const aRaces = sorted.filter((r) => r.priority === 'A');
	if (aRaces.length === 0) return { ok: false, reason: 'no_a_race', races: [] };

	const plans: SeasonPlanDraft[] = [];
	const gaps: SeasonGap[] = [];
	for (let i = 0; i < aRaces.length; i++) {
		const race = aRaces[i];
		const raceDay = epochDay(race.date)!;
		const prev = i > 0 ? aRaces[i - 1] : null;
		const recovery = prev ? seasonRecoveryDays(prev.distanceM) : 0;
		const earliest = prev
			? sundayOnOrAfter(epochDay(prev.date)! + 1 + recovery)
			: sundayOnOrAfter(today);
		const raceWeekStart = raceDay - dayOfWeek(raceDay);
		const available = Math.floor((raceWeekStart - earliest) / 7) + 1;
		if (available < RACE_PLAN_MIN_WEEKS) {
			return prev
				? { ok: false, reason: 'a_races_too_close', races: [prev.name.trim(), race.name.trim()] }
				: { ok: false, reason: 'first_too_soon', races: [race.name.trim()] };
		}
		const { goalEvent, goalDistanceM } = seasonGoal(race.distanceM);
		// The first plan takes the goal's usual length and starts later rather
		// than earlier, as a single race plan does (`racePlanPreset`); a later
		// plan fills the gap from the end of recovery, so the season has no
		// unplanned weeks between its blocks.
		const cap = prev ? SEASON_MAX_PLAN_WEEKS : Math.min(SEASON_MAX_PLAN_WEEKS, defaultPlanWeeks(goalEvent));
		const weeks = Math.min(available, cap);
		const start = raceWeekStart - (weeks - 1) * 7;
		const generated = generatePlan({
			goalEvent,
			goalDistanceM,
			goalTimeSec: race.goalTimeSec,
			recent5kSec: input.recent5kSec ?? null,
			startDate: isoFromEpochDay(start),
			daysPerWeek: input.daysPerWeek,
			weeks,
			gender: input.gender ?? null,
			age: input.age ?? null,
		});
		fitToARace(generated, race, goalDistanceM);
		plans.push({
			name: race.name.trim(),
			race,
			goalEvent,
			goalDistanceM,
			goalTimeSec: race.goalTimeSec,
			startDate: isoFromEpochDay(start),
			endDate: race.date,
			weeks,
			daysPerWeek: input.daysPerWeek,
			races: [],
			generated,
		});
		if (prev) {
			const prevDay = epochDay(prev.date)!;
			gaps.push({
				afterRace: prev.name.trim(),
				from: isoFromEpochDay(prevDay + 1),
				to: isoFromEpochDay(start - 1),
				days: start - prevDay - 1,
				recoveryDays: recovery,
			});
		}
	}

	const unplaced: SeasonUnplaced[] = [];
	for (const race of sorted) {
		if (race.priority === 'A') continue;
		const plan = plans.find((p) => p.startDate <= race.date && race.date <= p.endDate);
		if (!plan) {
			const reason: SeasonUnplacedReason =
				race.date < plans[0].startDate
					? 'before_first_plan'
					: race.date > plans[plans.length - 1].endDate
						? 'after_last_plan'
						: 'between_plans';
			unplaced.push({ race, reason });
			continue;
		}
		if (race.date === plan.endDate || plan.races.some((r) => r.date === race.date)) {
			unplaced.push({ race, reason: 'same_day' });
			continue;
		}
		const pace = race.goalTimeSec === null ? null : Math.round(race.goalTimeSec / (race.distanceM / 1000));
		placeWorkout(plan.generated, raceWorkout(race.date, race, race.distanceM, pace));
		plan.races.push(race);
	}
	for (const plan of plans) restateVolumes(plan.generated);
	return { ok: true, plans, gaps, unplaced };
}
