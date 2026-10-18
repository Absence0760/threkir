// Training engine: VDOT from a recent race, Riegel equivalence between race
// distances, pace targets by intensity zone, and an 8-16 week plan generator.
//
// Deliberately small and self-contained — no external deps. Tested under
// apps/web/tests/training.test.ts. If you change a number in here, run the
// tests before assuming the plan still looks right.
//
// Design choice: Riegel + goal-pace multipliers for training paces, not the
// full Daniels VDOT table. Daniels' percentages (E=70%, M=84%, T=88%, I=98%,
// R=105% of VDOT) are implicit in `vo2max = f(velocity)` — there's no clean
// inverse. The standard implementation is a lookup table. For MVP, multipliers
// of goal pace land within ~5 s/km of the Daniels tables for typical runners
// and carry zero table data. If users complain about pace accuracy, swap
// `paceFor` for a Daniels-table lookup without changing the public surface.

import type { RacePriority } from './plan_races';

export type GoalEvent = 'distance_5k' | 'distance_10k' | 'distance_half' | 'distance_full' | 'custom';
export type WorkoutKind =
	| 'easy'
	| 'long'
	| 'recovery'
	| 'tempo'
	| 'interval'
	| 'marathon_pace'
	| 'walk_run'
	| 'race'
	| 'rest';
export type PlanPhase = 'base' | 'build' | 'peak' | 'taper' | 'race' | 'graduation';

export const GOAL_DISTANCES_M: Record<Exclude<GoalEvent, 'custom'>, number> = {
	distance_5k: 5000,
	distance_10k: 10_000,
	distance_half: 21_097.5,
	distance_full: 42_195
};

const DEFAULT_PLAN_WEEKS: Record<Exclude<GoalEvent, 'custom'>, number> = {
	distance_5k: 8,
	distance_10k: 8,
	distance_half: 12,
	distance_full: 16
};

/// `distanceM` matters only for a custom goal: an ultra distance takes its
/// own, longer default (`ultraDefaultWeeks`), anything else the custom 12.
export function defaultPlanWeeks(goal: GoalEvent, distanceM?: number | null): number {
	if (goal !== 'custom') return DEFAULT_PLAN_WEEKS[goal];
	return distanceM != null && isUltraDistance(distanceM) ? ultraDefaultWeeks(distanceM) : 12;
}

/// The most training days a walk-run plan schedules. Every session is
/// followed by a rest day, so a week holds three (offsets 0/2/4); a request
/// for more is clamped here. The wizard offers 2 or 3 rather than letting a
/// runner pick a number this would silently cut. Mirrors training.dart.
export const WALK_RUN_MAX_DAYS_PER_WEEK = 3;

/// The fewest training days a week a plan may carry. A walk-run plan (at
/// least one walk_run session and nothing but walk_run, rest and race) may run
/// 2, which the wizard offers; every other plan needs 3. create_training_plan
/// applies the same rule (migration 20270915000001). Mirrors training.dart.
export function minDaysPerWeek(
	weeks: ReadonlyArray<{ workouts: ReadonlyArray<{ kind: string }> }>
): number {
	const kinds = weeks.flatMap((w) => w.workouts.map((wo) => wo.kind));
	const walkRun =
		kinds.includes('walk_run') && kinds.every((k) => k === 'walk_run' || k === 'rest' || k === 'race');
	return walkRun ? 2 : 3;
}

/// Default week count for a beginner C25K walk-run plan. The continuous-run
/// default (`defaultPlanWeeks('distance_5k')` = 8) is one week shorter than
/// the `WALK_RUN_PROGRESSION` table, so feeding it to the walk-run generator
/// drops the final graduation week (the single continuous run). Callers that
/// build a beginner plan should size `weeks` from this, not `defaultPlanWeeks`.
/// Persona round-5 runner-new.
export function walkRunDefaultWeeks(): number {
	return WALK_RUN_PROGRESSION.length;
}

// ─────────────────────── VDOT (Daniels) ───────────────────────

/**
 * Compute Daniels VDOT from a race time.
 *
 * `vo2 = -4.6 + 0.182258 v + 0.000104 v²` where v is m/min.
 * `pct = 0.8 + 0.1894393 e^(-0.012778 T) + 0.2989558 e^(-0.1932605 T)` where T is minutes.
 * `vdot = vo2 / pct`.
 *
 * Source: Daniels, J. — Daniels' Running Formula, 3rd ed.
 */
export function vdotFromRace(distanceMetres: number, timeSeconds: number): number {
	const minutes = timeSeconds / 60;
	const v = distanceMetres / minutes; // m/min
	const vo2 = -4.6 + 0.182258 * v + 0.000104 * v * v;
	const pct =
		0.8 +
		0.1894393 * Math.exp(-0.012778 * minutes) +
		0.2989558 * Math.exp(-0.1932605 * minutes);
	return vo2 / pct;
}

// ─────────────────────── Riegel equivalence ───────────────────────

/**
 * Predict a time at a different distance given a known race result. Uses
 * Riegel's 1981 formula `t2 = t1 * (d2/d1)^1.06`, widely regarded as
 * accurate within 1–2% for endurance races across the 5k–marathon range.
 */
export function riegelPredict(
	knownDistanceM: number,
	knownTimeSec: number,
	targetDistanceM: number,
	exponent = 1.06
): number {
	return knownTimeSec * Math.pow(targetDistanceM / knownDistanceM, exponent);
}

export type PredictionConfidence = 'high' | 'moderate' | 'low';

/// Machine-readable reason code for the binding limit on a prediction's
/// confidence. The UI maps these to localized prose; tests assert on
/// the code so the wording can change without churning the suite.
export type PredictionReason = 'similar' | 'extrapolated' | 'stale' | 'limited';

export interface PredictionQuality {
	confidence: PredictionConfidence;
	reason: PredictionReason;
}

/// Beyond this Riegel extrapolation factor (target/known distance, or
/// its reciprocal) the prediction is little better than a guess — a
/// marathon predicted from a 5k is ~8.4x. Caps confidence at 'low'.
const RIEGEL_FAR_FACTOR = 4;

/// Grade the data quality behind a Riegel race-time prediction. The
/// three levers are how far we extrapolate from the anchoring effort
/// (distance gap), how recent that effort is, and how many qualifying
/// recent efforts back it up. Pure — the caller supplies the anchor's
/// distance, its age in days, and the count of qualifying recent runs.
export function predictionConfidence(input: {
	/// Distance of the best recent effort the Riegel projection is anchored to.
	knownDistanceM: number;
	/// Target race distance.
	targetDistanceM: number;
	/// Age in days of the anchoring effort.
	daysSinceBest: number;
	/// Number of qualifying recent runs (the size of the pool the anchor came from).
	qualifyingRunCount: number;
}): PredictionQuality {
	const { knownDistanceM, targetDistanceM, daysSinceBest, qualifyingRunCount } = input;
	if (knownDistanceM <= 0 || targetDistanceM <= 0 || qualifyingRunCount <= 0) {
		return { confidence: 'low', reason: 'limited' };
	}
	const ratio = targetDistanceM / knownDistanceM;
	const factor = Math.max(ratio, 1 / ratio);

	// Extrapolating far past the anchoring effort dominates every other
	// signal — no amount of recency or sample size rescues a marathon
	// predicted off a parkrun.
	if (factor > RIEGEL_FAR_FACTOR) {
		return { confidence: 'low', reason: 'extrapolated' };
	}

	// A >60d anchor is too stale to anchor a race-day prediction at all, so it
	// caps confidence at 'low' regardless of the distance gap. Checked before
	// the distance-gap branch below: otherwise a far-AND-stale prediction fell
	// through to `!closeDistance` → 'moderate', outranking a close-BUT-stale one
	// ('low') — a doubly-bad prediction can never be more confident than a
	// singly-bad one.
	if (daysSinceBest > 60) {
		return { confidence: 'low', reason: 'stale' };
	}

	// A factor up to 2 (5k↔10k, 10k↔half-ish) is the band Riegel handles
	// well; beyond that error grows fast even within the 4x cap.
	const closeDistance = factor <= 2;
	const recent = daysSinceBest <= 30;
	const wellSampled = qualifyingRunCount >= 3;

	if (closeDistance && recent && wellSampled) {
		return { confidence: 'high', reason: 'similar' };
	}

	// One or more levers are soft. Report the binding constraint, with
	// distance gap first (it hurts the prediction most).
	if (!closeDistance) return { confidence: 'moderate', reason: 'extrapolated' };
	// 31–60 days: a soft staleness caveat (the harder >60d case already
	// returned 'low' above).
	if (!recent) return { confidence: 'moderate', reason: 'stale' };
	// Close + recent but thinly sampled.
	return { confidence: 'moderate', reason: 'limited' };
}

