// Unit tests for the local catalogue load the demo dataset runs (decisions § 2590).
// Run: node --test scripts/parks/lib/catalogue_local.test.mjs

import assert from 'node:assert/strict';
import test from 'node:test';

import { localLoadScript } from '../local_load.mjs';
import { findParkDirs, CATALOGUE_ROOT } from '../sync.mjs';
import { LOCAL_PUBLISHER_OWNER, localCatalogueSql } from './catalogue_local.mjs';
import { catalogueSyncSql } from './catalogue_sync.mjs';

const PUBLISHER = { clubSlug: 'official', clubId: '11111111-1111-4111-8111-111111111111' };
const payload = /** @type {any} */ ({ park: { slug: 'p' }, region: 'R', attribution: 'A', courses: [{ slug: 'c', waypoints: [] }] });

test('runs the release sync unchanged, after the seed guard and the local official club', () => {
	const sql = localCatalogueSql([payload], PUBLISHER);
	const sync = catalogueSyncSql([payload], PUBLISHER);
	assert.ok(sql.endsWith(sync));
	const guard = sql.indexOf("to_regprocedure('tests.confirm_consent()') is null");
	const club = sql.indexOf('insert into clubs');
	assert.ok(guard >= 0 && club > guard && sql.indexOf(sync) > club);
	assert.match(sql, new RegExp(`values \\('${PUBLISHER.clubId}', '${LOCAL_PUBLISHER_OWNER}', 'Threkir', 'official'`));
	assert.match(sql, /'open', true\)\non conflict \(id\) do nothing;/);
});

test('loads every committed park, staged ones included, in one committed transaction', () => {
	const { payloads, script } = localLoadScript();
	assert.equal(payloads.length, findParkDirs(CATALOGUE_ROOT).length);
	for (const p of payloads) assert.ok(script.includes(`'${p.park.slug}', l.course_slug`), String(p.park.slug));
	assert.doesNotMatch(script, /'staged'\)/);
	assert.match(script, /^\\set ON_ERROR_STOP on\nbegin;\n/);
	assert.ok(script.endsWith('commit;\n'));
});
