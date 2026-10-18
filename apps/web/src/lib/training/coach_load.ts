/**
 * Coach-roster injury-risk + load-band classification (coach_roster.md).
 *
 * Pure (no Svelte / Supabase) so it runs under `npx tsx --test` and stays the
 * single place the acute:chronic-workload-ratio (ACWR) risk policy lives —
 * web, mobile, and the coach_roster_summary RPC's display all classify through
 * this, so the thresholds can't drift. The RPC returns RAW acute (7d) +
 * chronic (28d-avg-per-7d) load sums; this helper turns them into the ratio,
 * the injury-risk band, and the load trend label the roster column shows.
 *
 * Dart twin: apps/mobile_android/lib/coach_load.dart (parity pair — keep the
 * algorithm, band edges, and test counts in lockstep).
 */

import { isWorkoutMissed } from './plan_current';

export type InjuryRiskBand = 'insufficient' | 'low' | 'optimal' | 'elevated' | 'high';
export type LoadTrend = 'ramping' | 'steady' | 'tapering';

/// ACWR band edges (the sports-science "sweet spot" model). A ratio in
/// [0.8, 1.3) is the protective optimal zone; below 0.8 is detraining/low;
/// [1.3, 1.5) is elevated; >=1.5 is the high-spike injury-risk zone. Exported
/// so the tests pin the exact boundaries and the UI can reference them.
export const ACWR_LOW_MAX = 0.8;
export const ACWR_OPTIMAL_MAX = 1.3;
export const ACWR_ELEVATED_MAX = 1.5;

/// Load-trend edges around 1.0 (acute vs chronic). A ±15% deadband keeps a
/// roughly-steady athlete out of the ramping/tapering labels.
export const TREND_TAPER_MAX = 0.85;
export const TREND_RAMP_MIN = 1.15;

/// Acute:chronic workload ratio. `chronic28dAvg` is the average weekly load
/// over the trailing 28 days (the RPC's load_chronic). Returns 0 when there is
/// no chronic base to divide by — the band classifier reads that as
/// "insufficient", never a false "low" (ACWR needs ~28 days of history to mean
/// anything; open question #1 in the spec).
export function acwr(acute7d: number, chronic28dAvg: number): number {
	if (!Number.isFinite(acute7d) || !Number.isFinite(chronic28dAvg)) return 0;
	if (chronic28dAvg <= 0) return 0;
	return acute7d / chronic28dAvg;
}

/// Bucket the ratio into an injury-risk band. A zero/negative chronic base (no
/// meaningful history) returns 'insufficient' rather than guessing — the
/// roster shows that honestly instead of a green "low" that would read as
/// "safe to push" for a brand-new athlete.
export function injuryRiskBand(acute7d: number, chronic28dAvg: number): InjuryRiskBand {
	if (!Number.isFinite(chronic28dAvg) || chronic28dAvg <= 0) return 'insufficient';
	const ratio = acwr(acute7d, chronic28dAvg);
	if (ratio < ACWR_LOW_MAX) return 'low';
	if (ratio < ACWR_OPTIMAL_MAX) return 'optimal';
	if (ratio < ACWR_ELEVATED_MAX) return 'elevated';
	return 'high';
}

/// Load-trend label for the roster's load column. 'ramping' when acute load
/// runs >15% above the chronic average, 'tapering' when >15% below, else
/// 'steady'. Falls back to 'steady' when there's no chronic base (a single
/// week of data isn't a trend).
export function loadTrend(acute7d: number, chronic28dAvg: number): LoadTrend {
	if (!Number.isFinite(chronic28dAvg) || chronic28dAvg <= 0) return 'steady';
	const ratio = acwr(acute7d, chronic28dAvg);
	if (ratio <= TREND_TAPER_MAX) return 'tapering';
	if (ratio >= TREND_RAMP_MIN) return 'ramping';
	return 'steady';
}

/// One of an athlete's recent planned workouts as `coach_roster_summary`
/// returns it in `recent_workouts` — the shape `isWorkoutMissed` takes.
export interface RosterRecentWorkout {
	scheduled_date: string;
	kind: string;
	completed: boolean;
	skipped: boolean;
}

/// Read `recent_workouts` off a roster row. An element missing its date or
/// kind drops out instead of failing the whole row; a non-array reads as none.
export function parseRosterRecentWorkouts(json: unknown): RosterRecentWorkout[] {
	if (!Array.isArray(json)) return [];
	const out: RosterRecentWorkout[] = [];
	for (const e of json) {
		if (!e || typeof e !== 'object') continue;
		const r = e as Record<string, unknown>;
		if (typeof r.scheduled_date !== 'string' || typeof r.kind !== 'string') continue;
		out.push({
			scheduled_date: r.scheduled_date,
			kind: r.kind,
			completed: r.completed === true,
			skipped: r.skipped === true
		});
	}
	return out;
}

/// Consecutive misses at or above which the roster flags the athlete.
export const CONSECUTIVE_MISS_FLAG = 2;

/// The athlete's current run of missed workouts, counting back from their
/// local yesterday. "Missed" is `isWorkoutMissed` from the plan_current pair,
/// never restated here, so the roster agrees with the athlete's own plan. A
/// done workout ends the run; a skipped one (an intentional change) and a rest
/// day neither count nor end it. Order of `recent` does not matter.
export function consecutiveMissedWorkouts(recent: RosterRecentWorkout[], todayIso: string): number {
	const past = recent
		.filter((w) => w.scheduled_date < todayIso)
		.sort((a, b) => (a.scheduled_date < b.scheduled_date ? 1 : a.scheduled_date > b.scheduled_date ? -1 : 0));
	let run = 0;
	for (const w of past) {
		if (isWorkoutMissed(w, todayIso)) {
			run += 1;
		} else if (w.completed) {
			break;
		}
	}
	return run;
}

/// Easy-run heart-rate drift (per cent) at or above which the roster flags it.
/// The RPC computes it as the change in mean heart rate on the athlete's
/// planned easy runs held within 15 s/km of their median easy pace, recent 14
/// days against the 42 before, only under health-data consent.
export const EASY_HR_DRIFT_FLAG_PCT = 5;

export function isEasyHrDriftFlagged(driftPct: number | null | undefined): boolean {
	return driftPct != null && Number.isFinite(driftPct) && driftPct >= EASY_HR_DRIFT_FLAG_PCT;
}
