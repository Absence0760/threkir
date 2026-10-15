import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	buildPhasePlan,
	phaseAt,
	phaseTargetPaceSecPerKm,
	goalPaceSecPerKm,
	gradePhases,
	parsePacingStrategy,
	PHASE_BAND_PCT,
	type PacingStrategy,
	type RacePhase,
	type RacePhaseIntent,
	type RacePhasePreset
} from './race_phases';
import type { TrackPoint } from '../types';

const TEN_MILE_FRACTION = 16_093.44 / 42_195;

function weightedMeanFactor(phases: RacePhase[]): number {
	const total = phases[phases.length - 1].endM;
	return phases.reduce((sum, p) => sum + p.paceFactor * (p.endM - p.startM), 0) / total;
}

test('even preset is one full-distance phase at factor 1', () => {
	const plan = buildPhasePlan(10_000, 'even');
	assert.equal(plan.length, 1);
	assert.deepEqual(plan[0], { startM: 0, endM: 10_000, intent: 'even', paceFactor: 1 });
});

test('ten_ten_ten boundaries land on the generalised 10-mile fractions for a marathon', () => {
	const plan = buildPhasePlan(42_195, 'ten_ten_ten');
	assert.equal(plan.length, 3);
	assert.equal(plan[0].startM, 0);
	assert.ok(Math.abs(plan[1].startM - 16_093.44) < 1e-9);
	assert.ok(Math.abs(plan[2].startM - 32_186.88) < 1e-9);
	assert.equal(plan[2].endM, 42_195);
	assert.equal(plan[0].endM, plan[1].startM);
	assert.equal(plan[1].endM, plan[2].startM);
});

test('ten_ten_ten intents and factors: hold back, settle, then a derived faster finish', () => {
	const plan = buildPhasePlan(42_195, 'ten_ten_ten');
	assert.deepEqual(
		plan.map((p) => p.intent),
		['hold_back', 'settle', 'race']
	);
	assert.equal(plan[0].paceFactor, 1.02);
	assert.equal(plan[1].paceFactor, 1);
	const f = TEN_MILE_FRACTION;
	const derived = (1 - f * 1.02 - f * 1) / (1 - f - f);
	assert.ok(Math.abs(plan[2].paceFactor - derived) < 1e-12);
	assert.ok(plan[2].paceFactor > 0.96 && plan[2].paceFactor < 0.97);
});

test('distance-weighted mean factor is 1 for ten_ten_ten at any distance', () => {
	for (const distanceM of [42_195, 10_000, 160_934]) {
		const plan = buildPhasePlan(distanceM, 'ten_ten_ten');
		assert.ok(Math.abs(weightedMeanFactor(plan) - 1) < 1e-9);
	}
});

test('negative_split is two halves: held back then a derived faster finish, mean 1', () => {
	const plan = buildPhasePlan(21_097.5, 'negative_split');
	assert.equal(plan.length, 2);
	assert.deepEqual(
		plan.map((p) => p.intent),
		['hold_back', 'race']
	);
	assert.equal(plan[0].endM, 21_097.5 / 2);
	assert.equal(plan[1].startM, 21_097.5 / 2);
	assert.equal(plan[0].paceFactor, 1.02);
	assert.ok(Math.abs(plan[1].paceFactor - (1 - 0.5 * 1.02) / 0.5) < 1e-12);
	assert.ok(Math.abs(weightedMeanFactor(plan) - 1) < 1e-9);
});

test('phaseAt: an exact boundary belongs to the next phase', () => {
	const plan = buildPhasePlan(42_195, 'ten_ten_ten');
	assert.equal(phaseAt(plan, 0), 0);
	assert.equal(phaseAt(plan, plan[1].startM - 0.001), 0);
	assert.equal(phaseAt(plan, plan[1].startM), 1);
	assert.equal(phaseAt(plan, plan[2].startM), 2);
});

