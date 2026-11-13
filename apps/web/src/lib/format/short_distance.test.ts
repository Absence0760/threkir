import { test } from 'node:test';
import assert from 'node:assert/strict';
import { formatShortDistance, formatThresholdDistance } from './short_distance';

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

test('threshold: one decimal for a race distance, dropped when whole', () => {
	assert.equal(formatThresholdDistance(5000, 'km', 1, 'en'), '5 km');
	assert.equal(formatThresholdDistance(21097, 'km', 1, 'en'), '21.1 km');
	assert.equal(formatThresholdDistance(42195, 'mi', 1, 'en'), '26.2 mi');
	assert.equal(formatThresholdDistance(50000, 'mi', 1, 'en'), '31.1 mi');
});

test('threshold: a whole number for a total, grouped by the locale', () => {
	assert.equal(formatThresholdDistance(1000000, 'km', 0, 'en'), '1,000 km');
	assert.equal(formatThresholdDistance(1000000, 'mi', 0, 'en'), '621 mi');
	assert.equal(formatThresholdDistance(5000000, 'mi', 0, 'de'), '3.107 mi');
	assert.equal(formatThresholdDistance(21097, 'km', 1, 'de'), '21,1 km');
});
