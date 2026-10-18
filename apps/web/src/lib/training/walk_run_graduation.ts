/**
 * The couch-to-5K completion moment: whether a walk-run plan's runner has
 * graduated, which is when the plan's last walk-run session (the 5K the
 * generator ends on, `WALK_RUN_GRADUATION_M`) is done. Pure; the plan page
 * shows the celebration and the next step off it.
 *
 * Mirrors `apps/mobile_android/lib/walk_run_graduation.dart` — keep in
 * lockstep (TS↔Dart parity pair, equal test counts).
 */

import { isWalkRunPlan } from './plan_restart.ts';
import { WALK_RUN_GRADUATION_M } from './training.ts';

export interface GraduationWorkout {
	id: string;
	kind: string;
	/// ISO scheduled date (YYYY-MM-DD).
	scheduled_date: string;
	/// Done: linked to a run or marked complete.
	done: boolean;
	/// A recorded run is linked to the session (`completed_run_id`). A manual
	/// tick is done, but is no evidence of what was run.
	linkedRun: boolean;
	/// The distance the session's one run ends on, when it ends on one
	/// (`structure.repeats.distance_m`).
	runDistanceM: number | null;
}

export interface WalkRunGraduation {
	workoutId: string;
	/// ISO date of the graduation session.
	date: string;
	/// The last session was the 5K and a recorded run backs it. A plan
	/// generated before the graduation run ended on a 5K finished on a timed
	/// run instead, and a 5K only ticked off by hand is not claimed as run;
	/// both are told they finished.
	ranFiveK: boolean;
}

/// The distance a stored `plan_workouts.structure` ends its run on
/// (`repeats.distance_m`), or null when it ends on time or is unreadable.
export function structureRunDistanceM(structure: unknown): number | null {
	if (structure == null || typeof structure !== 'object' || Array.isArray(structure)) return null;
	const r = (structure as Record<string, unknown>).repeats;
	if (r == null || typeof r !== 'object' || Array.isArray(r)) return null;
	const d = (r as Record<string, unknown>).distance_m;
	return typeof d === 'number' && Number.isFinite(d) && d > 0 ? d : null;
}

/// The graduation, or null when the plan is not a walk-run plan or its last
/// walk-run session is not done yet. A skipped last session is not a
/// graduation. Of two sessions on the last date, the later in plan order is
/// the last.
export function walkRunGraduation(workouts: readonly GraduationWorkout[]): WalkRunGraduation | null {
	if (!isWalkRunPlan(workouts)) return null;
	let last: GraduationWorkout | null = null;
	for (const w of workouts) {
		if (w.kind !== 'walk_run') continue;
		if (last === null || w.scheduled_date >= last.scheduled_date) last = w;
	}
	if (last === null || !last.done) return null;
	return {
		workoutId: last.id,
		date: last.scheduled_date,
		ranFiveK: last.linkedRun && last.runDistanceM != null && last.runDistanceM >= WALK_RUN_GRADUATION_M
	};
}
