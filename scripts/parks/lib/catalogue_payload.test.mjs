// Unit tests for the park catalogue load payload (issue #1342, decisions § 2425).
// Run: node --test scripts/parks/lib/catalogue_payload.test.mjs

import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

import { parseArgs, readPayload } from '../load.mjs';
import { MAX_CHECKPOINTS, SHARED_USES, cataloguePayload, courseLine, loadSql } from './catalogue_payload.mjs';
import { THIRD_PARTY_MARK, assertNoThirdPartyMarks, thirdPartyMarks } from './third_party_marks.mjs';

const POCAHONTAS = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', 'catalogue', 'us-va', 'pocahontas');
const CLUB = '11111111-1111-4111-8111-111111111111';
const AUTHOR = '22222222-2222-4222-8222-222222222222';

// A 0.001-degree square near the equator: about 111 m a side, 445 m around.
const SQUARE = [
	[0, 0, 5],
	[0.001, 0, 6],
	[0.001, 0.001, 7],
	[0, 0.001, 6],
	[0, 0, 5],
];
const SQUARE_M = 445;

/** @param {number[][]} coordinates */
const geojson = (coordinates) => ({
	type: 'FeatureCollection',
	features: [
		{ type: 'Feature', properties: { kind: 'course' }, geometry: { type: 'LineString', coordinates } },
		{ type: 'Feature', properties: { kind: 'start_finish' }, geometry: { type: 'Point', coordinates: coordinates[0] } },
	],
});

/** @param {Record<string, any>} [over] */
function manifest(over = {}) {
	return {
		park: {
			slug: 'test-park',
			name: 'Test Park',
			agency: 'state',
			region_code: 'US-VA',
			country_code: 'US',
			timezone: 'America/New_York',
			website_url: 'https://example.org/park',
		},
		attribution: '© OpenStreetMap contributors (ODbL)',
		courses: [
			{
				slug: 'square',
				name: 'Square',
				course_shape: 'loop',
				direction: 'clockwise',
				surface: 'trail',
				difficulty: 'easy',
				geometry_source: 'osm',
				source_ref: 'way/1',
				source_checked_at: '2026-11-09',
				geojson: 'square.geojson',
				distance_m: SQUARE_M,
				elevation_m: 2,
				checkpoints: [{ lat: 0.001, lng: 0.001 }],
				waypoint_count: SQUARE.length,
			},
		],
		...over,
	};
}

/** @param {Record<string, any>} files */
const reader = (files) => (/** @type {string} */ file) => {
	if (!(file in files)) throw new Error(`no ${file}`);
	return files[file];
};

const squareOnly = reader({ 'square.geojson': geojson(SQUARE) });

test('the Pocahontas manifest maps to six loop courses with their distances', () => {
	const payload = readPayload(POCAHONTAS);
	assert.equal(payload.park.slug, 'pocahontas');
	assert.equal(payload.region, 'Pocahontas State Park, Virginia');
	assert.deepEqual(
		payload.courses.map((c) => [c.slug, c.course_shape, c.distance_m, c.official_distance_m, c.checkpoints.length, c.laps]),
		[
			['beaver-lake-trail', 'loop', 3595, null, 3, 1],
			['swift-creek-5k', 'loop', 5000, 5000, 3, 1],
			['swift-creek-10k', 'loop', 10000, 10000, 6, 2],
			['swift-creek-half', 'loop', 21097.5, 21097.5, 6, 1],
			['swift-creek-marathon', 'loop', 42195, 42195, 12, 2],
			['swift-creek-50k', 'loop', 50000, 50000, 12, 2],
		],
	);
	assert.ok(payload.courses.every((c) => c.surface === 'trail' && c.geometry_source === 'osm'));
});

