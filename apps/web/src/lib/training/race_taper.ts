// A mini-taper and a recovery window around each B and C race a plan holds
// (decisions § 2051). The plan's phases (base/build/peak/taper/race) come from
// week position toward the end date, so they only ever taper for the A race;
// a B race in week 14 of a 30-week block got no easing either side of it.
// Pure: takes the plan's workouts, its races (`planRaces`) and today, and
// proposes per-workout changes the plan page previews before applying.
// Dart twin `apps/mobile_android/lib/race_taper.dart` — keep the windows,
// scales, tie-breaks and test counts in lockstep.

import { daysBetweenIso } from './cycle_plan';
import type { PlanRace } from './plan_races';

/// Days before a B race whose sessions are cut, and the cut: 35% off volume
/// across the 6 days, every quality session run easy. A tune-up race wants a
/// mini-taper of about a week at a 30-40% reduction, not the 2-3 weeks an A
/// race gets (Pfitzinger, Advanced Marathoning, tune-up races; Mujika &
/// Padilla 2003: volume is the lever, intensity can stay — but a B race is
/// the intensity that week, so the quality session goes).
export const B_TAPER_DAYS = 6;
export const B_TAPER_SCALE = 0.65;
/// The last 2 days before a B race carry only an easy shakeout: half the
/// prescribed distance, never more than 5 km.
export const B_SHAKEOUT_DAYS = 2;
export const SHAKEOUT_SCALE = 0.5;
export const SHAKEOUT_MAX_M = 5000;
/// Easy days after a B race: one per 3 km raced, held between 4 and 7
/// (5 when the race has no distance). The "a day per mile raced" rule is for
/// an all-out A effort; a B race is run hard off a short taper, so half that
/// density, inside the 4-7 day window a 10 km-to-half recovers in.
export const B_RECOVERY_KM_PER_DAY = 3;
export const B_RECOVERY_MIN_DAYS = 4;
export const B_RECOVERY_MAX_DAYS = 7;
export const B_RECOVERY_DEFAULT_DAYS = 5;
/// A C race is a training-load race (a parkrun, a club 10 km): 3 days before
/// eased by 20%, quality run easy, and 2 easy days after.
export const C_TAPER_DAYS = 3;
export const C_TAPER_SCALE = 0.8;
export const C_RECOVERY_DAYS = 2;
/// The long run inside a recovery window is held to 75% of its prescription.
export const RECOVERY_LONG_SCALE = 0.75;

const QUALITY_KINDS = new Set(['tempo', 'interval', 'marathon_pace']);
/// The A race's own taper already governs these weeks; a B race inside them
/// does not get to cut it twice.
const PROTECTED_PHASES = new Set(['taper', 'race']);

export type RaceTaperReason = 'pre_race' | 'shakeout' | 'post_race';

export type RaceTaperWorkout = {
	id: string;
	scheduledDate: string;
	kind: string;
	targetDistanceM: number | null;
	/// Phase of the week the workout sits in, when known.
	phase: string | null;
	/// Linked to a run or ticked done by hand.
	completed: boolean;
	skipped: boolean;
	/// Already eased by an applied taper (`race_taper_applied_at`). Its
	/// distance is the eased one, so scaling it again would compound.
	taperApplied: boolean;
};

export type RaceTaperChange = {
	workoutId: string;
	scheduledDate: string;
	reason: RaceTaperReason;
	raceDate: string;
	raceName: string | null;
	racePriority: 'B' | 'C';
	fromKind: string;
	toKind: string;
	fromMetres: number | null;
	toMetres: number | null;
	/// The session loses its pace target, tolerance and interval structure.
	clearsPace: boolean;
};

export type RaceTaperPatch = {
	kind?: string;
	target_distance_m?: number | null;
	target_pace_sec_per_km?: null;
	target_pace_tolerance_sec?: null;
	structure?: null;
};

const SEVERITY: Record<RaceTaperReason, number> = { shakeout: 3, pre_race: 2, post_race: 1 };

type Window = { reason: RaceTaperReason; race: PlanRace & { priority: 'B' | 'C' } };

function recoveryDays(race: PlanRace): number {
	if (race.priority === 'C') return C_RECOVERY_DAYS;
	if (race.distanceM == null || !(race.distanceM > 0)) return B_RECOVERY_DEFAULT_DAYS;
	const days = Math.round(race.distanceM / 1000 / B_RECOVERY_KM_PER_DAY);
	return Math.min(B_RECOVERY_MAX_DAYS, Math.max(B_RECOVERY_MIN_DAYS, days));
}

function windowFor(race: Window['race'], offset: number): RaceTaperReason | null {
	if (offset < 0) {
		const before = -offset;
		if (race.priority === 'B') {
			if (before <= B_SHAKEOUT_DAYS) return 'shakeout';
			return before <= B_TAPER_DAYS ? 'pre_race' : null;
		}
		return before <= C_TAPER_DAYS ? 'pre_race' : null;
	}
	if (offset > 0 && offset <= recoveryDays(race)) return 'post_race';
	return null;
}

