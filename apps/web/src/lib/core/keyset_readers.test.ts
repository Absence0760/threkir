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
import { readdirSync, readFileSync } from 'node:fs';
import { join, resolve } from 'node:path';

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

test('browseClubsWithError quotes its search term inside the or= tree', () => {
	// The term went into `or=(name.ilike.%…%,location_label.ilike.%…%)` raw, so
	// a `,` started a new, malformed filter, a `)` closed the tree, and `*` `%`
	// `_` were wildcards. Each filter must come from literalSubstringTerm.
	const fn = body('browseClubsWithError');
	assert.match(fn, /literalSubstringTerm\('name', term\)/);
	assert.match(fn, /literalSubstringTerm\('location_label', term\)/);
	assert.doesNotMatch(fn, /ilike/, 'an ilike pattern reads * % _ \\ as wildcards');
});

/** Every non-test .ts / .svelte file under apps/web/src, comments stripped. */
function webSources(): Array<[string, string]> {
	const root = resolve(import.meta.dirname, '../..');
	return (readdirSync(root, { recursive: true }) as string[])
		.filter((f) => /\.(ts|svelte)$/.test(f) && !/\.(test|spec)\.ts$/.test(f) && !f.endsWith('.d.ts'))
		.map((f) => [f, stripComments(readFileSync(join(root, f), 'utf-8'))]);
}

test('no PostgREST filter tree interpolates text into a pattern operator unquoted', () => {
	// Inside `or=` / `and=` an unquoted value runs to the next `,` or `)`, so
	// `name.ilike.%${q}%` lets the user's text rewrite the tree. Build the term
	// with literalSubstringTerm, which escapes and double-quotes it (the
	// `literal(` it calls is the one quoting site this rule allows).
	const offenders = webSources()
		.filter(([, src]) => /\.(i?like|i?match|fts|plfts|phfts|wfts)\.[%*]?\$\{(?!literal\()/.test(src))
		.map(([f]) => f);
	assert.deepEqual(offenders, []);
});

test('the public plan and gym-routine libraries match their search literally', () => {
	// Both sent `ilike('%q%')`, where PostgREST reads every `*` as `%` and `%`
	// `_` `\` are LIKE wildcards, so "5*5" or "100%" found the wrong plans.
	assert.match(body('fetchPublicPlanLibrary'), /\.regexIMatch\('name', literalSubstringPattern\(trimmed\)\)/);
	assert.match(body('fetchPublicGymRoutineLibrary'), /\.regexIMatch\('title', literalSubstringPattern\(trimmed\)\)/);
});

test('no web read filters with a LIKE pattern', () => {
	// `like` / `ilike` cannot express a literal `*` through PostgREST at all
	// (decisions § 1926), so a text search goes through imatch +
	// literalSubstringPattern, or literalSubstringTerm inside an or= tree.
	const offenders = webSources()
		.filter(([, src]) => /\.i?like(AllOf|AnyOf)?\(/.test(src))
		.map(([f]) => f);
	assert.deepEqual(offenders, []);
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

test('the my-clubs and pending-request reads walk by keyset cursor', () => {
	// Both were one unranged select, which PostgREST caps at `db.max-rows`
	// (1000) with a 200 and no flag, and nothing bounds how many clubs one user
	// joins or how many requests a club accumulates (§ 1931).
	for (const [name, order] of [
		['fetchMyClubsWithError', 'MY_CLUB_MEMBERSHIP_ORDER'],
		['fetchPendingRequests', 'CLUB_MEMBER_ORDER'],
	] as const) {
		const fn = body(name);
		assert.match(fn, new RegExp(`walkKeyset\\(${order}, `), `${name} must walk by cursor`);
		assert.match(fn, /if \(after\) q = q\.or\(after\)/, `${name} must start each page after the last`);
		assert.match(
			fn,
			new RegExp(`for \\(const k of ${order}\\)[\\s\\S]*?\\.order\\(k\\.column`),
			`${name} must sort by the order its cursor is taken in`,
		);
		assert.doesNotMatch(fn, /\.range\(/, `${name} must not page with .range()`);
	}
	assert.match(body('fetchMyClubsWithError'), /joined_at, clubs!inner\(/, 'the cursor reads joined_at off each row');
});

test('enrichClubs chunks its membership in filter', () => {
	// A walked fetchMyClubs can list more clubs than one `in` filter carries
	// before the request line overflows (§ 653).
	const start = source.indexOf('async function enrichClubs(');
	assert.ok(start >= 0, 'Could not locate enrichClubs — rename?');
	const fn = source.slice(start, source.indexOf('\nexport ', start));
	assert.match(fn, /chunk\(ids, FEED_FOLLOWEE_CHUNK\)/);
	assert.doesNotMatch(fn, /\.in\('club_id', ids\)/);
});

test('a whole-list read that ended short fails rather than returning what it reached', () => {
	// An export, a total or an admin queue built from a partial walk presents
	// the rows it never reached as rows that do not exist.
	assert.match(
		body('fetchPendingRequests'),
		/if \(!walk\.complete\) \{\s*throw dbError\(/,
		'fetchPendingRequests must throw on an incomplete walk',
	);
	assert.match(
		body('fetchRuns'),
		/if \(!walk\.complete\) \{\s*if \(opts\?\.throwOnError\) \{\s*throw dbError\(/,
		'fetchRuns must throw on an incomplete walk when its caller asked for errors',
	);
});

