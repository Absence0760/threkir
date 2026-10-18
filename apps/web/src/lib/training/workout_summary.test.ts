// Mirrored case-for-case by apps/mobile_android/test/workout_summary_test.dart.
import { test } from 'node:test';
import { strict as assert } from 'node:assert';

import { generatePlan } from './training';
import type { WorkoutStructure } from './training';
import {
	aboutMinutes,
	paceZoneName,
	plannedWorkoutSize,
	spokenDuration,
	structureSegments,
	structureTotal,
	walkRunPattern
} from './workout_summary';

const intervals: WorkoutStructure = {
	warmup: { distance_m: 1500, pace: 'easy' },
	repeats: {
		count: 5,
		distance_m: 1000,
		pace_sec_per_km: 240,
		recovery_distance_m: 400,
		recovery_pace: 'jog'
	},
	cooldown: { distance_m: 1500, pace: 'easy' }
};

const walkRunWeek1: WorkoutStructure = {
	warmup: { duration_s: 300, pace: 'easy' },
	repeats: {
		count: 8,
		duration_s: 60,
		pace_sec_per_km: 420,
		recovery_duration_s: 90,
		recovery_pace: 'walk'
	},
	cooldown: { duration_s: 300, pace: 'easy' }
};

test('structureSegments: a recovery sits between reps, never after the last', () => {
	const roles = structureSegments(intervals).map((s) => s.role);
	assert.deepEqual(roles, [
		'warmup',
		'work', 'recovery', 'work', 'recovery', 'work', 'recovery', 'work', 'recovery', 'work',
		'cooldown'
	]);
	const sum = structureSegments(intervals).reduce((s, x) => s + x.fraction, 0);
	assert.ok(Math.abs(sum - 1) < 1e-9);
});

test('structureTotal: sums the executed steps in one measure', () => {
	// 1500 + 5 × 1000 + 4 × 400 + 1500
	assert.deepEqual(structureTotal(intervals), { kind: 'distance', metres: 9600 });
	// 300 + 8 × 60 + 7 × 90 + 300
	assert.deepEqual(structureTotal(walkRunWeek1), { kind: 'duration', seconds: 1710 });
});

test('structureTotal: a session mixing metres and seconds has no total', () => {
	const mixed: WorkoutStructure = {
		warmup: { duration_s: 600, pace: 'easy' },
		steady: { distance_m: 5000, pace_sec_per_km: 300 }
	};
	assert.equal(structureTotal(mixed), null);
	assert.equal(structureSegments(mixed).length, 2);
	assert.equal(structureTotal(null), null);
	assert.deepEqual(structureSegments(null), []);
});

test('walkRunPattern: week 1 reads as its timed intervals', () => {
	assert.deepEqual(walkRunPattern(walkRunWeek1), {
		warmupS: 300,
		count: 8,
		runS: 60,
		walkS: 90,
		cooldownS: 300,
		totalS: 1710,
		runM: null
	});
});

test('walkRunPattern: the graduation run has no walk', () => {
	const grad: WorkoutStructure = {
		warmup: { duration_s: 300, pace: 'easy' },
		repeats: { count: 1, duration_s: 1500, pace_sec_per_km: 420, recovery_pace: 'walk' },
		cooldown: { duration_s: 300, pace: 'easy' }
	};
	const p = walkRunPattern(grad);
	assert.equal(p?.walkS, null);
	assert.equal(p?.totalS, 2100);
});

test('walkRunPattern: the graduation 5K ends on its distance, its walks still timed', () => {
	const fiveK: WorkoutStructure = {
		warmup: { duration_s: 300, pace: 'easy' },
		repeats: { count: 1, distance_m: 5000, pace_sec_per_km: 420, recovery_pace: 'walk' },
		cooldown: { duration_s: 300, pace: 'easy' }
	};
	assert.deepEqual(walkRunPattern(fiveK), {
		warmupS: 300,
		count: 1,
		runS: 0,
		walkS: null,
		cooldownS: 300,
		totalS: 600,
		runM: 5000
	});
	// A distance only ends a single run; repeated distance reps are not a walk-run pattern.
	assert.equal(walkRunPattern({ ...fiveK, repeats: { ...fiveK.repeats!, count: 2 } }), null);
});

