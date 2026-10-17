// Applies validated AI plan-edit operations to a plan with the deterministic
// plan helpers, and grades the result before the runner is asked to confirm.
//
// The model only chose WHICH operation and WHERE (ops.ts). What an operation
// does is decided here, by the same rules the manual editor already uses: a
// recovery week is `recoveryWorkoutPatch` + `recoveryWeekVolume` from
// `plan_bulk_ops.ts`, exactly as the week's "Make recovery week" button does;
// a scaled week multiplies its unstructured sessions and its target volume; a
// move or a swap only changes dates inside one plan week, so no week's volume
// moves with it.
//
// Then the edited plan is graded against the original with the acute:chronic
// workload ratio bands from `coach_load.ts` (the policy `plan_ramp.ts` already
// grades a new plan with): each open week's planned volume against the mean of
// the four weeks before it, with the runner's real recent weekly volume
// standing in for weeks before the plan began. An edit that pushes a week into
// a higher band, or puts two hard sessions on adjacent days that were not
// before, is exactly the failure § 12 kept the model away from, so:
//
//   - a week newly in the HIGH band rejects the whole set;
//   - a week newly ELEVATED, or newly stacked hard days, needs a second,
//     explicit confirmation naming what got harder.
//
// Pure: no Supabase, no DOM. The page persists the date changes together through
// `reschedulePlanWorkouts`, then the other fields through
// `updatePlanWorkout` / `updatePlanWeek` / `markWorkoutSkipped`.

import { injuryRiskBand, type InjuryRiskBand } from '../coach_load';
import { recoveryWeekVolume, recoveryWorkoutPatch } from '../plan_bulk_ops';
import { canDisplaceForMove } from '../plan_move';
import { MIN_ACTIVE_WEEKS, type RecentVolume } from '../plan_ramp';
import {
	isEditableWorkout,
	isOpenWeek,
	type PlanEditOp,
	type PlanEditSnapshot,
	type PlanEditWorkout,
} from './ops';

/// Sessions that carry real load. Two of them on adjacent days is the
/// "stacked hard days" § 12 names.
const HARD_KINDS: ReadonlySet<string> = new Set(['tempo', 'interval', 'marathon_pace', 'long', 'race']);

/// Weeks averaged into the chronic base — the ACWR convention `coach_load`
/// and `plan_ramp` already use.
export const PLAN_EDIT_CHRONIC_WEEKS = 4;

export interface WorkoutPatch {
	scheduled_date?: string;
	kind?: string;
	target_distance_m?: number | null;
	target_duration_seconds?: number | null;
	target_pace_sec_per_km?: number | null;
	target_pace_tolerance_sec?: number | null;
	structure?: null;
}

export interface WorkoutState {
	scheduledDate: string;
	kind: string;
	distanceM: number | null;
	durationSec: number | null;
	skipped: boolean;
}

export interface WorkoutChange {
	workoutId: string;
	before: WorkoutState;
	after: WorkoutState;
	/// Field changes for `updatePlanWorkout`; null when the only change is a skip.
	patch: WorkoutPatch | null;
	/// Persist through `markWorkoutSkipped(id, true)`.
	skip: boolean;
}

export interface WeekChange {
	weekId: string;
	weekIndex: number;
	beforeVolumeM: number | null;
	afterVolumeM: number | null;
}

export interface PlanEditApplication {
	workouts: WorkoutChange[];
	weeks: WeekChange[];
	after: PlanEditSnapshot;
	/// Operations that changed something. An operation whose target is no
	/// longer editable in the client's copy of the plan is skipped, not forced.
	applied: number;
}

const PATCH_FIELDS = [
	'scheduled_date',
	'kind',
	'target_distance_m',
	'target_duration_seconds',
	'target_pace_sec_per_km',
	'target_pace_tolerance_sec',
	'structure',
] as const;

function clone(snapshot: PlanEditSnapshot): PlanEditSnapshot {
	return {
		plan: { ...snapshot.plan },
		weeks: snapshot.weeks.map((w) => ({ ...w })),
		workouts: snapshot.workouts.map((w) => ({ ...w })),
	};
}

function stateOf(w: PlanEditWorkout): WorkoutState {
	return {
		scheduledDate: w.scheduled_date,
		kind: w.kind,
		distanceM: w.target_distance_m,
		durationSec: w.target_duration_seconds ?? null,
		skipped: w.skipped_at != null,
	};
}

function scaled(value: number | null | undefined, factor: number): number | null {
	if (value == null || !Number.isFinite(value)) return value ?? null;
	return Math.round(value * factor);
}

