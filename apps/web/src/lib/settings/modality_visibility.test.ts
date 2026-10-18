import { test } from 'node:test';
import assert from 'node:assert/strict';
import type { JsonObject } from '../types';
import {
	MODALITY_VISIBILITY_KEYS,
	explicitModalityChoice,
	modalityShown,
	nonRunDataPresence,
} from './modality_visibility';

test('unset: hidden for a runner with no data, shown once there is some', () => {
	assert.equal(modalityShown({ explicit: null, hasData: false }), false);
	assert.equal(
		modalityShown({ explicit: null, hasData: true }),
		true,
		'someone already logging lifts must not lose the surface',
	);
});

test('an explicit choice wins over the data either way', () => {
	assert.equal(modalityShown({ explicit: true, hasData: false }), true);
	assert.equal(modalityShown({ explicit: false, hasData: true }), false);
});

test('the choices live under the keys mobile reads', () => {
	assert.deepEqual(MODALITY_VISIBILITY_KEYS, { gym: 'show_gym', nutrition: 'show_nutrition' });
});

test('an explicit choice is read from the universal bag only, and only as a bool', () => {
	const read = (universal: JsonObject, device: JsonObject = {}) =>
		explicitModalityChoice({ universal, device }, 'gym');
	assert.equal(read({ show_gym: true }), true);
	assert.equal(read({ show_gym: false }), false);
	assert.equal(read({}), null);
	assert.equal(read({ show_gym: null }), null);
	assert.equal(read({ show_gym: 'false' }), null, 'a non-bool is no choice, not hidden');
	assert.equal(read({ show_gym: 0 }), null);
	assert.equal(read({}, { show_gym: true }), null, 'a device bag cannot carry a universal key');
	assert.equal(explicitModalityChoice({ universal: { show_nutrition: true }, device: {} }, 'nutrition'), true);
});

test('non-run data: one lift or meal is enough, even before the other read lands', () => {
	assert.equal(nonRunDataPresence(true, null), true);
	assert.equal(nonRunDataPresence(null, true), true);
	assert.equal(nonRunDataPresence(true, false), true);
	assert.equal(nonRunDataPresence(false, true), true);
});

test('non-run data: "none" needs both reads, so a pending one is never read as no', () => {
	assert.equal(nonRunDataPresence(false, false), false);
	assert.equal(nonRunDataPresence(false, null), null);
	assert.equal(nonRunDataPresence(null, false), null);
	assert.equal(nonRunDataPresence(null, null), null);
});
