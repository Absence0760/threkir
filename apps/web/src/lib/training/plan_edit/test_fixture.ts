// Shared plan fixture for the plan_edit suites. Not a test file itself.
//
// A four-week plan starting Monday 2026-10-12, read on Thursday 2026-10-15:
// week 1 is the current week (Tuesday already done), weeks 2-3 are build and
// peak, week 4 is the taper ending in the race on Sunday 2026-11-08.

import type { PlanEditSnapshot, PlanEditWorkout } from './ops';

export const TODAY = '2026-10-15';

function wo(
	id: string,
	week: number,
	date: string,
	kind: string,
	km: number | null,
	extra: Partial<PlanEditWorkout> = {},
): PlanEditWorkout {
	return {
		id,
		week_id: `wk${week}`,
		scheduled_date: date,
		kind,
		target_distance_m: km == null ? null : km * 1000,
		target_duration_seconds: null,
		target_pace_sec_per_km: kind === 'tempo' || kind === 'interval' ? 270 : null,
		target_pace_tolerance_sec: kind === 'tempo' || kind === 'interval' ? 10 : null,
		structure: null,
		completed_run_id: null,
		manually_completed: false,
		skipped_at: null,
		...extra,
	};
}

export function fixture(): PlanEditSnapshot {
	return {
		plan: { start_date: '2026-10-12', end_date: '2026-11-08', goal_distance_m: 21_097, goal_time_seconds: null },
		weeks: [
			{ id: 'wk0', week_index: 0, phase: 'build', target_volume_m: 40_000 },
			{ id: 'wk1', week_index: 1, phase: 'build', target_volume_m: 42_000 },
			{ id: 'wk2', week_index: 2, phase: 'peak', target_volume_m: 44_000 },
			{ id: 'wk3', week_index: 3, phase: 'taper', target_volume_m: 30_000 },
		],
		workouts: [
			wo('a-int', 0, '2026-10-13', 'interval', 8, { manually_completed: true }),
			wo('a-easy', 0, '2026-10-15', 'easy', 8),
			wo('a-tempo', 0, '2026-10-17', 'tempo', 10),
			wo('a-long', 0, '2026-10-18', 'long', 14),
			wo('b-int', 1, '2026-10-20', 'interval', 8, { structure: { reps: 5 } }),
			wo('b-easy', 1, '2026-10-22', 'easy', 8),
			wo('b-rest', 1, '2026-10-23', 'rest', null),
			wo('b-easy2', 1, '2026-10-24', 'easy', 6),
			wo('b-long', 1, '2026-10-25', 'long', 20),
			wo('c-tempo', 2, '2026-10-27', 'tempo', 10),
			wo('c-easy', 2, '2026-10-29', 'easy', 10),
			wo('c-long', 2, '2026-11-01', 'long', 24),
			wo('d-easy', 3, '2026-11-03', 'easy', 8),
			wo('d-tempo', 3, '2026-11-05', 'tempo', 6),
			wo('d-race', 3, '2026-11-08', 'race', 16),
		],
	};
}