// ─────────────────────── Training paces ───────────────────────

export interface TrainingPaces {
	easy: number; // seconds per km
	marathon: number;
	tempo: number;
	interval: number;
	repetition: number;
}

/// Optional gender hint for pace derivation. Matches the `gender`
/// column on `user_profiles`. Persona-hunt Round 3 finding Woman #3.
export type TrainingGender = 'male' | 'female' | 'prefer_not_to_say' | null;

// Female runners' actual VDOT plotted on Daniels' male-default curve
// under-predicts their training paces by ~3%. Applied as a uniform
// pace-time multiplier (slightly slower seconds/km in every band).
// Persona-hunt Round 3 finding Woman #3.
//
// Why 3% as the single calibration constant:
//  - Sport-science literature suggests female calibration corrections
//    in the 2-5% range depending on intensity zone. A single uniform
//    multiplier under-prescribes at the extreme bands but is the right
//    shape for the data we have (no per-band gender x VDOT calibration
//    has been published with the rigour required to override Daniels).
//  - Uniform multiplier keeps the helper a pure single-line tweak.
//  - The conservative direction (slower) is the right error mode —
//    over-prescribing female athletes' paces is the harm we're fixing.
//
// `male` and `null` use the original (male-derived) curve.
// `prefer_not_to_say` also defaults to the original — no validated
// calibration exists without a stated sex, and a wrong adjustment is
// worse than no adjustment.
const FEMALE_PACE_CALIBRATION = 1.03;

function genderPaceMultiplier(gender: TrainingGender | undefined): number {
	return gender === 'female' ? FEMALE_PACE_CALIBRATION : 1.0;
}

// Masters (50+) recovery calibration. Persona-hunt finding Older #30:
// the default week schedules the first quality session 48h after the
// Sunday long run and steps back volume every 4th week. Both are tuned
// for younger physiology — masters athletes recover more slowly, so
// the literature (and every masters-specific plan) widens hard-day
// spacing to ~72h and shortens the build/recover cycle. When `age >=
// MASTERS_AGE` we (a) push the first quality day from Tue→Wed (72h
// after the long run) and the second from Thu→Fri, and (b) step volume
// back every 3rd week instead of every 4th. Pace bands are left on the
// shared Daniels curve — no validated age×VDOT pace table exists, and
// the harm being fixed here is recovery density, not pace. See
// docs/architecture/decisions.md § masters-recovery-calibration.
const MASTERS_AGE = 50;

export function isMastersAge(age: number | null | undefined): boolean {
	return age != null && age >= MASTERS_AGE;
}

/// Whether a plan takes the masters recovery calibration: the runner is 50+,
/// or they asked for it (`extra_recovery`, a training preference any runner
/// can set — a comeback runner, or one with no date of birth on record).
/// The preference only ever adds recovery; it never removes it from a
/// masters runner.
export function usesMastersRecovery(
	age: number | null | undefined,
	extraRecovery: boolean | null | undefined
): boolean {
	return extraRecovery === true || isMastersAge(age);
}

/**
 * Derive the five Daniels intensity-zone paces as multipliers of goal-race
 * pace. Numbers chosen so the output sits close to Daniels' published tables
 * across the 3:00–5:00/km goal-pace band. `goalPaceSecPerKm` is the runner's
 * target pace for the goal race.
 *
 * Optional `gender` parameter applies the female-specific calibration —
 * see [decisions.md § 76](docs/architecture/decisions.md#76-training-pace-derivation-applies-a-3-female-specific-calibration-to-the-daniels-curve) and the
 * `FEMALE_PACE_CALIBRATION` constant above for the rationale.
 */
export function pacesFromGoalPace(
	goalPaceSecPerKm: number,
	gender: TrainingGender = null
): TrainingPaces {
	// Goal pace sits between marathon and tempo intensity for most runners.
	// These multipliers are a simplification of Daniels' percentages and are
	// stable across the typical distance/goal-time grid; see the regression
	// tests in training.test.ts.
	const g = genderPaceMultiplier(gender);
	return {
		easy: Math.round(goalPaceSecPerKm * 1.22 * g),
		marathon: Math.round(goalPaceSecPerKm * 1.06 * g),
		tempo: Math.round(goalPaceSecPerKm * 0.97 * g),
		interval: Math.round(goalPaceSecPerKm * 0.9 * g),
		repetition: Math.round(goalPaceSecPerKm * 0.85 * g)
	};
}

/// The conservative goal pace (sec/km) used when the runner gave us neither a
/// recent race nor a goal time. ~10:00/km — slow enough that the derived easy
/// pace won't injure a returning runner, but it's a placeholder, not a
/// personalised number. `resolveTrainingPacesWithMeta` flags when it's in play
/// so the caller can disclose it instead of presenting it as real. Persona
/// round-5 runner-comeback.
const FALLBACK_GOAL_PACE_SEC_PER_KM = 600;

/**
 * Resolve the runner's training paces plus whether they came from a real
 * fitness anchor or the conservative fallback. Priority: an explicit recent 5k
 * time (use Riegel to predict goal-distance pace) → a goal time on the target
 * distance (use directly) → fall back to a conservative "10:00/km as goal" so
 * the plan still generates for someone without any race history.
 *
 * `isFallback` is true only in that last case. The numbers are always usable
 * (the plan generates regardless); the flag exists so the wizard can label the
 * preview "estimated — add a recent run for personalised paces" rather than
 * presenting a placeholder as a confident prescription. Persona round-5
 * runner-comeback.
 *
 * `goalPaceSecPerKm` is the resolved race pace the bands were derived FROM,
 * returned so a caller prescribing the goal effort itself (the race workout,
 * `marathon_pace` sessions) uses it directly instead of trying to invert a
 * band's multiplier back out. It is deliberately not gender-calibrated: the
 * calibration shapes training zones, but the runner's goal is their goal.
 */
export function resolveTrainingPacesWithMeta(input: {
	goalDistanceM: number;
	goalTimeSec?: number | null;
	recent5kSec?: number | null;
	gender?: TrainingGender;
}): { paces: TrainingPaces; isFallback: boolean; goalPaceSecPerKm: number } {
	let goalPaceSecPerKm: number;
	let isFallback = false;
	if (input.recent5kSec) {
		const predicted = riegelPredict(5000, input.recent5kSec, input.goalDistanceM);
		goalPaceSecPerKm = predicted / (input.goalDistanceM / 1000);
	} else if (input.goalTimeSec) {
		goalPaceSecPerKm = input.goalTimeSec / (input.goalDistanceM / 1000);
	} else {
		goalPaceSecPerKm = FALLBACK_GOAL_PACE_SEC_PER_KM;
		isFallback = true;
	}
	// A 0 m goal distance divides to Infinity (or NaN), which every band then
	// rounds to and `fmtPace` printed as "Infinity:NaN/km"; the Dart twin's
	// `.round()` threw. An anchor that yields no usable pace is no anchor.
	if (!(Number.isFinite(goalPaceSecPerKm) && goalPaceSecPerKm > 0)) {
		goalPaceSecPerKm = FALLBACK_GOAL_PACE_SEC_PER_KM;
		isFallback = true;
	}
	return {
		paces: pacesFromGoalPace(goalPaceSecPerKm, input.gender ?? null),
		isFallback,
		goalPaceSecPerKm
	};
}

/**
 * Resolve the runner's training paces from whichever anchor they gave us.
 * Priority: an explicit recent 5k time (use Riegel to predict goal-distance
 * pace) → a goal time on the target distance (use directly) → fall back to a
 * conservative "10:00/km as goal" so the plan still generates for someone
 * without any race history. Thin wrapper over `resolveTrainingPacesWithMeta`
 * for callers that don't need the fallback flag.
 */
export function resolveTrainingPaces(input: {
	goalDistanceM: number;
	goalTimeSec?: number | null;
	recent5kSec?: number | null;
	gender?: TrainingGender;
}): TrainingPaces {
	return resolveTrainingPacesWithMeta(input).paces;
}

// ─────────────────────── Phase schedule ───────────────────────

const PHASE_SHARES: ReadonlyArray<readonly [PlanPhase, number]> = [
	['base', 0.3],
	['build', 0.4],
	['peak', 0.2],
	['taper', 0.1]
];

/**
 * Weeks per phase, in `PHASE_SHARES` order, over the non-race weeks.
 *
 * Flooring each share independently loses up to three weeks of the total to
 * rounding, and the taper — the smallest share, and the one the leftover used
 * to be — absorbed all of it: at exactly 10 and exactly 5 total weeks the
 * floors consumed every non-race week, leaving zero taper and the peak week
 * hard against race day. Largest-remainder keeps the sum exact at every total,
 * and the taper's first week is reserved before the split so rounding can
 * never be what takes it away.
 */
