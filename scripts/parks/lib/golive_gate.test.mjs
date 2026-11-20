// The go-live gate (decisions § 2600): each machine check over a small
// synthetic course, the release it derives, and the committed catalogue's
// manifests agreeing with it.
// Run: node --test scripts/parks/lib/golive_gate.test.mjs

import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import {
	BACKTRACK_MAX,
	MAX_LAPS,
	PARKING_MAX_M,
	backtrackShare,
	courseEndPoints,
	gateCourse,
	gateParkJoins,
	releaseFromGate,
} from './golive_gate.mjs';
import { parseRelease } from './catalogue_release.mjs';

// A square loop ~444 m round: nodes 1-2-3-4-1, ~111 m a side, at the equator.
const D = 0.001;
const nodes = {
	1: { lat: 0, lon: 0 },
	2: { lat: 0, lon: D },
	3: { lat: D, lon: D },
	4: { lat: D, lon: 0 },
	5: { lat: -D, lon: 0 },
};
const trail = { highway: 'path', name: 'Loop Trail' };
const ways = [{ id: 10, nodes: [1, 2, 3, 4, 1], tags: trail }];
const loopSeq = [1, 2, 3, 4, 1];
const line = loopSeq.map((id) => ({ lat: nodes[/** @type {1} */ (id)].lat, lng: nodes[/** @type {1} */ (id)].lon }));
const parking = { id: 'way/1', lat: 0, lng: 0.002, m: 222, tags: { amenity: 'parking' } };
const cleanSnapshot = {
	road_crossings: { nodes: {} },
	course_ends: { ends: [{ lat: 0, lng: 0, parking: [parking], roads: [] }] },
};

/** @param {Partial<import('./golive_gate.mjs').GateInput>} over */
function input(over = {}) {
	return /** @type {import('./golive_gate.mjs').GateInput} */ ({
		shape: 'loop',
		raceDistance: null,
		laps: null,
		lapM: null,
		sequence: loopSeq,
		lapSequence: null,
		nodes,
		ways,
		line,
		review: { checked_at: '2026-11-20', source_urls: [], designated: [10], refused: {} },
		snapshot: cleanSnapshot,
		...over,
	});
}

const checks = (/** @type {import('./golive_gate.mjs').GateFailure[]} */ f) => f.map((x) => x.check);

test('a clean loop passes every check', () => {
	assert.deepEqual(gateCourse(input()), []);
});

test('missing snapshot data stages, never passes', () => {
	assert.deepEqual(checks(gateCourse(input({ snapshot: { course_ends: cleanSnapshot.course_ends } }))), ['source_data']);
	assert.deepEqual(checks(gateCourse(input({ snapshot: { road_crossings: { nodes: {} } } }))), ['source_data']);
	const moved = { ...cleanSnapshot, course_ends: { ends: [{ lat: 0.001, lng: 0.001, parking: [parking], roads: [] }] } };
	const f = gateCourse(input({ snapshot: moved }));
	assert.deepEqual(checks(f), ['source_data', 'source_data'], 'start and finish both unmatched');
	assert.match(f[0].detail, /no course_ends entry within 10 m of the start/);
});

test('a way closed on foot fails foot_access; a confirmed cycleway does not', () => {
	const closed = [{ id: 10, nodes: [1, 2, 3, 4, 1], tags: { ...trail, foot: 'no' } }];
	const f = gateCourse(input({ ways: closed }));
	assert.deepEqual(checks(f), ['foot_access']);
	assert.match(f[0].detail, /way 10 is closed to people on foot \(foot=no\)/);
	const cycleway = [{ id: 10, nodes: [1, 2, 3, 4, 1], tags: { highway: 'cycleway' } }];
	assert.deepEqual(checks(gateCourse(input({ ways: cycleway }))), ['foot_access']);
	const review = { checked_at: '2026-11-20', source_urls: [], designated: [10], refused: {}, foot_confirmed: { 10: 'shared use' } };
	assert.deepEqual(gateCourse(input({ ways: cycleway, review })), []);
});

