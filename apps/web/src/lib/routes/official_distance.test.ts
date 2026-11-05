// Invocation:
//   npx tsx --test src/lib/routes/official_distance.test.ts
// Mirrors apps/mobile_android/test/official_distance_test.dart case for case.

import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
	courseDistanceScale,
	officialDistanceVerdict,
	routeDisplayDistanceM,
} from './official_distance';

test('a route shows its official distance when it has one', () => {
	assert.equal(routeDisplayDistanceM(42670, 42195), 42195);
});

test('a route without an official distance shows the measured one', () => {
	assert.equal(routeDisplayDistanceM(42670, null), 42670);
	assert.equal(routeDisplayDistanceM(42670, undefined), 42670);
	assert.equal(routeDisplayDistanceM(42670, 0), 42670);
	assert.equal(routeDisplayDistanceM(42670, Number.NaN), 42670);
});

test('the scale is official metres per metre of line', () => {
	assert.equal(courseDistanceScale(42670, 42195), 42195 / 42670);
	// Richmond: the race's km 42 sits 42,000 / scale = 42,473 m along the trace.
	assert.equal(Math.round(42000 / courseDistanceScale(42670, 42195)), 42473);
});

test('the scale is 1 when either figure is missing', () => {
	assert.equal(courseDistanceScale(42670, null), 1);
	assert.equal(courseDistanceScale(42670, 0), 1);
	assert.equal(courseDistanceScale(0, 42195), 1);
	assert.equal(courseDistanceScale(Number.NaN, 42195), 1);
});

test('an official distance within 10% of the measured one is accepted', () => {
	assert.equal(officialDistanceVerdict(42670, 42195), 'ok');
	assert.equal(officialDistanceVerdict(10000, 11000), 'ok');
	assert.equal(officialDistanceVerdict(10000, 9000), 'ok');
});

test('an official distance more than 10% off the measured one is refused', () => {
	assert.equal(officialDistanceVerdict(10000, 11001), 'tooFar');
	assert.equal(officialDistanceVerdict(42670, 50000), 'tooFar');
});

test('a non-positive or over-1,000 km official distance is out of range', () => {
	assert.equal(officialDistanceVerdict(42670, 0), 'outOfRange');
	assert.equal(officialDistanceVerdict(42670, -1), 'outOfRange');
	assert.equal(officialDistanceVerdict(990000, 1000001), 'outOfRange');
	assert.equal(officialDistanceVerdict(42670, Number.NaN), 'outOfRange');
});
