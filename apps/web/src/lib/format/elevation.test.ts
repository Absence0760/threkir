import { test } from 'node:test';
import assert from 'node:assert/strict';
import { formatElevationIn, formatElevationValue } from './elevation';

// Mirrored case for case by apps/mobile_android/test/unit_format_elevation_test.dart.

test('metric reads whole metres', () => {
	assert.equal(formatElevationValue(0, 'km', 'en'), '0');
	assert.equal(formatElevationValue(0.4, 'km', 'en'), '0');
	assert.equal(formatElevationValue(120.5, 'km', 'en'), '121');
	assert.equal(formatElevationValue(120.6, 'km', 'en'), '121');
	// A point below sea level rounds half up, as Math.round does.
	assert.equal(formatElevationValue(-0.5, 'km', 'en'), '0');
	assert.equal(formatElevationValue(-430.5, 'km', 'en'), '-430');
});

test('imperial converts to whole feet', () => {
	assert.equal(formatElevationValue(1, 'mi', 'en'), '3');
	assert.equal(formatElevationValue(100, 'mi', 'en'), '328');
	assert.equal(formatElevationValue(120, 'mi', 'en'), '394');
});

test('joins value and unit, and a missing gain is a dash', () => {
	assert.equal(formatElevationIn(120, 'km', 'en'), '120 m');
	assert.equal(formatElevationIn(120, 'mi', 'en'), '394 ft');
	assert.equal(formatElevationIn(null, 'mi', 'en'), '—');
	assert.equal(formatElevationIn(undefined, 'km', 'en'), '—');
});

test('a large gain is grouped by the locale (issue #1312)', () => {
	// 3048 m is 9999.996 ft, which rounds to 10000 ft.
	assert.equal(formatElevationIn(3048, 'mi', 'en'), '10,000 ft');
	assert.equal(formatElevationIn(10000, 'km', 'en'), '10,000 m');
	assert.equal(formatElevationIn(3048, 'mi', 'de'), '10.000 ft');
	assert.equal(formatElevationIn(10000, 'km', 'de'), '10.000 m');
	assert.match(formatElevationIn(3048, 'mi', 'fr'), /^10\s000 ft$/);
	assert.match(formatElevationIn(10000, 'km', 'fr'), /^10\s000 m$/);
	assert.equal(formatElevationIn(999, 'km', 'en'), '999 m');
});
