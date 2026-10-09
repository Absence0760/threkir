/// Multi-metric user goals, ported from `apps/mobile_android/lib/goals.dart`.
/// Four target kinds — distance, time, average pace, run count — over a
/// week or month period. Pace targets are distance-weighted and exclude
/// cycling (a single long bike ride would otherwise dominate the
/// average and make the metric meaningless for runners).
///
/// Stored in `localStorage` under a single JSON blob, mirroring the
/// local-first shape of the Android version. Not bag-synced today —
/// goals are highly personal and per-user, and the universal settings
/// bag is already carrying a scalar `weekly_mileage_goal_m` for the
/// simple case. When a user wants cross-device sync, promote this to
/// the bag as `run_goals` (array) with a new registered key.

import type { Run } from '../types';

/// What a goal is evaluated over: when the run happened, how far, how long,
/// and whether it was a bike ride (excluded from the pace targets). A
/// structural bound rather than `Run` for the reason `plan_ramp`'s
/// `RunForVolume` is one — the dashboard's read is ten columns, and demanding
/// the whole row would make the caller assert one it never fetched.
import { paceMinutesSeconds } from '../format/pace_format';

export type GoalPeriod = 'week' | 'month';

export interface RunGoal {
	id: string;
	period: GoalPeriod;
	title?: string;
	distanceMetres?: number;
	timeSeconds?: number;
	/// Lower-is-better target. Stored canonically as seconds per
	/// kilometre regardless of the user's display unit; the editor
	/// converts on the way in and out.
	paceSecPerKm?: number;
	runCount?: number;
}

export interface TargetProgress {
	kind: 'distance' | 'time' | 'pace' | 'runCount';
	label: string;
	currentLabel: string;
	targetLabel: string;
	percent: number;
	complete: boolean;
	/// True when the target can't yet be evaluated for this period
	/// (e.g. a pace target with no pace-eligible runs in the window —
	/// every run was a bike ride). Persona-hunt finding Intermediate
	/// #5: pre-fix, an ineligible pace target contributed `percent=0`
	/// to the overall ring average, masking distance + run-count
	/// progress at "0% complete" forever. Excluded targets are
	/// surfaced in the UI but skipped in `overallPercent`.
	pending?: boolean;
}

export interface GoalProgress {
	goal: RunGoal;
	targets: TargetProgress[];
	overallPercent: number;
	complete: boolean;
	runCount: number;
}

// localStorage is browser-scoped, not user-scoped. With a single
// fixed key, signing out and signing in as a different user on the
// same browser shows the previous user's goals. We key by user id
// to keep them separate. The pre-scoping key is migrated once per
// user (see loadGoals).
const LEGACY_STORAGE_KEY = 'run_app.goals_v1';
function storageKey(userId: string): string {
	return `${LEGACY_STORAGE_KEY}:${userId}`;
}

// Serialize to the Android-compatible snake_case wire format so goals
// survive a round-trip through backup/restore and the future settings-bag
// promotion. Aligns with goals.dart's toJson() keys.
function goalToWire(g: RunGoal): Record<string, unknown> {
	const w: Record<string, unknown> = { id: g.id, period: g.period };
	if (g.title != null) w.title = g.title;
	if (g.distanceMetres != null) w.distance_m = g.distanceMetres;
	if (g.timeSeconds != null) w.time_s = g.timeSeconds;
	if (g.paceSecPerKm != null) w.pace_s_per_km = g.paceSecPerKm;
	if (g.runCount != null) w.run_count = g.runCount;
	return w;
}

// Accept both the legacy camelCase keys (written by earlier web versions)
// and the canonical snake_case keys (Android + current web).
function goalFromWire(raw: Record<string, unknown>): RunGoal {
	return {
		id: raw.id as string,
		period: (raw.period as GoalPeriod) ?? 'week',
		title: (raw.title as string | undefined),
		distanceMetres: (raw.distance_m ?? raw.distanceMetres) as number | undefined,
		timeSeconds: (raw.time_s ?? raw.timeSeconds) as number | undefined,
		paceSecPerKm: (raw.pace_s_per_km ?? raw.paceSecPerKm) as number | undefined,
		runCount: (raw.run_count ?? raw.runCount) as number | undefined,
	};
}

function readGoalsFromKey(key: string): RunGoal[] | null {
	const raw = localStorage.getItem(key);
	if (!raw) return null;
	const list = JSON.parse(raw);
	if (!Array.isArray(list)) return null;
	return list
		.filter((g) => g && typeof g === 'object' && typeof g.id === 'string')
		.map((g) => goalFromWire(g as Record<string, unknown>));
}

