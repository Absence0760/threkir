// Mirrored case-for-case by apps/mobile_android/test/workout_summary_test.dart.
import { test } from 'node:test';
import { strict as assert } from 'node:assert';

import { generatePlan } from './training';
import type { WorkoutStructure } from './training';
import {
	aboutMinutes,
	paceZoneName,
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
		totalS: 1710
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

test('walkRunPattern: matches the generator for every C25K week', () => {
	const plan = generatePlan({
		goalEvent: 'distance_5k',
		startDate: '2026-06-01',
		daysPerWeek: 3,
		beginnerWalkRun: true
	});
	for (const week of plan.weeks) {
		for (const w of week.workouts.filter((x) => x.kind === 'walk_run')) {
			assert.equal(walkRunPattern(w.structure)?.totalS, w.target_duration_seconds);
		}
	}
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
});

test('aboutMinutes: rounds to whole minutes, never below one', () => {
	assert.equal(aboutMinutes(1710), 29);
	assert.equal(aboutMinutes(1680), 28);
	assert.equal(aboutMinutes(10), 1);
});

test('paceZoneName: Daniels codes and words, case-insensitive', () => {
	assert.equal(paceZoneName('T'), 'tempo');
	assert.equal(paceZoneName(' mp '), 'marathon');
	assert.equal(paceZoneName('I'), 'interval');
	assert.equal(paceZoneName('r'), 'repetition');
	assert.equal(paceZoneName('E'), 'easy');
	assert.equal(paceZoneName('Z2'), null);
	assert.equal(paceZoneName(null), null);
});
