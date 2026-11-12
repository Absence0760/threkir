/**
 * Race pacing-strategy phase plans — pure, locale/unit-agnostic. Slices a
 * race distance into intent phases (hold back / settle / race) whose pace
 * factors multiply the goal pace, with the derived final factor chosen so the
 * distance-weighted mean factor is exactly 1.0 — the plan still lands the
 * goal time.
 *
 * Presets: 'even' (one flat phase), 'negative_split' (2% held-back first
 * half, derived-faster second half), and 'ten_ten_ten' (the classic marathon
 * 10 mi / 10 mi / 10 K strategy generalised proportionally to any distance).
 * Intent is an identifier — i18n labels resolve at the render layer and are
 * not part of the pair.
 *
 * `gradePhases` is the post-run half: it reads the strategy the phone stamped
 * into `runs.metadata.pacing_strategy` back against the recorded track and
 * grades each phase's actual pace against its target (decisions § 1915).
 *
 * Twin of `apps/mobile_android/lib/race_phases.dart` — keep logic, edge
 * cases, and test count in lockstep. `fixtures/race_phase_vectors.json` pins
 * the two `gradePhases` outputs to each other.
 */

import type { TrackPoint } from '../types';
import { sliceTrackAtDistances } from './pace_analysis';
import { haversineMetres } from './run_stats';

export type RacePhasePreset = 'ten_ten_ten' | 'negative_split' | 'even';

export type RacePhaseIntent = 'hold_back' | 'settle' | 'race' | 'even';

export interface RacePhase {
	startM: number;
	endM: number;
	intent: RacePhaseIntent;
	paceFactor: number;
}

const TEN_MILE_FRACTION = 16_093.44 / 42_195;
const HOLD_BACK_FACTOR = 1.02;

export function buildPhasePlan(distanceM: number, preset: RacePhasePreset): RacePhase[] {
	if (!Number.isFinite(distanceM) || distanceM <= 0) return [];

	if (preset === 'even') {
		return [{ startM: 0, endM: distanceM, intent: 'even', paceFactor: 1 }];
	}

	if (preset === 'negative_split') {
		const raceFactor = (1 - 0.5 * HOLD_BACK_FACTOR) / 0.5;
		return [
			{ startM: 0, endM: distanceM / 2, intent: 'hold_back', paceFactor: HOLD_BACK_FACTOR },
			{ startM: distanceM / 2, endM: distanceM, intent: 'race', paceFactor: raceFactor }
		];
	}

	const f1 = TEN_MILE_FRACTION;
	const f2 = TEN_MILE_FRACTION;
	const f3 = 1 - f1 - f2;
	const raceFactor = (1 - f1 * HOLD_BACK_FACTOR - f2 * 1) / f3;
	return [
		{ startM: 0, endM: distanceM * f1, intent: 'hold_back', paceFactor: HOLD_BACK_FACTOR },
		{ startM: distanceM * f1, endM: distanceM * (f1 + f2), intent: 'settle', paceFactor: 1 },
		{ startM: distanceM * (f1 + f2), endM: distanceM, intent: 'race', paceFactor: raceFactor }
	];
}

/**
 * Index of the phase containing `distanceM` (start-inclusive, end-exclusive;
 * >= the last end clamps to the last index, < 0 clamps to the first).
 * Empty plan → -1.
 */
export function phaseAt(phases: RacePhase[], distanceM: number): number {
	if (phases.length === 0) return -1;
	if (distanceM < 0) return 0;
	for (let i = 0; i < phases.length; i++) {
		if (distanceM >= phases[i].startM && distanceM < phases[i].endM) return i;
	}
	return phases.length - 1;
}

export function phaseTargetPaceSecPerKm(
	phase: RacePhase,
	goalPaceSecPerKm: number | null
): number | null {
	if (
		goalPaceSecPerKm == null ||
		!Number.isFinite(goalPaceSecPerKm) ||
		goalPaceSecPerKm <= 0
	) {
		return null;
	}
	return goalPaceSecPerKm * phase.paceFactor;
}

export function goalPaceSecPerKm(distanceM: number, goalTimeS: number): number | null {
	if (!Number.isFinite(distanceM) || distanceM <= 0) return null;
	if (!Number.isFinite(goalTimeS) || goalTimeS <= 0) return null;
	return goalTimeS / (distanceM / 1000);
}

export interface PacingStrategy {
	preset: RacePhasePreset;
	distanceM: number;
	goalTimeS: number | null;
}

const PRESETS: readonly RacePhasePreset[] = ['ten_ten_ten', 'negative_split', 'even'];

/**
 * The `runs.metadata.pacing_strategy` bag as the phone writes it
 * (`{ preset, distance_m, goal_time_s? }`, docs/backend/metadata.md). Null for
 * anything the reader cannot rebuild a plan from — a preset a later build
 * added, a missing or non-positive distance — so the review renders nothing
 * rather than grading against a guess. A bad goal time drops to null and the
 * review falls back to the run's own average.
 */
