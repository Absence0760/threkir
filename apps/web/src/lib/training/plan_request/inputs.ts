// Pure validation + clamping for the AI plan-request wizard inputs.
//
// The AI is the interface, never the planner. The model only extracts what
// the runner typed into the same handful of fields the plan wizard already
// asks for; the deterministic generator (`generatePlan` in training.ts) builds
// every workout and every week's volume, and the wizard's ramp check grades
// the result as it does for a hand-filled form. That is the safety line
// decisions.md §12 drew — LLM-authored plans prescribe dangerous ramps and
// stacked hard days the runner cannot spot — and it holds here unchanged: the
// LLM never authors a workout, a distance, or a volume.
//
// The model's values are never trusted. Every field is clamped / whitelisted
// below, server-side, before it reaches the client; a hallucinated or hostile
// value is dropped to a documented default and named in `assumptions`, never
// passed through.
//
// Kept free of the Anthropic SDK and the `$app/env` graph so the clamp logic
// is unit-testable in isolation (inputs.test.ts).

import { lengthLimit } from '../../core/column_limits';
import { GOAL_DISTANCES_M, type GoalEvent } from '../training';

export type PlanRequestGoalEvent = Exclude<GoalEvent, 'custom'>;

/// Why a field holds what it holds when it is not simply what the runner
/// asked for. The client renders one localized line per key, so a key added
/// here needs a label there.
export const PLAN_REQUEST_ASSUMPTIONS = [
	'goal_event_default',
	'days_per_week_default',
	'days_per_week_clamped',
	'weeks_clamped',
	'race_date_dropped',
	'goal_time_dropped',
	'recent_5k_dropped',
	'beginner_5k',
] as const;
export type PlanRequestAssumption = (typeof PLAN_REQUEST_ASSUMPTIONS)[number];

export interface PlanRequestInputs {
	goalEvent: PlanRequestGoalEvent;
	/// ISO `yyyy-mm-dd`, strictly after today and at most two years out.
	raceDate: string | null;
	goalTimeSec: number | null;
	recent5kSec: number | null;
	daysPerWeek: number;
	weeks: number | null;
	beginnerWalkRun: boolean;
	planName: string | null;
	assumptions: PlanRequestAssumption[];
}

export const DEFAULT_GOAL_EVENT: PlanRequestGoalEvent = 'distance_half';
export const DEFAULT_DAYS_PER_WEEK = 4;
/// The wizard's own days-per-week select.
export const MIN_DAYS_PER_WEEK = 3;
export const MAX_DAYS_PER_WEEK = 7;
/// The wizard's week-override input bounds.
export const MIN_PLAN_WEEKS = 4;
export const MAX_PLAN_WEEKS = 24;

/// Goal pace sanity band, seconds per km. Faster than 2:30/km is beyond the
/// world record at every distance the wizard offers; slower than 15:00/km is a
/// walk the pace zones cannot be built from. Outside it the number is a
/// misread ("1:45" as minutes for a half), not a goal.
export const MIN_GOAL_PACE_SEC_PER_KM = 150;
export const MAX_GOAL_PACE_SEC_PER_KM = 900;
/// The goal-time hours field caps at 9, so a longer goal would fill a field
/// the browser then refuses to submit.
export const MAX_GOAL_TIME_SEC = 10 * 3600;

/// Recent 5K band: 12:00 is past the world record, and the minutes field caps
/// at 59, so 60:00 itself would fill a field the browser refuses to submit.
export const MIN_RECENT_5K_SEC = 12 * 60;
export const MAX_RECENT_5K_SEC = 60 * 60;

/// How far ahead a race date may sit. Further out is almost always a year
/// misread, and no plan the wizard builds runs that long.
export const MAX_RACE_DATE_YEARS = 2;

const GOAL_EVENTS: ReadonlySet<string> = new Set(Object.keys(GOAL_DISTANCES_M));
const ISO_DATE = /^\d{4}-\d{2}-\d{2}$/;
const CONTROL_CHARS = /\p{Cc}/gu;

/// Epoch-day for a real calendar date, or null. Round-trips the components so
/// "2027-02-31" is refused rather than rolled over into March.
export function isoEpochDay(iso: unknown): number | null {
	if (typeof iso !== 'string' || !ISO_DATE.test(iso)) return null;
	const [y, m, d] = iso.split('-').map(Number);
	const ms = Date.UTC(y, m - 1, d);
	const back = new Date(ms);
	if (back.getUTCFullYear() !== y || back.getUTCMonth() !== m - 1 || back.getUTCDate() !== d) {
		return null;
	}
	return Math.floor(ms / 86_400_000);
}

function finiteNumber(raw: unknown): number | null {
	if (typeof raw !== 'number' || !Number.isFinite(raw)) return null;
	return raw;
}

