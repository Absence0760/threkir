import { test } from 'node:test';
import assert from 'node:assert/strict';
import { hasSmoothedPosition, lineLat, lineLng, lineLngLat, toLinePoint } from './track_line';

// The line position of a stored fix (docs/features/gps_distance.md § Waypoint
// fields). Mirrors packages/core_models/test/waypoint_smoothed_position_test.dart.

test('the line reads the smoothed pair when both halves are present', () => {
	const p = { lat: 1, lng: 2, smoothedLat: 1.00001, smoothedLng: 2.00002 };
	assert.equal(hasSmoothedPosition(p), true);
	assert.equal(lineLat(p), 1.00001);
	assert.equal(lineLng(p), 2.00002);
	assert.deepEqual(lineLngLat(p), [2.00002, 1.00001]);
	assert.deepEqual(toLinePoint(p), { lat: 1.00001, lng: 2.00002, smoothedLat: 1.00001, smoothedLng: 2.00002 });
	assert.equal(p.lat, 1, 'the raw fix is not altered');
});

test('a missing, half or non-finite pair falls back to the raw fix', () => {
	for (const p of [
		{ lat: 1, lng: 2 },
		{ lat: 1, lng: 2, smoothedLat: 1.00001 },
		{ lat: 1, lng: 2, smoothedLng: 2.00002 },
		{ lat: 1, lng: 2, smoothedLat: Number.NaN, smoothedLng: 2.00002 },
		{ lat: 1, lng: 2, smoothedLat: null, smoothedLng: null },
	]) {
		assert.equal(hasSmoothedPosition(p), false, JSON.stringify(p));
		assert.deepEqual(lineLngLat(p), [2, 1]);
		assert.equal(toLinePoint(p), p);
	}
});
