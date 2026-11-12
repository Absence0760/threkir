import { test } from 'node:test';
import assert from 'node:assert/strict';
import { raceGoalInputSeconds } from './race_goal_input.ts';

test('blank or all-zero boxes are no goal', () => {
	assert.deepEqual(raceGoalInputSeconds(null, null, null), { ok: true, seconds: null });
	assert.deepEqual(raceGoalInputSeconds(0, 0, 0), { ok: true, seconds: null });
});

test('a multi-day ultra goal up to 999:59:59 is kept', () => {
	assert.deepEqual(raceGoalInputSeconds(105, 0, 0), { ok: true, seconds: 105 * 3600 });
	assert.deepEqual(raceGoalInputSeconds(999, 59, 59), { ok: true, seconds: 999 * 3600 + 59 * 60 + 59 });
	assert.deepEqual(raceGoalInputSeconds(null, 45, null), { ok: true, seconds: 45 * 60 });
});

test('a value the boxes advertise as out of range is refused, not saved', () => {
	// Reason: the editor is not a <form>, so max= only limited the spinner and a
	// typed 1000 h saved a goal no mobile editor could open.
	assert.deepEqual(raceGoalInputSeconds(1000, 0, 0), { ok: false });
	assert.deepEqual(raceGoalInputSeconds(3, 60, 0), { ok: false });
	assert.deepEqual(raceGoalInputSeconds(3, 0, 60), { ok: false });
	assert.deepEqual(raceGoalInputSeconds(-1, 0, 0), { ok: false });
	assert.deepEqual(raceGoalInputSeconds(1.5, 0, 0), { ok: false });
});
