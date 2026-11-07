import { isPlausibleRunDuration } from './run_duration';

/// The distance and time a period's average pace divides. A ride is speed, not
/// pace, and a run past the ten-day bound would pair its distance with time the
/// period total already left out — so both are left out of both halves, the
/// rule the Dart `computePeriodStats` applies. Summing the whole period instead
/// made a week of 10 km in 50:00 plus one 12,333-hour 2 km row read 4:10/km.
export function periodPaceTotals(
	runs: readonly { distance_m: number; duration_s: number; activity_type?: string | null }[],
): { distanceM: number; durationS: number } {
	let distanceM = 0;
	let durationS = 0;
	for (const r of runs) {
		if (r.activity_type === 'cycle' || !isPlausibleRunDuration(r.duration_s)) continue;
		distanceM += r.distance_m;
		durationS += r.duration_s;
	}
	return { distanceM, durationS };
}
