import { test } from 'node:test';
import assert from 'node:assert/strict';
import { formatShortDistance } from './short_distance';

// Mirrored case for case by apps/mobile_android/test/unit_format_short_distance_test.dart.

test('metric: metres below a kilometre, kilometres from one up', () => {
	assert.equal(formatShortDistance(0, 'km', 'en'), '0 m');
	assert.equal(formatShortDistance(400, 'km', 'en'), '400 m');
	assert.equal(formatShortDistance(999.4, 'km', 'en'), '999 m');
	assert.equal(formatShortDistance(1000, 'km', 'en'), '1.00 km');
	assert.equal(formatShortDistance(5234, 'km', 'en'), '5.23 km');
});

test('imperial: yards below a mile, miles from one up', () => {
	assert.equal(formatShortDistance(400, 'mi', 'en'), '437 yd');
	assert.equal(formatShortDistance(1371.6, 'mi', 'en'), '1,500 yd');
	assert.equal(formatShortDistance(1609.344, 'mi', 'en'), '1.00 mi');
	assert.equal(formatShortDistance(8046.72, 'mi', 'en'), '5.00 mi');
});

test('a 5 mi step 15 s in reads in miles, not 8779 yd (issue #1300)', () => {
	assert.equal(formatShortDistance(8027.7, 'mi', 'en'), '4.99 mi');
});

test('follows the locale separators', () => {
	assert.equal(formatShortDistance(5234, 'km', 'de'), '5,23 km');
	assert.equal(formatShortDistance(1371.6, 'mi', 'de'), '1.500 yd');
});
