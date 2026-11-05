// Every race a plan builds toward, not only the one on its end date
// (decisions § 2009): a `race` workout carries its own name and A/B/C
// priority, so a Comrades block can hold Two Oceans as a B race with its own
// countdown and goal. Dart twin `apps/mobile_android/lib/plan_races.dart`.

export const RACE_PRIORITIES = ['A', 'B', 'C'] as const;
/// The most hours a race goal time may hold, on every surface that reads or
/// edits one: a 240-mile race runs past 100 hours, so two digits would not do.
export const RACE_GOAL_MAX_HOURS = 999;
export type RacePriority = (typeof RACE_PRIORITIES)[number];

export type PlanRace = {
	date: string;
	name: string | null;
	priority: RacePriority;
	distanceM: number | null;
	goalTimeSec: number | null;
	workoutId: string | null;
};

type RacePlan = {
	end_date: string;
	goal_distance_m: number;
	goal_time_seconds: number | null;
	trimmed_at: string | null;
};

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

/// Plans built before #1294 end on the Saturday after their race week's
/// Sunday race, so the goal race sits up to six days before `end_date`.
const RACE_WEEK_DAYS = 7;

function isoDaysBefore(iso: string, days: number): string {
	const [y, m, d] = iso.split('-').map(Number);
	return new Date(Date.UTC(y, m - 1, d - days)).toISOString().slice(0, 10);
}

/// The race-week race that stands in for the goal race when nothing is on
/// the end date: the latest race in the final week with no priority or A.
function raceWeekGoal(plan: RacePlan, races: RaceWorkout[]): RaceWorkout | null {
	if (plan.trimmed_at || races.some((w) => w.scheduled_date === plan.end_date)) return null;
	const weekStart = isoDaysBefore(plan.end_date, RACE_WEEK_DAYS - 1);
	let goal: RaceWorkout | null = null;
	for (const w of races) {
		if (w.scheduled_date < weekStart || w.scheduled_date > plan.end_date) continue;
		const priority = parseRacePriority(w.race_priority);
		if (priority !== null && priority !== 'A') continue;
		if (
			goal === null ||
			w.scheduled_date > goal.scheduled_date ||
			(w.scheduled_date === goal.scheduled_date && w.id > goal.id)
		) {
			goal = w;
		}
	}
	return goal;
}

/// One entry per `race` workout, sorted by date (ties by workout id). An
/// unset priority is A on the plan's goal race and C anywhere else; the goal
/// race falls back to the plan goal for a missing distance or goal time. The
/// goal race is the race on the end date, or, with none there, the latest
/// race in the final seven days with no priority or A (`raceWeekGoal`). A plan
/// with neither gets a synthetic A race on its end date from the plan goal, so
/// a plan without race rows still has its race — unless the plan was ended
/// early (`trimmed_at`, migration 20270830000003): its end date is then the
/// day it was cut short, not a race day, and the goal race no longer happens
/// inside it.
export function planRaces(plan: RacePlan, workouts: RaceWorkout[]): PlanRace[] {
	const raceRows = workouts.filter((w) => w.kind === 'race');
	const weekGoal = raceWeekGoal(plan, raceRows);
	const races: PlanRace[] = raceRows.map((w) => {
		const isGoal = w.scheduled_date === plan.end_date || w === weekGoal;
		return {
			date: w.scheduled_date,
			name: w.race_name ?? null,
			priority: parseRacePriority(w.race_priority) ?? (isGoal ? 'A' : 'C'),
			distanceM: w.target_distance_m ?? (isGoal ? plan.goal_distance_m : null),
			goalTimeSec: w.target_duration_seconds ?? (isGoal ? plan.goal_time_seconds : null),
			workoutId: w.id
		};
	});
	const goalCovered = weekGoal !== null || raceRows.some((w) => w.scheduled_date === plan.end_date);
	if (!goalCovered && !plan.trimmed_at) {
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
