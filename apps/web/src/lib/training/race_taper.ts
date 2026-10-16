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
import type { JsonObject } from '../types';

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
/// Past the marathon a B race costs more than a week: the recovery keeps the
/// 7 days a marathon gets and adds a day per 2 km beyond it, up to 21 — so a
/// 56 km Two Oceans inside a Comrades block takes the two easy weeks Comrades
/// programmes give it, and a 90 km race the three-week ceiling. Road races are
/// unchanged.
export const B_ULTRA_RECOVERY_KM_PER_DAY = 2;
export const B_ULTRA_RECOVERY_MAX_DAYS = 21;
/// An ultra B race's taper starts 8 days out instead of 6, so the whole
/// weekend before it — a back-to-back long run on any weekday the race falls —
/// is eased, not just its Sunday.
export const B_ULTRA_TAPER_DAYS = 8;
const MARATHON_M = 42_195;
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
	targetDurationSeconds: number | null;
	/// The workout's `structure` jsonb; only a walk/run's is rebuilt.
	structure: unknown;
	notes: string | null;
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
	fromDurationS: number | null;
	toDurationS: number | null;
	/// The session loses its pace target, tolerance and interval structure.
	clearsPace: boolean;
	/// `structure` is rewritten to `toStructure`: a walk/run's repeats cut to
	/// the shorter session, or null when the kind changes under it.
	structureChanged: boolean;
	toStructure: JsonObject | null;
	/// The notes described a session that no longer exists (the kind changed,
	/// or a walk/run's structure was rebuilt), so they are cleared.
	clearsNotes: boolean;
};

export type RaceTaperPatch = {
	kind?: string;
	target_distance_m?: number | null;
	target_pace_sec_per_km?: null;
	target_pace_tolerance_sec?: null;
	structure?: JsonObject | null;
	target_duration_seconds?: number | null;
	notes?: null;
};

const SEVERITY: Record<RaceTaperReason, number> = { shakeout: 3, pre_race: 2, post_race: 1 };

type Window = { reason: RaceTaperReason; race: PlanRace & { priority: 'B' | 'C' } };

function recoveryDays(race: PlanRace): number {
	if (race.priority === 'C') return C_RECOVERY_DAYS;
	if (race.distanceM == null || !(race.distanceM > 0)) return B_RECOVERY_DEFAULT_DAYS;
	if (race.distanceM > MARATHON_M) {
		const extra = (race.distanceM - MARATHON_M) / 1000 / B_ULTRA_RECOVERY_KM_PER_DAY;
		return Math.min(B_ULTRA_RECOVERY_MAX_DAYS, Math.round(B_RECOVERY_MAX_DAYS + extra));
	}
	const days = Math.round(race.distanceM / 1000 / B_RECOVERY_KM_PER_DAY);
	return Math.min(B_RECOVERY_MAX_DAYS, Math.max(B_RECOVERY_MIN_DAYS, days));
}

function windowFor(race: Window['race'], offset: number): RaceTaperReason | null {
	if (offset < 0) {
		const before = -offset;
		if (race.priority === 'B') {
			if (before <= B_SHAKEOUT_DAYS) return 'shakeout';
			const taperDays =
				race.distanceM != null && race.distanceM > MARATHON_M ? B_ULTRA_TAPER_DAYS : B_TAPER_DAYS;
			return before <= taperDays ? 'pre_race' : null;
		}
		return before <= C_TAPER_DAYS ? 'pre_race' : null;
	}
	if (offset > 0 && offset <= recoveryDays(race)) return 'post_race';
	return null;
}

function scaled(m: number | null, scale: number): number | null {
	return m == null ? null : Math.round(m * scale);
}

type Plain = Record<string, unknown>;
const isPlain = (v: unknown): v is Plain => typeof v === 'object' && v !== null && !Array.isArray(v);
const secs = (v: unknown): number => (typeof v === 'number' && Number.isFinite(v) ? v : 0);