/// Apply operations to a copy of the plan. Each one re-checks its target
/// against this copy with the same editability rule the server used, so a
/// plan that changed between the request and the apply cannot be edited
/// through a stale operation.
export function applyPlanEditOps(
	snapshot: PlanEditSnapshot,
	ops: PlanEditOp[],
	todayIso: string,
): PlanEditApplication {
	const after = clone(snapshot);
	const byId = new Map(after.workouts.map((w) => [w.id, w]));
	const weekByIndex = new Map(after.weeks.map((w) => [w.week_index, w]));
	const editable = (id: string) => {
		const w = byId.get(id);
		return w && isEditableWorkout(w, todayIso) ? w : null;
	};
	const weekWorkouts = (weekId: string) =>
		after.workouts.filter((w) => w.week_id === weekId && isEditableWorkout(w, todayIso));

	let applied = 0;
	for (const op of ops) {
		switch (op.op) {
			case 'move_workout': {
				const w = editable(op.workoutId);
				if (!w) break;
				// One row per day per week: a move onto an occupied day trades
				// the two days, exactly as `move_plan_workout` does on save
				// (decisions § 2073). A day held by a completed workout or a race
				// is not the AI's to take.
				const occupant = after.workouts.find(
					(o) => o.id !== w.id && o.week_id === w.week_id && o.scheduled_date === op.date,
				);
				if (occupant && !canDisplaceForMove(occupant)) break;
				if (occupant) occupant.scheduled_date = w.scheduled_date;
				w.scheduled_date = op.date;
				applied++;
				break;
			}
			case 'swap_days': {
				const a = editable(op.workoutId);
				const b = editable(op.otherWorkoutId);
				if (!a || !b || a.week_id !== b.week_id) break;
				[a.scheduled_date, b.scheduled_date] = [b.scheduled_date, a.scheduled_date];
				applied++;
				break;
			}
			case 'scale_week': {
				const week = weekByIndex.get(op.weekIndex);
				if (!week || !isOpenWeek(after.plan, week, todayIso)) break;
				for (const w of weekWorkouts(week.id)) {
					// A structured session's reps would contradict a scaled
					// distance (the bug `recoveryWorkoutPatch` documents), so it
					// keeps its prescription; the diff shows it unchanged.
					if (w.structure != null) continue;
					w.target_distance_m = scaled(w.target_distance_m, op.factor);
					w.target_duration_seconds = scaled(w.target_duration_seconds, op.factor);
				}
				week.target_volume_m = scaled(week.target_volume_m, op.factor);
				applied++;
				break;
			}
			case 'mark_recovery': {
				const week = weekByIndex.get(op.weekIndex);
				if (!week || !isOpenWeek(after.plan, week, todayIso)) break;
				for (const w of weekWorkouts(week.id)) {
					const patch = recoveryWorkoutPatch(w);
					if (patch) Object.assign(w, patch);
				}
				week.target_volume_m = recoveryWeekVolume(week.target_volume_m);
				applied++;
				break;
			}
			case 'skip_workout': {
				const w = editable(op.workoutId);
				if (!w) break;
				w.skipped_at = 'pending';
				applied++;
				break;
			}
		}
	}

	const before = new Map(snapshot.workouts.map((w) => [w.id, w]));
	const workouts: WorkoutChange[] = [];
	for (const w of after.workouts) {
		const old = before.get(w.id);
		if (!old) continue;
		const patch: WorkoutPatch = {};
		for (const field of PATCH_FIELDS) {
			const a = (old as unknown as Record<string, unknown>)[field] ?? null;
			const b = (w as unknown as Record<string, unknown>)[field] ?? null;
			if (a !== b) (patch as Record<string, unknown>)[field] = b;
		}
		const skip = old.skipped_at == null && w.skipped_at != null;
		const hasPatch = Object.keys(patch).length > 0;
		if (!hasPatch && !skip) continue;
		workouts.push({
			workoutId: w.id,
			before: stateOf(old),
			after: stateOf(w),
			patch: hasPatch ? patch : null,
			skip,
		});
	}
	workouts.sort((a, b) => a.before.scheduledDate.localeCompare(b.before.scheduledDate));

	const weeks: WeekChange[] = [];
	for (const w of after.weeks) {
		const old = snapshot.weeks.find((x) => x.id === w.id);
		if (old && old.target_volume_m !== w.target_volume_m) {
			weeks.push({
				weekId: w.id,
				weekIndex: w.week_index,
				beforeVolumeM: old.target_volume_m,
				afterVolumeM: w.target_volume_m,
			});
		}
	}
	weeks.sort((a, b) => a.weekIndex - b.weekIndex);

	return { workouts, weeks, after, applied };
}

/// A week's planned running load: the sum of its non-rest, non-skipped
/// workout distances, or its stated target volume when no workout carries a
/// distance (a duration-only walk-run week).
export function plannedWeekVolumeM(snapshot: PlanEditSnapshot, weekId: string): number {
	let sum = 0;
	let any = false;
	for (const w of snapshot.workouts) {
		if (w.week_id !== weekId || w.kind === 'rest' || w.skipped_at != null) continue;
		if (w.target_distance_m != null && Number.isFinite(w.target_distance_m)) {
			sum += w.target_distance_m;
			any = true;
		}
	}
	if (any) return sum;
	const week = snapshot.weeks.find((w) => w.id === weekId);
	return week?.target_volume_m ?? 0;
}

