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

/// A non-exported function's body, up to the next top-level declaration.
function fnBody(name: string): string {
	const start = source.search(new RegExp(`\\n(?:async )?function ${name}\\b`));
	assert.ok(start >= 0, `${name} not found`);
	const next = source.slice(start + 1).search(/\n(?:export |async function |function )/);
	return source.slice(start, next < 0 ? undefined : start + 1 + next);
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
	// (decisions § 1935), so a text search goes through imatch +
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
	// run (§ 1936). Both must take a position from a row, never a count.
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
	// joins or how many requests a club accumulates (§ 1940).
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


test('the follow graph a picker filters is walked to its end in both directions', () => {
	// The message, send-route, group and audience pickers filter the whole
	// follow graph on the client. Reading one FOLLOW_PAGE_SIZE page of each
	// direction hid everyone past the 50th follow from the list and from its
	// search, with nothing on screen to say so (round 3 review, #1374).
	const walker = fnBody('walkFollowEdges');
	assert.match(walker, /return walkKeyset\(order, /, 'the follow-edge walker must walk by cursor');
	assert.match(walker, /if \(after\) q = q\.or\(after\)/, 'each page must start after the last');
	const fn = body('fetchFollowGraph');
	assert.match(fn, /walkFollowEdges\(userId, FOLLOWERS_ORDER, 'followee_id', 'follower_id'\)/);
	assert.match(fn, /walkFollowEdges\(userId, FOLLOWING_ORDER, 'follower_id', 'followee_id'\)/);
	assert.match(fn, /if \(!walk\.complete\) throw dbError\(/, 'a short walk must fail, not read as everyone');
	// The feeds' followee set is the same walk: one read stopped at
	// PostgREST's max-rows without saying so, and an error read as "follows
	// nobody" (round 3.6).
	const feed = fnBody('resolveFollowedAuthorIds');
	assert.match(feed, /walkFollowEdges\(userId, FOLLOWING_ORDER, 'follower_id', 'followee_id'\)/);
	assert.match(feed, /if \(!walk\.complete\) throw dbError\(/);
	assert.doesNotMatch(feed, /\.from\('user_follows'\)/, 'resolveFollowedAuthorIds must not read one page of follows');

	const pickers = webSources().filter(([, src]) =>
		/dmRecipientCandidates\(/.test(src) && !/export function dmRecipientCandidates/.test(src),
	);
	assert.ok(pickers.length >= 4, `expected the four follow pickers, found ${pickers.map(([f]) => f)}`);
	for (const [file, src] of pickers) {
		assert.match(src, /fetchFollowGraph\(/, `${file} must read the whole follow graph`);
		assert.doesNotMatch(src, /fetchFollowers\(|fetchFollowing\(/, `${file} must not read one page of follows`);
	}
});

test('the park catalogue lists are walked whole, and a short walk fails', () => {
	// Races & courses and /parks read every course once and search, order and
	// count it on the client. One unranged select stopped at PostgREST's
	// `db.max-rows` with a 200 and no flag, so past 1000 courses the list, its
	// "See all N courses" count, nearest-first and the search all saw a
	// partial catalogue (issue #1374). The records map, the parks, a park's
	// own courses and its runner counts are lists of the same catalogue.
	const helper = fnBody('walkWholeCatalogue');
	assert.match(helper, /walkKeyset\(keys, fetchPage\)/);
	assert.match(helper, /if \(!walk\.complete\) throw dbError\(/, 'a short walk must fail, not read as the catalogue');
	for (const [name, order, read] of [
		['fetchAllParkCourses', 'PARK_COURSE_ID_ORDER', /\.from\(TABLES\.park_courses\)/],
		['fetchParks', 'PARK_ORDER', /\.from\(TABLES\.parks\)/],
		['fetchParkCourses', 'PARK_COURSE_SLUG_ORDER', /\.from\(TABLES\.park_courses\)/],
		['fetchParkCourseRecords', 'COURSE_ID_ORDER', /\.rpc\('park_course_records'/],
		['fetchParkCourseMonthRunners', 'COURSE_ID_ORDER', /\.rpc\('park_course_month_runners'/],
	] as const) {
		const fn = body(name);
		assert.match(fn, new RegExp(`walkWholeCatalogue\\(${order}, `), `${name} must walk by cursor`);
		assert.match(fn, read, `${name} must read inside the walk`);
		assert.match(fn, /if \(after\) q = q\.or\(after\)/, `${name} must start each page after the last`);
		assert.match(
			fn,
			new RegExp(`for \\(const k of ${order}\\)[\\s\\S]*?\\.order\\(k\\.column`),
			`${name} must sort by the order its cursor is taken in`,
		);
		assert.match(fn, /return q\.limit\(limit\)/, `${name} must ask for one page`);
	}
	assert.match(source, /const PARK_ORDER: readonly KeysetKey\[\] = \[[\s\S]*?'region_code'[\s\S]*?'name'[\s\S]*?'id'/);
});

test('the recap park lines walk the runner\'s efforts whole', () => {
	// A year of catalogue efforts passes `db.max-rows` for a regular, and a
	// cut read undercounts their parks and courses (issue #1374).
	const fn = body('fetchRecapParkCourses');
	assert.match(fn, /walkKeyset\(EFFORT_ID_ORDER, /);
	assert.match(fn, /\.select\('id, global_segment_id'\)/, 'the cursor reads id off each effort');
	assert.match(fn, /if \(!walk\.complete\) throw dbError\(/);
});
