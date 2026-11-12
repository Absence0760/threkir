/**
 * Re-derive a plan's paces when its goal time changes (issue #1186). Every
 * training pace is a fixed multiple of goal pace (`pacesFromGoalPace`), so the
 * paces a new goal time would generate are the old ones scaled by new goal
 * pace / old goal pace. A plan anchored on a recent 5K resolves the same goal
 * pace either way and gets no changes, which is the generator's own priority.
 *
 * Only workouts still ahead and still open are touched: a completed or
 * skipped session is history, and so is anything before today.
 */

import { isWorkoutCompleted, isWorkoutSkipped, resolveTrainingPacesWithMeta } from './training.ts';

export interface RepaceWorkout {
	id: string;
	scheduled_date: string; // ISO YYYY-MM-DD
	kind: string;
	target_pace_sec_per_km: number | null;
	target_duration_seconds: number | null;
	structure: unknown;
	completed_run_id?: string | null;
	manually_completed?: boolean | null;
	skipped_at?: string | null;
}

export interface RepacePatch {
	id: string;
	target_pace_sec_per_km?: number;
	target_duration_seconds?: number;
	structure?: unknown;
}

/// The goal pace (sec/km) the plan's paces were derived from, the way the
/// generator resolves it.
function goalPace(goalDistanceM: number, goalTimeSec: number | null, recent5kSec: number | null): number {
	return resolveTrainingPacesWithMeta({ goalDistanceM, goalTimeSec, recent5kSec }).goalPaceSecPerKm;
}

/// `structure` with every `pace_sec_per_km` scaled by `ratio`. Effort labels
/// (`pace: 'easy'`, `recovery_pace: 'jog'`) are not paces and stay as they are.
export function scaleStructurePaces(structure: unknown, ratio: number): unknown {
	if (Array.isArray(structure)) return structure.map((s) => scaleStructurePaces(s, ratio));
	if (structure === null || typeof structure !== 'object') return structure;
	const out: Record<string, unknown> = {};
	for (const [k, v] of Object.entries(structure as Record<string, unknown>)) {
		out[k] =
			k === 'pace_sec_per_km' && typeof v === 'number'
				? Math.round(v * ratio)
				: scaleStructurePaces(v, ratio);
	}
	return out;
}

/// The patches a goal-time change from `oldGoalTimeSec` to `newGoalTimeSec`
/// implies for `workouts`, as of `todayIso`. A race workout carrying the old
/// goal time as its target takes the new one.
export function goalTimeRepacePatches(input: {
	goalDistanceM: number;
	oldGoalTimeSec: number | null;
	newGoalTimeSec: number | null;
	recent5kSec: number | null;
	todayIso: string;
	workouts: RepaceWorkout[];
}): RepacePatch[] {
	const { goalDistanceM, oldGoalTimeSec, newGoalTimeSec, recent5kSec } = input;
	if (oldGoalTimeSec === newGoalTimeSec) return [];
	const ratio =
		goalPace(goalDistanceM, newGoalTimeSec, recent5kSec) / goalPace(goalDistanceM, oldGoalTimeSec, recent5kSec);
	const goalChanged = oldGoalTimeSec != null && newGoalTimeSec != null && newGoalTimeSec > 0;
	const patches: RepacePatch[] = [];
	for (const w of input.workouts) {
		if (w.scheduled_date < input.todayIso) continue;
		if (isWorkoutCompleted(w) || isWorkoutSkipped(w)) continue;
		const patch: RepacePatch = { id: w.id };
		if (ratio !== 1 && w.target_pace_sec_per_km != null) {
			const next = Math.round(w.target_pace_sec_per_km * ratio);
			if (next !== w.target_pace_sec_per_km) patch.target_pace_sec_per_km = next;
		}
		if (ratio !== 1 && w.structure != null) {
			const next = scaleStructurePaces(w.structure, ratio);
			if (JSON.stringify(next) !== JSON.stringify(w.structure)) patch.structure = next;
		}
		if (goalChanged && w.kind === 'race' && w.target_duration_seconds === oldGoalTimeSec) {
			patch.target_duration_seconds = newGoalTimeSec!;
		}
		if (Object.keys(patch).length > 1) patches.push(patch);
	}
	return patches;
}
