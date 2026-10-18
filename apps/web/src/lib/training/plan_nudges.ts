/**
 * What Home says, unprompted, about the runner's plan — and the "+3 km" a
 * workout run long carries. Pure: the rules themselves live in
 * `plan_replan.ts` / `plan_adaptive_replan.ts` and are not restated here
 * (decisions §144); this module only decides WHEN an existing proposal is
 * worth putting in front of the runner, and names each occurrence so a
 * dismissal can stick to it across devices.
 *
 * Mirrors `apps/mobile_android/lib/plan_nudges.dart` — keep in lockstep
 * (TS↔Dart parity pair, equal test counts).
 */

import { adaptiveReplanRemaining } from './plan_adaptive_replan';
import { replanRemaining, type ReplanWeek } from './plan_replan';

/// A run past its target by less than this is not worth a word: GPS drift
/// and a loop home add a few hundred metres to most runs.
export const OVERRUN_MIN_METRES = 1000;

/// ...and nor is an extra kilometre on a 30 km long run. Both bars must be
/// cleared.
export const OVERRUN_MIN_FRACTION = 0.1;

/// How many trailing completed weeks the rest-day note looks at, and how
/// many of them must hold a run on a rest day before it speaks up.
export const REST_DAY_WINDOW = 3;
export const REST_DAY_MIN_WEEKS = 2;

/// Dismissed occurrences kept in the prefs bag. Each names one plan week, so
/// a short tail is all that can still match anything.
export const DISMISSED_NUDGES_CAP = 20;

/// The `user_settings.prefs` key holding dismissed occurrences.
export const DISMISSED_NUDGES_KEY = 'plan_nudges_dismissed';

export type PlanNudgeKind = 'adaptive_under' | 'ease_over' | 'rest_day_runs';

export interface PlanNudge {
	kind: PlanNudgeKind;
	/// The last completed plan week the occurrence was judged on.
	weekIndex: number;
	/// Identity of this occurrence, as stored when it is dismissed.
	key: string;
	/// Weeks in the trend window that showed the signal, and the window size.
	/// `ease_over` is one week by definition: 1 of 1.
	weeks: number;
	ofWeeks: number;
}

/// Metres a completed run went past its workout's distance target, or null
/// when there is no distance target, no run distance, or the extra is small
/// enough to be noise. Never negative: a short run is not an over-run.
export function workoutOverrunMetres(
	targetDistanceM: number | null | undefined,
	runDistanceM: number | null | undefined,
): number | null {
	if (targetDistanceM == null || runDistanceM == null) return null;
	if (!(targetDistanceM > 0) || !Number.isFinite(runDistanceM)) return null;
	const extra = runDistanceM - targetDistanceM;
	if (extra < OVERRUN_MIN_METRES) return null;
	if (extra < targetDistanceM * OVERRUN_MIN_FRACTION) return null;
	return extra;
}

/// Decimal places for an over-run shown in the runner's unit: whole units
/// once it reaches ten or when one decimal would read ".0", otherwise one.
export function overrunDigits(valueInUnits: number): 0 | 1 {
	if (valueInUnits >= 10) return 0;
	const tenths = Math.round(valueInUnits * 10);
	return tenths % 10 === 0 ? 0 : 1;
}

export function planNudgeKey(planId: string, kind: PlanNudgeKind, weekIndex: number): string {
	return `${planId}:${kind}:${weekIndex}`;
}

/// The dismissed list out of the prefs bag. Anything that is not a list of
/// strings reads as nothing dismissed, so a corrupt bag shows a card again
/// rather than hiding every card for good.
export function parseDismissedNudges(raw: unknown): string[] {
	if (!Array.isArray(raw)) return [];
	return raw.filter((k): k is string => typeof k === 'string');
}

/// `dismissed` with `key` added last, de-duplicated, keeping the newest
/// `DISMISSED_NUDGES_CAP`.
export function withDismissedNudge(dismissed: readonly string[], key: string): string[] {
	const next = dismissed.filter((k) => k !== key);
	next.push(key);
	return next.slice(-DISMISSED_NUDGES_CAP);
}

function shiftIso(iso: string, days: number): string {
	const [y, m, d] = iso.split('-').map(Number);
	return new Date(Date.UTC(y, m - 1, d + days)).toISOString().slice(0, 10);
}

export interface NudgeInputWorkout {
	id: string;
	/// ISO scheduled date (YYYY-MM-DD).
	scheduledDate: string;
	kind: string;
	targetDistanceM: number | null;
	completed: boolean;
	skipped: boolean;
}

export interface NudgeInputWeek {
	weekIndex: number;
	phase: string;
	targetVolumeM: number | null;
	workouts: NudgeInputWorkout[];
}

export interface NudgeInputRun {
	/// The run's LOCAL calendar day (YYYY-MM-DD).
	date: string;
	distanceM: number;
}

