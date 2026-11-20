// The build's linear race course wiring (decisions § 2581): buildPark over a
// small spec and snapshot, end to end through the manifest, the GeoJSON and
// the load payload.
// Run: node --test scripts/parks/lib/build_park.test.mjs

import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';

import { buildPark } from '../build.mjs';
import { cataloguePayload } from './catalogue_payload.mjs';

// A straight trail east along the equator, nodes 1..61 ~111.2 m apart
// (~6.7 km). Way 31 is a bare cycleway, which only foot_confirmed opens.
const nodes = Object.fromEntries(
	Array.from({ length: 61 }, (_, i) => [String(i + 1), { lat: 0, lon: i * 0.001, ele: 10 + (i % 5) }]),
);
const tags = { highway: 'cycleway', name: 'Test Trail', surface: 'asphalt' };
const ways = {
	30: { id: 30, version: 1, tags: { ...tags, foot: 'designated' }, nodes: Array.from({ length: 31 }, (_, i) => i + 1) },
	31: { id: 31, version: 1, tags, nodes: Array.from({ length: 31 }, (_, i) => i + 31) },
};

function spec() {
	/** @returns {Record<string, any>} */
	const race = (/** @type {Record<string, unknown>} */ r) => ({
		race_distance: '5k',
		surface: 'road',
		osm_ways: [30, 31],
		via: [1, 61],
		offset_m: 0,
		route_guide: { getting_there: 'Park at the lot.', ground_checked_at: null },
		...r,
	});
	return {
		park: {
			slug: 'test-trail',
			name: 'Test Trail',
			kind: 'trail',
			agency: 'other',
			region_code: 'US-VA',
			country_code: 'US',
			timezone: 'America/New_York',
			website_url: 'https://example.org/trail',
		},
		trail_review: {
			checked_at: '2026-11-19',
			source_urls: ['https://example.org/map.pdf'],
			designated: [30, 31],
			refused: {},
			/** @type {Record<string, string> | undefined} */
			foot_confirmed: { 31: 'shared-use path per the land manager' },
		},
		courses: [],
		race_courses: [
			race({ slug: 'p2p', name: 'Test Trail, point to point', course_shape: 'point_to_point', anchor: 'via_end', via_ends_at_trail_end: true, checkpoint_count: 2 }),
			race({ slug: 'oab', name: 'Test Trail, out and back', course_shape: 'out_and_back', anchor: 'via_start', checkpoint_count: 3 }),
		],
	};
}

// What the go-live gate reads besides the ways: no road crossings, and a car
// park beside each course end (the trail's two ends and its 1.5 km mark).
const lot = (/** @type {number} */ lng) => ({ lat: 0.0005, lng, parking: [{ id: 'way/9', lat: 0.001, lng, m: 56, tags: { amenity: 'parking' } }], roads: [] });
const surroundings = {
	road_crossings: { nodes: {} },
	course_ends: { ends: [{ ...lot(0), lat: 0 }, { ...lot(0.06), lat: 0 }, { ...lot(0.015034), lat: 0 }] },
};

/**
 * Build `s` in a throwaway park directory and return a reader over the outputs.
 *
 * @param {ReturnType<typeof spec>} s
 * @param {{ snapshotWays?: Record<string, any>, warn?: (message: string) => void, extra?: Record<string, unknown> }} [options]
 */
function build(s, { snapshotWays = ways, warn = (/** @type {string} */ _m) => {}, extra = surroundings } = {}) {
	const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'build-park-'));
	try {
		fs.writeFileSync(path.join(dir, 'park.json'), JSON.stringify(s));
		fs.writeFileSync(path.join(dir, 'snapshot.json'), JSON.stringify({ fetched_at: '2026-11-19', ways: snapshotWays, nodes, ...extra }));
		const out = buildPark(dir, { warn });
		return (/** @type {string} */ file) => JSON.parse(/** @type {string} */ (out.get(path.join(dir, file))));
	} finally {
		fs.rmSync(dir, { recursive: true, force: true });
	}
}

