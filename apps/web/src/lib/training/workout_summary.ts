// Display derivations for one planned workout: the segment timeline, its
// total, the walk-run pattern a beginner reads instead of a distance and a
// pace, and the name behind a pace-zone code. Pure and locale-free; each
// platform formats the result with its own catalogue.
//
// Parity pair with apps/mobile_android/lib/workout_summary.dart — keep in
// lockstep (docs/architecture/parity_pairs.md).

import type { WorkoutStructure } from './training';

export type SegmentRole = 'warmup' | 'work' | 'recovery' | 'steady' | 'cooldown';

export interface StructureSegment {
	role: SegmentRole;
	/// Share of the session's summed magnitude, 0-1.
	fraction: number;
}

type Measured = { distance_m?: number | null; duration_s?: number | null };

function positive(n: number | null | undefined): number | null {
	return typeof n === 'number' && Number.isFinite(n) && n > 0 ? n : null;
}

// A step is measured by its distance when it names one, else its duration,
// which is the order the recorder reads them in.
function magnitude(step: Measured | null | undefined): number {
	if (!step) return 0;
	return positive(step.distance_m) ?? positive(step.duration_s) ?? 0;
}

function recoveryOf(r: NonNullable<WorkoutStructure['repeats']>): Measured | null {
	const d = positive(r.recovery_distance_m);
	const s = positive(r.recovery_duration_s);
	if (d == null && s == null) return null;
	return { distance_m: d, duration_s: s };
}

function repCount(r: NonNullable<WorkoutStructure['repeats']>): number {
	return Number.isFinite(r.count) && r.count > 0 ? Math.floor(r.count) : 0;
}

/// The steps the recorder runs, in order. A recovery sits BETWEEN
/// consecutive reps, never after the last one, matching expandWorkoutSteps.
function executedSteps(s: WorkoutStructure): { role: SegmentRole; step: Measured }[] {
	const out: { role: SegmentRole; step: Measured }[] = [];
	if (s.warmup && magnitude(s.warmup) > 0) out.push({ role: 'warmup', step: s.warmup });
	const r = s.repeats;
	if (r && magnitude(r) > 0) {
		const count = repCount(r);
		const recovery = recoveryOf(r);
		for (let i = 0; i < count; i++) {
			out.push({ role: 'work', step: { distance_m: r.distance_m, duration_s: r.duration_s } });
			if (recovery && i < count - 1) out.push({ role: 'recovery', step: recovery });
		}
	}
	if (s.steady && magnitude(s.steady) > 0) out.push({ role: 'steady', step: s.steady });
	if (s.cooldown && magnitude(s.cooldown) > 0) out.push({ role: 'cooldown', step: s.cooldown });
	return out;
}

/// One proportional bar per executed step. The fractions mix metres and
/// seconds when a session mixes the two, which is acceptable for a picture
/// and is why [structureTotal] refuses to sum such a session.
export function structureSegments(s: WorkoutStructure | null | undefined): StructureSegment[] {
	if (!s) return [];
	const steps = executedSteps(s);
	const total = steps.reduce((sum, x) => sum + magnitude(x.step), 0);
	if (total <= 0) return [];
	return steps.map((x) => ({ role: x.role, fraction: magnitude(x.step) / total }));
}

export type StructureTotal =
	| { kind: 'distance'; metres: number }
	| { kind: 'duration'; seconds: number };

/// The session's total, only when every executed step uses one measure.
export function structureTotal(s: WorkoutStructure | null | undefined): StructureTotal | null {
	if (!s) return null;
	const steps = executedSteps(s);
	if (steps.length === 0) return null;
	if (steps.every((x) => positive(x.step.distance_m) != null)) {
		return {
			kind: 'distance',
			metres: steps.reduce((sum, x) => sum + (positive(x.step.distance_m) ?? 0), 0)
		};
	}
	if (steps.every((x) => positive(x.step.distance_m) == null && positive(x.step.duration_s) != null)) {
		return {
			kind: 'duration',
			seconds: steps.reduce((sum, x) => sum + (positive(x.step.duration_s) ?? 0), 0)
		};
	}
	return null;
}

export interface WalkRunPattern {
	warmupS: number | null;
	count: number;
	runS: number;
	/// Null when the session is one continuous run (the graduation week).
	walkS: number | null;
	cooldownS: number | null;
	totalS: number;
}

function timeOnly(step: Measured | null | undefined): number | null | 'mixed' {
	if (!step) return null;
	if (positive(step.distance_m) != null) return 'mixed';
	return positive(step.duration_s);
}

/// The timed pattern of a walk-run session (a repeats block whose recovery
/// is a walk, the same test expandWorkoutSteps uses), or null for any other
/// session and for one that measures a step by distance.
export function walkRunPattern(s: WorkoutStructure | null | undefined): WalkRunPattern | null {
	const r = s?.repeats;
	if (!s || !r || r.recovery_pace !== 'walk') return null;
	const runS = timeOnly(r);
	const count = repCount(r);
	if (runS == null || runS === 'mixed' || count === 0) return null;
	if (positive(r.recovery_distance_m) != null) return null;
	const warmupS = timeOnly(s.warmup);
	const cooldownS = timeOnly(s.cooldown);
	if (warmupS === 'mixed' || cooldownS === 'mixed' || s.steady) return null;
	const walk = positive(r.recovery_duration_s);
	const walkS = count > 1 && walk != null ? walk : null;
	return {
		warmupS,
		count,
		runS,
		walkS,
		cooldownS,
		totalS: (warmupS ?? 0) + count * runS + (walkS != null ? (count - 1) * walkS : 0) + (cooldownS ?? 0)
	};
}

export type SpokenDuration =
	| { unit: 'min'; minutes: number }
	| { unit: 'sec'; seconds: number }
	| { unit: 'minSec'; minutes: number; seconds: number };

/// How an interval length reads aloud: whole minutes as minutes, anything
/// under two minutes that isn't whole as seconds ("90 s"), else both.
export function spokenDuration(totalSeconds: number): SpokenDuration {
	const sec = Math.max(0, Math.round(totalSeconds));
	if (sec >= 60 && sec % 60 === 0) return { unit: 'min', minutes: sec / 60 };
	if (sec < 120) return { unit: 'sec', seconds: sec };
	return { unit: 'minSec', minutes: Math.floor(sec / 60), seconds: sec % 60 };
}

/// A session length rounded to whole minutes, never below one.
export function aboutMinutes(totalSeconds: number): number {
	return Math.max(1, Math.round(totalSeconds / 60));
}

export type PaceZoneName = 'easy' | 'marathon' | 'tempo' | 'interval' | 'repetition';

const ZONE_NAMES: Record<string, PaceZoneName> = {
	e: 'easy',
	easy: 'easy',
	m: 'marathon',
	mp: 'marathon',
	marathon: 'marathon',
	t: 'tempo',
	tempo: 'tempo',
	threshold: 'tempo',
	i: 'interval',
	interval: 'interval',
	r: 'repetition',
	rep: 'repetition',
	repetition: 'repetition'
};

/// The Daniels pace a `plan_workouts.pace_zone` code names, or null for
/// free text the editor let a coach type.
export function paceZoneName(zone: string | null | undefined): PaceZoneName | null {
	if (!zone) return null;
	return ZONE_NAMES[zone.trim().toLowerCase()] ?? null;
}
