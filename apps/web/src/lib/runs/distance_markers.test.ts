import { describe, it } from 'node:test';
import assert from 'node:assert/strict';

import { computeDistanceMarkers, distanceMarkerRank, METRES_PER_MILE } from './distance_markers.ts';

const METRES_PER_LAT_DEGREE = 111320;

function straight(n: number, stepM: number): [number, number][] {
	return Array.from({ length: n }, (_, i) => [0, (i * stepM) / METRES_PER_LAT_DEGREE]);
}

describe('distanceMarkerRank', () => {
	it('ranks every 10th, then every 5th, then even, then odd', () => {
		assert.deepEqual([10, 20, 40].map(distanceMarkerRank), [0, 0, 0]);
		assert.deepEqual([5, 15, 35].map(distanceMarkerRank), [1, 1, 1]);
		assert.deepEqual([2, 4, 42].map(distanceMarkerRank), [2, 2, 2]);
		assert.deepEqual([1, 3, 41].map(distanceMarkerRank), [3, 3, 3]);
	});
});

describe('computeDistanceMarkers', () => {
	it('emits one ranked marker per km on a 12 km straight track', () => {
		const fc = computeDistanceMarkers(straight(121, 100), 1000);
		const labels = fc.features.map((f) => f.properties.label);
		assert.deepEqual(labels.slice(0, 11), ['1', '2', '3', '4', '5', '6', '7', '8', '9', '10', '11']);
		assert.equal(fc.features[9].properties.rank, 0);
		assert.equal(fc.features[4].properties.rank, 1);
		assert.equal(fc.features[0].properties.rank, 3);
	});

	it('steps in miles when given the mile length', () => {
		const fc = computeDistanceMarkers(straight(51, 100), METRES_PER_MILE);
		assert.deepEqual(fc.features.map((f) => f.properties.label), ['1', '2', '3']);
	});

	it('scales a sparse polyline to the authoritative distance', () => {
		const fc = computeDistanceMarkers(straight(11, 100), 1000, 4000);
		assert.deepEqual(fc.features.map((f) => f.properties.label), ['1', '2', '3', '4']);
	});

	it('places an official distance shorter than the line at its own km', () => {
		// 12 km of line for a 10.5 km course: km k sits k·12/10.5 km along it.
		const fc = computeDistanceMarkers(straight(121, 100), 1000, 12000, 10500);
		assert.deepEqual(
			fc.features.map((f) => f.properties.label),
			['1', '2', '3', '4', '5', '6', '7', '8', '9', '10'],
		);
		const lat = fc.features[4].geometry.coordinates[1];
		assert.ok(Math.abs(lat * METRES_PER_LAT_DEGREE - (5000 * 12000) / 10500) < 1);
	});

	it('lets an official distance win over the sparse-line heuristic', () => {
		const fc = computeDistanceMarkers(straight(11, 100), 1000, 4000, 2500);
		assert.deepEqual(fc.features.map((f) => f.properties.label), ['1', '2']);
	});

	it('returns nothing for fewer than two points', () => {
		assert.deepEqual(computeDistanceMarkers([], 1000).features, []);
		assert.deepEqual(computeDistanceMarkers([[0, 0]], 1000).features, []);
	});
});
