// The load-more readers page by keyset, not by offset. Invocation:
//   npx tsx --test src/lib/core/keyset_readers.test.ts
//
// An offset is a position. Delete one row from page 1 between two reads and
// offset 50 starts at what was row 51, so a row is never shown; the list looks
// complete and is not. Each reader below takes the previous page's cursor
// (`after`) and builds its filter with `keysetAfter`, so a page starts strictly
// after the last row shown wherever that row now sits. This pins the shape so
// a later edit cannot quietly put the offset back.

import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

import { stripComments } from './strip_comments.ts';

const source = stripComments(readFileSync(resolve(import.meta.dirname, 'data.ts'), 'utf-8'));

/** The body of `export async function <name>(`, to the next top-level export. */
function body(name: string): string {
	// The LAST declaration: an overloaded reader declares its signatures first.
	const start = source.lastIndexOf(`export async function ${name}(`);
	assert.ok(start >= 0, `Could not locate ${name} — rename?`);
	const next = source.indexOf('\nexport ', start + 1);
	return source.slice(start, next === -1 ? undefined : next);
}

const READERS = [
	'fetchFollowers',
	'fetchFollowing',
	'fetchClubMembers',
	'fetchEventAttendees',
	'searchPublicRoutes',
];

for (const name of READERS) {
	test(`${name} pages by keyset cursor, not by offset`, () => {
		const fn = body(name);
		assert.match(fn, /after\?: KeysetCursor \| null/, `${name} must take the previous page's cursor`);
		assert.doesNotMatch(fn, /p_offset/, `${name} must not page through an offset RPC parameter`);
		assert.match(fn, /keysetAfter\(/, `${name} must filter to the rows after the cursor`);
		assert.match(fn, /nextCursor\(/, `${name} must hand back the cursor of the last row it read`);
		assert.doesNotMatch(fn, /\boffset\b/, `${name} must not page by offset`);
		assert.doesNotMatch(fn, /\.range\(/, `${name} must not page with .range()`);
	});
}

test('searchPublicRoutes matches the query literally, not as a LIKE pattern', () => {
	// PostgREST rewrites every `*` in an ilike value to `%`, and `%` / `_` /
	// `\` are LIKE metacharacters, so `q.ilike('name', `%${q}%`)` turned a
	// search for "5*5" into "5%5". The reader must hand the query to imatch
	// through literalSubstringPattern, which escapes it.
	const fn = body('searchPublicRoutes');
	assert.match(
		fn,
		/\.regexIMatch\('name', literalSubstringPattern\(trimmed\)\)/,
		'searchPublicRoutes must match the name through literalSubstringPattern',
	);
	assert.doesNotMatch(fn, /\.ilike\(/, 'an ilike pattern reads * % _ \\ as wildcards');
});

test('fetchRuns takes a keyset cursor, and its whole-history walk is a keyset walk too', () => {
	// The limited branch is one load-more page starting at the cursor. The
	// unlimited branch reads the whole history for recap, heatmap and the
	// account export, and used to walk it with `.range()`: an OFFSET walk
	// over a history a sync or a delete changes mid-read skips or repeats a
	// run (§ 1927). Both must take a position from a row, never a count.
	const fn = body('fetchRuns');
	assert.match(fn, /keysetAfter\(RUN_ORDER, opts\.after\)/, 'fetchRuns must filter to the runs after the cursor');
	assert.match(fn, /walkKeyset\(RUN_ORDER, page/, 'the whole-history read must walk by cursor');
	assert.match(
		fn,
		/for \(const k of RUN_ORDER\)[\s\S]*?\.order\(k\.column/,
		'the read must sort by the order its cursor is taken in',
	);
	assert.doesNotMatch(fn, /\.range\(/, 'fetchRuns must not page with .range()');
	assert.doesNotMatch(fn, /opts\.offset|opts\?\.offset/, 'fetchRuns must not page by offset');
	assert.match(
		body('fetchRunsWithError'),
		/nextCursor\(RUN_ORDER, runs, opts\.limit\)/,
		'fetchRunsWithError must hand back the cursor of the last run it read',
	);
});
