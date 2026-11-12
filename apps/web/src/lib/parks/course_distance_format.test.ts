import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { courseDistanceRangeText, courseDistanceText } from './course_distance_text.ts';

// The template face of a course distance. The labels follow
// apps/mobile_android/test/park_course_distance_test.dart's label and range
// cases one for one (km, mi, rounding, a range whose ends read the same,
// missing values), read through the coercion a stored distance takes on web:
// a numeric column can arrive as a string, and a missing one is no label,
// never "0 km".

test('courseDistanceText: whole kilometres read without decimals', () => {
	assert.equal(courseDistanceText(5000, 'km', 'en'), '5 km');
	assert.equal(courseDistanceText(10000, 'km', 'en'), '10 km');
	assert.equal(courseDistanceText(50000, 'km', 'en'), '50 km');
	assert.equal(courseDistanceText(0, 'km', 'en'), '0 km');
});

test('courseDistanceText: anything else reads with one decimal, never two', () => {
	assert.equal(courseDistanceText(21100, 'km', 'en'), '21.1 km');
	assert.equal(courseDistanceText(42200, 'km', 'en'), '42.2 km');
	assert.equal(courseDistanceText(21097.5, 'km', 'en'), '21.1 km');
	assert.equal(courseDistanceText(500, 'km', 'en'), '0.5 km');
	assert.equal(courseDistanceText(4940, 'km', 'en'), '4.9 km');
});

test('courseDistanceText: within 0.05 of a whole number reads whole', () => {
	assert.equal(courseDistanceText(4960, 'km', 'en'), '5 km');
	assert.equal(courseDistanceText(5040, 'km', 'en'), '5 km');
	assert.equal(courseDistanceText(5060, 'km', 'en'), '5.1 km');
});

test('courseDistanceText: miles', () => {
	assert.equal(courseDistanceText(5000, 'mi', 'en'), '3.1 mi');
	assert.equal(courseDistanceText(42195, 'mi', 'en'), '26.2 mi');
	assert.equal(courseDistanceText(1609.344, 'mi', 'en'), '1 mi');
	assert.equal(courseDistanceText(50000, 'mi', 'en'), '31.1 mi');
});

test('courseDistanceText: the decimal separator follows the locale', () => {
	assert.equal(courseDistanceText(21100, 'km', 'de'), '21,1 km');
	assert.equal(courseDistanceText(5000, 'km', 'de'), '5 km');
});

test('courseDistanceText: a numeric string reads like the number', () => {
	assert.equal(courseDistanceText('21100', 'km', 'en'), '21.1 km');
	assert.equal(courseDistanceText('42195.0', 'mi', 'en'), '26.2 mi');
});

test('courseDistanceText: a missing or unreadable distance is empty, not 0 km', () => {
	assert.equal(courseDistanceText(null, 'km', 'en'), '');
	assert.equal(courseDistanceText(undefined, 'km', 'en'), '');
	assert.equal(courseDistanceText('', 'km', 'en'), '');
	assert.equal(courseDistanceText('  ', 'mi', 'en'), '');
	assert.equal(courseDistanceText('abc', 'km', 'en'), '');
	assert.equal(courseDistanceText(Number.NaN, 'km', 'en'), '');
	assert.equal(courseDistanceText(-1, 'km', 'en'), '');
	assert.equal(courseDistanceText(Number.POSITIVE_INFINITY, 'mi', 'en'), '');
});

test('courseDistanceRangeText: shortest to longest, in any input order', () => {
	assert.equal(courseDistanceRangeText([21100, 5000, 50000, 10000], 'km', 'en'), '5–50 km');
	assert.equal(courseDistanceRangeText([5000, 50000], 'mi', 'en'), '3.1–31.1 mi');
	assert.equal(courseDistanceRangeText(['50000', '5000'], 'km', 'en'), '5–50 km');
});

test('courseDistanceRangeText: one label when every course reads the same', () => {
	assert.equal(courseDistanceRangeText([5000], 'km', 'en'), '5 km');
	assert.equal(courseDistanceRangeText([5000, 4980], 'km', 'en'), '5 km');
});

test('courseDistanceRangeText: missing distances are skipped, and none left is null', () => {
	assert.equal(courseDistanceRangeText([5000, Number.NaN, 21100], 'km', 'en'), '5–21.1 km');
	assert.equal(courseDistanceRangeText([5000, null, undefined, '', 21100], 'km', 'en'), '5–21.1 km');
	assert.equal(courseDistanceRangeText([], 'km', 'en'), null);
	assert.equal(courseDistanceRangeText([Number.NaN, -5], 'km', 'en'), null);
	assert.equal(courseDistanceRangeText([null, ''], 'km', 'en'), null);
});

test('course_distance_format reads the unit and locale preferences, not fixed values', () => {
	const src = readFileSync(resolve(import.meta.dirname, 'course_distance_format.ts'), 'utf8');
	assert.match(src, /courseDistanceText\(metres, getUnit\(\), currentLocale\(\)\)/);
	assert.match(src, /courseDistanceRangeText\(metres, getUnit\(\), currentLocale\(\)\)/);
});
