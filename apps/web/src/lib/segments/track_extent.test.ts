import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { trackExtent } from './track_extent';

test('trackExtent measures line positions, so a smoothed fix widens the box', () => {
	assert.deepEqual(
		trackExtent([
			{ lat: 37.5, lng: -77.5 },
			{ lat: 37.6, lng: -77.4, smoothedLat: 37.61, smoothedLng: -77.39 },
		]),
		{ minLat: 37.5, minLng: -77.5, maxLat: 37.61, maxLng: -77.39 },
	);
});

test('trackExtent widens an antimeridian crossing to every longitude', () => {
	assert.deepEqual(
		trackExtent([
			{ lat: -17, lng: 179.9 },
			{ lat: -17.1, lng: -179.9 },
		]),
		{ minLat: -17.1, minLng: -180, maxLat: -17, maxLng: 180 },
	);
});

test('trackExtent is null for an empty track or a non-finite position', () => {
	assert.equal(trackExtent([]), null);
	assert.equal(trackExtent([{ lat: 1, lng: 2 }, { lat: Number.NaN, lng: 2 }]), null);
});
