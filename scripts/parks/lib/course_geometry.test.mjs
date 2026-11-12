// Unit tests for the park-course geometry (issue #1313, phase 3).
// Run: node --test scripts/parks/lib/course_geometry.test.mjs

import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';

import {
	RACE_DISTANCES_M,
	assertFootAccess,
	assertTrailReview,
	distanceDeviation,
	elevationGainM,
	footAccessRefusal,
	haversineM,
	lapCourse,
	pathLengthM,
	checkpointPositionsM,
	placeCheckpoints,
	simplify,
	slice,
	toPoints,
	traceLoop,
	traceVia,
	GATE_BEARING_LOOK_AHEAD_M,
	GATE_BEARING_MIN_LINE_M,
	GATE_HALF_WIDTH_SEGMENT_M,
	curatedGates,
	courseEndDirection,
	derivedGateBearing,
	trimToDistance,
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
	const cps = placeCheckpoints(pts, checkpointPositionsM(pathLengthM(pts), 3));
	assert.equal(cps.length, 3);
	// Quarter, half and three-quarter marks of a square started at a corner are its other corners.
	assert.deepEqual(cps, [
		{ lat: 0, lng: 0.001 },
		{ lat: 0.001, lng: 0.001 },
		{ lat: 0.001, lng: 0 },
	]);
});

test('checkpointPositionsM takes explicit positions, and refuses a list that does not fit the course', () => {
	assert.deepEqual(checkpointPositionsM(400, 3), [100, 200, 300]);
	assert.deepEqual(checkpointPositionsM(400, 2, [50, 380]), [50, 380]);
	assert.throws(() => checkpointPositionsM(400, 3, [50, 380]), /2 positions for 3/);
	assert.throws(() => checkpointPositionsM(400, 2, [200, 100]), /increase strictly/);
	assert.throws(() => checkpointPositionsM(400, 2, [0, 100]), /increase strictly/);
	assert.throws(() => checkpointPositionsM(400, 1, [400]), /increase strictly/);
	assert.throws(() => checkpointPositionsM(400, 1, [Number.NaN]), /increase strictly/);
});

// A loop 1-2-3-4 that a long OSM way 20 crosses (8-2-3-9), so the named ways
// branch and only the via list says which way round the course goes.
const branching = [
	{ id: 20, nodes: [8, 2, 3, 9] },
	{ id: 21, nodes: [1, 2] },
	{ id: 22, nodes: [3, 4, 1] },
	{ id: 23, nodes: [5, 1] },
];
const branchNodes = {
	...nodes,
	8: { lat: -0.0005, lon: 0.001 },
	9: { lat: 0.0015, lon: 0.001 },
};

test('traceVia follows the via order along the named ways', () => {
	assert.deepEqual(traceVia({ ways: branching, nodes: branchNodes, via: [5, 1, 2, 3, 1] }), [5, 1, 2, 3, 4, 1]);
});

test('traceVia ignores a repeated via node', () => {
	assert.deepEqual(traceVia({ ways: branching, nodes: branchNodes, via: [1, 2, 2, 3] }), [1, 2, 3]);
});

test('traceVia refuses a via node no named way reaches', () => {
	const island = { id: 24, nodes: [6, 7] };
	const withIsland = { ...branchNodes, 7: { lat: 0.002, lon: 0.002 } };
	assert.throws(() => traceVia({ ways: [...branching, island], nodes: withIsland, via: [1, 6] }), /not reachable/);
	assert.throws(() => traceVia({ ways: branching, nodes: branchNodes, via: [1, 99] }), /not on any named way/);
});

test('lapCourse runs the lead-in, every lap, and the lead-in back', () => {
	assert.deepEqual(lapCourse({ leadIn: [5, 1], loop: [1, 2, 3, 4, 1], laps: 2 }), [5, 1, 2, 3, 4, 1, 2, 3, 4, 1, 5]);
});

test('lapCourse refuses a loop that does not start where the lead-in ends', () => {
	assert.throws(() => lapCourse({ leadIn: [5, 1], loop: [2, 3, 4, 1, 2], laps: 1 }), /must start and end/);
	assert.throws(() => lapCourse({ leadIn: [5, 1], loop: [1, 2, 3, 4, 1], laps: 0 }), /positive integer/);
});