test('phaseAt clamps: past the end to last, negative to first, empty to -1', () => {
	const plan = buildPhasePlan(42_195, 'ten_ten_ten');
	assert.equal(phaseAt(plan, 42_195), 2);
	assert.equal(phaseAt(plan, 100_000), 2);
	assert.equal(phaseAt(plan, -5), 0);
	assert.equal(phaseAt([], 1_000), -1);
});

test('a non-positive or non-finite distance yields an empty plan', () => {
	for (const distanceM of [0, -42_195, Number.NaN, Number.POSITIVE_INFINITY]) {
		assert.deepEqual(buildPhasePlan(distanceM, 'ten_ten_ten'), []);
		assert.deepEqual(buildPhasePlan(distanceM, 'negative_split'), []);
		assert.deepEqual(buildPhasePlan(distanceM, 'even'), []);
	}
});

test('goalPaceSecPerKm divides the goal time over the km and rejects bad inputs', () => {
	assert.equal(goalPaceSecPerKm(10_000, 3_000), 300);
	assert.equal(goalPaceSecPerKm(0, 3_000), null);
	assert.equal(goalPaceSecPerKm(-1, 3_000), null);
	assert.equal(goalPaceSecPerKm(10_000, 0), null);
	assert.equal(goalPaceSecPerKm(10_000, -60), null);
	assert.equal(goalPaceSecPerKm(Number.NaN, 3_000), null);
	assert.equal(goalPaceSecPerKm(10_000, Number.NaN), null);
});

test('phaseTargetPaceSecPerKm scales the goal pace by the phase factor and rejects bad pace', () => {
	const plan = buildPhasePlan(42_195, 'ten_ten_ten');
	assert.ok(Math.abs(phaseTargetPaceSecPerKm(plan[0], 300)! - 306) < 1e-9);
	assert.equal(phaseTargetPaceSecPerKm(plan[1], 300), 300);
	assert.equal(phaseTargetPaceSecPerKm(plan[0], null), null);
	assert.equal(phaseTargetPaceSecPerKm(plan[0], 0), null);
	assert.equal(phaseTargetPaceSecPerKm(plan[0], -300), null);
	assert.equal(phaseTargetPaceSecPerKm(plan[0], Number.NaN), null);
});

test('preset and intent wire names are stable', () => {
	const presets: RacePhasePreset[] = ['ten_ten_ten', 'negative_split', 'even'];
	const intents: RacePhaseIntent[] = ['hold_back', 'settle', 'race', 'even'];
	assert.deepEqual(presets, ['ten_ten_ten', 'negative_split', 'even']);
	assert.deepEqual(intents, ['hold_back', 'settle', 'race', 'even']);
});

const M_PER_DEG_LAT = 111_320;

/// A meridian-aligned track of `legs`, each `m` metres at `pace` s/km in 50 m
/// steps; a `pauseS` leg holds position for that many seconds.
function trackOf(legs: ({ m: number; pace: number } | { pauseS: number })[]): TrackPoint[] {
	let cumM = 0;
	let tMs = Date.UTC(2026, 3, 12, 7, 0, 0);
	const at = () => ({ lat: 40 + cumM / M_PER_DEG_LAT, lng: -105, ts: new Date(tMs).toISOString() });
	const out: TrackPoint[] = [at()];
	for (const leg of legs) {
		if ('pauseS' in leg) {
			tMs += leg.pauseS * 1000;
			out.push(at());
			continue;
		}
		const n = Math.max(1, Math.round(leg.m / 50));
		for (let i = 0; i < n; i++) {
			cumM += leg.m / n;
			tMs += Math.round((leg.m / n) * leg.pace);
			out.push(at());
		}
	}
	return out;
}

const HALF: PacingStrategy = { preset: 'negative_split', distanceM: 10_000, goalTimeS: 3_000 };

test('parsePacingStrategy reads the writer shape and drops an absent goal to null', () => {
	assert.deepEqual(parsePacingStrategy({ preset: 'ten_ten_ten', distance_m: 42_195, goal_time_s: 12_600 }), {
		preset: 'ten_ten_ten',
		distanceM: 42_195,
		goalTimeS: 12_600,
	});
	assert.deepEqual(parsePacingStrategy({ preset: 'even', distance_m: 5_000 }), {
		preset: 'even',
		distanceM: 5_000,
		goalTimeS: null,
	});
});

