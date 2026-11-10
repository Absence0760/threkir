// Unit tests for the route guide generator (issue #1344).
// Run: node --test scripts/parks/lib/route_guide.test.mjs

import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';

import {
	CLIMB_MIN_GAIN_M,
	MAX_GETTING_THERE_LENGTH,
	STEP_KINDS,
	bearingDeg,
	buildRouteGuide,
	climbs,
	loopLandmark,
	pointInRing,
	rotationOf,
	routeGuideRefusal,
	surfaceClass,
	turnAt,
	wayKind,
} from './route_guide.mjs';

// A square of ~111 m sides at the equator: 1 SW, 2 SE, 3 NE, 4 NW. Walked
// 1-2-3-4-1 it runs east, north, west, south: counterclockwise.
const nodes = {
	1: { lat: 0, lon: 0, ele: 10 },
	2: { lat: 0, lon: 0.001, ele: 10 },
	3: { lat: 0.001, lon: 0.001, ele: 30 },
	4: { lat: 0.001, lon: 0, ele: 10 },
	5: { lat: 0.0005, lon: 0.001, ele: 20 },
};
const alpha = { id: 10, nodes: [1, 2, 5, 3], tags: { highway: 'path', name: 'Alpha Trail', surface: 'gravel' } };
const beta = { id: 11, nodes: [3, 4, 1], tags: { highway: 'path', name: 'Beta Trail', surface: 'asphalt' } };
const square = [1, 2, 5, 3, 4, 1];

/** @param {Partial<import('./route_guide.mjs').GuideInput>} over */
function guide(over = {}) {
	return buildRouteGuide({
		sequence: square,
		nodes,
		ways: [alpha, beta],
		allWays: [alpha, beta],
		lengthM: 444.8,
		checkpointCount: 1,
		lang: 'en',
		...over,
	});
}

test('bearingDeg reads clockwise from north', () => {
	assert.equal(Math.round(bearingDeg({ lat: 0, lng: 0 }, { lat: 0.001, lng: 0 })), 0);
	assert.equal(Math.round(bearingDeg({ lat: 0, lng: 0 }, { lat: 0, lng: 0.001 })), 90);
	assert.equal(Math.round(bearingDeg({ lat: 0, lng: 0 }, { lat: -0.001, lng: 0 })), 180);
	assert.equal(Math.round(bearingDeg({ lat: 0, lng: 0 }, { lat: 0, lng: -0.001 })), 270);
});

test('turnAt tells left, right and straight', () => {
	const pts = (/** @type {number[][]} */ xs) => xs.map(([lat, lng]) => ({ lat, lng }));
	const cum = [0, 111, 222];
	// East then north is a left turn; east then south a right; east then east straight.
	assert.equal(turnAt(pts([[0, 0], [0, 0.001], [0.001, 0.001]]), cum, 1), 'left');
	assert.equal(turnAt(pts([[0, 0], [0, 0.001], [-0.001, 0.001]]), cum, 1), 'right');
	assert.equal(turnAt(pts([[0, 0], [0, 0.001], [0.0001, 0.002]]), cum, 1), 'straight');
	assert.equal(turnAt(pts([[0, 0], [0, 0.001], [0.001, 0.001]]), cum, 0), 'straight', 'no line before the first point');
});

test('surfaceClass maps OSM surface tags and says nothing for an untagged way', () => {
	assert.equal(surfaceClass({ surface: 'asphalt' }), 'paved');
	assert.equal(surfaceClass({ surface: 'compacted' }), 'gravel');
	assert.equal(surfaceClass({ surface: 'ground' }), 'dirt');
	assert.equal(surfaceClass({ surface: 'unpaved' }), 'unpaved');
	assert.equal(surfaceClass({ surface: 'wood' }), 'boardwalk');
	assert.equal(surfaceClass({}), null);
	assert.equal(surfaceClass({ surface: 'grass' }), null);
});

test('wayKind reads a track as a fire road and a service way as a road', () => {
	assert.equal(wayKind({ highway: 'track' }), 'fire_road');
	assert.equal(wayKind({ highway: 'service' }), 'road');
	assert.equal(wayKind({ highway: 'footway' }), 'path');
	assert.equal(wayKind({}), 'path');
});