function scaled(m: number | null, scale: number): number | null {
	return m == null ? null : Math.round(m * scale);
}

function adjust(
	w: RaceTaperWorkout,
	reason: RaceTaperReason,
	priority: 'B' | 'C'
): { toKind: string; toMetres: number | null; clearsPace: boolean } {
	const quality = QUALITY_KINDS.has(w.kind);
	// Only a quality session or a long run changes kind: an easy, recovery or
	// walk/run day is already the right kind of session, just shorter.
	const eased = quality || w.kind === 'long' ? 'easy' : w.kind;
	if (reason === 'shakeout') {
		const half = scaled(w.targetDistanceM, SHAKEOUT_SCALE);
		return {
			toKind: eased,
			toMetres: half == null ? null : Math.min(half, SHAKEOUT_MAX_M),
			clearsPace: quality
		};
	}
	if (reason === 'pre_race') {
		const scale = priority === 'B' ? B_TAPER_SCALE : C_TAPER_SCALE;
		return {
			toKind: eased,
			toMetres: scaled(w.targetDistanceM, scale),
			clearsPace: quality
		};
	}
	if (quality) return { toKind: 'easy', toMetres: w.targetDistanceM, clearsPace: true };
	if (w.kind === 'long') {
		return {
			toKind: 'long',
			toMetres: scaled(w.targetDistanceM, RECOVERY_LONG_SCALE),
			clearsPace: false
		};
	}
	return { toKind: w.kind, toMetres: w.targetDistanceM, clearsPace: false };
}

/// The proposed changes around every B and C race dated after `today`,
/// sorted by date then workout id. Expects `races` sorted, as `planRaces`
/// returns them. Only workouts dated today or later that are not done,
/// skipped, a rest day, a race, already eased by an applied taper, or inside
/// the A race's taper/race weeks are touched. A workout inside two races'
/// windows takes the stronger rule (shakeout, then taper, then recovery; then
/// the B race, then the earlier race). A workout the rule would leave
/// unchanged yields no change.
export function raceTaperProposals(input: {
	workouts: RaceTaperWorkout[];
	races: PlanRace[];
	today: string;
}): RaceTaperChange[] {
	const races = input.races.filter(
		(r): r is Window['race'] => (r.priority === 'B' || r.priority === 'C') && r.date > input.today
	);
	const changes: RaceTaperChange[] = [];
	for (const w of input.workouts) {
		if (w.scheduledDate < input.today) continue;
		if (w.completed || w.skipped || w.taperApplied) continue;
		if (w.kind === 'rest' || w.kind === 'race') continue;
		if (w.phase != null && PROTECTED_PHASES.has(w.phase)) continue;
		let best: Window | null = null;
		for (const race of races) {
			const offset = daysBetweenIso(race.date, w.scheduledDate);
			if (offset == null) continue;
			const reason = windowFor(race, offset);
			if (reason == null) continue;
			if (
				best == null ||
				SEVERITY[reason] > SEVERITY[best.reason] ||
				(SEVERITY[reason] === SEVERITY[best.reason] &&
					race.priority === 'B' &&
					best.race.priority === 'C')
			) {
				best = { reason, race };
			}
		}
		if (best == null) continue;
		const a = adjust(w, best.reason, best.race.priority);
		if (a.toKind === w.kind && a.toMetres === w.targetDistanceM && !a.clearsPace) continue;
		changes.push({
			workoutId: w.id,
			scheduledDate: w.scheduledDate,
			reason: best.reason,
			raceDate: best.race.date,
			raceName: best.race.name,
			racePriority: best.race.priority,
			fromKind: w.kind,
			toKind: a.toKind,
			fromMetres: w.targetDistanceM,
			toMetres: a.toMetres,
			clearsPace: a.clearsPace
		});
	}
	return changes.sort((x, y) => {
		if (x.scheduledDate !== y.scheduledDate) return x.scheduledDate < y.scheduledDate ? -1 : 1;
		return x.workoutId < y.workoutId ? -1 : x.workoutId > y.workoutId ? 1 : 0;
	});
}

/// The plan_workouts columns one change writes.
export function raceTaperPatch(c: RaceTaperChange): RaceTaperPatch {
	const patch: RaceTaperPatch = {};
	if (c.toKind !== c.fromKind) patch.kind = c.toKind;
	if (c.toMetres !== c.fromMetres) patch.target_distance_m = c.toMetres;
	if (c.clearsPace) {
		patch.target_pace_sec_per_km = null;
		patch.target_pace_tolerance_sec = null;
		patch.structure = null;
	}
	return patch;
}

/// Every change as an `apply_workout_adjustments` entry, each stamped with
/// `race_taper_applied_at` so the next proposal leaves the eased workout
/// alone. Web-only: mobile's `TrainingService.applyRaceTaper` stamps the
/// same column.
export function raceTaperAdjustments(
	changes: RaceTaperChange[],
	appliedAt: string
): Array<RaceTaperPatch & { id: string; race_taper_applied_at: string }> {
	return changes.map((c) => ({ id: c.workoutId, ...raceTaperPatch(c), race_taper_applied_at: appliedAt }));
}