test('trimToDistance cuts both ends equally to land on the target', () => {
	const pts = toPoints([5, 1, 2, 3, 4, 1, 5], nodes);
	const leadInM = haversineM({ lat: -0.0005, lng: 0 }, { lat: 0, lng: 0 });
	const target = pathLengthM(pts) - 20;
	const { points, trimEachEndM } = trimToDistance(pts, target, leadInM);
	assert.ok(Math.abs(trimEachEndM - 10) < 1e-9);
	assert.ok(Math.abs(pathLengthM(points) - target) < 0.01, `${pathLengthM(points)} vs ${target}`);
	// The start and finish land on the same spot on the lead-in.
	assert.ok(haversineM(points[0], points[points.length - 1]) < 0.01);
});

test('trimToDistance refuses a short course and a start line off the lead-in', () => {
	const pts = toPoints([5, 1, 2, 3, 4, 1, 5], nodes);
	const total = pathLengthM(pts);
	assert.throws(() => trimToDistance(pts, total + 1, 50), /short of/);
	assert.throws(() => trimToDistance(pts, total - 200, 50), /past the/);
});

const M_PER_DEG = (6371008.8 * Math.PI) / 180;

/** Points from metre offsets [east, north] of 0,0, where a degree is the same length both ways. */
const metres = (/** @type {Array<[number, number]>} */ xy) => xy.map(([x, y]) => ({ lat: y / M_PER_DEG, lng: x / M_PER_DEG }));

/** Out east `bendAtM`, then north, then back the same way, as a lead-in run out and back. */
const bentOutAndBack = (/** @type {number} */ bendAtM) =>
	metres([
		[0, 0],
		[bendAtM, 0],
		[bendAtM, 60],
		[bendAtM + 1, 60],
		[bendAtM, 0],
		[0, 0],
	]);

test('derivedGateBearing aims each end at the point 25 m along, as the trigger does', () => {
	const straight = metres([
		[0, 0],
		[10, 10],
		[100, 100],
	]);
	assert.ok(Math.abs(/** @type {number} */ (derivedGateBearing(straight, false)) - 45) < 1e-6);
	assert.ok(Math.abs(/** @type {number} */ (derivedGateBearing(straight, true)) - 45) < 1e-6);
	const bent = metres([
		[0, 0],
		[15, 0],
		[15, 100],
	]);
	const expected = (Math.atan2(15, 10) * 180) / Math.PI;
	assert.ok(Math.abs(/** @type {number} */ (derivedGateBearing(bent, false)) - expected) < 1e-6);
	assert.ok(Math.abs(/** @type {number} */ (derivedGateBearing(bent, true))) < 1e-6);
});

test('derivedGateBearing gives no line under the trigger minimum, and skips repeated points', () => {
	const short = metres([
		[0, 0],
		[GATE_BEARING_MIN_LINE_M - 0.5, 0],
	]);
	assert.equal(derivedGateBearing(short, false), null);
	assert.equal(derivedGateBearing(short.slice(0, 1), false), null);
	const repeated = metres([
		[0, 0],
		[0, 0],
		[0, 30],
	]);
	assert.ok(Math.abs(/** @type {number} */ (derivedGateBearing(repeated, false))) < 1e-6);
});

test('courseEndDirection reads the first and last 5 m only', () => {
	const pts = bentOutAndBack(15);
	assert.ok(Math.abs(courseEndDirection(pts, false) - 90) < 1e-6);
	assert.ok(Math.abs(courseEndDirection(pts, true) - 270) < 1e-6);
});

test('curatedGates emits no line for an end the trigger derives within tolerance', () => {
	assert.deepEqual(curatedGates(bentOutAndBack(GATE_BEARING_LOOK_AHEAD_M + 1)), {});
});

test('curatedGates places a curator line on each skewed end, facing the course over its first or last 5 m', () => {
	const pts = bentOutAndBack(15);
	const gates = curatedGates(pts);
	assert.deepEqual(gates.start_gate, {
		lat: pts[0].lat,
		lng: pts[0].lng,
		bearing_deg: 90,
		half_width_m: GATE_HALF_WIDTH_SEGMENT_M,
	});
	assert.deepEqual(gates.end_gate, {
		lat: pts[pts.length - 1].lat,
		lng: pts[pts.length - 1].lng,
		bearing_deg: 270,
		half_width_m: 15,
	});
});

test('curatedGates curates only the end that is skewed', () => {
	// East 15 m, north 60 m: the start derives 34 degrees off, the end faces north
	// straight down a 60 m run.
	const pts = metres([
		[0, 0],
		[15, 0],
		[15, 60],
	]);
	const gates = curatedGates(pts);
	assert.equal(gates.start_gate?.bearing_deg, 90);
	assert.equal(gates.end_gate, undefined);
});

