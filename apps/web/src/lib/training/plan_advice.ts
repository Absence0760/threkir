/**
 * The advice line a plan week or a workout shows, read from what the row
 * already holds rather than from an English sentence the generator saved
 * into `notes` (decisions § 2347). Pure; each surface localizes the kind.
 *
 * Mirrors `apps/mobile_android/lib/plan_advice.dart` — keep in lockstep
 * (TS↔Dart parity pair, equal test counts).
 */

import { isUltraDistance } from './training.ts';

export type WeekAdviceKind = 'race' | 'taper' | 'graduation' | 'walk_breaks' | 'back_to_back';

export interface AdviceWeekWorkout {
	kind: string;
}

export function weekAdviceKind(
	phase: string,
	workouts: readonly AdviceWeekWorkout[]
): WeekAdviceKind | null {
	if (phase === 'race') return 'race';
	if (phase === 'taper') return 'taper';
	if (phase === 'graduation') return 'graduation';
	if (workouts.some((w) => w.kind === 'walk_run')) return 'walk_breaks';
	// The ultra generator opens the week on Sunday's long run and closes it on
	// Saturday's, the first half of the next weekend's pair.
	return workouts.filter((w) => w.kind === 'long').length >= 2 ? 'back_to_back' : null;
}

export type WorkoutAdviceKind =
	| 'easy'
	| 'long'
	| 'time_on_feet'
	| 'tempo'
	| 'interval'
	| 'marathon_pace'
	| 'walk_run'
	| 'race'
	| 'ultra_race'
	| 'rest';

export interface AdviceWorkout {
	kind: string;
	target_distance_m: number | null;
	target_duration_seconds: number | null;
	target_pace_sec_per_km: number | null;
}

/// A long run set by time with no pace is a time-on-feet run (the ultra
/// generator's shape); a race past the marathon is an ultra race.
export function workoutAdviceKind(w: AdviceWorkout): WorkoutAdviceKind {
	switch (w.kind) {
		case 'easy':
		case 'recovery':
			return 'easy';
		case 'long':
			return w.target_duration_seconds != null &&
				w.target_duration_seconds > 0 &&
				w.target_pace_sec_per_km == null
				? 'time_on_feet'
				: 'long';
		case 'tempo':
		case 'interval':
		case 'marathon_pace':
		case 'walk_run':
			return w.kind;
		case 'race':
			return w.target_distance_m != null && isUltraDistance(w.target_distance_m)
				? 'ultra_race'
				: 'race';
		default:
			return 'rest';
	}
}