function phaseWeekCounts(totalWeeks: number): number[] {
	const trainWeeks = totalWeeks - 1;
	if (trainWeeks <= 0) return [0, 0, 0, 0];
	const exact = PHASE_SHARES.map(([, share]) => share * (trainWeeks - 1));
	const counts = exact.map((v) => Math.floor(v));
	counts[counts.length - 1] += 1;
	let left = trainWeeks - counts.reduce((a, b) => a + b, 0);
	const frac = exact.map((v) => v - Math.floor(v));
	const order = exact.map((_, i) => i).sort((a, b) => frac[b] - frac[a] || a - b);
	for (const i of order) {
		if (left <= 0) break;
		counts[i]++;
		left--;
	}
	return counts;
}

export function phaseFor(weekIndex: number, totalWeeks: number): PlanPhase {
	if (weekIndex >= totalWeeks - 1) return 'race';
	const counts = phaseWeekCounts(totalWeeks);
	let end = 0;
	for (let i = 0; i < counts.length; i++) {
		end += counts[i];
		if (weekIndex < end) return PHASE_SHARES[i][0];
	}
	return 'taper';
}

// ─────────────────────── Workout structure ───────────────────────

/**
 * Structured-workout descriptor stored in `plan_workouts.structure`. Tempo,
 * interval, and repetition workouts use this; easy/long/recovery/rest do
 * not. See `docs/features/training.md` for the shape spec.
 *
 * An alias rather than an interface, and that is load-bearing: only an alias
 * of an object type gets TypeScript's implicit index signature, so an
 * interface is refused as the `Json` this jsonb column takes however
 * JSON-shaped it is. The Dart twin has no such distinction.
 */
export type WorkoutStructure = {
	warmup?: { distance_m?: number; duration_s?: number; pace: 'easy' };
	// A rep / recovery may be expressed by distance (distance_m) or by time
	// (duration_s) — the runner reads whichever is present (distance wins).
	// Walk-run (C25K / Galloway) sessions use duration-based reps with a
	// 'walk' recovery; see docs/features/training.md § walk-run.
	repeats?: {
		count: number;
		distance_m?: number;
		duration_s?: number;
		pace_sec_per_km: number;
		recovery_distance_m?: number;
		recovery_duration_s?: number;
		recovery_pace: 'easy' | 'jog' | 'walk';
	};
	steady?: { distance_m?: number; duration_s?: number; pace_sec_per_km: number };
	cooldown?: { distance_m?: number; duration_s?: number; pace: 'easy' };
};

// ─────────────────────── Plan generation ───────────────────────

export interface GeneratedWorkout {
	scheduled_date: string; // ISO date YYYY-MM-DD
	kind: WorkoutKind;
	target_distance_m: number | null;
	target_duration_seconds: number | null;
	target_pace_sec_per_km: number | null;
	target_pace_tolerance_sec: number | null;
	structure: WorkoutStructure | null;
	notes: string | null;
	race_name?: string | null;
	race_priority?: RacePriority | null;
	/// Set only on a workout read from a JSON export a B/C race taper had
	/// eased (decisions § 2063); the generator never sets it.
	race_taper_applied_at?: string | null;
}

export interface GeneratedWeek {
	week_index: number;
	phase: PlanPhase;
	target_volume_m: number;
	notes: string | null;
	workouts: GeneratedWorkout[];
}

export interface GeneratePlanInput {
	goalEvent: GoalEvent;
	goalDistanceM?: number; // required if goalEvent === 'custom'
	goalTimeSec?: number | null;
	recent5kSec?: number | null;
	startDate: string; // ISO date
	daysPerWeek: number; // 3–7
	weeks?: number;
	/// Optional gender from `user_profiles.gender` — applies the
	/// female-specific calibration to derived training paces.
	/// Persona-hunt Round 3 finding Woman #3.
	gender?: TrainingGender;
	/// Optional age (years) from `user_profiles.date_of_birth`. At or above
	/// MASTERS_AGE it applies the masters recovery calibration — wider
	/// hard-day spacing + a 3-week build/recover cycle. Persona-hunt
	/// finding Older #30.
	age?: number | null;
	/// The runner's `extra_recovery` setting: apply the masters recovery
	/// calibration whatever `age` says. See `usesMastersRecovery`.
	extraRecovery?: boolean;
	/// When true, produce a beginner C25K-style walk-run plan instead of the
	/// continuous-running plan. The goal stays a 5k; every session is a
	/// `walk_run` workout of timed run/walk intervals (persona #22).
	beginnerWalkRun?: boolean;
}

export interface GeneratedPlan {
	weeks: GeneratedWeek[];
	paces: TrainingPaces;
	vdot: number | null;
	endDate: string; // ISO date
	goalDistanceM: number;
	/// True when `paces` are the conservative 10:00/km fallback (no recent
	/// race, no goal time) rather than derived from real fitness. The plan
	/// is still valid; the caller should disclose the paces are estimated.
	/// Persona round-5 runner-comeback.
	pacesAreFallback: boolean;
}

/**
 * Generate a full plan from (goal, start date, days/week, fitness anchor).
 * Phase breakdown is 30 / 40 / 20 / 10 of base / build / peak / taper with
 * the final week always a 'race' week. Mileage ramps with a step-back every
 * fourth week to cap cumulative fatigue.
 */
export function generatePlan(input: GeneratePlanInput): GeneratedPlan {
	const goalDistanceM =
		input.goalEvent === 'custom'
			? input.goalDistanceM!
			: GOAL_DISTANCES_M[input.goalEvent];
	const totalWeeks = input.weeks ?? defaultPlanWeeks(input.goalEvent, goalDistanceM);
	const ultra = !input.beginnerWalkRun && isUltraDistance(goalDistanceM);
	// An ultra's training zones are anchored at its marathon equivalent: zone
	// multipliers of a 100-mile goal pace would put "tempo" slower than a
	// marathon jog. See `ultraMarathonEquivalentSec`.
	const paceDistanceM = ultra ? GOAL_DISTANCES_M.distance_full : goalDistanceM;
	const paceGoalTimeSec =
		ultra && input.goalTimeSec
			? ultraMarathonEquivalentSec(input.goalTimeSec, goalDistanceM)
			: input.goalTimeSec;
	const {
		paces,
		isFallback: pacesAreFallback,
		goalPaceSecPerKm
	} = resolveTrainingPacesWithMeta({
		goalDistanceM: paceDistanceM,
		goalTimeSec: paceGoalTimeSec,
		recent5kSec: input.recent5kSec,
		gender: input.gender
	});
	const vdot = input.recent5kSec
		? vdotFromRace(5000, input.recent5kSec)
		: paceGoalTimeSec
		? vdotFromRace(paceDistanceM, paceGoalTimeSec)
		: null;

	const startDate = parseISO(input.startDate);

	if (input.beginnerWalkRun) {
		return generateWalkRunPlan(input, goalDistanceM, paces, vdot, startDate, pacesAreFallback);
	}
	if (ultra) {
		return generateUltraPlan(input, {
			goalDistanceM,
			totalWeeks,
			paces,
			vdot,
			startDate,
			pacesAreFallback
		});
	}

	const weeks: GeneratedWeek[] = [];
	const masters = usesMastersRecovery(input.age, input.extraRecovery);

	for (let i = 0; i < totalWeeks; i++) {
		const phase = phaseFor(i, totalWeeks);
		// Mileage curve: ramp from 0.6× peak at week 0 up to 1.0× at peak-end,
		// then drop to 0.5× in taper and 0.35× in race week.
		const peakWeeklyKm = peakVolumeKm(
			goalDistanceM,
			input.daysPerWeek,
			!!(input.goalTimeSec || input.recent5kSec)
		);
		const fraction = mileageFraction(i, totalWeeks, phase, masters);
		const weeklyKm = Math.round(peakWeeklyKm * fraction);
		const workouts = generateWeek({
			weekIndex: i,
			phase,
			weekStart: addDays(startDate, i * 7),
			daysPerWeek: input.daysPerWeek,
			weeklyKm,
			paces,
			goalDistanceM,
			goalPaceSecPerKm,
			masters
		});
		// The stated weekly volume must equal what the week actually
		// prescribes. The emitted workouts are rounded/floored per-day
		// (easy filler clamps to >=3 km, intervals/tempo/long carry their
		// own distances), so `weeklyKm * 1000` overstated the real ask by
		// ~25-70% on small-volume (5k/half) plans. Sum the emitted
		// distances so the headline number is honest. Quality + long run
		// stay uncapped (that's training design); only the stated total
		// is reconciled.
		weeks.push({
			week_index: i,
			phase,
			target_volume_m: workouts.reduce((s, w) => s + (w.target_distance_m ?? 0), 0),
			notes: weekNote(phase, i, totalWeeks, masters),
			workouts
		});
	}

	const endDate = addDays(startDate, totalWeeks * 7 - 1);
	return {
		weeks,
		paces,
		vdot,
		endDate: formatISO(endDate),
		goalDistanceM,
		pacesAreFallback
	};
}

