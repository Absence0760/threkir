import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
	KM_TENTH_ROUNDING_M,
	MILE_TENTH_ROUNDING_M,
	parseStatedDistanceUnit,
	snapStatedDistanceM,
} from './stated_distance';

test('a tenth-of-a-mile figure snaps to the whole kilometre or mile it names', () => {
	assert.equal(snapStatedDistanceM(31.1 * 1609.344, 'mi'), 50_000);
	assert.equal(snapStatedDistanceM(62.1 * 1609.344, 'mi'), 100_000);
	assert.equal(snapStatedDistanceM(50.0 * 1609.344, 'mi'), 50 * 1609.344);
	assert.equal(snapStatedDistanceM(100.0 * 1609.344, 'mi'), 100 * 1609.344);
});

test('a tenth-of-a-kilometre figure snaps to the whole mile or kilometre it names', () => {
	// 160.9 km is 34 m short of 100 miles.
	assert.equal(snapStatedDistanceM(160_900, 'km'), 100 * 1609.344);
	assert.equal(snapStatedDistanceM(50_000, 'km'), 50_000);
});

test('a kilometre figure is not rewritten by the mile tolerance', () => {
	// 60 m off 50 km: inside half a tenth of a mile, outside half a tenth of a km.
	assert.equal(snapStatedDistanceM(50_060, 'km'), 50_060);
	assert.equal(snapStatedDistanceM(50_060, 'mi'), 50_000);
	assert.equal(snapStatedDistanceM(50_000 + KM_TENTH_ROUNDING_M, 'km'), 50_000);
	assert.equal(snapStatedDistanceM(50_000 + KM_TENTH_ROUNDING_M + 1, 'km'), 50_000 + KM_TENTH_ROUNDING_M + 1);
});

test('a distance further than half a tenth of its unit from a round one is kept', () => {
	assert.equal(snapStatedDistanceM(87_700, 'km'), 87_700);
	assert.equal(snapStatedDistanceM(87_700, 'mi'), 87_700);
	assert.equal(
		snapStatedDistanceM(50_000 + MILE_TENTH_ROUNDING_M + 1, 'mi'),
		50_000 + MILE_TENTH_ROUNDING_M + 1,
	);
	assert.equal(snapStatedDistanceM(50_000 + MILE_TENTH_ROUNDING_M, 'mi'), 50_000);
});

test('the nearer of a round kilometre and a round mile wins', () => {
	// 80.5 km is 33 m from 50 mi and 500 m from 80 km.
	assert.equal(snapStatedDistanceM(80_500, 'mi'), 50 * 1609.344);
	assert.equal(snapStatedDistanceM(80_500, 'km'), 50 * 1609.344);
});

test('nothing usable comes back unchanged', () => {
	for (const unit of ['km', 'mi'] as const) {
		assert.equal(snapStatedDistanceM(0, unit), 0);
		assert.equal(snapStatedDistanceM(-5, unit), -5);
		assert.ok(Number.isNaN(snapStatedDistanceM(NaN, unit)));
		assert.equal(snapStatedDistanceM(40, unit), 40, 'no round distance of zero');
	}
});

test('an unreadable stated unit is km, the tolerance that rewrites less', () => {
	assert.equal(parseStatedDistanceUnit('mi'), 'mi');
	assert.equal(parseStatedDistanceUnit('km'), 'km');
	assert.equal(parseStatedDistanceUnit('miles'), 'km');
	assert.equal(parseStatedDistanceUnit(undefined), 'km');
});