test('a point-to-point course measures the race distance and finishes at the trail end', () => {
	const read = build(spec());
	const manifest = read('manifest.json');
	assert.equal(manifest.park.kind, 'trail');
	const p2p = manifest.race_courses[0];
	assert.deepEqual([p2p.course_shape, p2p.distance_m, p2p.laps], ['point_to_point', 5000, undefined]);
	assert.ok(p2p.start && p2p.finish && !p2p.start_finish);
	assert.equal(p2p.finish.lng, 0.06, 'anchored at the via end, it finishes on the last node');
	assert.ok(!p2p.route_guide.steps.some((/** @type {{ kind: string }} */ st) => st.kind === 'direction'));
	assert.deepEqual(
		read('p2p.geojson').features.map((/** @type {any} */ f) => f.properties.kind),
		['race_course', 'start', 'finish', 'checkpoint', 'checkpoint'],
	);
});

test('an out-and-back course turns at half the distance, on its last checkpoint', () => {
	const oab = build(spec())('manifest.json').race_courses[1];
	assert.deepEqual([oab.course_shape, oab.distance_m, oab.turn_at_m], ['out_and_back', 5000, 2500]);
	assert.deepEqual(oab.start_finish, { lat: 0, lng: 0 });
	assert.equal(oab.checkpoints.length, 3);
	assert.equal(oab.checkpoints[2].lng, 0.022483, 'the last checkpoint sits on the turn, 2500 m out');
	assert.ok(oab.checkpoints.every((/** @type {{ lng: number }} */ c) => c.lng <= 0.022483), 'all on the way out');
});

test('the built manifest loads with each shape and no laps', () => {
	const read = build(spec());
	const payload = cataloguePayload(read('manifest.json'), read);
	assert.deepEqual(
		payload.courses.map((c) => [c.slug, c.course_shape, c.laps, c.official_distance_m]),
		[
			['p2p', 'point_to_point', null, 5000],
			['oab', 'out_and_back', null, 5000],
		],
	);
});

test('the gate puts a park live when every course passes, and the build reads no release from park.json', () => {
	const manifest = build(spec())('manifest.json');
	assert.deepEqual(manifest.release, { status: 'live' });
	assert.deepEqual(manifest.race_courses.map((/** @type {any} */ c) => c.gate_failures), [[], []]);
	assert.throws(() => build(/** @type {any} */ ({ ...spec(), release: { status: 'live' } })), /declares a release, but the go-live gate derives it/);
});

test('missing gate data stages the park, never publishes it', () => {
	const manifest = build(spec(), { extra: {} })('manifest.json');
	assert.equal(manifest.release.status, 'staged');
	assert.match(manifest.release.reason, /^Go-live gate failed: p2p: source_data; oab: source_data\./);
});

test('a bare cycleway with no foot confirmation stages the park on foot_access', () => {
	const s = spec();
	delete s.trail_review.foot_confirmed;
	const manifest = build(s)('manifest.json');
	assert.equal(manifest.release.status, 'staged');
	assert.deepEqual(manifest.race_courses[0].gate_failures, [
		{ check: 'foot_access', detail: 'way 31 is closed to people on foot (highway=cycleway)' },
	]);
});

