// Every race a plan builds toward, not only the one on its end date
// (decisions § 2009): a `race` workout carries its own name and A/B/C
// priority, so a Comrades block can hold Two Oceans as a B race with its own
// countdown and goal. Dart twin `apps/mobile_android/lib/plan_races.dart`.

export const RACE_PRIORITIES = ['A', 'B', 'C'] as const;
export type RacePriority = (typeof RACE_PRIORITIES)[number];

export type PlanRace = {
	date: string;
	name: string | null;
	priority: RacePriority;
	distanceM: number | null;
	goalTimeSec: number | null;
	workoutId: string | null;
};

type RacePlan = { end_date: string; goal_distance_m: number; goal_time_seconds: number | null };

type RaceWorkout = {
	id: string;
	scheduled_date: string;
	kind: string;
	race_name?: string | null;
	race_priority?: string | null;
	target_distance_m: number | null;
	target_duration_seconds: number | null;
};

function parseRacePriority(value: string | null | undefined): RacePriority | null {
	return (RACE_PRIORITIES as readonly string[]).includes(value ?? '') ? (value as RacePriority) : null;
}

/// One entry per `race` workout, sorted by date (ties by workout id). An
/// unset priority is A on the plan's end date and C anywhere else; the
/// end-date race falls back to the plan goal for a missing distance or goal
/// time. A plan with no race workout on its end date gets a synthetic A race
/// there from the plan goal, so a plan without race rows still has its race.
export function planRaces(plan: RacePlan, workouts: RaceWorkout[]): PlanRace[] {
	const races: PlanRace[] = [];
	let endDateCovered = false;
	for (const w of workouts) {
		if (w.kind !== 'race') continue;
		const onEnd = w.scheduled_date === plan.end_date;
		if (onEnd) endDateCovered = true;
		races.push({
			date: w.scheduled_date,
			name: w.race_name ?? null,
			priority: parseRacePriority(w.race_priority) ?? (onEnd ? 'A' : 'C'),
			distanceM: w.target_distance_m ?? (onEnd ? plan.goal_distance_m : null),
			goalTimeSec: w.target_duration_seconds ?? (onEnd ? plan.goal_time_seconds : null),
			workoutId: w.id
		});
	}
	if (!endDateCovered) {
		races.push({
			date: plan.end_date,
			name: null,
			priority: 'A',
			distanceM: plan.goal_distance_m,
			goalTimeSec: plan.goal_time_seconds,
			workoutId: null
		});
	}
	return races.sort((a, b) => {
		if (a.date !== b.date) return a.date < b.date ? -1 : 1;
		const ai = a.workoutId ?? '';
		const bi = b.workoutId ?? '';
		return ai < bi ? -1 : ai > bi ? 1 : 0;
	});
}

/// The first race on or after `todayIso` (race day itself counts), or null
/// once the last race has passed. Expects `races` sorted, as `planRaces`
/// returns them.
export function nextRace(races: PlanRace[], todayIso: string): PlanRace | null {
	return races.find((r) => r.date >= todayIso) ?? null;
}
