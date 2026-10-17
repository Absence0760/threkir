// The days a planned workout can be moved to (decisions § 2073).
//
// A workout moves inside its own plan week and the plan's dates, never onto a
// day already past, and never displaces a completed workout or a race. A day
// that already holds a row is offered with that row as its occupant: the move
// trades the two days (`move_plan_workout`). The server enforces the week,
// the plan's dates and completion; the past and races are the pickers' rule.
//
// Dart twin: apps/mobile_android/lib/plan_move.dart. Keep the algorithm, edge
// cases, outputs and test counts in lockstep.

import { shiftIsoDate } from './plan_bulk_ops';
import { isWorkoutCompleted } from './training';

export interface MovableWorkout {
	id: string;
	week_id: string;
	scheduled_date: string;
	kind: string;
	completed_run_id?: string | null;
	manually_completed?: boolean | null;
}

export interface WorkoutMoveDay<W extends MovableWorkout> {
	date: string;
	/// The row already on that day, which takes the moved workout's old day.
	occupant: W | null;
}

/// Whether a move may push this workout to another day by taking its day.
export function canDisplaceForMove(w: MovableWorkout): boolean {
	return !isWorkoutCompleted(w) && w.kind !== 'race';
}

/// The days `workout` (in plan week `weekIndex`) may move to, in date order.
/// Empty for a completed workout, which keeps its day.
export function workoutMoveDays<W extends MovableWorkout>(
	planStartIso: string,
	planEndIso: string,
	weekIndex: number,
	workout: W,
	workouts: readonly W[],
	todayIso: string,
): WorkoutMoveDay<W>[] {
	if (isWorkoutCompleted(workout)) return [];
	const weekStart = shiftIsoDate(planStartIso, weekIndex * 7);
	const days: WorkoutMoveDay<W>[] = [];
	for (let i = 0; i < 7; i++) {
		const date = shiftIsoDate(weekStart, i);
		if (date > planEndIso) break;
		if (date === workout.scheduled_date || date < todayIso) continue;
		const occupant =
			workouts.find(
				(o) => o.id !== workout.id && o.week_id === workout.week_id && o.scheduled_date === date,
			) ?? null;
		if (occupant && !canDisplaceForMove(occupant)) continue;
		days.push({ date, occupant });
	}
	return days;
}