test('the build warns, and still builds, on a bike-designated path with no foot tag', () => {
	// York River State Park's bike-only trails are tagged exactly this way.
	const bikeWays = { ...ways, 30: { ...ways[30], tags: { highway: 'path', bicycle: 'designated', name: 'Bike Trail' } } };
	/** @type {string[]} */
	const warnings = [];
	const read = build(spec(), { snapshotWays: bikeWays, warn: (m) => warnings.push(m) });
	assert.equal(read('manifest.json').race_courses.length, 2);
	assert.equal(warnings.length, 2, 'once per course that walks it');
	assert.match(warnings[0], /^p2p: way 30 \(bicycle=designated with no foot tag\) may be bike-only; check the land manager's trail map/);
	assert.match(warnings[1], /^oab: way 30 /);

	const confirmed = spec();
	/** @type {Record<string, string>} */ (confirmed.trail_review.foot_confirmed)[30] = 'open to walkers per the park trail map';
	warnings.length = 0;
	build(confirmed, { snapshotWays: bikeWays, warn: (m) => warnings.push(m) });
	assert.deepEqual(warnings, [], 'the land manager\'s word in foot_confirmed settles it');
});

test('a course anchored at the trail end can finish short of it, and the guard still reads the real end', () => {
	const s = spec();
	s.race_courses[0].offset_m = 50;
	const p2p = build(s)('manifest.json').race_courses[0];
	assert.equal(p2p.distance_m, 5000);
	assert.ok(Math.abs(p2p.finish.lng - (0.06 - 50 / 111194.93)) < 1e-6, 'finishes 50 m before the trail end');
});

test('an out-and-back puts its checkpoints on the way out, the last on the turn, so none overlap', () => {
	const s = spec();
	s.race_courses[1].checkpoint_count = 2;
	const oab = build(s)('manifest.json').race_courses[1];
	assert.deepEqual(oab.checkpoints.map((/** @type {{ lng: number }} */ c) => c.lng), [0.011242, 0.022483]);
});
test('the build refuses a via_ends_at_trail_end course whose via stops short of the end', () => {
	const s = spec();
	s.race_courses[0].via = [1, 60];
	assert.throws(() => build(s), /p2p: via_ends_at_trail_end, but the via's last node \(node 60\) joins 2 edges/);
});

/**
 * The test trail with way 31 cut loose from way 30: it starts at node 100,
 * `gapM` east of node 31, as OSM draws a near-miss junction.
 *
 * @param {number} gapM
 */
function gappedBuild(gapM, /** @type {Array<{ nodes: number[], reason: string }> | undefined} */ joins) {
	const s = spec();
	/** @type {any} */ (s.trail_review).joins = joins;
	const gapped = { ...ways, 31: { ...ways[31], nodes: [100, ...ways[31].nodes.slice(1)] } };
	const gappedNodes = { ...nodes, 100: { lat: 0, lon: 0.03 + gapM / 111195, ele: 10 } };
	const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'build-park-'));
	try {
		fs.writeFileSync(path.join(dir, 'park.json'), JSON.stringify(s));
		fs.writeFileSync(path.join(dir, 'snapshot.json'), JSON.stringify({ fetched_at: '2026-11-19', ways: gapped, nodes: gappedNodes, ...surroundings }));
		const out = buildPark(dir);
		return (/** @type {string} */ file) => JSON.parse(/** @type {string} */ (out.get(path.join(dir, file))));
	} finally {
		fs.rmSync(dir, { recursive: true, force: true });
	}
}

test('a trail_review join closes a near-miss junction, is reported with its gap, and adds no guide step', () => {
	assert.throws(() => gappedBuild(2.9, undefined), /not reachable/);
	const read = gappedBuild(2.9, [{ nodes: [31, 100], reason: 'near-miss junction in OSM' }]);
	const p2p = read('manifest.json').race_courses.find((/** @type {any} */ c) => c.slug === 'p2p');
	assert.deepEqual(p2p.joins, [{ nodes: [31, 100], gap_m: 2.9 }]);
	assert.equal(p2p.distance_m, 5000);
	assert.deepEqual(
		p2p.route_guide.steps.map((/** @type {any} */ s) => s.kind),
		['start', 'checkpoint', 'checkpoint', 'finish'],
	);
});

test('a join over the cap stages the park, naming its gap', () => {
	const manifest = gappedBuild(15, [{ nodes: [31, 100], reason: 'near-miss junction in OSM' }])('manifest.json');
	assert.deepEqual(manifest.gate.park_failures, [{ check: 'join_gap', detail: 'join 31-100 spans 15.0 m, over 10 m' }]);
	assert.match(manifest.release.reason, /^Go-live gate failed: park: join_gap/);
});

test('every committed park rebuilds byte for byte from its spec and snapshot', () => {
	const root = path.join(path.dirname(new URL(import.meta.url).pathname), '..', 'catalogue');
	for (const region of fs.readdirSync(root)) {
		for (const park of fs.readdirSync(path.join(root, region))) {
			const dir = path.join(root, region, park);
			for (const [file, contents] of buildPark(dir)) {
				assert.equal(contents, fs.readFileSync(file, 'utf8'), `${file} is stale`);
			}
		}
	}
});