export function parsePacingStrategy(raw: unknown): PacingStrategy | null {
	if (raw == null || typeof raw !== 'object' || Array.isArray(raw)) return null;
	const r = raw as Record<string, unknown>;
	const preset = PRESETS.find((p) => p === r.preset);
	if (preset == null) return null;
	const d = r.distance_m;
	if (typeof d !== 'number' || !Number.isFinite(d) || d <= 0) return null;
	const g = r.goal_time_s;
	const goalTimeS = typeof g === 'number' && Number.isFinite(g) && g > 0 ? g : null;
	return { preset, distanceM: d, goalTimeS };
}

/**
 * Relative band around a phase's target pace inside which the phase is on
 * target: 1.5 %, 4.5 s/km at a 5:00/km target. It has to sit inside the 2 %
 * hold-back step, or running the hold-back phase at goal pace — the exact
 * mistake the strategy exists to prevent — would grade as on target.
 */
export const PHASE_BAND_PCT = 0.015;

/**
 * How far the recorded distance may sit from the planned one and still count
 * as the whole race: 10 %. Inside it the phase boundaries scale to the track,
 * so a GPS line that measured a marathon 300 m long or short is cut where the
 * runner actually crossed the 10-mile marks; outside it the boundaries stay at
 * their planned metres and a short run reads as stopped short.
 */
export const FINISH_TOLERANCE_PCT = 0.1;

/** Below this much moving distance a phase is shown but not graded. */
export const MIN_GRADED_PHASE_M = 200;

/**
 * A segment slower than this is a stop, not running — the threshold
 * `movingTimeSeconds` uses. Phase paces are moving paces, so a pause, an aid
 * station or a traffic light does not grade as a phase run slow.
 */
export const MOVING_MIN_SPEED_MPS = 0.5;

export type PhaseCoverage = 'full' | 'partial' | 'not_reached';
export type PhaseGrade = 'on_target' | 'fast' | 'slow';
export type PhaseTargetBasis = 'goal' | 'average';
export type PhaseReviewVerdict =
	| 'on_plan'
	| 'went_out_too_fast'
	| 'faded'
	| 'negative_split'
	| 'faster_than_plan'
	| 'slower_than_plan'
	| 'ungraded';
export type PhaseUngradedReason = 'no_track' | 'no_goal';

export interface PhaseResult {
	intent: RacePhaseIntent;
	paceFactor: number;
	/** Planned boundaries, metres from the start. */
	startM: number;
	endM: number;
	coverage: PhaseCoverage;
	coveredM: number;
	movingS: number;
	movingM: number;
	actualPaceSecPerKm: number | null;
	targetPaceSecPerKm: number | null;
	/** Actual minus target, seconds per km. Positive = slower than planned. */
	gapSecPerKm: number | null;
	grade: PhaseGrade | null;
}

export interface PhaseReview {
	strategy: PacingStrategy;
	basis: PhaseTargetBasis;
	basisPaceSecPerKm: number | null;
	trackDistanceM: number;
	completed: boolean;
	phases: PhaseResult[];
	verdict: PhaseReviewVerdict;
	ungradedReason: PhaseUngradedReason | null;
}

function tsMs(p: TrackPoint): number {
	return p.ts ? Date.parse(p.ts) : NaN;
}

function pathLength(track: TrackPoint[]): number {
	let total = 0;
	for (let i = 1; i < track.length; i++) {
		total += haversineMetres(track[i - 1].lat, track[i - 1].lng, track[i].lat, track[i].lng);
	}
	return total;
}

/**
 * Grade a recorded run against the pacing strategy it was run under.
 *
 * Phases are cut by DISTANCE with the same slicer `analysePacing` uses (see
 * FINISH_TOLERANCE_PCT for when the boundaries scale to the track). Each
 * phase's actual pace is its moving time over its moving distance. Targets
 * come from the goal time when one was set; otherwise from the run's own
 * average moving pace, re-weighted by the factors of the distance covered, so
 * the review grades the SHAPE of the run against the plan's shape — which
 * needs at least two graded phases to mean anything.
 *
 * Verdict, first match wins, with g = (actual - target) / target of the first
 * (F) and last (L) graded phases and b = PHASE_BAND_PCT:
 *   no graded phase                → ungraded
 *   every graded phase within b    → on_plan
 *   one graded phase               → faster_than_plan / slower_than_plan
 *   gF < -b and gL - gF > b        → went_out_too_fast
 *   gL > b and gL - gF > b         → faded
 *   gF - gL > b                    → negative_split (finished stronger than planned)
 *   otherwise, by the distance-weighted mean gap → faster_ / slower_than_plan
 */