// ─────────────────────── Beginner walk-run (C25K) ───────────────────────

/// Simplified, monotonic C25K-style progression: each week is a uniform
/// run/walk interval that lengthens the run and trims the walk, graduating
/// to a continuous ~25-minute run. `count - 1` walk breaks sit between the
/// runs; week 9 has a single continuous run (no recovery). Real C25K mixes
/// interval lengths mid-program; we keep it uniform-per-week so the plan is
/// legible and the TS↔Dart parity stays tractable.
export const WALK_RUN_PROGRESSION: ReadonlyArray<{
	runSec: number;
	walkSec: number;
	count: number;
}> = [
	{ runSec: 60, walkSec: 90, count: 8 },
	{ runSec: 90, walkSec: 120, count: 7 },
	{ runSec: 120, walkSec: 120, count: 6 },
	{ runSec: 180, walkSec: 120, count: 5 },
	{ runSec: 300, walkSec: 120, count: 4 },
	{ runSec: 480, walkSec: 150, count: 3 },
	{ runSec: 600, walkSec: 120, count: 3 },
	{ runSec: 900, walkSec: 180, count: 2 },
	{ runSec: 1500, walkSec: 0, count: 1 }
];
const WALK_RUN_WARMUP_S = 300;
const WALK_RUN_COOLDOWN_S = 300;
const WALK_PACE_SEC_PER_KM = 700; // ~11:40/km brisk walk, for distance estimates

function walkRunWorkout(
	scheduledDate: string,
	weekIndex: number,
	easyPaceSecPerKm: number
): GeneratedWorkout {
	const prog = WALK_RUN_PROGRESSION[Math.min(weekIndex, WALK_RUN_PROGRESSION.length - 1)];
	const hasRecovery = prog.count > 1 && prog.walkSec > 0;
	const repeats: NonNullable<WorkoutStructure['repeats']> = {
		count: prog.count,
		duration_s: prog.runSec,
		pace_sec_per_km: easyPaceSecPerKm,
		recovery_pace: 'walk',
		...(hasRecovery ? { recovery_duration_s: prog.walkSec } : {})
	};
	const totalRunSec = prog.count * prog.runSec;
	const totalWalkSec =
		(hasRecovery ? (prog.count - 1) * prog.walkSec : 0) +
		WALK_RUN_WARMUP_S +
		WALK_RUN_COOLDOWN_S;
	const estDistanceM = Math.round(
		(totalRunSec * 1000) / easyPaceSecPerKm + (totalWalkSec * 1000) / WALK_PACE_SEC_PER_KM
	);
	return {
		scheduled_date: scheduledDate,
		kind: 'walk_run',
		target_distance_m: estDistanceM,
		target_duration_seconds: totalRunSec + totalWalkSec,
		target_pace_sec_per_km: easyPaceSecPerKm,
		target_pace_tolerance_sec: null,
		structure: {
			warmup: { duration_s: WALK_RUN_WARMUP_S, pace: 'easy' },
			repeats,
			cooldown: { duration_s: WALK_RUN_COOLDOWN_S, pace: 'easy' }
		},
		notes: null
	};
}

function generateWalkRunPlan(
	input: GeneratePlanInput,
	goalDistanceM: number,
	paces: TrainingPaces,
	vdot: number | null,
	startDate: Date,
	pacesAreFallback: boolean
): GeneratedPlan {
	// Never run fewer weeks than the progression has stages — truncating it
	// drops the final graduation week (the single continuous run), which is
	// the whole point of a C25K plan. A default 5k plan arrives here with
	// weeks=8 (defaultPlanWeeks('distance_5k')) against a 9-stage table, so
	// without this floor the graduation week silently vanishes. Persona
	// round-5 runner-new. A longer request is honoured (the table's last
	// stage repeats for the extra weeks via the index clamp in walkRunWorkout).
	const totalWeeks = Math.max(input.weeks ?? WALK_RUN_PROGRESSION.length, WALK_RUN_PROGRESSION.length);
	// Beginners train 3 days/week; respect a lower request but cap at 3.
	const runDays = Math.max(1, Math.min(input.daysPerWeek, WALK_RUN_MAX_DAYS_PER_WEEK));
	// Spread run days across Mon/Wed/Fri-style offsets.
	// Two sessions sit three days apart (0/3) rather than 0/2, which would
	// leave a five-day gap before the next week's first session.
	const dayOffsets =
		runDays === 2 ? [0, 3] : [0, 2, 4, 1, 3, 5, 6].slice(0, runDays).sort((a, b) => a - b);
	const weeks: GeneratedWeek[] = [];
	for (let i = 0; i < totalWeeks; i++) {
		const weekStart = addDays(startDate, i * 7);
		const runSet = new Set(dayOffsets);
		const workouts: GeneratedWorkout[] = [];
		for (let d = 0; d < 7; d++) {
			const date = formatISO(addDays(weekStart, d));
			if (runSet.has(d)) {
				workouts.push(walkRunWorkout(date, i, paces.easy));
			} else {
				workouts.push({
					scheduled_date: date,
					kind: 'rest',
					target_distance_m: null,
					target_duration_seconds: null,
					target_pace_sec_per_km: null,
					target_pace_tolerance_sec: null,
					structure: null,
					notes: null
				});
			}
		}
		weeks.push({
			week_index: i,
			phase: i === totalWeeks - 1 ? 'graduation' : 'build',
			target_volume_m: workouts.reduce((s, w) => s + (w.target_distance_m ?? 0), 0),
			notes:
				i === totalWeeks - 1
					? 'Final week — you can run the distance continuously now.'
					: 'Take the walk breaks even when you feel good — they make the runs sustainable.',
			workouts
		});
	}
	return {
		weeks,
		paces,
		vdot,
		endDate: formatISO(addDays(startDate, totalWeeks * 7 - 1)),
		goalDistanceM,
		pacesAreFallback
	};
}

// ─────────────────────── Ultra distances ───────────────────────
//
// Anything longer than the marathon. The road plan's shape stops working
// there: a long run sized as a third of the week becomes a 7-hour outing, the
// goal-pace zone multipliers stop describing training intensity, and a single
// week of taper is not enough to absorb the load. The ultra branch follows the
// time-on-feet method of Koop, "Training Essentials for Ultrarunning" (2016):
// long runs capped by duration rather than distance, back-to-back weekend long
// runs from ~80 km up, and a 2-3 week taper that cuts volume progressively
// while a little intensity stays.

/// The ultra distances the plan wizards offer by name. Comrades runs 86-90 km
/// depending on the year's direction, so the wizards let the runner correct
/// any of these to their race's exact distance.
export const ULTRA_PRESETS = [
	{ id: 'ultra_50k', distanceM: 50_000 },
	{ id: 'ultra_56k', distanceM: 56_000 },
	{ id: 'ultra_90k', distanceM: 90_000 },
	{ id: 'ultra_100mi', distanceM: 160_934.4 }
] as const;
export type UltraPresetId = (typeof ULTRA_PRESETS)[number]['id'];

/// Strictly longer than the marathon. A non-finite distance is not an ultra.
export function isUltraDistance(distanceM: number): boolean {
	return Number.isFinite(distanceM) && distanceM > GOAL_DISTANCES_M.distance_full;
}

/// From this distance up, build and peak weekends carry a Saturday long run
/// before the Sunday one: the race outlasts any single long run a body can
/// recover from in a week, so the second day on tired legs stands in for the
/// distance.
export const ULTRA_BACK_TO_BACK_MIN_M = 80_000;

/// Riegel's 1.06 was fitted to races up to the marathon; ultra finish times
/// slow faster than it predicts, so converting an ultra goal to its marathon
/// equivalent uses a steeper exponent. 1.15 puts a 24-hour 100-miler at a
/// ~5:09 marathon and an 11-hour Comrades at ~4:36, which is where those
/// finishers' road marathons sit. It only anchors training zones — it never
/// predicts a race time.
export const ULTRA_RIEGEL_EXPONENT = 1.15;

/// The marathon time an ultra goal time corresponds to, in whole seconds.
export function ultraMarathonEquivalentSec(goalTimeSec: number, distanceM: number): number {
	return Math.round(
		goalTimeSec * Math.pow(GOAL_DISTANCES_M.distance_full / distanceM, ULTRA_RIEGEL_EXPONENT)
	);
}

