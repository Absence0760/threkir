import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { buildNextTargetHints, type HintRoutineExercise } from './next_target_hints';

function exercise(
	exercise_name: string,
	targetReps: number,
	progression: HintRoutineExercise['progression'] = 'linear',
): HintRoutineExercise {
	return {
		exercise_name,
		progression,
		progression_params: {},
		sets: [{ target_reps_min: targetReps, target_reps_max: targetReps }],
	};
}

function logged(exercise_name: string, weight_kg: number, reps: number) {
	return { exercise_name, weight_kg, reps, rpe: null, set_type: 'working' };
}

test('a lift programmed into two blocks yields one hint, from the first block', () => {
	// Heavy top set then back-offs: the same lift in two routine blocks, both
	// on a scheme. Two hints shared the review's `exerciseKey` {#each} key,
	// Svelte threw each_key_duplicate and the owner's /gym/[id] page broke.
	const hints = buildNextTargetHints({
		exercises: [exercise('Squat', 5), exercise('Bench Press', 5), exercise('squat', 8)],
		sets: [logged('Squat', 100, 5), logged('Bench Press', 60, 5), logged('squat', 80, 8)],
		history: [],
	});
	const keys = hints.map((h) => h.exerciseKey);
	assert.equal(new Set(keys).size, keys.length);
	assert.deepEqual(keys, ['squat', 'bench press']);
	assert.equal(hints[0].exerciseName, 'Squat');
	assert.equal(hints[0].suggestedRepsMin, 5);
	assert.equal(hints[0].currentTopKg, 100);
});

test('a lift on no scheme or with no logged sets gets no hint', () => {
	const hints = buildNextTargetHints({
		exercises: [exercise('Squat', 5, 'none'), exercise('Deadlift', 5)],
		sets: [logged('Squat', 100, 5)],
		history: [],
	});
	assert.deepEqual(hints, []);
});

test('a second block still speaks for the lift when the first is on no scheme', () => {
	const hints = buildNextTargetHints({
		exercises: [exercise('Squat', 5, 'none'), exercise('Squat', 8)],
		sets: [logged('Squat', 80, 8)],
		history: [],
	});
	assert.equal(hints.length, 1);
	assert.equal(hints[0].suggestedRepsMin, 8);
});