export function gradePhases(
	track: TrackPoint[] | null | undefined,
	strategy: PacingStrategy
): PhaseReview {
	const plan = buildPhasePlan(strategy.distanceM, strategy.preset);
	const pts = track ?? [];
	const total = pts.length >= 2 ? pathLength(pts) : 0;
	const planned = strategy.distanceM;
	const withinTolerance = total > 0 && Math.abs(total - planned) <= planned * FINISH_TOLERANCE_PCT;
	const completed = total >= planned * (1 - FINISH_TOLERANCE_PCT);
	const scale = withinTolerance ? total / planned : 1;
	const slices =
		total > 0
			? sliceTrackAtDistances(
					pts,
					plan.slice(0, -1).map((p) => p.endM * scale)
				)
			: plan.map(() => [] as TrackPoint[]);

	const phases: PhaseResult[] = plan.map((p, i) => {
		const slice = slices[i];
		const last = i === plan.length - 1;
		const coverage: PhaseCoverage =
			total <= p.startM * scale
				? 'not_reached'
				: (last ? completed : total >= p.endM * scale)
					? 'full'
					: 'partial';
		let movingS = 0;
		let movingM = 0;
		for (let j = 1; j < slice.length; j++) {
			const a = tsMs(slice[j - 1]);
			const b = tsMs(slice[j]);
			if (!Number.isFinite(a) || !Number.isFinite(b)) continue;
			const dt = (b - a) / 1000;
			if (dt <= 0) continue;
			const d = haversineMetres(slice[j - 1].lat, slice[j - 1].lng, slice[j].lat, slice[j].lng);
			if (d / dt < MOVING_MIN_SPEED_MPS) continue;
			movingS += dt;
			movingM += d;
		}
		const graded = movingM >= MIN_GRADED_PHASE_M && movingS > 0;
		return {
			intent: p.intent,
			paceFactor: p.paceFactor,
			startM: p.startM,
			endM: p.endM,
			coverage,
			coveredM: slice.length >= 2 ? pathLength(slice) : 0,
			movingS,
			movingM,
			actualPaceSecPerKm: graded ? Math.round(movingS / (movingM / 1000)) : null,
			targetPaceSecPerKm: null,
			gapSecPerKm: null,
			grade: null,
		};
	});

	const measured = phases.filter((p) => p.actualPaceSecPerKm != null);
	let basis: PhaseTargetBasis = 'goal';
	let basisPace: number | null = null;
	let ungradedReason: PhaseUngradedReason | null = null;
	if (strategy.goalTimeS != null) {
		basisPace = goalPaceSecPerKm(planned, strategy.goalTimeS);
	} else {
		basis = 'average';
		if (measured.length >= 2) {
			const sumS = measured.reduce((s, p) => s + p.movingS, 0);
			const sumM = measured.reduce((s, p) => s + p.movingM, 0);
			const weighted = measured.reduce((s, p) => s + p.paceFactor * p.movingM, 0) / sumM;
			basisPace = sumS / (sumM / 1000) / weighted;
		}
	}
	if (measured.length === 0) ungradedReason = 'no_track';
	else if (basisPace == null) ungradedReason = 'no_goal';

	if (basisPace != null) {
		for (const p of phases) {
			p.targetPaceSecPerKm = Math.round(basisPace * p.paceFactor);
			if (p.actualPaceSecPerKm == null) continue;
			p.gapSecPerKm = p.actualPaceSecPerKm - p.targetPaceSecPerKm;
			const rel = p.gapSecPerKm / p.targetPaceSecPerKm;
			p.grade = Math.abs(rel) <= PHASE_BAND_PCT ? 'on_target' : rel < 0 ? 'fast' : 'slow';
		}
	}

	return {
		strategy,
		basis,
		basisPaceSecPerKm: basisPace == null ? null : Math.round(basisPace),
		trackDistanceM: total,
		completed,
		phases,
		verdict: verdictOf(phases.filter((p) => p.grade != null)),
		ungradedReason,
	};
}

function verdictOf(graded: PhaseResult[]): PhaseReviewVerdict {
	if (graded.length === 0) return 'ungraded';
	if (graded.every((p) => p.grade === 'on_target')) return 'on_plan';
	const rel = (p: PhaseResult) => (p.gapSecPerKm as number) / (p.targetPaceSecPerKm as number);
	if (graded.length === 1) return rel(graded[0]) < 0 ? 'faster_than_plan' : 'slower_than_plan';
	const gF = rel(graded[0]);
	const gL = rel(graded[graded.length - 1]);
	if (gF < -PHASE_BAND_PCT && gL - gF > PHASE_BAND_PCT) return 'went_out_too_fast';
	if (gL > PHASE_BAND_PCT && gL - gF > PHASE_BAND_PCT) return 'faded';
	if (gF - gL > PHASE_BAND_PCT) return 'negative_split';
	const gap = graded.reduce((s, p) => s + (p.gapSecPerKm as number) * p.movingM, 0);
	return gap < 0 ? 'faster_than_plan' : 'slower_than_plan';
}
