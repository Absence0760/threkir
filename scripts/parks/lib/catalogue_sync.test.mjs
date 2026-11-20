// Unit tests for the park catalogue sync stage (issue #1349, decisions § 2429).
// Run: node --test scripts/parks/lib/catalogue_sync.test.mjs

import assert from 'node:assert/strict';
import fs from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import test from 'node:test';

import { parkLoadSql } from '../load.mjs';
import { CATALOGUE_ROOT, PUBLISHER_FILE, findParkDirs, parkCatalogueStage } from '../sync.mjs';
import { parseRelease } from './catalogue_release.mjs';
import { SYNC_COLUMNS, catalogueSyncSql, loadablePayload, parkDirsFromManifests, parsePublisher, splitByRelease } from './catalogue_sync.mjs';

const CLUB = '11111111-1111-4111-8111-111111111111';
const AUTHOR = '22222222-2222-4222-8222-222222222222';
const PUBLISHER = { clubSlug: 'official', clubId: CLUB };

/** @param {string} slug */
const payload = (slug) =>
	/** @type {any} */ ({
		park: { slug },
		region: 'R',
		attribution: 'A',
		courses: [{ slug: 'c', waypoints: [] }],
	});

test('the committed publisher is the official club, with no author committed', () => {
	const publisher = parsePublisher(JSON.parse(fs.readFileSync(PUBLISHER_FILE, 'utf8')));
	assert.deepEqual(publisher, { clubSlug: 'threkir', clubId: '42cb8259-8e1e-475e-8c56-321254794da1' });
});

test('a publisher config with a missing, extra or malformed key is refused', () => {
	assert.throws(() => parsePublisher(null), /must be an object/);
	assert.throws(() => parsePublisher({ club_slug: 'x' }), /exactly club_slug and club_id/);
	assert.throws(
		() => parsePublisher({ club_slug: 'x', club_id: CLUB, author_id: AUTHOR }),
		/exactly club_slug and club_id, got author_id,club_id,club_slug/,
		'an author is resolved at run time, never committed',
	);
	assert.throws(() => parsePublisher({ club_slug: 'x', club_id: 'not-a-uuid' }), /club_id not-a-uuid/);
	assert.throws(() => parsePublisher({ club_slug: 'Bad Slug', club_id: CLUB }), /not a slug/);
	assert.deepEqual(parsePublisher({ club_slug: 'x', club_id: CLUB.toUpperCase() }).clubId, CLUB);
});

test('park dirs are the region/park pairs holding a manifest, sorted', () => {
	assert.deepEqual(
		parkDirsFromManifests([
			'us-va/pocahontas/manifest.json',
			'us-md/patapsco/manifest.json',
			'us-va/pocahontas/park.json',
			'us-va/manifest.json',
			'us-va/a/b/manifest.json',
		]),
		['us-md/patapsco', 'us-va/pocahontas'],
	);
});

// Derived from the tree rather than listed: every lane adding a park used to
// edit the same hand-written line, so parallel park work always conflicted.
// What the test pins is that findParkDirs finds exactly the folders that hold
// a manifest, in path order, and that the catalogue has the one live park.
/** Every committed park, read from disk independently of sync.mjs. */
function committedParks() {
	const parks = [];
	for (const region of fs.readdirSync(CATALOGUE_ROOT).sort()) {
		const regionDir = path.join(CATALOGUE_ROOT, region);
		if (!fs.statSync(regionDir).isDirectory()) continue;
		for (const park of fs.readdirSync(regionDir).sort()) {
			const dir = path.join(regionDir, park);
			if (!fs.existsSync(path.join(dir, 'manifest.json'))) continue;
			const manifest = JSON.parse(fs.readFileSync(path.join(dir, 'manifest.json'), 'utf8'));
			const slugs = [...(manifest.courses ?? []), ...(manifest.race_courses ?? [])].map((/** @type {{ slug: string }} */ c) => c.slug);
			const held = (manifest.release.held ?? []).map((/** @type {{ course: string }} */ h) => h.course);
			parks.push({ rel: path.join(region, park), slug: manifest.park.slug, status: manifest.release.status, slugs, held });
		}
	}
	return parks;
}

