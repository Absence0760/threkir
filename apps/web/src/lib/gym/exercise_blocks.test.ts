import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { groupExerciseBlocks } from './exercise_blocks';

function set(set_index: number, exercise_name: string) {
	return { set_index, exercise_name };
}

test('consecutive sets of one lift form one block, spelling variants included', () => {
	const blocks = groupExerciseBlocks([
		set(0, 'Bench Press'),
		set(1, 'bench  press'),
		set(2, 'Row'),
	]);
	assert.deepEqual(
		blocks.map((b) => [b.name, b.start, b.sets.length]),
		[
			['Bench Press', 0, 2],
			['Row', 2, 1],
		],
	);
});

test('a superset alternating two lifts yields repeated names but unique block keys', () => {
	// The /share/workout/[id] page keyed its blocks on `name`, so this input —
	// any superset or circuit — threw each_key_duplicate and the public page
	// fell into the error boundary.
	const blocks = groupExerciseBlocks([
		set(0, 'Squat'),
		set(1, 'Bench Press'),
		set(2, 'Squat'),
		set(3, 'Bench Press'),
	]);
	assert.deepEqual(
		blocks.map((b) => b.name),
		['Squat', 'Bench Press', 'Squat', 'Bench Press'],
	);
	const starts = blocks.map((b) => b.start);
	assert.equal(new Set(starts).size, starts.length);
	assert.deepEqual(starts, [0, 1, 2, 3]);
});

test('an empty workout has no blocks', () => {
	assert.deepEqual(groupExerciseBlocks([]), []);
});