/// The longest single long run, in seconds. Beyond ~3-3.5 h for a 50-56 km
/// race and ~5-6 h for 90 km and up, a run costs more recovery than it adds
/// fitness (Koop ch. 8), so the cap is a duration, never a distance.
export function ultraLongRunCapSec(distanceM: number): number {
	if (distanceM < 60_000) return 3.5 * 3600;
	if (distanceM < ULTRA_BACK_TO_BACK_MIN_M) return 4 * 3600;
	if (distanceM < 120_000) return 5 * 3600;
	return 6 * 3600;
}

/// Default plan length for an ultra goal.
export function ultraDefaultWeeks(distanceM: number): number {
	if (distanceM < 60_000) return 16;
	if (distanceM < ULTRA_BACK_TO_BACK_MIN_M) return 18;
	if (distanceM < 120_000) return 20;
	return 24;
}

/// Taper weeks before race week: 3 from ~80 km up, 2 below, and never more
/// than a quarter of the training weeks, so a short plan still builds.
export function ultraTaperWeeks(distanceM: number, totalWeeks: number): number {
	if (totalWeeks <= 1) return 0;
	const wanted = distanceM >= ULTRA_BACK_TO_BACK_MIN_M ? 3 : 2;
	return Math.min(wanted, Math.max(1, Math.floor((totalWeeks - 1) / 4)));
}

/// The base peak weekly volume (km) before the training-day and anchor
/// factors: continuous with the marathon's 1.8× at 42.195 km, then 0.4 km per
/// extra race km, capped at 120 km.
const ULTRA_PEAK_CAP_KM = 120;
function ultraPeakBaseKm(distanceM: number): number {
	const marathonKm = GOAL_DISTANCES_M.distance_full / 1000;
	return Math.min(ULTRA_PEAK_CAP_KM, marathonKm * 1.8 + 0.4 * (distanceM / 1000 - marathonKm));
}

const ULTRA_BUILD_SHARES: ReadonlyArray<readonly [PlanPhase, number]> = [
	['base', 0.35],
	['build', 0.45],
	['peak', 0.2]
];

/// Phase of a week in an ultra plan: the last week is the race, the
/// `ultraTaperWeeks` before it taper, and the rest split base / build / peak
/// 35 / 45 / 20 by largest remainder.
export function ultraPhaseFor(weekIndex: number, totalWeeks: number, distanceM: number): PlanPhase {
	if (weekIndex >= totalWeeks - 1) return 'race';
	const buildWeeks = totalWeeks - 1 - ultraTaperWeeks(distanceM, totalWeeks);
	if (weekIndex >= buildWeeks) return 'taper';
	const exact = ULTRA_BUILD_SHARES.map(([, share]) => share * buildWeeks);
	const counts = exact.map((v) => Math.floor(v));
	let left = buildWeeks - counts.reduce((a, b) => a + b, 0);
	const order = exact
		.map((_, i) => i)
		.sort((a, b) => exact[b] - Math.floor(exact[b]) - (exact[a] - Math.floor(exact[a])) || a - b);
	for (const i of order) {
		if (left <= 0) break;
		counts[i]++;
		left--;
	}
	let end = 0;
	for (let i = 0; i < counts.length; i++) {
		end += counts[i];
		if (weekIndex < end) return ULTRA_BUILD_SHARES[i][0];
	}
	return 'peak';
}

/// Phase of a week in a plan toward `goalDistanceM`: the ultra split for a
/// distance past the marathon, the road one otherwise. The one rule anything
/// rebuilding phases for a plan it did not generate (a pasted import) uses,
/// so it agrees with the generator.
export function planPhaseFor(weekIndex: number, totalWeeks: number, goalDistanceM: number): PlanPhase {
	return isUltraDistance(goalDistanceM)
		? ultraPhaseFor(weekIndex, totalWeeks, goalDistanceM)
		: phaseFor(weekIndex, totalWeeks);
}

/// Most a build week may grow over the build week before it. The 10% rule is
/// a convention rather than a measured threshold, but it is the one every
/// published ultra plan honours, and a plan too short to reach its peak inside
/// it peaks lower instead.
export const ULTRA_MAX_WEEKLY_RAMP = 1.1;

/// Fraction of peak volume for every week of an ultra plan. Build weeks ramp
/// linearly from 0.6 to 1.0, never more than ULTRA_MAX_WEEKLY_RAMP over the
/// previous build week, with the road plan's step-back cycle; taper weeks
/// fall evenly to 0.45 in the week before the race; race week is 0.35.
export function ultraMileageFractions(
	totalWeeks: number,
	distanceM: number,
	masters = false
): number[] {
	const taperWeeks = ultraTaperWeeks(distanceM, totalWeeks);
	const buildWeeks = totalWeeks - 1 - taperWeeks;
	const out: number[] = [];
	let ramp = 0;
	for (let i = 0; i < totalWeeks; i++) {
		if (i === totalWeeks - 1) {
			out.push(0.35);
		} else if (i >= buildWeeks) {
			out.push(0.85 - (0.4 * (i - buildWeeks + 1)) / taperWeeks);
		} else if (isStepBackWeek(i, masters)) {
			out.push(ramp * 0.82);
		} else {
			const linear = 0.6 + (0.4 * i) / Math.max(1, buildWeeks - 1);
			ramp = i === 0 ? 0.6 : Math.min(1, linear, ramp * ULTRA_MAX_WEEKLY_RAMP);
			out.push(ramp);
		}
	}
	return out;
}

/// Share of the week's volume the Sunday long run takes, and on a
/// back-to-back weekend the Saturday one. A back-to-back weekend carries
/// over half the week, as Koop's weekend blocks do.
const ULTRA_LONG_SHARE = 0.35;
const ULTRA_B2B_SUNDAY_SHARE = 0.32;
const ULTRA_B2B_SATURDAY_SHARE = 0.24;
/// The Saturday run is held to 60% of the Sunday cap.
const ULTRA_B2B_SATURDAY_CAP = 0.6;
/// Long-run durations round down to the quarter hour, so a long run never
/// takes more than its share of the week, and none is under an hour.
const LONG_RUN_STEP_SEC = 900;
const ULTRA_LONG_RUN_MIN_SEC = 3600;
/// An easy day is never longer than two hours at easy pace. The weekend is
/// where an ultra plan's long time on feet lives; a week too short on
/// training days to reach its volume target comes in under it instead of
/// turning a midweek easy run into a second long run.
const ULTRA_EASY_MAX_SEC = 2 * 3600;

function floorToStep(sec: number): number {
	return Math.floor(sec / LONG_RUN_STEP_SEC) * LONG_RUN_STEP_SEC;
}

/// A time-on-feet long run: the duration is the target, sized from the
/// week's volume at easy pace and capped; the distance is what that duration
/// covers at easy pace (to 100 m), carried so the week's volume stays honest.
/// No pace target — on an ultra long run the terrain, the climbs and the
/// fuelling decide the pace.
function ultraLongRunWorkout(
	date: string,
	budgetKm: number,
	capSec: number,
	easyPace: number,
	notes: string
): GeneratedWorkout {
	const durationSec = Math.min(
		capSec,
		Math.max(ULTRA_LONG_RUN_MIN_SEC, floorToStep(budgetKm * easyPace))
	);
	return {
		scheduled_date: date,
		kind: 'long',
		target_distance_m: Math.round((durationSec / easyPace) * 10) * 100,
		target_duration_seconds: durationSec,
		target_pace_sec_per_km: null,
		target_pace_tolerance_sec: null,
		structure: null,
		notes
	};
}

const ULTRA_LONG_NOTE =
	'Time on feet at easy effort: the duration is the target, not the pace. Practise race-day fuelling.';
const ULTRA_B2B_NOTE =
	'Back-to-back, day one: easy effort, and tomorrow’s long run starts on tired legs.';

function ultraWeekNote(
	phase: PlanPhase,
	i: number,
	total: number,
	masters: boolean,
	backToBack: boolean
): string | null {
	if (phase === 'taper') return 'Taper — volume comes down week by week; keep a little intensity.';
	if (backToBack && !isStepBackWeek(i, masters) && (phase === 'build' || phase === 'peak')) {
		return 'Back-to-back weekend — Saturday and Sunday long runs.';
	}
	return weekNote(phase, i, total, masters);
}

interface UltraPlanContext {
	goalDistanceM: number;
	totalWeeks: number;
	paces: TrainingPaces;
	vdot: number | null;
	startDate: Date;
	pacesAreFallback: boolean;
}

