/**
 * Which week of a training plan a given day falls in.
 *
 * The offset between the plan's start date and today is counted in whole UTC
 * epoch-days rather than by subtracting two local-midnight `Date` values: a
 * local-midnight span that crosses a DST transition is not an exact multiple
 * of 86.4M ms (it is ±1h), so raw local-ms division would `Math.floor` a day
 * short and, on a 7-day boundary, report the previous week. Mirrors the
 * `isoToEpochDay` approach in `cycle_plan.ts`.
 */

function isoToEpochDay(iso: string): number {
	const [y, m, d] = iso.split('-').map((n) => parseInt(n, 10));
	return Math.floor(Date.UTC(y, m - 1, d) / 86_400_000);
}

export function currentPlanWeekIndex(
	startDateIso: string,
	todayIso: string,
	weekCount: number
): number {
	const dayIndex = isoToEpochDay(todayIso) - isoToEpochDay(startDateIso);
	if (dayIndex < 0) return 0;
	return Math.min(weekCount - 1, Math.floor(dayIndex / 7));
}

/**
 * Where today sits against a plan's race day (its end date): before the plan
 * starts, counting down to the race, on it, or past it. `days` is whole days to
 * the start (`starts_in`) or to the race (`race_in`), counted in epoch-days for
 * the same DST reason as above; it is 0 for `race_day` and `race_past`. Callers
 * own the wording ("Race tomorrow" is `race_in` with 1).
 */
export type PlanRaceCountdown =
	| { kind: 'starts_in'; days: number }
	| { kind: 'race_in'; days: number }
	| { kind: 'race_day'; days: 0 }
	| { kind: 'race_past'; days: 0 };

export function planRaceCountdown(
	startDateIso: string,
	endDateIso: string,
	todayIso: string
): PlanRaceCountdown {
	const today = isoToEpochDay(todayIso);
	const start = isoToEpochDay(startDateIso);
	const end = isoToEpochDay(endDateIso);
	if (today < start) return { kind: 'starts_in', days: start - today };
	if (today > end) return { kind: 'race_past', days: 0 };
	if (today === end) return { kind: 'race_day', days: 0 };
	return { kind: 'race_in', days: end - today };
}
