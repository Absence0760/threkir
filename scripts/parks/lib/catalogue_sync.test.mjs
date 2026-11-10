// Unit tests for the park catalogue sync stage (issue #1349, decisions § 2429).
// Run: node --test scripts/parks/lib/catalogue_sync.test.mjs

import assert from 'node:assert/strict';
import fs from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import test from 'node:test';

import { CATALOGUE_ROOT, PUBLISHER_FILE, findParkDirs, parkCatalogueStage } from '../sync.mjs';
import { SYNC_COLUMNS, catalogueSyncSql, parkDirsFromManifests, parsePublisher } from './catalogue_sync.mjs';

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

test('the committed catalogue is found on disk', () => {
	assert.deepEqual(
		findParkDirs(CATALOGUE_ROOT).map((d) => path.relative(CATALOGUE_ROOT, d)),
		[path.join('us-va', 'pocahontas')],
	);
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

test('the Pocahontas stage carries its six courses and the committed club', () => {
	const stage = parkCatalogueStage();
	assert.equal(stage.id, 'park-catalogue');
	assert.equal(stage.note, '1 park(s): pocahontas (6 courses)');
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