test('walkRunPattern: matches the generator for every C25K week', () => {
	const plan = generatePlan({
		goalEvent: 'distance_5k',
		startDate: '2026-06-01',
		daysPerWeek: 3,
		beginnerWalkRun: true
	});
	for (const week of plan.weeks) {
		for (const w of week.workouts.filter((x) => x.kind === 'walk_run')) {
			const p = walkRunPattern(w.structure);
			assert.ok(p);
			if (p.runM != null) assert.equal(p.runM, w.structure?.repeats?.distance_m);
			else assert.equal(p.totalS, w.target_duration_seconds);
		}
	}
});

test('plannedWorkoutSize: a walk-run reads as minutes, its graduation 5K as 5 km, a road run as its target', () => {
	const size = (kind: string, targetDistanceM: number | null, targetDurationS: number | null, structure: unknown) =>
		plannedWorkoutSize({ kind, targetDistanceM, targetDurationS, structure });
	assert.deepEqual(size('walk_run', 2050, 1710, walkRunWeek1), { kind: 'duration', seconds: 1710 });
	assert.deepEqual(
		size('walk_run', 5857, 4260, {
			warmup: { duration_s: 300, pace: 'easy' },
			repeats: { count: 1, distance_m: 5000, recovery_pace: 'walk' },
			cooldown: { duration_s: 300, pace: 'easy' }
		}),
		{ kind: 'distance', metres: 5000 }
	);
	// No readable pattern: the stored duration, never the estimated distance.
	assert.deepEqual(size('walk_run', 2050, 1710, null), { kind: 'duration', seconds: 1710 });
	assert.deepEqual(size('walk_run', 2050, 1710, 'x'), { kind: 'duration', seconds: 1710 });
	assert.equal(size('walk_run', 2050, null, [1]), null);
	assert.deepEqual(size('easy', 8000, 2400, null), { kind: 'distance', metres: 8000 });
	assert.equal(size('easy', null, 2400, null), null);
	assert.equal(size('easy', 0, null, null), null);
	assert.equal(size('rest', 3000, null, null), null);
});

test('walkRunPattern: null for a paced session and a distance-measured one', () => {
	assert.equal(walkRunPattern(intervals), null);
	assert.equal(
		walkRunPattern({
			...walkRunWeek1,
			warmup: { distance_m: 800, pace: 'easy' }
		}),
		null
	);
	assert.equal(walkRunPattern(null), null);
});

test('spokenDuration: minutes, seconds, or both', () => {
	assert.deepEqual(spokenDuration(60), { unit: 'min', minutes: 1 });
	assert.deepEqual(spokenDuration(300), { unit: 'min', minutes: 5 });
	assert.deepEqual(spokenDuration(90), { unit: 'sec', seconds: 90 });
	assert.deepEqual(spokenDuration(45), { unit: 'sec', seconds: 45 });
	assert.deepEqual(spokenDuration(150), { unit: 'minSec', minutes: 2, seconds: 30 });
	assert.deepEqual(spokenDuration(Number.NaN), { unit: 'sec', seconds: 0 });
	assert.deepEqual(spokenDuration(-5), { unit: 'sec', seconds: 0 });
});

test('aboutMinutes: rounds to whole minutes, never below one', () => {
	assert.equal(aboutMinutes(1710), 29);
	assert.equal(aboutMinutes(1680), 28);
	assert.equal(aboutMinutes(10), 1);
	assert.equal(aboutMinutes(Number.POSITIVE_INFINITY), 1);
});

test('paceZoneName: Daniels codes and words, case-insensitive', () => {
	assert.equal(paceZoneName('T'), 'tempo');
	assert.equal(paceZoneName(' mp '), 'marathon');
	assert.equal(paceZoneName('I'), 'interval');
	assert.equal(paceZoneName('r'), 'repetition');
	assert.equal(paceZoneName('E'), 'easy');
	assert.equal(paceZoneName('Z2'), null);
	assert.equal(paceZoneName('\u0085t'), null);
	assert.equal(paceZoneName(null), null);
});
