import { test } from 'node:test';
import assert from 'node:assert/strict';

import { MILE_TENTH_ROUNDING_M, snapStatedDistanceM } from './stated_distance';

test('a tenth-of-a-mile figure snaps to the whole kilometre or mile it names', () => {
	assert.equal(snapStatedDistanceM(31.1 * 1609.344), 50_000);
	assert.equal(snapStatedDistanceM(62.1 * 1609.344), 100_000);
	assert.equal(snapStatedDistanceM(50.0 * 1609.344), 50 * 1609.344);
	assert.equal(snapStatedDistanceM(100.0 * 1609.344), 100 * 1609.344);
});

test('a distance further than half a tenth of a mile from a round one is kept', () => {
	assert.equal(snapStatedDistanceM(87_700), 87_700);
	assert.equal(snapStatedDistanceM(50_000 + MILE_TENTH_ROUNDING_M + 1), 50_000 + MILE_TENTH_ROUNDING_M + 1);
	assert.equal(snapStatedDistanceM(50_000 + MILE_TENTH_ROUNDING_M), 50_000);
});

test('the nearer of a round kilometre and a round mile wins', () => {
	// 80.5 km is 33 m from 50 mi and 500 m from 80 km.
	assert.equal(snapStatedDistanceM(80_500), 50 * 1609.344);
});

test('nothing usable comes back unchanged', () => {
	assert.equal(snapStatedDistanceM(0), 0);
	assert.equal(snapStatedDistanceM(-5), -5);
	assert.ok(Number.isNaN(snapStatedDistanceM(NaN)));
	assert.equal(snapStatedDistanceM(40), 40, 'no round distance of zero');
});
