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
		release: { status: 'staged', reason: 'test' },
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

/**
 * Build `s` in a throwaway park directory and return a reader over the outputs.
 *
 * @param {ReturnType<typeof spec>} s
 */
function build(s) {
	const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'build-park-'));
	try {
		fs.writeFileSync(path.join(dir, 'park.json'), JSON.stringify(s));
		fs.writeFileSync(path.join(dir, 'snapshot.json'), JSON.stringify({ fetched_at: '2026-11-19', ways, nodes }));
		const out = buildPark(dir);
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

test('the build refuses a bare cycleway with no foot confirmation', () => {
	const s = spec();
	delete s.trail_review.foot_confirmed;
	assert.throws(() => build(s), /p2p: the course runs on way\(s\) not open to people on foot: way 31 \(highway=cycleway\)/);
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
		fs.writeFileSync(path.join(dir, 'snapshot.json'), JSON.stringify({ fetched_at: '2026-11-19', ways: gapped, nodes: gappedNodes }));
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

test('the build refuses a join over the cap, naming its gap', () => {
	assert.throws(
		() => gappedBuild(15, [{ nodes: [31, 100], reason: 'near-miss junction in OSM' }]),
		/join 31-100 spans 15\.0 m, over the 10 m a join may close/,
	);
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
