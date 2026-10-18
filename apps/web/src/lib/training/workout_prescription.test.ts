import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import {
	isEditedByCoach,
	parseTargetRange,
	rangeShape,
	RPE_BOUNDS,
	TARGET_HR_BOUNDS
} from './workout_prescription';

test('rangeShape: both ends, one end, equal ends, none', () => {
	assert.equal(rangeShape(3, 4), 'between');
	assert.equal(rangeShape(null, 125), 'atMost');
	assert.equal(rangeShape(110, null), 'atLeast');
	assert.equal(rangeShape(5, 5), 'exact');
	assert.equal(rangeShape(null, null), null);
	assert.equal(rangeShape(undefined, undefined), null);
});

test('parseTargetRange: open ends are allowed', () => {
	assert.deepEqual(parseTargetRange(null, 125, TARGET_HR_BOUNDS), { ok: true, min: null, max: 125 });
	assert.deepEqual(parseTargetRange(3, null, RPE_BOUNDS), { ok: true, min: 3, max: null });
	assert.deepEqual(parseTargetRange(null, null, RPE_BOUNDS), { ok: true, min: null, max: null });
});

test('parseTargetRange: the bounds are the columns\' CHECKs, inclusive', () => {
	assert.deepEqual(parseTargetRange(1, 10, RPE_BOUNDS), { ok: true, min: 1, max: 10 });
	assert.deepEqual(parseTargetRange(0, 4, RPE_BOUNDS), { ok: false, reason: 'outOfRange' });
	assert.deepEqual(parseTargetRange(3, 11, RPE_BOUNDS), { ok: false, reason: 'outOfRange' });
	assert.deepEqual(parseTargetRange(30, 230, TARGET_HR_BOUNDS), { ok: true, min: 30, max: 230 });
	assert.deepEqual(parseTargetRange(null, 231, TARGET_HR_BOUNDS), { ok: false, reason: 'outOfRange' });
});

test('parseTargetRange: a fraction or a non-number is refused', () => {
	assert.deepEqual(parseTargetRange(3.5, 4, RPE_BOUNDS), { ok: false, reason: 'notWhole' });
	assert.deepEqual(parseTargetRange(Number.NaN, null, RPE_BOUNDS), { ok: false, reason: 'notWhole' });
});

test('parseTargetRange: a low end above the high end is refused', () => {
	assert.deepEqual(parseTargetRange(5, 4, RPE_BOUNDS), { ok: false, reason: 'reversed' });
	assert.deepEqual(parseTargetRange(5, 5, RPE_BOUNDS), { ok: true, min: 5, max: 5 });
});

test('isEditedByCoach: the owner sees an edit by someone else', () => {
	assert.equal(isEditedByCoach({ updated_by: 'coach' }, 'me', 'me'), true);
	assert.equal(isEditedByCoach({ updated_by: 'me' }, 'me', 'me'), false);
	assert.equal(isEditedByCoach({ updated_by: null }, 'me', 'me'), false);
	assert.equal(isEditedByCoach({}, 'me', 'me'), false);
});

test('isEditedByCoach: only the owner is told, and an unknown owner or viewer is not', () => {
	assert.equal(isEditedByCoach({ updated_by: 'athlete' }, 'athlete', 'coach'), false);
	assert.equal(isEditedByCoach({ updated_by: 'coach' }, null, 'me'), false);
	assert.equal(isEditedByCoach({ updated_by: 'coach' }, 'me', null), false);
});