const BAND_RANK: Record<InjuryRiskBand, number> = {
	insufficient: 0,
	low: 0,
	optimal: 0,
	elevated: 1,
	high: 2,
};

/// Each open week's ACWR band: its planned volume against the mean of the
/// up-to-four weeks before it in the plan, with the runner's recent weekly
/// volume filling the slots before week 0 when it has enough history to mean
/// anything (`MIN_ACTIVE_WEEKS`, the threshold `plan_ramp` uses).
export function openWeekBands(
	snapshot: PlanEditSnapshot,
	recent: Pick<RecentVolume, 'weeklyM' | 'activeWeeks'>,
	todayIso: string,
): Map<number, InjuryRiskBand> {
	const weeks = [...snapshot.weeks].sort((a, b) => a.week_index - b.week_index);
	const volumeByIndex = new Map(weeks.map((w) => [w.week_index, plannedWeekVolumeM(snapshot, w.id)]));
	const recentUsable = recent.activeWeeks >= MIN_ACTIVE_WEEKS && recent.weeklyM > 0;
	const bands = new Map<number, InjuryRiskBand>();
	for (const week of weeks) {
		if (!isOpenWeek(snapshot.plan, week, todayIso)) continue;
		const prior: number[] = [];
		for (let k = 1; k <= PLAN_EDIT_CHRONIC_WEEKS; k++) {
			const idx = week.week_index - k;
			const v = volumeByIndex.get(idx);
			if (v !== undefined) prior.push(v);
			else if (idx < 0 && recentUsable) prior.push(recent.weeklyM);
		}
		const chronic = prior.length > 0 ? prior.reduce((s, v) => s + v, 0) / prior.length : 0;
		bands.set(week.week_index, injuryRiskBand(volumeByIndex.get(week.week_index) ?? 0, chronic));
	}
	return bands;
}

function hardPairs(snapshot: PlanEditSnapshot, todayIso: string): Map<string, [string, string]> {
	const hard = snapshot.workouts
		.filter((w) => HARD_KINDS.has(w.kind) && w.skipped_at == null && w.scheduled_date >= todayIso)
		.sort((a, b) => a.scheduled_date.localeCompare(b.scheduled_date) || a.id.localeCompare(b.id));
	const day = (iso: string) => {
		const [y, m, d] = iso.split('-').map(Number);
		return Math.floor(Date.UTC(y, m - 1, d) / 86_400_000);
	};
	const pairs = new Map<string, [string, string]>();
	for (let i = 0; i < hard.length; i++) {
		for (let j = i + 1; j < hard.length; j++) {
			const gap = day(hard[j].scheduled_date) - day(hard[i].scheduled_date);
			if (gap > 1) break;
			const ids = [hard[i].id, hard[j].id].sort();
			pairs.set(ids.join('|'), [hard[i].scheduled_date, hard[j].scheduled_date]);
		}
	}
	return pairs;
}

export type PlanEditLoadVerdict = 'ok' | 'confirm' | 'reject';

export interface PlanEditLoadCheck {
	verdict: PlanEditLoadVerdict;
	/// Open weeks whose band went up, numbered by `week_index`.
	raisedWeeks: { weekIndex: number; before: InjuryRiskBand; after: InjuryRiskBand }[];
	/// Newly adjacent hard sessions, as their two dates.
	stackedDays: [string, string][];
}

/// Grade an edited plan against the original. Fail-safe in the direction that
/// matters: an edit can only ever make the verdict stricter, never excuse a
/// band the original plan already carried.
export function planEditLoadCheck(
	before: PlanEditSnapshot,
	after: PlanEditSnapshot,
	recent: Pick<RecentVolume, 'weeklyM' | 'activeWeeks'>,
	todayIso: string,
): PlanEditLoadCheck {
	const was = openWeekBands(before, recent, todayIso);
	const now = openWeekBands(after, recent, todayIso);
	const raisedWeeks: PlanEditLoadCheck['raisedWeeks'] = [];
	let reject = false;
	for (const [weekIndex, band] of now) {
		const prior = was.get(weekIndex) ?? 'insufficient';
		if (BAND_RANK[band] > BAND_RANK[prior]) {
			raisedWeeks.push({ weekIndex, before: prior, after: band });
			if (band === 'high') reject = true;
		}
	}
	raisedWeeks.sort((a, b) => a.weekIndex - b.weekIndex);

	const pairsBefore = hardPairs(before, todayIso);
	const stackedDays: [string, string][] = [];
	for (const [key, dates] of hardPairs(after, todayIso)) {
		if (!pairsBefore.has(key)) stackedDays.push(dates);
	}
	stackedDays.sort((a, b) => a[0].localeCompare(b[0]));

	const verdict: PlanEditLoadVerdict = reject
		? 'reject'
		: raisedWeeks.length > 0 || stackedDays.length > 0
			? 'confirm'
			: 'ok';
	return { verdict, raisedWeeks, stackedDays };
}