export function loadGoals(userId: string | null | undefined): RunGoal[] {
	if (!userId || typeof localStorage === 'undefined') return [];
	try {
		const scoped = readGoalsFromKey(storageKey(userId));
		if (scoped !== null) return scoped;
		// First load with the new key. If there's still a value at the
		// pre-scoping key, take ownership of it for the current user
		// (the most likely case is a single-user device where the legacy
		// data is theirs anyway). On a shared device the first user to
		// sign in inherits any leftover goals; subsequent users start
		// clean — a one-time blip but no longer a recurring cross-user
		// leak.
		const legacy = readGoalsFromKey(LEGACY_STORAGE_KEY);
		if (legacy !== null) {
			saveGoals(userId, legacy);
			localStorage.removeItem(LEGACY_STORAGE_KEY);
			return legacy;
		}
		return [];
	} catch {
		return [];
	}
}

export function saveGoals(userId: string | null | undefined, goals: RunGoal[]): void {
	if (!userId || typeof localStorage === 'undefined') return;
	try {
		localStorage.setItem(storageKey(userId), JSON.stringify(goals.map(goalToWire)));
	} catch {
		/* quota — noop */
	}
}

export function newGoalId(): string {
	return typeof crypto !== 'undefined' && 'randomUUID' in crypto
		? crypto.randomUUID()
		: `g_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
}

/// 00:00 local time of the week containing `now`, starting on the user's
/// `week_start_day`. The single source of truth for "this week" on web — the
/// dashboard tile, weekly chart, week strip, week lead, trend deltas,
/// consistency card, period summary and goals all take their window from
/// here. Dart twin: `weekStartLocal` in goals.dart. `setDate` is calendar
/// arithmetic, so a week spanning a DST change still starts at midnight.
export function weekStartLocal(now: Date, weekStartDay: 'monday' | 'sunday' = 'monday'): Date {
	const d = new Date(now);
	d.setHours(0, 0, 0, 0);
	const offset = weekStartDay === 'sunday' ? d.getDay() : (d.getDay() + 6) % 7;
	d.setDate(d.getDate() - offset);
	return d;
}

export function periodStart(
	period: GoalPeriod,
	now: Date,
	weekStartDay: 'monday' | 'sunday' = 'monday',
): Date {
	if (period === 'week') return weekStartLocal(now, weekStartDay);
	const d = new Date(now);
	d.setHours(0, 0, 0, 0);
	d.setDate(1);
	return d;
}

export function periodEnd(period: GoalPeriod, now: Date, weekStartDay: 'monday' | 'sunday' = 'monday'): Date {
	const start = periodStart(period, now, weekStartDay);
	const end = new Date(start);
	if (period === 'week') {
		end.setDate(end.getDate() + 7);
	} else {
		end.setMonth(end.getMonth() + 1);
	}
	return end;
}

function formatKm(m: number): string {
	return `${(m / 1000).toFixed(1)} km`;
}

function formatMinutes(s: number): string {
	const h = Math.floor(s / 3600);
	const m = Math.floor((s % 3600) / 60);
	if (h > 0) return `${h}h ${m}m`;
	return `${m}m`;
}

/// `secondsPerKm` -> `mm:ss/km` (or "—" if zero / negative).
export function formatPaceSecPerKm(secPerKm: number): string {
	if (!isFinite(secPerKm) || secPerKm <= 0) return '—';
	return `${paceMinutesSeconds(secPerKm)}/km`;
}

/// The plan-workout fields that say whether a session was marked done by
/// hand. A structural bound so the dashboard's plan rows and the week lead's
/// own input type both satisfy it.
export interface PlanCompletion {
	scheduled_date: string;
	target_distance_m: number | null;
	manually_completed: boolean;
	completed_run_id: string | null;
}

function localIsoDate(d: Date): string {
	const y = d.getFullYear();
	const mo = String(d.getMonth() + 1).padStart(2, '0');
	const da = String(d.getDate()).padStart(2, '0');
	return `${y}-${mo}-${da}`;
}

/// Plan workouts the runner marked done without a linked run, scheduled from
/// `from`'s calendar day through `now`'s. Such a session is activity the
/// runner says happened (a treadmill run logged elsewhere, a run recorded on
/// a device that never synced), so it counts toward a period the way the
/// dashboard's This Week card has always counted it, with its target distance
/// standing in for the distance nobody recorded. A workout with a linked run
/// is left out because that run is already counted, and a future-dated one
/// because a mark on a day that has not happened is not activity yet. The one
/// definition behind both the week lead and the Goals section (decisions
/// § 1813).
export function markedDoneTally(
	workouts: readonly PlanCompletion[],
	from: Date,
	now: Date,
): { distanceM: number; count: number } {
	const first = localIsoDate(from);
	const last = localIsoDate(now);
	let distanceM = 0;
	let count = 0;
	for (const w of workouts) {
		if (!(w.manually_completed === true && w.completed_run_id == null)) continue;
		if (w.scheduled_date < first || w.scheduled_date > last) continue;
		distanceM += w.target_distance_m ?? 0;
		count += 1;
	}
	return { distanceM, count };
}

/// Pure evaluator. Given a goal, the full run list and the active plan's
/// workouts, compute progress per active target. Mirrors the shape of
/// `evaluateGoal` in `goals.dart` — active-target list, aggregate percent,
/// overall completion flag. Workouts marked done without a run add to the
/// distance and run-count targets through `markedDoneTally`; time and pace
/// stay with recorded runs, since a mark carries no duration anyone measured.
export function evaluateGoal(
	goal: RunGoal,
	runs: readonly Pick<Run, 'started_at' | 'distance_m' | 'duration_s' | 'activity_type'>[],
	now: Date,
	weekStartDay: 'monday' | 'sunday' = 'monday',
	planWorkouts: readonly PlanCompletion[] = [],
): GoalProgress {
	const startDate = periodStart(goal.period, now, weekStartDay);
	const start = startDate.getTime();
	const end = periodEnd(goal.period, now, weekStartDay).getTime();
	const inPeriod = runs.filter((r) => {
		const t = new Date(r.started_at).getTime();
		return t >= start && t < end;
	});
	const marked = markedDoneTally(planWorkouts, startDate, now);
	const activityCount = inPeriod.length + marked.count;
	const totalMetres = inPeriod.reduce((s, r) => s + r.distance_m, 0) + marked.distanceM;
	const totalSeconds = inPeriod.reduce((s, r) => s + r.duration_s, 0);

	// Pace calculations exclude cycling — a distance-weighted average
	// would otherwise be dominated by a single long bike ride.
	const paceEligible = inPeriod.filter((r) => r.activity_type !== 'cycle');

	const targets: TargetProgress[] = [];

	if (goal.distanceMetres != null && goal.distanceMetres > 0) {
		const pct = Math.min(1, totalMetres / goal.distanceMetres);
		targets.push({
			kind: 'distance',
			label: 'Distance',
			currentLabel: formatKm(totalMetres),
			targetLabel: formatKm(goal.distanceMetres),
			percent: pct,
			complete: totalMetres >= goal.distanceMetres,
		});
	}
	if (goal.timeSeconds != null && goal.timeSeconds > 0) {
		const pct = Math.min(1, totalSeconds / goal.timeSeconds);
		targets.push({
			kind: 'time',
			label: 'Time',
			currentLabel: formatMinutes(totalSeconds),
			targetLabel: formatMinutes(goal.timeSeconds),
			percent: pct,
			complete: totalSeconds >= goal.timeSeconds,
		});
	}
	if (goal.paceSecPerKm != null && goal.paceSecPerKm > 0) {
		const paceMetres = paceEligible.reduce((s, r) => s + r.distance_m, 0);
		const paceSeconds = paceEligible.reduce((s, r) => s + r.duration_s, 0);
		const current = paceMetres > 10 ? paceSeconds / (paceMetres / 1000) : 0;
		// Lower-is-better. If we don't yet have any running data,
		// mark the target as `pending` so the overall ring doesn't
		// drag to 0 because of an unmeasurable contributor (Intermediate
		// #5). Once any pace-eligible distance exists, the percent
		// reflects target/current and the pending flag goes away.
		const pending = current <= 0;
		let percent: number;
		let complete: boolean;
		if (pending) {
			percent = 0;
			complete = false;
		} else if (current <= goal.paceSecPerKm) {
			percent = 1;
			complete = true;
		} else {
			percent = Math.max(0, Math.min(1, goal.paceSecPerKm / current));
			complete = false;
		}
		targets.push({
			kind: 'pace',
			label: 'Avg pace',
			currentLabel: pending ? '—' : formatPaceSecPerKm(current),
			targetLabel: formatPaceSecPerKm(goal.paceSecPerKm),
			percent,
			complete,
			pending,
		});
	}
	if (goal.runCount != null && goal.runCount > 0) {
		const pct = Math.min(1, activityCount / goal.runCount);
		targets.push({
			kind: 'runCount',
			label: 'Runs',
			currentLabel: `${activityCount}`,
			targetLabel: `${goal.runCount}`,
			percent: pct,
			complete: activityCount >= goal.runCount,
		});
	}

	// Exclude pending targets (can't be evaluated yet) from the
	// overall-progress average so an ineligible pace target doesn't
	// drag the ring down with a fake 0%. The target row is still
	// shown to the user — just labelled "—" instead of counted.
	const measurable = targets.filter((t) => !t.pending);
	const overall =
		measurable.length === 0
			? 0
			: measurable.reduce((s, t) => s + t.percent, 0) / measurable.length;
	const complete = measurable.length > 0 && measurable.every((t) => t.complete);

	return {
		goal,
		targets,
		overallPercent: overall,
		complete,
		runCount: activityCount,
	};
}

export function periodLabel(period: GoalPeriod): string {
	return period === 'week' ? 'This week' : 'This month';
}