test('rotationOf and pointInRing', () => {
	const ccw = square.map((n) => ({ lat: nodes[/** @type {1} */ (n)].lat, lng: nodes[/** @type {1} */ (n)].lon }));
	assert.equal(rotationOf(ccw), 'counterclockwise');
	assert.equal(rotationOf([...ccw].reverse()), 'clockwise');
	assert.equal(pointInRing({ lat: 0.0005, lng: 0.0005 }, ccw), true);
	assert.equal(pointInRing({ lat: 0.002, lng: 0.0005 }, ccw), false);
});

test('loopLandmark names only a named water feature wholly inside the loop', () => {
	const ring = square.map((n) => ({ lat: nodes[/** @type {1} */ (n)].lat, lng: nodes[/** @type {1} */ (n)].lon }));
	const pond = [
		{ lat: 0.0004, lon: 0.0004 },
		{ lat: 0.0004, lon: 0.0006 },
		{ lat: 0.0006, lon: 0.0005 },
	];
	assert.deepEqual(loopLandmark(ring, 'counterclockwise', [{ name: 'Mill Pond', ring: pond }]), {
		keep_on: 'left',
		landmark: 'Mill Pond',
	});
	assert.deepEqual(loopLandmark(ring, 'clockwise', [{ name: 'Mill Pond', ring: pond }]), {
		keep_on: 'right',
		landmark: 'Mill Pond',
	});
	assert.equal(loopLandmark(ring, 'clockwise', [{ ring: pond }]), null, 'an unnamed pond is no landmark');
	const straddling = [...pond, { lat: 0.002, lon: 0.0005 }];
	assert.equal(loopLandmark(ring, 'clockwise', [{ name: 'Big Lake', ring: straddling }]), null);
	assert.equal(loopLandmark(ring, 'clockwise', []), null);
});

test('climbs keeps a rise over the threshold and drops a small one', () => {
	const pts = [{ ele: 10 }, { ele: 20 }, { ele: 30 }, { ele: 28 }, { ele: 33 }, { ele: 10 }, { ele: 16 }, { ele: 10 }];
	const cum = [0, 100, 200, 250, 300, 500, 600, 700];
	// 10 -> 33 is one climb (the 2 m dip is inside the band); 10 -> 16 is too small.
	assert.deepEqual(climbs(pts, cum), [{ from: 0, to: 4, gainM: 23 }]);
	// The same gain spread too thin is a drag, not a climb.
	assert.deepEqual(climbs([{ ele: 0 }, { ele: CLIMB_MIN_GAIN_M }], [0, 10_000]), []);
	assert.deepEqual(climbs([{ ele: null }, { ele: 5 }], [0, 10]), []);
});

test('a two-trail loop reads start, direction, junction, surface, climb, checkpoint, finish in order', () => {
	const g = guide();
	assert.equal(g.version, 1);
	assert.equal(g.lang, 'en');
	assert.deepEqual(
		g.steps.map((s) => s.kind),
		['start', 'direction', 'climb', 'junction', 'surface', 'checkpoint', 'finish'],
	);
	assert.deepEqual(g.steps[0], { kind: 'start', at_m: 0, name: 'Alpha Trail' });
	assert.deepEqual(g.steps[1], { kind: 'direction', at_m: 0, rotation: 'counterclockwise' });
	const junction = g.steps.find((s) => s.kind === 'junction');
	assert.deepEqual(junction, { kind: 'junction', turn: 'left', name: 'Beta Trail', at_m: 222 });
	assert.deepEqual(g.steps.find((s) => s.kind === 'surface'), { kind: 'surface', surface: 'paved', at_m: 222 });
	assert.deepEqual(g.steps.find((s) => s.kind === 'climb'), { kind: 'climb', gain_m: 20, length_m: 110, at_m: 111 });
	assert.deepEqual(g.steps.find((s) => s.kind === 'checkpoint'), { kind: 'checkpoint', at_m: 222, order: 1, of: 1 });
	assert.deepEqual(g.steps.at(-1), { kind: 'finish', at_m: 445 });
	for (const s of g.steps) assert.ok(STEP_KINDS.includes(s.kind));
});