/**
 * A road through node 2 running north-south, so the loop (1 -> 2 -> 3)
 * crosses it at grade.
 *
 * @param {Record<string, string>} tags
 * @param {Record<string, string>} [nodeTags]
 */
function crossingAt2(tags, nodeTags = {}) {
	return {
		...cleanSnapshot,
		road_crossings: {
			nodes: {
				2: {
					tags: nodeTags,
					roads: [{ id: 99, tags, arms: [{ node: 50, lat: -D, lon: D * 1.5 }, { node: 51, lat: D, lon: D * 0.5 }] }],
				},
			},
		},
	};
}

test('a motorway or trunk crossing fails; a primary fails only without a signal; a minor road passes', () => {
	const run = (/** @type {Record<string, string>} */ tags, /** @type {Record<string, string>} */ nodeTags = {}) =>
		gateCourse(input({ snapshot: crossingAt2(tags, nodeTags) }));
	assert.deepEqual(checks(run({ highway: 'trunk', name: 'Route 5' })), ['major_road_crossing']);
	assert.deepEqual(checks(run({ highway: 'motorway_link' })), ['major_road_crossing']);
	assert.deepEqual(checks(run({ highway: 'trunk', name: 'Route 5' }, { highway: 'traffic_signals' })), ['major_road_crossing']);
	const primary = run({ highway: 'primary', name: 'Main Street' });
	assert.deepEqual(checks(primary), ['major_road_crossing']);
	assert.match(primary[0].detail, /crosses Main Street \(primary\) at grade with no traffic signal/);
	assert.deepEqual(run({ highway: 'primary', name: 'Main Street' }, { highway: 'traffic_signals' }), []);
	assert.deepEqual(run({ highway: 'secondary', name: 'Side Road' }), []);
	assert.deepEqual(run({ highway: 'trunk', name: 'Route 5', bridge: 'yes' }), [], 'a road on a bridge is not at grade');
});

test('road connectors: one stretch over 250 m, or over 15 % of the course, fails', () => {
	// The whole loop is a road connector: 444 m of road in one go, 100 % of the course.
	const review = { checked_at: '2026-11-20', source_urls: [], designated: [], refused: {}, road_connectors: { 10: 'tour road' } };
	assert.deepEqual(checks(gateCourse(input({ review }))), ['road_connector', 'road_share']);
	// One 111 m side of road is 25 % of the loop: under the stretch cap, over the share.
	const split = [
		{ id: 10, nodes: [1, 2], tags: { highway: 'service', name: 'Tour Road' } },
		{ id: 11, nodes: [2, 3, 4, 1], tags: trail },
	];
	const one = { checked_at: '2026-11-20', source_urls: [], designated: [11], refused: {}, road_connectors: { 10: 'tour road' } };
	const f = gateCourse(input({ ways: split, review: one }));
	assert.deepEqual(checks(f), ['road_share']);
	assert.match(f[0].detail, /25 % of the course is road, over 15 %/);
});

test('backtrack: the share a lap re-runs, capped at 15 %; an out-and-back is exempt', () => {
	assert.equal(backtrackShare(loopSeq, nodes), 0);
	assert.equal(backtrackShare([1, 2, 1], nodes), 0.5);
	const spur = [1, 5, 1, 2, 3, 4, 1];
	assert.ok(Math.abs(backtrackShare(spur, nodes) - 1 / 6) < 0.01);
	assert.ok(backtrackShare(spur, nodes) > BACKTRACK_MAX);
	const spurWays = [...ways, { id: 11, nodes: [1, 5], tags: trail }];
	const spurLine = spur.map((id) => ({ lat: nodes[/** @type {1} */ (id)].lat, lng: nodes[/** @type {1} */ (id)].lon }));
	assert.deepEqual(checks(gateCourse(input({ ways: spurWays, sequence: spur, line: spurLine }))), ['backtrack']);
	const oab = [1, 2, 1];
	const oabLine = oab.map((id) => ({ lat: nodes[/** @type {1} */ (id)].lat, lng: nodes[/** @type {1} */ (id)].lon }));
	assert.deepEqual(gateCourse(input({ shape: 'out_and_back', sequence: oab, line: oabLine })), []);
});

