// Unit tests for the park-course geometry (issue #1313, phase 3).
// Run: node --test scripts/parks/lib/course_geometry.test.mjs

import assert from 'node:assert/strict';
import test from 'node:test';

import {
	distanceDeviation,
	elevationGainM,
	haversineM,
	pathLengthM,
	placeCheckpoints,
	simplify,
	toPoints,
	traceLoop,
} from './course_geometry.mjs';

// A square loop 1-2-3-4 (counterclockwise in node order: SW, SE, NE, NW),
// a trailhead spur 5-1, and a dead-end pier 3-6, split across ways the way
// OSM splits a real trail at bridges.
const nodes = {
	1: { lat: 0, lon: 0, ele: 10 },
	2: { lat: 0, lon: 0.001, ele: 12 },
	3: { lat: 0.001, lon: 0.001, ele: 20 },
	4: { lat: 0.001, lon: 0, ele: 15 },
	5: { lat: -0.0005, lon: 0, ele: 9 },
	6: { lat: 0.0012, lon: 0.0012, ele: 20 },
};
const loopWays = [
	{ id: 10, nodes: [1, 2, 3] },
	{ id: 11, nodes: [3, 4] },
	{ id: 12, nodes: [1, 4] },
];
const spur = { id: 13, nodes: [5, 1] };
const pier = { id: 14, nodes: [3, 6] };

test('traceLoop starting on the loop goes once around and closes', () => {
	const seq = traceLoop({ ways: loopWays, nodes, start: 1, direction: 'counterclockwise' });
	assert.deepEqual(seq, [1, 2, 3, 4, 1]);
});

test('traceLoop honours the requested direction', () => {
	const seq = traceLoop({ ways: loopWays, nodes, start: 1, direction: 'clockwise' });
	assert.deepEqual(seq, [1, 4, 3, 2, 1]);
});

test('traceLoop runs out and back along a trailhead spur and ignores dead ends', () => {
	const seq = traceLoop({ ways: [...loopWays, spur, pier], nodes, start: 5, direction: 'counterclockwise' });
	assert.deepEqual(seq, [5, 1, 2, 3, 4, 1, 5]);
});

test('traceLoop refuses two loops rather than guessing one', () => {
	const extra = { 7: { lat: 0.0005, lon: 0.002 } };
	const twoLoops = [...loopWays, { id: 15, nodes: [2, 7, 3] }];
	assert.throws(
		() => traceLoop({ ways: twoLoops, nodes: { ...nodes, ...extra }, start: 1, direction: 'clockwise' }),
		/more than one loop/,
	);
});

test('traceLoop refuses ways that form no loop', () => {
	assert.throws(
		() => traceLoop({ ways: [spur, { id: 16, nodes: [1, 2] }], nodes, start: 5, direction: 'clockwise' }),
		/no loop/,
	);
});

test('traceLoop refuses a start that is on none of the ways', () => {
	assert.throws(() => traceLoop({ ways: loopWays, nodes, start: 99, direction: 'clockwise' }), /not on any named way/);
});

test('traceLoop refuses a start that cannot reach the loop', () => {
	const island = { id: 17, nodes: [5, 6] };
	assert.throws(
		() => traceLoop({ ways: [...loopWays, island], nodes, start: 5, direction: 'clockwise' }),
		/does not reach the loop/,
	);
});

test('pathLengthM of the square is four sides of ~111 m', () => {
	const pts = toPoints([1, 2, 3, 4, 1], nodes);
	const side = haversineM({ lat: 0, lng: 0 }, { lat: 0, lng: 0.001 });
	assert.ok(Math.abs(side - 111.2) < 0.1, `side ${side}`);
	assert.ok(Math.abs(pathLengthM(pts) - 4 * side) < 0.5);
});

test('elevationGainM counts real climbs and ignores sub-band noise', () => {
	const pts = [10, 11, 10, 11, 10, 15, 14, 20, 12, 16].map((ele) => ({ lat: 0, lng: 0, ele }));
	// 10 -> 15 (+5), 15 -> 20 (+5), down to 12, 12 -> 16 (+4); the 1 m wiggles count nothing.
	assert.equal(elevationGainM(pts), 14);
});

test('elevationGainM skips points with no elevation', () => {
	const pts = [{ lat: 0, lng: 0, ele: null }, { lat: 0, lng: 0, ele: 0 }, { lat: 0, lng: 0, ele: 5 }];
	assert.equal(elevationGainM(pts), 5);
});

test('simplify drops collinear points and keeps corners', () => {
	const pts = [
		{ lat: 0, lng: 0 },
		{ lat: 0, lng: 0.0005 },
		{ lat: 0, lng: 0.001 },
		{ lat: 0.001, lng: 0.001 },
	];
	assert.deepEqual(simplify(pts, 1), [pts[0], pts[2], pts[3]]);
});

test('placeCheckpoints splits the course into equal distances', () => {
	const pts = toPoints([1, 2, 3, 4, 1], nodes);
	const cps = placeCheckpoints(pts, 3);
	assert.equal(cps.length, 3);
	// Quarter, half and three-quarter marks of a square started at a corner are its other corners.
	assert.deepEqual(cps, [
		{ lat: 0, lng: 0.001 },
		{ lat: 0.001, lng: 0.001 },
		{ lat: 0.001, lng: 0 },
	]);
});

test('distanceDeviation is signed and relative', () => {
	assert.equal(distanceDeviation(95, 100), -0.05);
	assert.equal(distanceDeviation(110, 100), 0.1);
});
