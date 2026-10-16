import { RACE_GOAL_MAX_HOURS } from './plan_races.ts';

/// Reads the workout editor's three goal-time boxes. The editor is not a
/// <form>, so the inputs' min/max never stop a save; this is the check.
/// All blank (or all zero) is no goal; anything else must be whole numbers,
/// hours up to RACE_GOAL_MAX_HOURS and minutes / seconds under 60.
export function raceGoalInputSeconds(
	hours: number | null,
	minutes: number | null,
	seconds: number | null,
): { ok: true; seconds: number | null } | { ok: false } {
	const h = hours ?? 0;
	const m = minutes ?? 0;
	const s = seconds ?? 0;
	const whole = (n: number) => Number.isInteger(n) && n >= 0;
	if (!whole(h) || !whole(m) || !whole(s)) return { ok: false };
	if (h > RACE_GOAL_MAX_HOURS || m > 59 || s > 59) return { ok: false };
	const total = h * 3600 + m * 60 + s;
	return { ok: true, seconds: total > 0 ? total : null };
}