function validRaceDate(raw: unknown, todayIso: string): string | null {
	const race = isoEpochDay(raw);
	const today = isoEpochDay(todayIso);
	if (race === null || today === null || race <= today) return null;
	const [y, m, d] = todayIso.split('-').map(Number);
	const limit = Math.floor(Date.UTC(y + MAX_RACE_DATE_YEARS, m - 1, d) / 86_400_000);
	return race <= limit ? (raw as string) : null;
}

function goalTimeFitsPace(goalTimeSec: number, goalEvent: PlanRequestGoalEvent): boolean {
	if (goalTimeSec >= MAX_GOAL_TIME_SEC) return false;
	const pace = goalTimeSec / (GOAL_DISTANCES_M[goalEvent] / 1000);
	return pace >= MIN_GOAL_PACE_SEC_PER_KM && pace <= MAX_GOAL_PACE_SEC_PER_KM;
}

function cleanPlanName(raw: unknown): string | null {
	if (typeof raw !== 'string') return null;
	const cleaned = raw.replace(CONTROL_CHARS, ' ').replace(/\s+/g, ' ').trim();
	if (cleaned.length === 0) return null;
	return Array.from(cleaned).slice(0, lengthLimit('training_plans.name')).join('').trim();
}

/// Validate + clamp the model's raw tool-call output into wizard inputs.
/// Never throws: every malformed / missing / hostile field collapses to a
/// documented default (or null, meaning "leave the wizard's field alone").
/// This is the single trust boundary between the LLM and the plan wizard.
export function validatePlanInputs(raw: unknown, todayIso: string): PlanRequestInputs {
	const o = (raw && typeof raw === 'object' && !Array.isArray(raw) ? raw : {}) as Record<
		string,
		unknown
	>;
	const assumptions: PlanRequestAssumption[] = [];

	const beginnerWalkRun = o.beginner_walk_run === true;

	const requestedEvent = GOAL_EVENTS.has(o.goal_event as string)
		? (o.goal_event as PlanRequestGoalEvent)
		: null;
	let goalEvent: PlanRequestGoalEvent;
	if (beginnerWalkRun) {
		// A walk-run plan is the couch-to-5K progression; it has no other
		// distance and no goal time, so anything else the model sent is dropped.
		goalEvent = 'distance_5k';
	} else if (requestedEvent) {
		goalEvent = requestedEvent;
	} else {
		goalEvent = DEFAULT_GOAL_EVENT;
		assumptions.push('goal_event_default');
	}

	let goalTimeSec: number | null = null;
	const rawGoalTime = finiteNumber(o.goal_time_sec);
	if (rawGoalTime !== null) {
		const rounded = Math.round(rawGoalTime);
		if (!beginnerWalkRun && rounded > 0 && goalTimeFitsPace(rounded, goalEvent)) {
			goalTimeSec = rounded;
		} else if (!beginnerWalkRun) {
			assumptions.push('goal_time_dropped');
		}
	}
	if (
		beginnerWalkRun &&
		((requestedEvent !== null && requestedEvent !== 'distance_5k') || rawGoalTime !== null)
	) {
		assumptions.push('beginner_5k');
	}

	let recent5kSec: number | null = null;
	const rawRecent = finiteNumber(o.recent_5k_sec);
	if (rawRecent !== null) {
		const rounded = Math.round(rawRecent);
		if (rounded >= MIN_RECENT_5K_SEC && rounded < MAX_RECENT_5K_SEC) recent5kSec = rounded;
		else assumptions.push('recent_5k_dropped');
	}

	let daysPerWeek = DEFAULT_DAYS_PER_WEEK;
	const rawDays = finiteNumber(o.days_per_week);
	if (rawDays === null) {
		assumptions.push('days_per_week_default');
	} else {
		const rounded = Math.round(rawDays);
		daysPerWeek = Math.min(MAX_DAYS_PER_WEEK, Math.max(MIN_DAYS_PER_WEEK, rounded));
		if (daysPerWeek !== rounded) assumptions.push('days_per_week_clamped');
	}

	let weeks: number | null = null;
	const rawWeeks = finiteNumber(o.weeks);
	if (rawWeeks !== null && rawWeeks > 0) {
		const roundedWeeks = Math.round(rawWeeks);
		weeks = Math.min(MAX_PLAN_WEEKS, Math.max(MIN_PLAN_WEEKS, roundedWeeks));
		if (weeks !== roundedWeeks) assumptions.push('weeks_clamped');
	}

	const raceDate = validRaceDate(o.race_date, todayIso);
	if (raceDate === null && o.race_date !== undefined && o.race_date !== null) {
		assumptions.push('race_date_dropped');
	}

	return {
		goalEvent,
		raceDate,
		goalTimeSec,
		recent5kSec,
		daysPerWeek,
		weeks,
		beginnerWalkRun,
		planName: cleanPlanName(o.plan_name),
		assumptions,
	};
}