test('parsePacingStrategy refuses an unknown preset, a bad distance, and a non-object', () => {
	assert.equal(parsePacingStrategy({ preset: 'pyramid', distance_m: 10_000 }), null);
	assert.equal(parsePacingStrategy({ preset: 'even', distance_m: 0 }), null);
	assert.equal(parsePacingStrategy({ preset: 'even', distance_m: '5000' }), null);
	assert.equal(parsePacingStrategy({ preset: 'even' }), null);
	assert.equal(parsePacingStrategy('even'), null);
	assert.equal(parsePacingStrategy(null), null);
	assert.equal(parsePacingStrategy([]), null);
});

test('gradePhases grades phases on moving time, so a stop does not read as a slow phase', () => {
	const r = gradePhases(
		trackOf([{ m: 2_500, pace: 306 }, { pauseS: 240 }, { m: 2_500, pace: 306 }, { m: 5_000, pace: 294 }]),
		HALF
	);
	assert.deepEqual(
		r.phases.map((p) => p.grade),
		['on_target', 'on_target']
	);
	assert.equal(r.verdict, 'on_plan');
	assert.ok(Math.abs(r.phases[0].actualPaceSecPerKm! - 306) <= 1);
});

test('gradePhases without a track keeps the goal targets and grades nothing', () => {
	const r = gradePhases(null, HALF);
	assert.equal(r.verdict, 'ungraded');
	assert.equal(r.ungradedReason, 'no_track');
	assert.equal(r.completed, false);
	assert.deepEqual(
		r.phases.map((p) => [p.coverage, p.targetPaceSecPerKm, p.actualPaceSecPerKm]),
		[
			['not_reached', 306, null],
			['not_reached', 294, null],
		]
	);
});

test('gradePhases calls a fast first phase followed by a slow finish going out too fast', () => {
	const r = gradePhases(trackOf([{ m: 5_000, pace: 290 }, { m: 5_000, pace: 310 }]), HALF);
	assert.deepEqual(
		r.phases.map((p) => p.grade),
		['fast', 'slow']
	);
	assert.equal(r.verdict, 'went_out_too_fast');
	assert.ok(r.phases[0].gapSecPerKm! < 0 && r.phases[1].gapSecPerKm! > 0);
});

test('gradePhases on a run well short of the plan marks it incomplete and leaves later phases unreached', () => {
	const r = gradePhases(trackOf([{ m: 3_000, pace: 306 }]), HALF);
	assert.equal(r.completed, false);
	assert.deepEqual(
		r.phases.map((p) => p.coverage),
		['partial', 'not_reached']
	);
	assert.equal(r.phases[1].actualPaceSecPerKm, null);
	assert.equal(r.verdict, 'on_plan');
});

test('gradePhases needs a goal time to grade a single-phase even plan', () => {
	const r = gradePhases(trackOf([{ m: 5_000, pace: 300 }]), {
		preset: 'even',
		distanceM: 5_000,
		goalTimeS: null,
	});
	assert.equal(r.basis, 'average');
	assert.equal(r.verdict, 'ungraded');
	assert.equal(r.ungradedReason, 'no_goal');
	assert.equal(r.phases[0].targetPaceSecPerKm, null);
});

test('gradePhases band: a 1.4% miss is on target, a 2.7% miss is not', () => {
	assert.equal(PHASE_BAND_PCT, 0.015);
	const even: PacingStrategy = { preset: 'even', distanceM: 5_000, goalTimeS: 1_500 };
	assert.equal(gradePhases(trackOf([{ m: 5_000, pace: 304 }]), even).phases[0].grade, 'on_target');
	assert.equal(gradePhases(trackOf([{ m: 5_000, pace: 308 }]), even).phases[0].grade, 'slow');
	assert.equal(gradePhases(trackOf([{ m: 5_000, pace: 292 }]), even).phases[0].grade, 'fast');
});