function generateUltraPlan(input: GeneratePlanInput, ctx: UltraPlanContext): GeneratedPlan {
	const { goalDistanceM, totalWeeks, paces, startDate } = ctx;
	const masters = usesMastersRecovery(input.age, input.extraRecovery);
	const backToBack = goalDistanceM >= ULTRA_BACK_TO_BACK_MIN_M;
	const peakKm = peakVolumeKm(
		goalDistanceM,
		input.daysPerWeek,
		!!(input.goalTimeSec || input.recent5kSec)
	);
	const fractions = ultraMileageFractions(totalWeeks, goalDistanceM, masters);
	const weeks: GeneratedWeek[] = [];
	// The ramp limit holds on what the weeks actually prescribe, not only on
	// the fractions: rounding a long run or an easy day can move a week a
	// kilometre either way, so each build week's budget is also held to
	// ULTRA_MAX_WEEKLY_RAMP over the volume the previous build week emitted.
	let lastBuildM: number | null = null;
	for (let i = 0; i < totalWeeks; i++) {
		const phase = ultraPhaseFor(i, totalWeeks, goalDistanceM);
		const buildWeek =
			(phase === 'base' || phase === 'build' || phase === 'peak') && !isStepBackWeek(i, masters);
		const targetKm = Math.round(peakKm * fractions[i]);
		const workouts = generateUltraWeek({
			phase,
			weekStart: addDays(startDate, i * 7),
			daysPerWeek: input.daysPerWeek,
			weeklyKm:
				buildWeek && lastBuildM !== null
					? Math.min(targetKm, (lastBuildM / 1000) * ULTRA_MAX_WEEKLY_RAMP)
					: targetKm,
			paces,
			goalDistanceM,
			goalTimeSec: input.goalTimeSec ?? null,
			masters,
			backToBack: backToBack && buildWeek && phase !== 'base'
		});
		const volumeM = workouts.reduce((s, w) => s + (w.target_distance_m ?? 0), 0);
		if (buildWeek) lastBuildM = volumeM;
		weeks.push({
			week_index: i,
			phase,
			target_volume_m: volumeM,
			notes: ultraWeekNote(phase, i, totalWeeks, masters, backToBack),
			workouts
		});
	}
	return {
		weeks,
		paces,
		vdot: ctx.vdot,
		endDate: formatISO(addDays(startDate, totalWeeks * 7 - 1)),
		goalDistanceM,
		pacesAreFallback: ctx.pacesAreFallback
	};
}

interface UltraWeekInput {
	phase: PlanPhase;
	weekStart: Date;
	daysPerWeek: number;
	weeklyKm: number;
	paces: TrainingPaces;
	goalDistanceM: number;
	goalTimeSec: number | null;
	masters: boolean;
	backToBack: boolean;
}

/// Quality for an ultra week. Base and build keep the road plan's threshold
/// and VO2 work; the marathon-pace session becomes a longer threshold run,
/// since there is no goal pace to rehearse; the taper keeps one short tempo.
/// A back-to-back weekend is the week's second hard stimulus, so it replaces
/// the second quality day rather than stacking three hard days.
function allocateUltraQuality(w: UltraWeekInput): {
	a: GeneratedWorkout | null;
	b: GeneratedWorkout | null;
} {
	const placeholder = '';
	let a: GeneratedWorkout | null = null;
	let b: GeneratedWorkout | null = null;
	const second = w.daysPerWeek >= 5 && !w.backToBack;
	if (w.phase === 'base') {
		a = tempoWorkout(placeholder, 6, w.paces);
	} else if (w.phase === 'build') {
		a = intervalsWorkout(placeholder, w.paces);
		if (second) b = tempoWorkout(placeholder, 7, w.paces);
	} else if (w.phase === 'peak') {
		a = intervalsWorkout(placeholder, w.paces);
		if (second) b = tempoWorkout(placeholder, 8, w.paces);
	} else if (w.phase === 'taper') {
		a = tempoWorkout(placeholder, 4, w.paces);
	}
	return { a, b };
}

function generateUltraWeek(w: UltraWeekInput): GeneratedWorkout[] {
	// Same day roles as the road week (Sun long, Mon rest, Tue/Thu quality,
	// Wed/Fri for masters), plus Saturday for the back-to-back's first day.
	const rest = w.daysPerWeek >= 7 ? -1 : 1;
	const longRun = 0;
	const saturday = 6;
	const qualityA = w.masters ? 3 : 2;
	const qualityB = w.masters ? 5 : 4;
	const isRaceWeek = w.phase === 'race';
	const easyPace = w.paces.easy;
	const capSec = ultraLongRunCapSec(w.goalDistanceM);
	const quality = allocateUltraQuality(w);

	const sunday = isRaceWeek
		? null
		: ultraLongRunWorkout(
				'',
				w.weeklyKm * (w.backToBack ? ULTRA_B2B_SUNDAY_SHARE : ULTRA_LONG_SHARE),
				capSec,
				easyPace,
				ULTRA_LONG_NOTE
			);
	const saturdayRun = w.backToBack
		? ultraLongRunWorkout(
				'',
				w.weeklyKm * ULTRA_B2B_SATURDAY_SHARE,
				floorToStep(capSec * ULTRA_B2B_SATURDAY_CAP),
				easyPace,
				ULTRA_B2B_NOTE
			)
		: null;

	const daysUsed = new Set<number>(rest >= 0 ? [longRun, rest] : [longRun]);
	if (quality.a) daysUsed.add(qualityA);
	if (quality.b) daysUsed.add(qualityB);
	if (saturdayRun) daysUsed.add(saturday);

	const anchorKm = isRaceWeek ? w.goalDistanceM / 1000 : (sunday!.target_distance_m ?? 0) / 1000;
	const fixedKm =
		anchorKm +
		((saturdayRun?.target_distance_m ?? 0) +
			(quality.a?.target_distance_m ?? 0) +
			(quality.b?.target_distance_m ?? 0)) /
			1000;
	const remainingKm = Math.max(0, w.weeklyKm - fixedKm);
	const easySlots = Math.max(0, w.daysPerWeek - [...daysUsed].filter((d) => d !== rest).length);
	// Unlike the road week, every ultra week only fills the easy days its
	// budget holds at the 3 km floor: on a low-volume plan with many training
	// days the floors alone would otherwise outgrow the ramp limit.
	const easyDayCount = Math.min(easySlots, Math.floor(remainingKm / EASY_RUN_FLOOR_KM));
	// Whole kilometres per easy day, floored on the week's total rather than
	// rounded per day — five easy days each rounding 4.6 up would put the week
	// 2 km over its budget — with the leftover kilometres on the first days.
	const easyTotalKm =
		easyDayCount > 0
			? Math.floor(Math.min(remainingKm, (easyDayCount * ULTRA_EASY_MAX_SEC) / easyPace))
			: 0;
	const easyBaseKm = easyDayCount > 0 ? Math.floor(easyTotalKm / easyDayCount) : 0;
	const easyExtraDays = easyTotalKm - easyBaseKm * easyDayCount;

	const workouts: GeneratedWorkout[] = [];
	let easyEmitted = 0;
	for (let dow = 0; dow < 7; dow++) {
		const date = formatISO(addDays(w.weekStart, dow));
		if (dow === rest) {
			workouts.push(emptyWorkout(date, 'rest'));
		} else if (dow === longRun) {
			workouts.push(
				isRaceWeek ? ultraRaceWorkout(date, w.goalDistanceM, w.goalTimeSec) : { ...sunday!, scheduled_date: date }
			);
		} else if (dow === saturday && saturdayRun) {
			workouts.push({ ...saturdayRun, scheduled_date: date });
		} else if (dow === qualityA && quality.a) {
			workouts.push({ ...quality.a, scheduled_date: date });
		} else if (dow === qualityB && quality.b) {
			workouts.push({ ...quality.b, scheduled_date: date });
		} else if (easyEmitted < easyDayCount) {
			workouts.push(
				easyWorkout(date, easyBaseKm + (easyEmitted < easyExtraDays ? 1 : 0), w.paces)
			);
			easyEmitted++;
		} else {
			workouts.push(emptyWorkout(date, 'rest'));
		}
	}
	return limitToDays(workouts, w.daysPerWeek);
}

/// An ultra's race day carries the goal time as its duration and no pace:
/// an average pace over 100 miles folds in aid stations, climbs and the
/// night, so it is no number to run to.
function ultraRaceWorkout(
	date: string,
	goalDistanceM: number,
	goalTimeSec: number | null
): GeneratedWorkout {
	return {
		scheduled_date: date,
		kind: 'race',
		target_distance_m: goalDistanceM,
		target_duration_seconds: goalTimeSec && goalTimeSec > 0 ? goalTimeSec : null,
		target_pace_sec_per_km: null,
		target_pace_tolerance_sec: null,
		structure: null,
		notes: 'Race day. Run by effort and fuel early — the clock looks after itself.'
	};
}