test('Beaver Lake Trail keeps its clockwise line and says so', () => {
	const beaver = readPayload(POCAHONTAS).courses[0];
	const built = JSON.parse(fs.readFileSync(path.join(POCAHONTAS, 'beaver-lake-trail.geojson'), 'utf8'));
	const coords = built.features[0].geometry.coordinates;
	assert.deepEqual(beaver.waypoints[1], { lat: coords[1][1], lng: coords[1][0], ele: coords[1][2] });
	assert.equal(beaver.waypoints.length, coords.length);
	assert.equal(beaver.difficulty, 'moderate');
	assert.equal(beaver.description, 'Run it clockwise.');
});

test('a race course becomes a park course with its race distance as the official distance', () => {
	const half = readPayload(POCAHONTAS).courses.find((c) => c.slug === 'swift-creek-half');
	assert.ok(half);
	assert.equal(half.difficulty, null);
	assert.equal(
		half.description,
		'Measures exactly the half-marathon distance (21.1 km): one lap of the loop, starting and finishing on one line on the lead-in.',
	);
});

test('courseLine reads [lng, lat, ele] and refuses anything but one line in range', () => {
	assert.deepEqual(courseLine(geojson([[1, 2], [3, 4, 5]]), 'x'), [
		{ lat: 2, lng: 1 },
		{ lat: 4, lng: 3, ele: 5 },
	]);
	const two = geojson(SQUARE);
	two.features.push(two.features[0]);
	assert.throws(() => courseLine(two, 'x'), /exactly one LineString, found 2/);
	assert.throws(() => courseLine(geojson([[0, 0], [0, 91]]), 'x'), /point 1 .* not a \[lng, lat\] in range/);
	assert.throws(() => courseLine(geojson([[0, 0]]), 'x'), /at least two points/);
	assert.throws(() => courseLine({ type: 'Feature' }, 'x'), /not a FeatureCollection/);
});

test('a valid manifest maps every field the load writes', () => {
	const payload = cataloguePayload(manifest(), squareOnly);
	assert.deepEqual(payload.courses[0], {
		slug: 'square',
		name: 'Square',
		course_shape: 'loop',
		surface: 'trail',
		difficulty: 'easy',
		geometry_source: 'osm',
		source_ref: 'way/1',
		source_checked_at: '2026-11-09',
		distance_m: SQUARE_M,
		elevation_m: 2,
		official_distance_m: null,
		description: 'Run it clockwise.',
		laps: 1,
		checkpoints: [{ lat: 0.001, lng: 0.001 }],
		waypoints: SQUARE.map(([lng, lat, ele]) => ({ lat, lng, ele })),
		start_gate: null,
		end_gate: null,
		route_guide: null,
		route_guide_checked_at: null,
		shared_use: null,
	});
	assert.equal(payload.attribution, '© OpenStreetMap contributors (ODbL)');
});

const GUIDE = {
	version: 1,
	lang: 'en',
	steps: [
		{ kind: 'start', at_m: 0, name: 'Square Trail' },
		{ kind: 'direction', at_m: 0, rotation: 'clockwise' },
		{ kind: 'finish', at_m: SQUARE_M },
	],
};

test('a route guide and its ground-check date travel to the load as they are', () => {
	const payload = cataloguePayload(
		manifest({ courses: [{ ...manifest().courses[0], route_guide: GUIDE, route_guide_checked_at: '2026-12-01' }] }),
		squareOnly,
	);
	assert.deepEqual(payload.courses[0].route_guide, GUIDE);
	assert.equal(payload.courses[0].route_guide_checked_at, '2026-12-01');
});

test('every Pocahontas course carries its guide, none yet checked on the ground', () => {
	for (const c of readPayload(POCAHONTAS).courses) {
		assert.equal(/** @type {any} */ (c.route_guide)?.steps?.[0]?.kind, 'start', c.slug);
		assert.equal(c.route_guide_checked_at, null, c.slug);
	}
});