/// The re-plan engine's input, built the one way every caller builds it:
/// planned volume is the week's target or, when unset, its non-rest
/// distances; actual volume is every run on a local day inside the week; a
/// week is complete once its last day has ended.
export function buildReplanWeeks(input: {
	startDate: string;
	today: string;
	weeks: NudgeInputWeek[];
	runs: NudgeInputRun[];
}): ReplanWeek[] {
	return input.weeks.map((w) => {
		let planned = w.targetVolumeM ?? 0;
		if (!(planned > 0)) {
			planned = w.workouts.reduce(
				(s, x) => s + (x.kind !== 'rest' ? (x.targetDistanceM ?? 0) : 0),
				0,
			);
		}
		const weekStart = shiftIso(input.startDate, w.weekIndex * 7);
		const weekEnd = shiftIso(weekStart, 7);
		let actual = 0;
		for (const r of input.runs) {
			if (r.date >= weekStart && r.date < weekEnd) actual += r.distanceM;
		}
		return {
			weekIndex: w.weekIndex,
			phase: w.phase,
			plannedMetres: planned,
			actualMetres: actual,
			isComplete: weekEnd <= input.today,
			workouts: w.workouts.map((x) => ({
				id: x.id,
				scheduledDate: x.scheduledDate,
				kind: x.kind,
				targetDistanceM: x.targetDistanceM,
				completed: x.completed,
				skipped: x.skipped,
				isPast: x.scheduledDate < input.today,
			})),
		};
	});
}

/// Completed weeks that held at least one run on a day with no session
/// planned (a rest day, or a day the plan left empty), among the last
/// `REST_DAY_WINDOW` completed weeks that schedule anything at all.
function restDayRunWeeks(
	startDate: string,
	weeks: ReplanWeek[],
	runDates: readonly string[],
): { weeks: number; ofWeeks: number } {
	const window = weeks
		.filter((w) => w.isComplete && w.workouts.length > 0)
		.slice(-REST_DAY_WINDOW);
	let flagged = 0;
	for (const w of window) {
		const weekStart = shiftIso(startDate, w.weekIndex * 7);
		const weekEnd = shiftIso(weekStart, 7);
		const planned = new Set(
			w.workouts.filter((x) => x.kind !== 'rest').map((x) => x.scheduledDate),
		);
		if (runDates.some((d) => d >= weekStart && d < weekEnd && !planned.has(d))) flagged++;
	}
	return { weeks: flagged, ofWeeks: window.length };
}

/// The one plan card Home shows, or null. Only an active, started, unfinished,
/// non-template plan qualifies (the caller owns the "is the viewer the owner"
/// check). In order, the first occurrence not yet dismissed wins:
///
///  1. `adaptive_under` — the adaptive re-plan's 2-of-3 under-run trend, and
///     only when it has a change to propose;
///  2. `ease_over` — the last completed week ran over plan and the re-plan
///     eases next week;
///  3. `rest_day_runs` — runs on rest days in 2 of the last 3 completed weeks.
export function planNudge(input: {
	planId: string;
	status: string;
	isTemplate: boolean;
	startDate: string;
	endDate: string;
	today: string;
	weeks: ReplanWeek[];
	runDates: readonly string[];
	dismissed: readonly string[];
	/// A break's days (`breakWindow`, the plan_break pair): a judged week that
	/// overlaps them is missed training the break offer answers, not a trend.
	breakFromIso?: string | null;
	breakUntilIso?: string | null;
}): PlanNudge | null {
	if (input.status !== 'active' || input.isTemplate) return null;
	if (input.today < input.startDate || input.today > input.endDate) return null;
	const weeks = [...input.weeks].sort((a, b) => a.weekIndex - b.weekIndex);
	const lastComplete = [...weeks].reverse().find((w) => w.isComplete);
	if (!lastComplete) return null;
	const at = lastComplete.weekIndex;
	if (input.breakFromIso && input.breakUntilIso) {
		const weekStart = shiftIso(input.startDate, 7 * at);
		if (shiftIso(weekStart, 6) >= input.breakFromIso && weekStart <= input.breakUntilIso) return null;
	}
	const dismissed = new Set(input.dismissed);
	const candidates: PlanNudge[] = [];

	// P1 only, by construction: no fitness snapshot reaches Home (decisions
	// § 2125), so the gated P2 load input keeps its one call site.
	const adaptive = adaptiveReplanRemaining({ weeks, today: input.today });
	if (adaptive.reason === 'trend_underfitness' && adaptive.changes.length > 0) {
		candidates.push({
			kind: 'adaptive_under',
			weekIndex: at,
			key: planNudgeKey(input.planId, 'adaptive_under', at),
			weeks: adaptive.trailingDirections.filter((d) => d === 'under').length,
			ofWeeks: adaptive.trailingDirections.length,
		});
	}

	const replan = replanRemaining({ weeks, today: input.today });
	if (replan.changes.some((c) => c.reason === 'ease_over_running')) {
		candidates.push({
			kind: 'ease_over',
			weekIndex: at,
			key: planNudgeKey(input.planId, 'ease_over', at),
			weeks: 1,
			ofWeeks: 1,
		});
	}

	const rest = restDayRunWeeks(input.startDate, weeks, input.runDates);
	if (rest.weeks >= REST_DAY_MIN_WEEKS) {
		candidates.push({
			kind: 'rest_day_runs',
			weekIndex: at,
			key: planNudgeKey(input.planId, 'rest_day_runs', at),
			weeks: rest.weeks,
			ofWeeks: rest.ofWeeks,
		});
	}

	return candidates.find((c) => !dismissed.has(c.key)) ?? null;
}