test('laps: the owner\'s caps per distance, and a 14 km floor from the marathon up', () => {
	const race = (/** @type {string} */ d, /** @type {number} */ laps, /** @type {number} */ lapM) =>
		checks(gateCourse(input({ raceDistance: d, laps, lapM, lapSequence: loopSeq })));
	assert.deepEqual(MAX_LAPS, { '5k': 1, '10k': 2, half: 3, marathon: 3, '50k': 3, '50mi': 3, '100k': 3 });
	assert.deepEqual(race('10k', 2, 4900), []);
	assert.deepEqual(race('10k', 3, 3300), ['laps']);
	assert.deepEqual(race('half', 3, 6900), []);
	assert.deepEqual(race('half', 4, 5200), ['laps']);
	assert.deepEqual(race('marathon', 2, 20900), []);
	assert.deepEqual(race('marathon', 3, 13000), ['laps'], 'a short marathon lap');
	assert.deepEqual(race('marathon', 4, 10500), ['laps', 'laps']);
	assert.deepEqual(race('50k', 2, 24900), []);
	assert.deepEqual(race('5k', 2, 2400), ['laps']);
});

test('parking: a start needs a public car park within 800 m; a point-to-point finish too', () => {
	const far = { ...parking, m: PARKING_MAX_M + 1 };
	const snap = (/** @type {any[]} */ p) => ({ ...cleanSnapshot, course_ends: { ends: [{ lat: 0, lng: 0, parking: p, roads: [] }] } });
	assert.deepEqual(checks(gateCourse(input({ snapshot: snap([far]) }))), ['parking']);
	assert.deepEqual(checks(gateCourse(input({ snapshot: snap([]) }))), ['parking']);
	const priv = { ...parking, tags: { amenity: 'parking', access: 'private' } };
	assert.deepEqual(checks(gateCourse(input({ snapshot: snap([priv]) }))), ['parking'], 'a private lot is no lot');
	assert.deepEqual(gateCourse(input({ snapshot: snap([priv, parking]) })), []);

	const p2p = [1, 2, 3];
	const p2pLine = p2p.map((id) => ({ lat: nodes[/** @type {1} */ (id)].lat, lng: nodes[/** @type {1} */ (id)].lon }));
	const ends = [
		{ lat: 0, lng: 0, parking: [parking], roads: [] },
		{ lat: D, lng: D, parking: [], roads: [] },
	];
	const f = gateCourse(input({ shape: 'point_to_point', sequence: p2p, line: p2pLine, snapshot: { ...cleanSnapshot, course_ends: { ends } } }));
	assert.deepEqual(checks(f), ['parking']);
	assert.match(f[0].detail, /of the finish/);
});

test('end runout: a start whose waiting area reaches a roadway fails', () => {
	// A road running east-west 10 m south of the start, behind it as the loop sets off east.
	const behind = { id: 7, name: 'Park Road', highway: 'residential', line: [{ lat: 0, lng: -0.001 }, { lat: 0, lng: -0.0001 }] };
	const snap = { ...cleanSnapshot, course_ends: { ends: [{ lat: 0, lng: 0, parking: [parking], roads: [behind] }] } };
	const f = gateCourse(input({ snapshot: snap }));
	assert.ok(checks(f).includes('end_runout'));
	assert.match(f.find((x) => x.check === 'end_runout')?.detail ?? '', /runs out onto Park Road/);
});

test('a join wider than 10 m fails the park', () => {
	assert.deepEqual(gateParkJoins([{ nodes: [1, 2], gapM: 2.9 }]), []);
	assert.deepEqual(gateParkJoins([{ nodes: [1, 2], gapM: 15 }]).map((f) => f.detail), ['join 1-2 spans 15.0 m, over 10 m']);
});