/// A walk/run structure cut by `factor`: the repeat count scales (rounded, at
/// least one) and the run and walk lengths stay — they are the runner's stage
/// of the progression, which a taper week does not move. A single continuous
/// run (count 1) scales its run length instead. Null when nothing changes.
function scaledWalkRun(structure: unknown, factor: number): Plain | null {
	if (!isPlain(structure) || !isPlain(structure.repeats)) return null;
	const reps = structure.repeats;
	const count = typeof reps.count === 'number' ? reps.count : 1;
	if (count > 1) {
		const next = Math.max(1, Math.round(count * factor));
		return next === count ? null : { ...structure, repeats: { ...reps, count: next } };
	}
	if (typeof reps.duration_s !== 'number') return null;
	const next = Math.max(1, Math.round(reps.duration_s * factor));
	return next === reps.duration_s ? null : { ...structure, repeats: { ...reps, duration_s: next } };
}

/// Total seconds a walk/run structure prescribes: warm-up, every run, the
/// walks between them, cool-down.
function walkRunSeconds(structure: Plain): number {
	const reps = isPlain(structure.repeats) ? structure.repeats : {};
	const count = typeof reps.count === 'number' ? reps.count : 1;
	const warm = isPlain(structure.warmup) ? secs(structure.warmup.duration_s) : 0;
	const cool = isPlain(structure.cooldown) ? secs(structure.cooldown.duration_s) : 0;
	return warm + count * secs(reps.duration_s) + Math.max(0, count - 1) * secs(reps.recovery_duration_s) + cool;
}

function adjust(
	w: RaceTaperWorkout,
	reason: RaceTaperReason,
	priority: 'B' | 'C'
): { toKind: string; toMetres: number | null; clearsPace: boolean; scale: number } {
	return { ...kindAndDistance(w, reason, priority), scale: ruleScale(w, reason, priority) };
}

/// The rule's volume factor before any cap: what a session with no distance
/// is scaled by.
function ruleScale(w: RaceTaperWorkout, reason: RaceTaperReason, priority: 'B' | 'C'): number {
	if (reason === 'shakeout') return SHAKEOUT_SCALE;
	if (reason === 'pre_race') return priority === 'B' ? B_TAPER_SCALE : C_TAPER_SCALE;
	return w.kind === 'long' ? RECOVERY_LONG_SCALE : 1;
}

function kindAndDistance(
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
/// unchanged yields no change. The whole prescription eases together
/// (issue #1183): duration by the factor the distance moved, a walk/run's
/// repeats cut to match, and notes cleared once they describe a session that
/// no longer exists.
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
		// The factor the distance actually moved by (the shakeout's 5 km cap
		// included), so duration and structure shrink with it; the rule's own
		// factor when there is no distance to measure by.
		const factor =
			w.targetDistanceM != null && w.targetDistanceM > 0 && a.toMetres != null
				? a.toMetres / w.targetDistanceM
				: a.scale;
		const kindChanged = a.toKind !== w.kind;
		let toStructure: JsonObject | null = null;
		let structureChanged = false;
		let rebuiltWalkRun: Plain | null = null;
		if (!a.clearsPace && kindChanged && w.structure != null) {
			toStructure = null;
			structureChanged = true;
		} else if (!a.clearsPace && w.kind === 'walk_run') {
			rebuiltWalkRun = scaledWalkRun(w.structure, factor);
			if (rebuiltWalkRun != null) {
				toStructure = rebuiltWalkRun as JsonObject;
				structureChanged = true;
			}
		}
		const fromDuration = w.targetDurationSeconds;
		const toDurationS =
			fromDuration == null
				? null
				: rebuiltWalkRun != null && walkRunSeconds(rebuiltWalkRun) > 0
					? walkRunSeconds(rebuiltWalkRun)
					: Math.round(fromDuration * factor);
		const clearsNotes = w.notes != null && (kindChanged || rebuiltWalkRun != null);
		if (
			!kindChanged &&
			a.toMetres === w.targetDistanceM &&
			!a.clearsPace &&
			toDurationS === fromDuration &&
			!structureChanged &&
			!clearsNotes
		) {
			continue;
		}
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
			fromDurationS: fromDuration,
			toDurationS,
			clearsPace: a.clearsPace,
			structureChanged,
			toStructure,
			clearsNotes
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
	if (c.toDurationS !== c.fromDurationS) patch.target_duration_seconds = c.toDurationS;
	if (c.clearsPace) {
		patch.target_pace_sec_per_km = null;
		patch.target_pace_tolerance_sec = null;
		patch.structure = null;
	} else if (c.structureChanged) {
		patch.structure = c.toStructure;
	}
	if (c.clearsNotes) patch.notes = null;
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