export function peakVolumeKm(
	goalDistanceM: number,
	daysPerWeek: number,
	hasAnchor: boolean = true
): number {
	// Rough volumes: ~4× goal for 5k/10k runners, ~2.5× for half, ~1.8× for full,
	// scaled gently by training days. Tuneable; see tests for expected outputs.
	// Past the marathon the multiple stops: weekly volume keeps growing with
	// the race, but far more slowly than the race does.
	const baseKm = isUltraDistance(goalDistanceM)
		? ultraPeakBaseKm(goalDistanceM)
		: (goalDistanceM / 1000) *
			(goalDistanceM <= 10_000 ? 5 : goalDistanceM <= 21_100 ? 2.5 : 1.8);
	const dayFactor = 0.7 + (daysPerWeek - 3) * 0.1;
	// With no fitness anchor (no goal time, no recent 5k) we can't assume the
	// runner can absorb the full volume — a no-info 5k plan otherwise peaked
	// at ~25 km/week with a punishing week-1 (new persona #23). Scale the peak
	// down so the ramp starts somewhere a cautious runner can actually hit.
	const anchorFactor = hasAnchor ? 1 : 0.6;
	return Math.round(baseKm * dayFactor * anchorFactor);
}

// Masters recover on a 3-week cycle (step back every 3rd week); the
// default build/recover cycle is 4 weeks. Both keep the very first
// week (i === 0) at full ramp so the plan doesn't open on a step-back.
function isStepBackWeek(i: number, masters: boolean): boolean {
	if (i === 0) return false;
	return masters ? i % 3 === 2 : i % 4 === 3;
}

export function mileageFraction(
	i: number,
	total: number,
	phase: PlanPhase,
	masters = false
): number {
	if (phase === 'race') return 0.35;
	if (phase === 'taper') return 0.55;
	// Linear ramp inside base+build+peak, with a 0.82× step-back on the
	// recovery week (every 3rd week for masters, every 4th otherwise).
	const ramp = 0.6 + (0.4 * i) / Math.max(1, total - 3);
	const stepBack = isStepBackWeek(i, masters) ? 0.82 : 1;
	return Math.min(1, ramp * stepBack);
}

function weekNote(phase: PlanPhase, i: number, total: number, masters = false): string | null {
	if (phase === 'race') return 'Race week — trust the work.';
	if (phase === 'taper') return 'Taper — volume down, sharpness stays.';
	if (isStepBackWeek(i, masters)) return 'Step-back week — recover before the next build.';
	return null;
}

interface WeekGenInput {
	weekIndex: number;
	phase: PlanPhase;
	weekStart: Date;
	daysPerWeek: number;
	weeklyKm: number;
	paces: TrainingPaces;
	goalDistanceM: number;
	goalPaceSecPerKm: number;
	masters?: boolean;
}

// The shortest distance an easy/recovery run is ever prescribed at. Below this
// there is no point emitting a run, so the race-week shakeout budget is
// measured in whole floor-length days. Exported so a pass that rescales a
// generated plan (comeback.ts `capReturnRamp`) keeps to the same floor.
export const EASY_RUN_FLOOR_KM = 3;

/// An easy run shorter than this is labelled a recovery run.
export const RECOVERY_RUN_MAX_KM = 4;

function generateWeek(w: WeekGenInput): GeneratedWorkout[] {
	const workouts: GeneratedWorkout[] = [];
	// Fixed rest day: Monday. Long run: Sunday.
	// Quality days: Tuesday (intervals or tempo), Thursday (tempo or MP).
	// Masters (Older #30) recover slower, so the first quality day moves
	// to Wednesday — 72h after the Sunday long run instead of 48h — and
	// the second to Friday, keeping ~48h between the two hard sessions.
	// Remaining active days are easy.
	// Monday is the rest day — UNLESS the runner asked to run all 7 days, in
	// which case there is no rest day (rest = -1, a dow no day matches) and
	// Monday falls through to an easy run. Both wizards offer up to 7 d/wk; a
	// hardwired Monday rest silently capped a 7-day plan at 6 active days.
	const rest = w.daysPerWeek >= 7 ? -1 : 1; // Mon, or none at 7 d/wk
	const longRun = 0; // Sun (weekday 0)
	const qualityA = w.masters ? 3 : 2; // Wed for masters, else Tue
	const qualityB = w.masters ? 5 : 4; // Fri for masters, else Thu
	const longRunKm = longRunDistance(w);
	const qualityDistribution = allocateQualityKm(w);
	const daysUsed = new Set<number>(rest >= 0 ? [longRun, rest] : [longRun]);
	// Persona-hunt Intermediate #4: a 3-day plan used to be all
	// long-run + easy with zero quality work across every phase — i.e.
	// not a training plan, just a mileage log. A 3-day intermediate
	// runner training for a half should still get one tempo/interval
	// per week (the phase decides which); 4-day plans get qualityA;
	// 5-day plans add qualityB. Reserve a quality slot only when the phase
	// actually fills it — `allocateQualityKm` returns null for the race phase
	// and never populates b for base/taper. Reserving an empty slot
	// understated the easy-day count, so the slot fell through to an extra
	// easy run and the week overshot its volume target (#326).
	if (qualityDistribution.a) daysUsed.add(qualityA);
	if (qualityDistribution.b) daysUsed.add(qualityB);

	// In a race week the Sunday slot emits the race itself (goalDistanceM),
	// standing in for the long run, and typically dwarfs the light race-week
	// budget on its own — so the anchor subtracted from the weekly budget must
	// be the race distance, not the (much smaller) nominal long run (#326).
	const isRaceWeek = w.phase === 'race';
	const anchorKm = isRaceWeek ? w.goalDistanceM / 1000 : longRunKm;
	const remainingKm = Math.max(
		0,
		w.weeklyKm - anchorKm - qualityDistribution.totalKm
	);
	const easySlots = w.daysPerWeek - [...daysUsed].filter(
		(d) => d !== rest
	).length;
	// Race week: only add the shakeout easy days the light remaining budget
	// supports at the 3 km floor, so a race that dwarfs the budget isn't padded
	// back up toward peak volume. Every other phase honours the requested day
	// count even when a low-volume week's fixed tempo/long run nudges it
	// slightly over its nominal target (persona #23 — daysPerWeek is a promise
	// the training-load phases keep).
	const easyDayCount = isRaceWeek
		? Math.min(easySlots, Math.floor(remainingKm / EASY_RUN_FLOOR_KM))
		: easySlots;
	const easyKm = easyDayCount > 0 ? remainingKm / easyDayCount : 0;

	let easyEmitted = 0;
	for (let dow = 0; dow < 7; dow++) {
		const date = formatISO(addDays(w.weekStart, dow));
		if (dow === rest) {
			workouts.push(emptyWorkout(date, 'rest'));
			continue;
		}
		if (dow === longRun) {
			if (w.phase === 'race') {
				workouts.push({
					scheduled_date: date,
					kind: 'race',
					target_distance_m: w.goalDistanceM,
					target_duration_seconds: null,
					target_pace_sec_per_km: Math.round(w.goalPaceSecPerKm),
					target_pace_tolerance_sec: 5,
					structure: null,
					notes: null
				});
			} else {
				workouts.push(longRunWorkout(date, longRunKm, w));
			}
			continue;
		}
		// If this phase allocated a quality workout for this slot, use it with
		// the current date. Otherwise fall through to the easy default. The
		// previous implementation mutated qualityDistribution.a with a
		// non-null assertion even when it was null, producing a workout row
		// with only `scheduled_date` — which the DB then rejected on insert
		// because `kind` is NOT NULL. Race week (which allocates nothing)
		// was the trigger.
		if (dow === qualityA && w.daysPerWeek >= 3 && qualityDistribution.a) {
			workouts.push({ ...qualityDistribution.a, scheduled_date: date });
			continue;
		}
		if (dow === qualityB && w.daysPerWeek >= 5 && qualityDistribution.b) {
			workouts.push({ ...qualityDistribution.b, scheduled_date: date });
			continue;
		}
		if (easyEmitted < easyDayCount) {
			workouts.push(easyWorkout(date, easyKm, w.paces));
			easyEmitted++;
		} else {
			workouts.push(emptyWorkout(date, 'rest'));
		}
	}

	// Trim to the requested days — remove 'rest' + empty easy days if the
	// runner asked for fewer than 7 slots. Always preserve the long run + any
	// quality sessions we allocated.
	const trimmed = limitToDays(workouts, w.daysPerWeek);
	return trimmed;
}