test('the release: live when all pass, live with held courses when some fail, staged when none pass or the park fails', () => {
	assert.deepEqual(releaseFromGate([], [{ slug: 'a', failures: [] }]), { status: 'live' });
	const partial = releaseFromGate([], [
		{ slug: 'a', failures: [] },
		{ slug: 'b', failures: [{ check: 'parking', detail: 'x' }, { check: 'parking', detail: 'y' }, { check: 'laps', detail: 'z' }] },
	]);
	assert.deepEqual(partial, {
		status: 'live',
		held: [{ course: 'b', reason: 'Go-live gate failed: parking, laps. Details in the manifest gate_failures.' }],
	});
	assert.deepEqual(parseRelease(partial, 'p'), partial);
	const none = releaseFromGate([], [
		{ slug: 'a', failures: [{ check: 'source_data', detail: 'x' }] },
		{ slug: 'b', failures: [{ check: 'parking', detail: 'y' }] },
	]);
	assert.deepEqual(none, { status: 'staged', reason: 'Go-live gate failed: a: source_data; b: parking. Details in the manifest gate_failures.' });
	const parkWide = releaseFromGate([{ check: 'join_gap', detail: 'j' }], [{ slug: 'a', failures: [] }]);
	assert.equal(parkWide.status, 'staged', 'a park-wide failure holds every course');
	const many = releaseFromGate(
		[{ check: 'join_gap', detail: 'j' }],
		Array.from({ length: 40 }, (_, i) => ({ slug: `a-very-long-course-slug-${i}`, failures: [{ check: 'major_road_crossing', detail: 'x' }] })),
	);
	assert.equal(parseRelease(many, 'p').status, 'staged', 'within the 500 characters a release reason may take');
	assert.match(many.status === 'staged' ? many.reason : '', /^Go-live gate failed: park: join_gap; .*; and \d+ more\. Details/);
});

test('course ends are each distinct start and finish', () => {
	const a = { lat: 0, lng: 0 };
	const b = { lat: 0, lng: 0.01 };
	assert.deepEqual(courseEndPoints([[a, b, a], [a, b], [b, a]]), [a, b]);
});

test('every committed manifest\'s release is what its gate results derive', () => {
	const root = path.join(path.dirname(new URL(import.meta.url).pathname), '..', 'catalogue');
	for (const region of fs.readdirSync(root)) {
		for (const park of fs.readdirSync(path.join(root, region))) {
			const manifest = JSON.parse(fs.readFileSync(path.join(root, region, park, 'manifest.json'), 'utf8'));
			const courses = [...manifest.courses, ...(manifest.race_courses ?? [])].map((c) => ({ slug: c.slug, failures: c.gate_failures }));
			assert.ok(courses.every((c) => Array.isArray(c.failures)), `${park}: every course carries gate_failures`);
			assert.deepEqual(manifest.release, releaseFromGate(manifest.gate.park_failures, courses), park);
		}
	}
});

test('end runout: a road the course itself runs along at its end is not run out onto', () => {
	// The loop's first side (1 -> 2) is a service road the course walks, and its start sits on it.
	const onRoad = [
		{ id: 10, nodes: [1, 2], tags: { highway: 'service' } },
		{ id: 11, nodes: [2, 3, 4, 1], tags: trail },
	];
	const road = { id: 10, name: null, highway: 'service', line: [{ lat: 0, lng: -0.001 }, { lat: 0, lng: 0.001 }] };
	const snap = { ...cleanSnapshot, course_ends: { ends: [{ lat: 0, lng: 0, parking: [parking], roads: [road] }] } };
	const review = { checked_at: '2026-11-20', source_urls: [], designated: [10, 11], refused: {} };
	assert.ok(!checks(gateCourse(input({ ways: onRoad, review, snapshot: snap }))).includes('end_runout'));
	const other = { ...road, id: 77 };
	const snapOther = { ...cleanSnapshot, course_ends: { ends: [{ lat: 0, lng: 0, parking: [parking], roads: [other] }] } };
	assert.ok(checks(gateCourse(input({ ways: onRoad, review, snapshot: snapOther }))).includes('end_runout'));
});