test('the same inputs give the same guide, byte for byte', () => {
	assert.equal(JSON.stringify(guide()), JSON.stringify(guide()));
});

test('a trail that changes only its letter case is one trail', () => {
	const g = guide({ ways: [alpha, { ...beta, tags: { ...beta.tags, name: 'ALPHA trail' } }] });
	assert.equal(g.steps.filter((s) => s.kind === 'junction').length, 0);
});

test('a short unnamed bridge inside one trail is a crossing, not two junctions', () => {
	const bridge = { id: 12, nodes: [2, 5], tags: { highway: 'footway', bridge: 'yes' } };
	const n2 = { ...nodes, 5: { lat: 0.0002, lon: 0.001, ele: 12 } };
	const alphaSplit = { ...alpha, nodes: [1, 2] };
	const alphaRest = { ...alpha, id: 13, nodes: [5, 3] };
	const g = guide({ nodes: n2, ways: [alphaSplit, bridge, alphaRest, beta], allWays: [alphaSplit, bridge, alphaRest, beta] });
	const junctions = g.steps.filter((s) => s.kind === 'junction');
	assert.deepEqual(junctions.map((s) => s.name), ['Beta Trail']);
	assert.deepEqual(
		g.steps.filter((s) => s.kind === 'crossing'),
		[{ kind: 'crossing', crossing: 'bridge', at_m: 111 }],
	);
});

test('a ford is a ford crossing', () => {
	const ford = { ...beta, tags: { highway: 'track', ford: 'yes' } };
	const g = guide({ ways: [alpha, ford], allWays: [alpha, ford] });
	assert.deepEqual(
		g.steps.filter((s) => s.kind === 'crossing').map((s) => s.crossing),
		['ford'],
	);
	assert.deepEqual(g.steps.find((s) => s.kind === 'junction'), { kind: 'junction', turn: 'left', way: 'fire_road', at_m: 222 });
});

test('a turn between two unnamed ways is a junction only where the trail branches', () => {
	const a = { id: 20, nodes: [1, 2, 5, 3], tags: { highway: 'track' } };
	const b = { id: 21, nodes: [3, 4, 1], tags: { highway: 'track' } };
	assert.equal(
		guide({ ways: [a, b], allWays: [a, b] }).steps.filter((s) => s.kind === 'junction').length,
		0,
		'no branch at node 3: an OSM split, not a junction',
	);
	const spur = { id: 22, nodes: [3, 99], tags: { highway: 'path' } };
	const withSpur = guide({ ways: [a, b], allWays: [a, b, spur] });
	assert.deepEqual(withSpur.steps.find((s) => s.kind === 'junction'), {
		kind: 'junction',
		turn: 'left',
		way: 'fire_road',
		at_m: 222,
	});
	assert.deepEqual(withSpur.steps[0], { kind: 'start', at_m: 0, way: 'fire_road' });
});

test('laps 2..N keep only the lap marker, the checkpoints and what differs from lap 1', () => {
	const twice = [1, 2, 5, 3, 4, 1, 2, 5, 3, 4, 1];
	const g = guide({
		sequence: twice,
		lengthM: 889.6,
		checkpointCount: 2,
		laps: { count: 2, firstStartM: 0, lapM: 444.8 },
	});
	const kinds = g.steps.map((s) => `${s.kind}@${s.at_m}`);
	assert.deepEqual(kinds, [
		'start@0',
		'direction@0',
		'climb@111',
		'junction@222',
		'surface@222',
		'checkpoint@297',
		'lap@445',
		'junction@445',
		'surface@445',
		'checkpoint@593',
		'finish@890',
	]);
	assert.deepEqual(g.steps.find((s) => s.kind === 'lap'), { kind: 'lap', at_m: 445, lap: 2, of: 2 });
});