test('a route guide the database would refuse is refused first', () => {
	const withGuide = (/** @type {any} */ guide, /** @type {string | null} */ checked = null) =>
		() => cataloguePayload(manifest({ courses: [{ ...manifest().courses[0], route_guide: guide, route_guide_checked_at: checked }] }), squareOnly);
	assert.throws(withGuide({ ...GUIDE, version: 2 }), /square: route_guide is not valid: version must be 1/);
	assert.throws(withGuide({ ...GUIDE, steps: GUIDE.steps.slice(0, 2) }), /close with its one finish step/);
	assert.throws(withGuide(null, '2026-12-01'), /route_guide_checked_at must be YYYY-MM-DD, and only beside a route_guide/);
	assert.throws(withGuide(GUIDE, '1 Dec'), /route_guide_checked_at/);
});

test('the description is the course\'s own text: the credit travels only as the payload attribution', () => {
	const payload = readPayload(POCAHONTAS);
	assert.equal(payload.attribution, '© OpenStreetMap contributors (ODbL); elevation: USGS 3DEP');
	for (const c of payload.courses) {
		assert.ok(c.description === null || !/OpenStreetMap|ODbL|3DEP/.test(c.description), c.slug);
	}
});

test('a trail course is one lap of a loop, and has no lap count when it is not a loop', () => {
	const line = [
		[0, 0],
		[0.004, 0],
	];
	const lineM = 445;
	const lineCourse = {
		...manifest().courses[0],
		slug: 'line',
		course_shape: 'point_to_point',
		geojson: 'line.geojson',
		distance_m: lineM,
		waypoint_count: 2,
		checkpoints: [],
	};
	const files = reader({ 'square.geojson': geojson(SQUARE), 'line.geojson': geojson(line) });
	const payload = cataloguePayload(manifest({ courses: [manifest().courses[0], lineCourse] }), files);
	assert.deepEqual(
		payload.courses.map((c) => [c.slug, c.laps]),
		[
			['square', 1],
			['line', null],
		],
	);
	const twice = cataloguePayload(manifest({ courses: [{ ...manifest().courses[0], laps: 2 }] }), squareOnly);
	assert.equal(twice.courses[0].laps, 2);
});

test('a curated start or end line passes through as the gate the load writes', () => {
	const gate = { lat: 0, lng: 0, bearing_deg: 90, half_width_m: 15 };
	const payload = cataloguePayload(manifest({ courses: [{ ...manifest().courses[0], start_gate: gate }] }), squareOnly);
	assert.deepEqual(payload.courses[0].start_gate, gate);
	assert.equal(payload.courses[0].end_gate, null);
	const both = cataloguePayload(
		manifest({ courses: [{ ...manifest().courses[0], start_gate: gate, end_gate: { ...gate, bearing_deg: 180 } }] }),
		squareOnly,
	);
	assert.deepEqual(both.courses[0].end_gate, { ...gate, bearing_deg: 180 });
});

test('a curated line is refused where the gate columns would refuse it, or off its end of the line', () => {
	const gate = { lat: 0, lng: 0, bearing_deg: 90, half_width_m: 15 };
	/** @param {any} g @param {'start_gate' | 'end_gate'} [end] */
	const withGate = (g, end = 'start_gate') => refused((m) => (m.courses[0][end] = g));
	assert.throws(withGate({ ...gate, bearing_deg: 360 }), /square: start_gate bearing_deg must be in \[0, 360\)/);
	assert.throws(withGate({ ...gate, bearing_deg: -1 }), /bearing_deg must be in/);
	assert.throws(withGate({ ...gate, half_width_m: 4 }), /half_width_m must be 5-100/);
	assert.throws(withGate({ ...gate, half_width_m: 101 }), /half_width_m must be 5-100/);
	assert.throws(withGate({ ...gate, lat: 91 }), /not a lat and lng in range/);
	assert.throws(withGate({ ...gate, source: 'curator' }), /exactly lat, lng, bearing_deg and half_width_m/);
	assert.throws(withGate([gate]), /must be an object/);
	assert.throws(withGate({ ...gate, lat: 0.0001 }, 'end_gate'), /square: end_gate sits 11\.1 m from its end of the course line/);
});