function limitToDays(ws: GeneratedWorkout[], days: number): GeneratedWorkout[] {
	const activeCount = ws.filter((w) => w.kind !== 'rest').length;
	if (activeCount <= days) return ws;
	// Shouldn't happen with current allocation, but guard against it: drop
	// extra 'easy' workouts from the end of the week.
	let remove = activeCount - days;
	// Drop the auto-generated filler days (easy AND recovery — a short easy
	// day is emitted as 'recovery', which the old check missed, so a 4-day
	// plan silently ran 6 days and stacked floored 3 km recoveries into an
	// impossible week-1 volume — new persona #23). Long runs + quality
	// sessions are always preserved.
	return ws.map((w) => {
		if (remove > 0 && (w.kind === 'easy' || w.kind === 'recovery')) {
			remove--;
			return { ...w, kind: 'rest' as WorkoutKind, target_distance_m: null, target_pace_sec_per_km: null };
		}
		return w;
	});
}

export function longRunDistance(w: WeekGenInput): number {
	// Long run is a flat 33% of the week's volume.
	return Math.round(w.weeklyKm * 0.33);
}

function longRunWorkout(
	date: string,
	km: number,
	w: WeekGenInput
): GeneratedWorkout {
	return {
		scheduled_date: date,
		kind: 'long',
		target_distance_m: km * 1000,
		target_duration_seconds: null,
		target_pace_sec_per_km: w.paces.easy,
		target_pace_tolerance_sec: 20,
		structure: null,
		notes: null
	};
}

function easyWorkout(
	date: string,
	km: number,
	paces: TrainingPaces
): GeneratedWorkout {
	return {
		scheduled_date: date,
		kind: km < RECOVERY_RUN_MAX_KM ? 'recovery' : 'easy',
		target_distance_m: Math.max(EASY_RUN_FLOOR_KM, Math.round(km)) * 1000,
		target_duration_seconds: null,
		target_pace_sec_per_km: paces.easy,
		target_pace_tolerance_sec: 30,
		structure: null,
		notes: null
	};
}

function emptyWorkout(date: string, kind: WorkoutKind): GeneratedWorkout {
	return {
		scheduled_date: date,
		kind,
		target_distance_m: null,
		target_duration_seconds: null,
		target_pace_sec_per_km: null,
		target_pace_tolerance_sec: null,
		structure: null,
		notes: null
	};
}

function allocateQualityKm(
	w: WeekGenInput
): { a: GeneratedWorkout | null; b: GeneratedWorkout | null; totalKm: number } {
	const placeholder = '';
	let a: GeneratedWorkout | null = null;
	let b: GeneratedWorkout | null = null;
	if (w.phase === 'base') {
		if (w.daysPerWeek >= 3) a = tempoWorkout(placeholder, 6, w.paces);
	} else if (w.phase === 'build') {
		if (w.daysPerWeek >= 3) a = intervalsWorkout(placeholder, w.paces);
		if (w.daysPerWeek >= 5) b = tempoWorkout(placeholder, 7, w.paces);
	} else if (w.phase === 'peak') {
		if (w.daysPerWeek >= 3) a = intervalsWorkout(placeholder, w.paces);
		if (w.daysPerWeek >= 5)
			b = marathonPaceWorkout(placeholder, w.paces, w.goalDistanceM, w.goalPaceSecPerKm);
	} else if (w.phase === 'taper') {
		if (w.daysPerWeek >= 3) a = tempoWorkout(placeholder, 4, w.paces);
	}
	const totalKm =
		(a?.target_distance_m ?? 0) / 1000 + (b?.target_distance_m ?? 0) / 1000;
	return { a, b, totalKm };
}

function tempoWorkout(
	date: string,
	totalKm: number,
	paces: TrainingPaces
): GeneratedWorkout {
	const steady = Math.max(2, totalKm - 3);
	return {
		scheduled_date: date,
		kind: 'tempo',
		target_distance_m: totalKm * 1000,
		target_duration_seconds: null,
		target_pace_sec_per_km: paces.tempo,
		target_pace_tolerance_sec: 8,
		structure: {
			warmup: { distance_m: 1500, pace: 'easy' },
			steady: { distance_m: steady * 1000, pace_sec_per_km: paces.tempo },
			cooldown: { distance_m: 1500, pace: 'easy' }
		},
		notes: null
	};
}

function intervalsWorkout(date: string, paces: TrainingPaces): GeneratedWorkout {
	const reps = 5;
	const repDistance = 1000;
	const recovery = 400;
	return {
		scheduled_date: date,
		kind: 'interval',
		target_distance_m: 1500 + reps * (repDistance + recovery) + 1500,
		target_duration_seconds: null,
		target_pace_sec_per_km: paces.interval,
		target_pace_tolerance_sec: 5,
		structure: {
			warmup: { distance_m: 1500, pace: 'easy' },
			repeats: {
				count: reps,
				distance_m: repDistance,
				pace_sec_per_km: paces.interval,
				recovery_distance_m: recovery,
				recovery_pace: 'jog'
			},
			cooldown: { distance_m: 1500, pace: 'easy' }
		},
		notes: null
	};
}

function marathonPaceWorkout(
	date: string,
	paces: TrainingPaces,
	goalDistanceM: number,
	goalPaceSecPerKm: number
): GeneratedWorkout {
	const isLongGoal = goalDistanceM >= 21_000;
	const mpKm = isLongGoal ? 10 : 5;
	// On a half/marathon plan this session IS goal-pace practice, which is
	// why it doubles to 10 km. On a 5K/10K plan it is a
	// steady aerobic session at marathon *effort*, which is genuinely slower
	// than the goal, so the training band is the right prescription there.
	const steadyPace = isLongGoal ? Math.round(goalPaceSecPerKm) : paces.marathon;
	return {
		scheduled_date: date,
		kind: 'marathon_pace',
		target_distance_m: (mpKm + 3) * 1000,
		target_duration_seconds: null,
		target_pace_sec_per_km: steadyPace,
		target_pace_tolerance_sec: 8,
		structure: {
			warmup: { distance_m: 1500, pace: 'easy' },
			steady: { distance_m: mpKm * 1000, pace_sec_per_km: steadyPace },
			cooldown: { distance_m: 1500, pace: 'easy' }
		},
		notes: null
	};
}

/// A workout is "done" if a tracked run has been auto-matched to it
/// (`completed_run_id`) or the user manually marked it from the editor
/// (`manually_completed`). Both fields can be set together once a real
/// run lands; either alone is enough to count as done.
export function isWorkoutCompleted(
	wo: { manually_completed?: boolean | null; completed_run_id?: string | null }
): boolean {
	return wo.manually_completed === true || wo.completed_run_id != null;
}

/// A workout is "skipped" when the runner deliberately dropped it
/// (`skipped_at` stamped). Skip and done are mutually exclusive: the
/// write layer clears completion when skipping and clears the skip when
/// completing, so a row is never both. A skipped workout is neither a
/// debt (it doesn't count as outstanding in the progress ring's
/// denominator) nor an achievement (it isn't "done") — it's off the
/// books. Read sites that filter the active to-do set exclude skipped
/// alongside completed.
export function isWorkoutSkipped(wo: { skipped_at?: string | null }): boolean {
	return wo.skipped_at != null;
}

// ─────────────────────── Date helpers ───────────────────────
// Pure ISO date helpers (YYYY-MM-DD). Intentionally UTC-free — the caller
// feeds the runner's local date; all internal math is in day counts.

export function parseISO(s: string): Date {
	const [y, m, d] = s.split('-').map(Number);
	return new Date(y, m - 1, d);
}

export function formatISO(d: Date): string {
	const pad = (n: number) => String(n).padStart(2, '0');
	return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}

/**
 * "Today" in the *local* timezone as yyyy-mm-dd. Use this instead of
 * `new Date().toISOString().slice(0, 10)` — `toISOString` formats in UTC,
 * so in any positive-offset timezone it rolls over before midnight local
 * and the date comes out a day early. Mirror of `formatISO(new Date())`.
 */
export function todayISO(): string {
	return formatISO(new Date());
}

export function addDays(d: Date, n: number): Date {
	const c = new Date(d);
	c.setDate(c.getDate() + n);
	return c;
}

// ─────────────────────── Formatters ───────────────────────
//
// `fmtKm` / `fmtPace` (unit-aware, used by every plan surface) live in
// `./units.svelte` so that this file stays pure TS — `training.test.ts`
// runs under `tsx --test` which can't resolve Svelte runes. Import
// them from `#lib/format/units.svelte` at the call site.

export function fmtHms(sec: number | null | undefined): string {
	// `!sec` catches 0/null/NaN but a NEGATIVE is truthy and would format a
	// nonsensical negative clock (e.g. -90 → "-2:-30"); guard <= 0 too, matching
	// the Dart twin (`sec == null || sec <= 0`).
	if (!sec || !Number.isFinite(sec) || sec <= 0) return '—';
	const h = Math.floor(sec / 3600);
	const m = Math.floor((sec % 3600) / 60);
	const s = Math.floor(sec % 60);
	if (h > 0) return `${h}:${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}`;
	return `${m}:${String(s).padStart(2, '0')}`;
}