test('offsetM and lengthM cut the guide to the published course', () => {
	const g = guide({ offsetM: 150, lengthM: 200, checkpointCount: 0 });
	assert.deepEqual(
		g.steps.map((s) => `${s.kind}@${s.at_m}`),
		['start@0', 'direction@0', 'junction@72', 'surface@72', 'finish@200'],
	);
	assert.deepEqual(g.steps[0], { kind: 'start', at_m: 0, name: 'Alpha Trail' });
});

test('getting_there is carried trimmed, and refused when too long', () => {
	assert.equal(guide({ gettingThere: '  Park by the lake.  ' }).getting_there, 'Park by the lake.');
	assert.equal('getting_there' in guide({ gettingThere: '   ' }), false);
	assert.throws(() => guide({ gettingThere: 'x'.repeat(MAX_GETTING_THERE_LENGTH + 1) }), /getting_there/);
});

test('every committed manifest carries a guide that starts, finishes and stays in order', () => {
	const root = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', 'catalogue');
	const manifests = fs
		.readdirSync(root)
		.flatMap((region) => fs.readdirSync(path.join(root, region)).map((park) => path.join(root, region, park, 'manifest.json')))
		.filter((f) => fs.existsSync(f));
	assert.ok(manifests.length > 0);
	for (const file of manifests) {
		const manifest = JSON.parse(fs.readFileSync(file, 'utf8'));
		for (const course of [...manifest.courses, ...(manifest.race_courses ?? [])]) {
			const steps = course.route_guide?.steps;
			assert.ok(Array.isArray(steps), `${course.slug} has no route guide`);
			assert.equal(steps[0].kind, 'start', course.slug);
			assert.equal(steps.at(-1).kind, 'finish', course.slug);
			assert.ok(Math.abs(steps.at(-1).at_m - course.distance_m) <= 1, course.slug);
			for (let i = 1; i < steps.length; i++) assert.ok(steps[i].at_m >= steps[i - 1].at_m, course.slug);
			assert.ok(course.route_guide_checked_at === null || /^\d{4}-\d{2}-\d{2}$/.test(course.route_guide_checked_at));
		}
	}
});

test('routeGuideRefusal accepts what the CHECK accepts and names what it refuses', () => {
	const ok = guide({ gettingThere: 'Park by the lake.' });
	assert.equal(routeGuideRefusal(ok), null);
	const bad = (/** @type {(g: any) => void} */ edit) => {
		const g = structuredClone(ok);
		edit(g);
		return routeGuideRefusal(g);
	};
	assert.match(String(bad((g) => (g.steps[2].kind = 'waypoint'))), /unknown kind waypoint/);
	assert.match(String(bad((g) => (g.steps[3].turn = 'uturn'))), /turn uturn/);
	assert.match(String(bad((g) => (g.steps[3].way = 'path'))), /a name or a way, not both/);
	assert.match(String(bad((g) => (g.steps[3].at_m = 1))), /in order/);
	assert.match(String(bad((g) => (g.steps[0].at_m = 5))), /in order|at 0/);
	assert.match(String(bad((g) => g.steps.pop())), /finish step/);
	assert.match(String(bad((g) => (g.steps[4].surface = 'lava'))), /surface lava/);
	assert.match(String(bad((g) => (g.steps[1].landmark = 'Lake'))), /keep_on and landmark go together/);
	assert.match(String(bad((g) => (g.lang = 'English'))), /lang/);
	assert.match(String(bad((g) => (g.notes = 'x'))), /unknown field notes/);
	assert.match(String(bad((g) => (g.getting_there = ' '))), /getting_there/);
	assert.match(String(bad((g) => (g.steps[5].of = 0))), /checkpoint order/);
	assert.equal(routeGuideRefusal([]), 'it is not an object');
});

test('every committed guide passes routeGuideRefusal', () => {
	const root = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', 'catalogue');
	for (const region of fs.readdirSync(root)) {
		for (const park of fs.readdirSync(path.join(root, region))) {
			const manifest = JSON.parse(fs.readFileSync(path.join(root, region, park, 'manifest.json'), 'utf8'));
			for (const course of [...manifest.courses, ...(manifest.race_courses ?? [])]) {
				assert.equal(routeGuideRefusal(course.route_guide), null, course.slug);
			}
		}
	}
});