test('a region outside the US is labelled by the park alone', () => {
	const m = manifest();
	m.park.region_code = 'GB-ENG';
	m.park.country_code = 'GB';
	assert.equal(cataloguePayload(m, squareOnly).region, 'Test Park');
});

/** @param {(m: any) => void} mutate */
function refused(mutate) {
	const m = manifest();
	mutate(m);
	return () => cataloguePayload(m, squareOnly);
}

test('an nps park carries its NPS park code into the payload, and no other park takes one', () => {
	const m = manifest();
	Object.assign(m.park, { agency: 'nps', nps_park_code: 'shen' });
	assert.equal(cataloguePayload(m, squareOnly).park.nps_park_code, 'shen');
	assert.equal(cataloguePayload(manifest(), squareOnly).park.nps_park_code, null);
	assert.throws(refused((m) => (m.park.agency = 'nps')), /an nps park needs its nps_park_code/);
	assert.throws(refused((m) => Object.assign(m.park, { agency: 'nps', nps_park_code: 'SHEN' })), /nps_park_code/);
	assert.throws(refused((m) => Object.assign(m.park, { agency: 'nps', nps_park_code: 'sh' })), /nps_park_code/);
	assert.throws(refused((m) => (m.park.nps_park_code = 'shen')), /only an nps park takes an nps_park_code/);
});

test('the manifest is refused where the database would refuse it', () => {
	assert.throws(refused((m) => (m.park.slug = 'Test Park')), /park slug/);
	assert.throws(refused((m) => (m.park.agency = 'federal')), /park agency federal/);
	assert.throws(refused((m) => (m.park.region_code = 'Virginia')), /region_code/);
	assert.throws(refused((m) => (m.park.website_url = 'http://example.org')), /https/);
	assert.throws(refused((m) => (m.attribution = ' ')), /no attribution/);
	assert.throws(refused((m) => (m.attribution = 'x'.repeat(301))), /attribution is longer than 300 characters/);
	assert.throws(refused((m) => (m.courses[0].laps = 0)), /square: laps must be a whole number from 1 to 1000/);
	assert.throws(refused((m) => (m.courses[0].laps = 1.5)), /square: laps must be a whole number/);
	assert.throws(refused((m) => (m.courses[0].laps = '2')), /square: laps must be a whole number/);
	assert.throws(refused((m) => (m.courses[0].slug = 'Square')), /course slug Square/);
	assert.throws(refused((m) => (m.courses[0].course_shape = 'lollipop')), /course_shape lollipop/);
	assert.throws(refused((m) => (m.courses[0].surface = 'gravel')), /surface gravel/);
	assert.throws(refused((m) => (m.courses[0].difficulty = 'brutal')), /difficulty brutal/);
	assert.throws(refused((m) => (m.courses[0].geometry_source = 'strava')), /geometry_source strava/);
	assert.throws(refused((m) => (m.courses[0].source_checked_at = 'November')), /YYYY-MM-DD/);
	assert.throws(refused((m) => (m.courses[0].name = '')), /name must be/);
	assert.throws(
		refused((m) => (m.courses[0].checkpoints = Array.from({ length: MAX_CHECKPOINTS + 1 }, () => ({ lat: 0, lng: 0 })))),
		/at most 50 checkpoints/,
	);
	assert.throws(refused((m) => (m.courses[0].checkpoints = [{ lat: 0, lng: 200 }])), /checkpoint 1/);
	assert.throws(refused((m) => (m.courses = [])), /no courses/);
	assert.throws(refused((m) => m.courses.push({ ...m.courses[0] })), /course slugs repeat/);
});

