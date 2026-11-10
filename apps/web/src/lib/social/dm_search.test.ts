import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { DM_SEARCH_MAX_CHARS, DM_SEARCH_MIN_CHARS, dmSearchSnippet, normalizeDmSearchQuery } from './dm_search.ts';

test('the query bounds are the ones search_direct_messages enforces', () => {
	const dir = fileURLToPath(new URL('../../../../backend/supabase/migrations/', import.meta.url));
	const file = readdirSync(dir).find((f) => f.endsWith('_dm_search.sql'));
	assert.ok(file, 'the dm_search migration is missing — re-anchor');
	const m = readFileSync(dir + file, 'utf8').match(/char_length\(q\.t\) between (\d+) and (\d+)/);
	assert.ok(m, 'the length bound was not found — re-anchor');
	assert.equal(DM_SEARCH_MIN_CHARS, Number(m[1]));
	assert.equal(DM_SEARCH_MAX_CHARS, Number(m[2]));
});

test('a query is trimmed and bounded by characters, not UTF-16 units', () => {
	assert.equal(normalizeDmSearchQuery('  tempo  '), 'tempo');
	assert.equal(normalizeDmSearchQuery('a'), null);
	assert.equal(normalizeDmSearchQuery('   '), null);
	assert.equal(normalizeDmSearchQuery('x'.repeat(100)), 'x'.repeat(100));
	assert.equal(normalizeDmSearchQuery('x'.repeat(101)), null);
	assert.equal(normalizeDmSearchQuery(String.fromCodePoint(0x1f3c3).repeat(2)), String.fromCodePoint(0x1f3c3).repeat(2));
	assert.equal(normalizeDmSearchQuery(String.fromCodePoint(0x1f3c3)), null);
});

test('the snippet centres the first match, case-insensitively', () => {
	assert.deepEqual(dmSearchSnippet('Meet at the TRACK at six', 'track', 5), {
		before: '… the ',
		match: 'TRACK',
		after: ' at s…',
	});
	assert.deepEqual(dmSearchSnippet('track day', 'track'), { before: '', match: 'track', after: ' day' });
});

test('a body without a match is shown from its start', () => {
	assert.deepEqual(dmSearchSnippet('abcdef', 'zz', 2), { before: '', match: '', after: 'abcd…' });
	assert.deepEqual(dmSearchSnippet('ab', 'zz', 2), { before: '', match: '', after: 'ab' });
});