test('the committed catalogue is found on disk', () => {
	const parks = committedParks();
	assert.deepEqual(
		findParkDirs(CATALOGUE_ROOT).map((d) => path.relative(CATALOGUE_ROOT, d)),
		parks.map((p) => p.rel),
	);
	assert.ok(parks.some((p) => p.rel === path.join('us-va', 'pocahontas')), 'the one live park is committed');
	assert.ok(parks.length >= 2, 'more than the live park, so staging is exercised');
});

test('the stage resolves the author at run time and loads every park as it, with the backfill flag on', () => {
	const sql = catalogueSyncSql([payload('park-a'), payload('park-b')], PUBLISHER);
	assert.match(sql, /^set local role service_role;\n/);
	assert.ok(
		sql.includes(`select private.resolve_club_publisher('official', '${CLUB}'::uuid) as author_id;`),
		'the club is named by slug, with its id as the cross-check',
	);
	assert.ok(sql.indexOf('resolve_club_publisher') < sql.indexOf('load_park_catalogue'), 'resolved before any load');
	assert.equal(sql.match(/from private\.load_park_catalogue\(/g)?.length, 2);
	assert.equal(
		sql.match(
			new RegExp(`'${CLUB}'::uuid,\\n  \\(select author_id from pg_temp\\.park_catalogue_publisher\\),\\n  true\\n\\) l;`, 'g'),
		)?.length,
		2,
	);
	assert.ok(!sql.includes(AUTHOR));
	assert.ok(sql.includes("select 'park-a', l.course_slug"));
	assert.ok(sql.includes("select 'park-b', l.course_slug"));
	assert.ok(sql.indexOf("'park-a'") < sql.indexOf("'park-b'"), 'parks load in the order given');
	assert.ok(
		sql.endsWith(
			'select s.park, s.course_slug, s.action, s.backfill_job_id, s.park_course_id, p.author_id as published_by\n' +
				'  from pg_temp.park_catalogue_sync s cross join pg_temp.park_catalogue_publisher p order by s.seq;\n',
		),
	);
	assert.deepEqual(SYNC_COLUMNS.at(-1), 'published_by');
	assert.equal(sql.match(/^select /gm)?.length, 3, 'one result set: the two inserts select into the table');
});

test('an empty catalogue, a repeated park or a malformed publisher is refused', () => {
	assert.throws(() => catalogueSyncSql([], PUBLISHER), /no parks/);
	assert.throws(() => catalogueSyncSql([payload('p')], { clubSlug: "x'; drop", clubId: CLUB }), /not a club slug and id/);
	assert.throws(() => catalogueSyncSql([payload('p'), payload('p')], PUBLISHER), /park slugs repeat: p, p/);
});

test('the committed stage loads every park the go-live gate passed as the committed club and holds every other park staged', () => {
	const stage = parkCatalogueStage();
	assert.equal(stage.id, 'park-catalogue');
	const live = committedParks().filter((p) => p.status === 'live');
	assert.ok(live.some((p) => p.slug === 'pocahontas'), 'Pocahontas, already loaded, still passes the gate');
	assert.match(stage.note, new RegExp(`^${live.length} park\\(s\\): `));
	assert.equal(stage.sql.match(/from private\.load_park_catalogue\(/g)?.length, live.length);
	for (const park of live) {
		assert.ok(stage.sql.includes(`"slug":"${park.slug}"`), `${park.slug} is loaded`);
		for (const slug of park.held) {
			assert.ok(stage.sql.includes(`('${park.slug}', '${slug}')`), `${slug} is reported, held`);
			assert.ok(!stage.sql.includes(`"slug":"${slug}","name"`), `${slug} is held out of the load`);
		}
		if (park.held.length > 0) assert.ok(stage.sql.includes(`"held":${JSON.stringify(park.held)}`), `${park.slug} names its held courses`);
	}
	assert.ok(live.some((p) => p.held.length > 0), 'per-course staging is exercised by the committed catalogue');
	const staged = committedParks().filter((p) => p.status === 'staged');
	assert.ok(staged.length > 0);
	for (const park of staged) {
		assert.ok(stage.note.includes(`${park.slug} (${park.slugs.length} courses): `), `${park.slug} is listed as staged with its course count`);
		assert.ok(!stage.sql.includes(`"slug":"${park.slug}"`), `${park.slug} never reaches the load`);
		for (const slug of park.slugs) {
			assert.ok(stage.sql.includes(`('${park.slug}', '${slug}')`), slug);
			assert.ok(!stage.sql.includes(`"slug":"${slug}","name"`), `${slug} is not loaded`);
		}
	}
	assert.ok(stage.sql.includes("private.resolve_club_publisher('threkir', '42cb8259-8e1e-475e-8c56-321254794da1'::uuid)"));
	assert.ok(!stage.sql.includes('442e4798'), 'no owner id is committed or emitted');
	for (const slug of ['beaver-lake-trail', 'swift-creek-5k', 'swift-creek-10k', 'swift-creek-half', 'swift-creek-marathon', 'swift-creek-50k']) {
		assert.ok(stage.sql.includes(`"slug":"${slug}"`), slug);
	}
});

test('a stage built from a catalogue root and publisher file elsewhere reads those', () => {
	const tmp = fs.mkdtempSync(path.join(tmpdir(), 'park-sync-'));
	try {
		const parkDir = path.join(tmp, 'us-va', 'pocahontas');
		fs.mkdirSync(parkDir, { recursive: true });
		for (const f of fs.readdirSync(path.join(CATALOGUE_ROOT, 'us-va', 'pocahontas'))) {
			fs.copyFileSync(path.join(CATALOGUE_ROOT, 'us-va', 'pocahontas', f), path.join(parkDir, f));
		}
		const publisherFile = path.join(tmp, 'publisher.json');
		fs.writeFileSync(publisherFile, JSON.stringify({ club_slug: 'other', club_id: CLUB }));
		const stage = parkCatalogueStage({ root: tmp, publisherFile });
		assert.ok(stage.sql.includes(`resolve_club_publisher('other', '${CLUB}'::uuid)`));
		assert.ok(!stage.sql.includes('42cb8259-8e1e-475e-8c56-321254794da1'));
	} finally {
		fs.rmSync(tmp, { recursive: true, force: true });
	}
});

/**
 * A copy of the committed Pocahontas park under `root`, renamed to `slug`, with its release set.
 *
 * @param {string} root
 * @param {string} slug
 * @param {any} release
 */
function copyPark(root, slug, release) {
	const from = path.join(CATALOGUE_ROOT, 'us-va', 'pocahontas');
	const to = path.join(root, 'us-va', slug);
	fs.mkdirSync(to, { recursive: true });
	for (const f of fs.readdirSync(from)) fs.copyFileSync(path.join(from, f), path.join(to, f));
	const manifest = JSON.parse(fs.readFileSync(path.join(to, 'manifest.json'), 'utf8'));
	manifest.park.slug = slug;
	if (release === undefined) delete manifest.release;
	else manifest.release = release;
	fs.writeFileSync(path.join(to, 'manifest.json'), JSON.stringify(manifest));
	return to;
}

test('a release is live, or staged with a reason, and nothing else', () => {
	assert.deepEqual(parseRelease({ status: 'live' }, 'p'), { status: 'live' });
	assert.deepEqual(parseRelease({ status: 'staged', reason: ' waits on #1097 ' }, 'p'), { status: 'staged', reason: 'waits on #1097' });
	assert.throws(() => parseRelease(undefined, 'p'), /p has no release/, 'there is no default');
	assert.throws(() => parseRelease(null, 'p'), /has no release/);
	assert.throws(() => parseRelease('live', 'p'), /must be an object/);
	assert.throws(() => parseRelease({ status: 'Live' }, 'p'), /"Live" is not one of live, staged/);
	assert.throws(() => parseRelease({ staged: true }, 'p'), /undefined is not one of/, 'a misspelt key never reads as live');
	assert.throws(() => parseRelease({ status: 'live', reason: 'x' }, 'p'), /takes status and an optional held/);
	assert.deepEqual(parseRelease({ status: 'live', held: [{ course: 'a-5k', reason: ' gate ' }] }, 'p'), {
		status: 'live',
		held: [{ course: 'a-5k', reason: 'gate' }],
	});
	assert.throws(() => parseRelease({ status: 'live', held: [] }, 'p'), /non-empty list/);
	assert.throws(() => parseRelease({ status: 'live', held: [{ course: 'A K', reason: 'x' }] }, 'p'), /not a slug/);
	assert.throws(() => parseRelease({ status: 'live', held: [{ course: 'a', reason: 'x', extra: 1 }] }, 'p'), /exactly course and reason/);
	assert.throws(() => parseRelease({ status: 'live', held: [{ course: 'a', reason: 'x' }, { course: 'a', reason: 'y' }] }, 'p'), /twice/);
	assert.throws(() => parseRelease({ status: 'staged' }, 'p'), /exactly status and reason/);
	assert.throws(() => parseRelease({ status: 'staged', reason: '  ' }, 'p'), /reason must be 1-500/);
	assert.throws(() => parseRelease({ status: 'staged', reason: 'x'.repeat(501) }, 'p'), /reason must be 1-500/);
});

test('a staged park is reported per course and never reaches a load call', () => {
	const live = payload('park-a');
	const held = /** @type {any} */ ({ park: { slug: 'park-b' }, courses: [{ slug: 'c1' }, { slug: 'c2' }] });
	const { live: loads, staged } = splitByRelease([
		{ payload: live, release: { status: 'live' } },
		{ payload: held, release: { status: 'staged', reason: 'waits' } },
	]);
	assert.deepEqual(loads, [live]);
	assert.deepEqual(staged, [{ park: 'park-b', courses: ['c1', 'c2'], reason: 'waits' }]);
	const sql = catalogueSyncSql(loads, PUBLISHER, staged);
	assert.equal(sql.match(/from private\.load_park_catalogue\(/g)?.length, 1);
	assert.ok(!sql.includes('"slug":"park-b"'), 'no payload for the staged park');
	assert.ok(sql.includes("  from (values\n  ('park-b', 'c1'),\n  ('park-b', 'c2')\n) v(park, course_slug);\n"));
	assert.match(sql, /case when exists \(select 1 from public\.park_courses pc join public\.parks p on p\.id = pc\.park_id\n\s+where p\.slug = v\.park and pc\.slug = v\.course_slug and pc\.status <> 'closed'\)\n\s+then 'held_live' else 'staged' end/);
	assert.ok(sql.indexOf("'staged'") < sql.lastIndexOf('select s.park'), 'the staged rows are in the one result set');
	assert.throws(() => catalogueSyncSql([live], PUBLISHER, [{ park: 'park-a', courses: ['c'], reason: 'r' }]), /held courses and its staged rows disagree/);
	assert.throws(() => catalogueSyncSql([live, live], PUBLISHER, []), /park slugs repeat/);
	assert.throws(() => catalogueSyncSql([], PUBLISHER, [{ park: "x'", courses: ['c'], reason: 'r' }]), /not a park slug/);
	assert.match(catalogueSyncSql([], PUBLISHER, staged), /'staged'/, 'a catalogue of only staged parks still reports them');
});

test('a held course of a live park is never created: it stays out of the payload, named in held so the load never closes it', () => {
	const park = /** @type {any} */ ({ park: { slug: 'park-c' }, region: 'R', attribution: 'A', courses: [{ slug: 'pass-5k' }, { slug: 'fail-10k' }] });
	/** @type {import('./catalogue_release.mjs').Release} */
	const release = { status: 'live', held: [{ course: 'fail-10k', reason: 'Go-live gate failed: source_data' }] };
	const { live, staged } = splitByRelease([{ payload: park, release }]);
	assert.deepEqual(live.map((p) => [p.courses.map((c) => c.slug), p.held]), [[['pass-5k'], ['fail-10k']]]);
	assert.deepEqual(staged, [{ park: 'park-c', courses: ['fail-10k'], reason: 'Go-live gate failed: source_data' }]);
	const sql = catalogueSyncSql(live, PUBLISHER, staged);
	assert.ok(sql.includes('"held":["fail-10k"]'), 'the load is told which absent course to leave alone');
	assert.ok(!sql.includes('"slug":"fail-10k"'), 'no geometry for the held course reaches the load');
	assert.ok(sql.includes("('park-c', 'fail-10k')"), 'it is reported, held_live or staged by what is loaded');
	assert.deepEqual(loadablePayload(park, { status: 'live' }), park, 'a park with nothing held loads whole');
	assert.throws(() => loadablePayload(park, { status: 'live', held: [{ course: 'nope', reason: 'x' }] }), /does not name: nope/);
	assert.throws(
		() => loadablePayload(park, { status: 'live', held: [{ course: 'pass-5k', reason: 'x' }, { course: 'fail-10k', reason: 'x' }] }),
		/holds every course; its release must be staged/,
	);
	assert.throws(() => loadablePayload(park, { status: 'staged', reason: 'x' }), /is staged/);
});

test('the one-park fallback loads only the passing courses of a park with held ones', () => {
	const tmp = fs.mkdtempSync(path.join(tmpdir(), 'park-held-'));
	try {
		const dir = copyPark(tmp, 'pocahontas', { status: 'live', held: [{ course: 'swift-creek-50k', reason: 'Go-live gate failed: parking' }] });
		const { payload: loaded, sql } = parkLoadSql(dir, { clubId: CLUB, authorId: AUTHOR, enqueueBackfill: false });
		assert.equal(loaded.courses.length, 5);
		assert.deepEqual(loaded.held, ['swift-creek-50k']);
		assert.ok(!sql.includes('"slug":"swift-creek-50k"') && sql.includes('"held":["swift-creek-50k"]'));
	} finally {
		fs.rmSync(tmp, { recursive: true, force: true });
	}
});

test('the stage over a catalogue with a staged park loads only the live one and names the staged one', () => {
	const tmp = fs.mkdtempSync(path.join(tmpdir(), 'park-staged-'));
	try {
		copyPark(tmp, 'pocahontas', { status: 'live' });
		copyPark(tmp, 'held-park', { status: 'staged', reason: 'owner check pending' });
		const stage = parkCatalogueStage({ root: tmp });
		assert.equal(stage.note, '1 park(s): pocahontas (6 courses). Held out of the load: held-park (6 courses): owner check pending');
		assert.equal(stage.sql.match(/from private\.load_park_catalogue\(/g)?.length, 1);
		assert.ok(!stage.sql.includes('"slug":"held-park"'));
		assert.equal(stage.sql.match(/\('held-park', '[a-z0-9-]+'\)/g)?.length, 6);
	} finally {
		fs.rmSync(tmp, { recursive: true, force: true });
	}
});

test('a manifest with no release, or a malformed one, fails the stage rather than loading', () => {
	for (const release of [undefined, { status: 'stagd', reason: 'x' }, { publish: false }]) {
		const tmp = fs.mkdtempSync(path.join(tmpdir(), 'park-release-'));
		try {
			copyPark(tmp, 'pocahontas', release);
			assert.throws(() => parkCatalogueStage({ root: tmp }), /release/);
		} finally {
			fs.rmSync(tmp, { recursive: true, force: true });
		}
	}
});

test('the one-park fallback refuses a staged park', () => {
	const tmp = fs.mkdtempSync(path.join(tmpdir(), 'park-load-'));
	try {
		const opts = { clubId: CLUB, authorId: AUTHOR, enqueueBackfill: false };
		const held = copyPark(tmp, 'held-park', { status: 'staged', reason: 'owner check pending' });
		assert.throws(() => parkLoadSql(held, opts), /held-park is staged and does not load .* Reason: owner check pending$/);
		const live = copyPark(tmp, 'pocahontas', { status: 'live' });
		assert.match(parkLoadSql(live, opts).sql, /^select \* from private\.load_park_catalogue\(/);
	} finally {
		fs.rmSync(tmp, { recursive: true, force: true });
	}
});