test('a GeoJSON that no longer matches its manifest entry is refused', () => {
	assert.throws(refused((m) => (m.courses[0].distance_m = 600)), /measures 445 m against the manifest's 600 m; rebuild it/);
	assert.throws(refused((m) => (m.courses[0].waypoint_count = 9)), /has 5 points, the manifest says 9/);
});

test('a loop whose line does not close is refused', () => {
	const open = SQUARE.slice(0, 4);
	const m = manifest();
	m.courses[0].waypoint_count = 4;
	m.courses[0].distance_m = 334;
	assert.throws(() => cataloguePayload(m, reader({ 'square.geojson': geojson(open) })), /ends are 111 m apart/);
});

test('a race course must measure exactly its race distance', () => {
	// Four laps of the square, near enough a 2 km "race" to test the rule.
	const line = [SQUARE[0], ...[1, 2, 3, 4].flatMap(() => SQUARE.slice(1))];
	const race = {
		slug: 'square-race',
		name: 'Square Race',
		race_distance: '5k',
		distance_m: 4999,
		laps: 4,
		surface: 'road',
		geometry_source: 'traced',
		geojson: 'race.geojson',
		checkpoints: [],
	};
	const files = reader({ 'square.geojson': geojson(SQUARE), 'race.geojson': geojson(line) });
	assert.throws(() => cataloguePayload(manifest({ race_courses: [race] }), files), /measures 4999 m, not the 5k distance 5000 m/);
	assert.throws(
		() => cataloguePayload(manifest({ race_courses: [{ ...race, race_distance: '3k' }] }), files),
		/unknown race distance 3k/,
	);
});

test('loadSql prints one dollar-quoted call that round-trips the payload', () => {
	const payload = cataloguePayload(manifest(), squareOnly);
	const sql = loadSql(payload, { clubId: CLUB, authorId: AUTHOR.toUpperCase() });
	assert.match(sql, /^select \* from private\.load_park_catalogue\(\n {2}\$park_catalogue\$/);
	assert.ok(sql.endsWith(`'${CLUB}'::uuid,\n  '${AUTHOR}'::uuid,\n  false\n);\n`));
	assert.equal(sql.split(';').length, 2);
	const json = sql.slice(sql.indexOf('$park_catalogue$') + 16, sql.lastIndexOf('$park_catalogue$'));
	assert.deepEqual(JSON.parse(json), payload);
	assert.match(loadSql(payload, { clubId: CLUB, authorId: AUTHOR, enqueueBackfill: true }), /::uuid,\n {2}true\n\);/);
});

test('loadSql picks a dollar tag the payload does not contain', () => {
	const payload = cataloguePayload(manifest(), squareOnly);
	payload.courses[0].name = 'Square $park_catalogue$';
	const sql = loadSql(payload, { clubId: CLUB, authorId: AUTHOR });
	assert.match(sql, /\(\n {2}\$park_catalogue_1\$\{/);
	assert.ok(sql.includes('$park_catalogue_1$::jsonb'));
});

test('loadSql refuses an id that is not a uuid', () => {
	const payload = cataloguePayload(manifest(), squareOnly);
	assert.throws(() => loadSql(payload, { clubId: "x'; drop table parks; --", authorId: AUTHOR }), /--club-id .* is not a uuid/);
	assert.throws(() => loadSql(payload, { clubId: CLUB, authorId: 'me' }), /--author-id me is not a uuid/);
});

test('parseArgs takes a park dir, both ids and the backfill flag', () => {
	assert.deepEqual(parseArgs(['dir', '--club-id', CLUB, '--author-id', AUTHOR]), {
		dir: 'dir',
		clubId: CLUB,
		authorId: AUTHOR,
		enqueueBackfill: false,
	});
	assert.equal(parseArgs(['--enqueue-backfill', 'dir', '--club-id', CLUB, '--author-id', AUTHOR]).enqueueBackfill, true);
	assert.throws(() => parseArgs(['dir', '--club-id', CLUB]), /usage/);
	assert.throws(() => parseArgs(['dir', '--club-id', '--author-id', AUTHOR]), /--club-id needs a value/);
	assert.throws(() => parseArgs(['dir', '--club', CLUB, '--author-id', AUTHOR]), /unknown option --club/);
});

test('a third-party event mark is found in any spelling, and plain park words are not', () => {
	for (const text of [
		'parkrun',
		'Deep Run parkrun loop',
		'PARKRUN',
		'Park Run 5k',
		'park-run',
		'park_run',
		'(not)parkrun',
		'junior parkrun',
		'parkwalk',
		'Park Walk',
		'https://www.parkrun.us/deeprun/course/',
		'eventsupport@parkrun.com',
	]) {
		assert.ok(THIRD_PARTY_MARK.test(text), text);
	}
	for (const text of ['Deep Run Park, 5 km', 'deep-run-park-5k', 'Run around the park', 'Park at the lot and run to the pond', 'Swift Creek Loop, 5 km']) {
		assert.ok(!THIRD_PARTY_MARK.test(text), text);
	}
});

test('every string in a spec or manifest is checked, keys and nested lists included, with its path', () => {
	assert.deepEqual(
		thirdPartyMarks({ park: { name: 'X' }, courses: [{ name: 'ok', route_guide: { getting_there: 'Meet the parkrun crowd' } }] }),
		[{ path: 'courses[0].route_guide.getting_there', text: 'Meet the parkrun crowd' }],
	);
	assert.deepEqual(thirdPartyMarks({ notes: { parkrun: 1 } }), [{ path: 'notes.parkrun', text: 'parkrun' }]);
	assert.throws(
		() => assertNoThirdPartyMarks({ published: { source: 'https://www.parkrun.us/deeprun/course/' } }, 'park.json'),
		/park\.json names a third-party event .* published\.source = "https:\/\/www\.parkrun\.us/,
	);
	assert.doesNotThrow(() => assertNoThirdPartyMarks({ name: 'Deep Run Park, 5 km', n: 5, ok: true, z: null }, 'x'));
});

test('a manifest naming a third-party event anywhere is refused before it can load', () => {
	assert.throws(() => cataloguePayload(manifest({ courses: [{ ...manifest().courses[0], name: 'Square parkrun' }] }), squareOnly), /courses\[0\]\.name/);
	assert.throws(() => cataloguePayload(manifest({ park: { ...manifest().park, name: 'Test Park Run' } }), squareOnly), /park\.name/);
	assert.throws(
		() => cataloguePayload(manifest({ park: { ...manifest().park, website_url: 'https://www.parkrun.us/test/' } }), squareOnly),
		/park\.website_url/,
	);
	assert.throws(() => cataloguePayload(manifest({ attribution: '© OpenStreetMap contributors; route from parkrun' }), squareOnly), /attribution/);
});

test('every committed manifest and spec is free of third-party event marks', () => {
	const root = path.join(POCAHONTAS, '..', '..');
	for (const region of fs.readdirSync(root)) {
		for (const park of fs.readdirSync(path.join(root, region))) {
			for (const file of ['park.json', 'manifest.json']) {
				assertNoThirdPartyMarks(JSON.parse(fs.readFileSync(path.join(root, region, park, file), 'utf8')), `${region}/${park}/${file}`);
			}
		}
	}
});

test('a course may name when an organised group shares its paths, from the vocabulary only', () => {
	const course = manifest().courses[0];
	assert.equal(cataloguePayload(manifest(), squareOnly).courses[0].shared_use, null);
	assert.deepEqual(SHARED_USES, ['saturday_morning_group']);
	assert.equal(
		cataloguePayload(manifest({ courses: [{ ...course, shared_use: 'saturday_morning_group' }] }), squareOnly).courses[0].shared_use,
		'saturday_morning_group',
	);
	assert.throws(() => cataloguePayload(manifest({ courses: [{ ...course, shared_use: 'Saturday 8am group' }] }), squareOnly), /shared_use Saturday 8am group is not one of/);
});