test('curatedGates wraps a bearing that rounds to 360 to 0', () => {
	// The first 5 m head a hair west of north (359.98 degrees); the line then
	// bends north-east inside the look-ahead.
	const tilted = metres([
		[0, 0],
		[-0.002, 6],
		[20, 25],
		[20, 60],
	]);
	assert.equal(curatedGates(tilted).start_gate?.bearing_deg, 0);
});

test('curatedGates refuses an end too short for the trigger to place any line', () => {
	assert.throws(
		() =>
			curatedGates(
				metres([
					[0, 0],
					[5, 0],
				]),
			),
		/the start line gets no bearing .* the end line gets no bearing/,
	);
});

test('the curated half-width mirrors the segment gate trigger', () => {
	const sql = fs.readFileSync(
		fileURLToPath(new URL('../../../apps/backend/supabase/migrations/20271122002402_global_segment_gates.sql', import.meta.url)),
		'utf8',
	);
	const body = sql.slice(sql.indexOf('function public.global_segments_set_gates()'));
	const hw = /c_half_width constant double precision := (\d+(?:\.\d+)?);/.exec(body);
	assert.ok(hw, 'c_half_width not found');
	assert.equal(Number(hw[1]), GATE_HALF_WIDTH_SEGMENT_M);
});

const DEFINES_BEARING = /create (?:or replace )?function private\.course_end_bearing\(/;

test('the gate look-ahead mirrors the trigger it is named for', () => {
	const dir = fileURLToPath(new URL('../../../apps/backend/supabase/migrations/', import.meta.url));
	const defining = fs
		.readdirSync(dir)
		.filter((f) => f.endsWith('.sql'))
		.sort()
		.filter((f) => DEFINES_BEARING.test(fs.readFileSync(path.join(dir, f), 'utf8')));
	assert.ok(defining.length > 0, 'a migration defines private.course_end_bearing');
	const sql = fs.readFileSync(path.join(dir, /** @type {string} */ (defining.at(-1))), 'utf8');
	const body = sql.slice(/** @type {number} */ ([...sql.matchAll(new RegExp(DEFINES_BEARING, 'g'))].at(-1)?.index));
	const along = /c_along constant double precision := (\d+(?:\.\d+)?);/.exec(body);
	assert.ok(along, `${defining.at(-1)}: c_along not found`);
	assert.equal(Number(along[1]), GATE_BEARING_LOOK_AHEAD_M);
	const min = /c_min constant double precision := (\d+(?:\.\d+)?);/.exec(body);
	assert.ok(min, `${defining.at(-1)}: c_min not found`);
	assert.equal(Number(min[1]), GATE_BEARING_MIN_LINE_M);
});

test('slice interpolates elevation at the cut', () => {
	const pts = [
		{ lat: 0, lng: 0, ele: 0 },
		{ lat: 0, lng: 0.001, ele: 10 },
	];
	const half = haversineM(pts[0], pts[1]) / 2;
	const out = slice(pts, half, 2 * half);
	assert.equal(out.length, 2);
	assert.ok(Math.abs(/** @type {number} */ (out[0].ele) - 5) < 1e-9);
});

test('race distances are the standard ones', () => {
	assert.deepEqual(RACE_DISTANCES_M, { '5k': 5000, '10k': 10000, half: 21097.5, marathon: 42195, '50k': 50000 });
});

test('distanceDeviation is signed and relative', () => {
	assert.equal(distanceDeviation(95, 100), -0.05);
	assert.equal(distanceDeviation(110, 100), 0.1);
});

test('footAccessRefusal passes ordinary trails and fire roads', () => {
	assert.equal(footAccessRefusal({ highway: 'path' }), null);
	assert.equal(footAccessRefusal({ highway: 'track', foot: 'yes', bicycle: 'yes' }), null);
	assert.equal(footAccessRefusal({ highway: 'cycleway', foot: 'designated' }), null);
	assert.equal(footAccessRefusal({ highway: 'path', mtb: 'designated', foot: 'yes' }), null);
});

test('footAccessRefusal lets foot=yes or foot=designated override access=no', () => {
	// The Co-Op Trail at Pocahontas is tagged exactly this way.
	assert.equal(footAccessRefusal({ highway: 'footway', access: 'no', foot: 'designated' }), null);
	assert.equal(footAccessRefusal({ highway: 'path', access: 'private', foot: 'yes' }), null);
});

test('footAccessRefusal refuses a social trail', () => {
	assert.equal(footAccessRefusal({ highway: 'path', informal: 'yes' }), 'informal=yes');
});

test('footAccessRefusal refuses foot=no and foot=private', () => {
	assert.equal(footAccessRefusal({ highway: 'path', foot: 'no' }), 'foot=no');
	assert.equal(footAccessRefusal({ highway: 'path', foot: 'private' }), 'foot=private');
});

test('footAccessRefusal refuses access=no and access=private with no foot override', () => {
	assert.equal(footAccessRefusal({ highway: 'track', access: 'no' }), 'access=no');
	assert.equal(footAccessRefusal({ highway: 'track', access: 'private', foot: 'permissive' }), 'access=private');
});

test('footAccessRefusal refuses a cycleway without foot access', () => {
	assert.equal(footAccessRefusal({ highway: 'cycleway' }), 'highway=cycleway');
});

test('footAccessRefusal refuses mountain-bike-only trails', () => {
	assert.equal(footAccessRefusal({ highway: 'path', bicycle: 'designated', foot: 'no' }), 'foot=no, bicycle=designated');
	assert.equal(footAccessRefusal({ highway: 'path', mtb: 'designated' }), 'mtb=designated');
});

test('assertFootAccess names the refused way and its tags', () => {
	/** @type {import('./course_geometry.mjs').SnapshotWay[]} */
	const ways = [
		{ id: 10, nodes: [1, 2, 3], tags: { highway: 'path' } },
		{ id: 11, nodes: [3, 4], tags: { highway: 'path', informal: 'yes' } },
		{ id: 12, nodes: [1, 4], tags: { highway: 'footway', access: 'no', foot: 'designated' } },
	];
	assert.throws(() => assertFootAccess([1, 2, 3, 4, 1], ways), /way 11 \(informal=yes\)/);
	assert.doesNotThrow(() => assertFootAccess([1, 4], ways));
});

test('assertFootAccess ignores a listed way the line never walks', () => {
	const ways = [...loopWays.map((w) => ({ ...w, tags: { highway: 'path' } })), { ...pier, tags: { highway: 'path', informal: 'yes' } }];
	assert.doesNotThrow(() => assertFootAccess(traceLoop({ ways, nodes, start: 1, direction: 'clockwise' }), ways));
});

const reviewed = (/** @type {Partial<import('./course_geometry.mjs').TrailReview>} */ over = {}) => ({
	checked_at: '2026-11-09',
	source_urls: ['https://example.org/trail-map.pdf'],
	designated: [10, 11, 12],
	refused: {},
	...over,
});
const square = [1, 2, 3, 4, 1];

test('assertTrailReview passes a course that walks only designated ways', () => {
	assert.deepEqual(assertTrailReview(square, loopWays, reviewed()), []);
});

test('assertTrailReview refuses a way the review refused, naming it and why', () => {
	const review = reviewed({ designated: [10, 12], refused: { 11: 'not on the park map' } });
	assert.throws(
		() => assertTrailReview(square, loopWays, review),
		/way 11 was refused on review \(not on the park map\)/,
	);
});

test('assertTrailReview refuses a way nobody has reviewed yet', () => {
	assert.throws(
		() => assertTrailReview(square, loopWays, reviewed({ designated: [10, 12] })),
		/way 11 has not been checked against the land manager's trail map/,
	);
	assert.throws(() => assertTrailReview(square, loopWays, undefined), /the park has no trail_review/);
});

test('assertTrailReview ignores an unreviewed way the line never walks', () => {
	const ways = [...loopWays, pier];
	const seq = traceLoop({ ways, nodes, start: 1, direction: 'clockwise' });
	assert.doesNotThrow(() => assertTrailReview(seq, ways, reviewed()));
});

test('assertTrailReview refuses a review that both designates and refuses a way', () => {
	assert.throws(
		() => assertTrailReview(square, loopWays, reviewed({ refused: { 12: 'social trail' } })),
		/way\(s\) 12 as both designated and refused/,
	);
});

test('assertTrailReview returns the walked fords and refuses an unrecorded one', () => {
	const ways = loopWays.map((w) => (w.id === 11 ? { ...w, tags: { highway: 'track', ford: 'yes' } } : w));
	assert.throws(() => assertTrailReview(square, ways, reviewed()), /way 11 is tagged ford=yes but trail_review does not list it/);
	assert.deepEqual(assertTrailReview(square, ways, reviewed({ fords: [11] })), [11]);
	assert.throws(() => assertTrailReview(square, ways, reviewed({ fords: [99] })), /ford\(s\) 99 that are not designated/);
});
