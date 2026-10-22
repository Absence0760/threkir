// Pins the fix for the over-long `in` filter class on web.
//
// PostgREST serialises `.in(col, ids)` into the request URL. A list past the
// gateway's request-line budget does not reliably error — decisions § 653
// recorded a gateway answering 200 with an EMPTY match, so the read looks like
// "this runner follows nobody" or "this race has no names". FEED_FOLLOWEE_CHUNK
// is the project's stated ceiling for one in-filter (mobile: kInFilterChunk,
// guarded by packages/api_client/test/in_filter_bound_test.dart).
//
// The rule: every id list handed to `.in(...)` anywhere in the web app is
// either a chunk — the `queryChunked` / `readChunked` / `chunk(...).map`
// closure parameter is named `part` by convention, which is what makes this
// readable off the source — or a literal array of string constants, or it is
// listed below with the ceiling that holds it under FEED_FOLLOWEE_CHUNK.

import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join, relative, resolve } from 'node:path';

import { stripComments } from './strip_comments';
import { FEED_FOLLOWEE_CHUNK } from '../social/feed_merge';

const ROOTS = ['src', 'lambda'];

function sourceFiles(dir: string): string[] {
	const out: string[] = [];
	for (const name of readdirSync(dir).sort()) {
		if (name === 'node_modules' || name.startsWith('.')) continue;
		const full = join(dir, name);
		if (statSync(full).isDirectory()) out.push(...sourceFiles(full));
		else if (/\.(ts|svelte)$/.test(name) && !/\.test\.ts$/.test(name)) out.push(full);
	}
	return out;
}

/// The argument text of the call whose `(` is at `open`, quote-aware, with
/// whitespace collapsed so a call wrapped over several lines reads as one.
function callArgs(src: string, open: number): string {
	let depth = 0;
	let quote: string | null = null;
	for (let i = open; i < src.length; i++) {
		const c = src[i];
		if (quote) {
			if (c === '\\') i++;
			else if (c === quote) quote = null;
			continue;
		}
		if (c === "'" || c === '"' || c === '`') quote = c;
		else if (c === '(') depth++;
		else if (c === ')' && --depth === 0) {
			return src
				.slice(open + 1, i)
				.replace(/\s+/g, ' ')
				.replace(/^ | $/g, '')
				.replace(/,$/, '');
		}
	}
	throw new Error(`unbalanced call at offset ${open}`);
}

const CHUNKED = /^'[a-z_]+', part$/;
const LITERAL_LIST = /^'[a-z_]+', \[\s*'[^']*'(\s*,\s*'[^']*')*\s*,?\s*\]$/;

/// `file :: .in(args)` -> how many times it may appear. Counting rather than
/// merely listing keeps a second, unbounded read from hiding behind a bounded
/// one that happens to be written identically.
const ALLOWED: Record<string, number> = {
	// fetchNextRsvpedEvent: event ids off its own RSVP read, capped by
	// `.limit(RSVP_CANDIDATE_LIMIT)`, asserted below.
	"src/lib/core/data.ts :: .in('event_id', rows.map((r) => r.event_id as string))": 1,
	// Author ids off one page of rows, each capped by its function's own
	// `limit`, asserted below: fetchPublicPlanLibrary,
	// fetchPublicGymRoutineLibrary, fetchFollowingFeed, fetchFollowingLifts.
	"src/lib/core/data.ts :: .in('id', authorIds)": 4,
	// Uploader ids off one page of event_gallery_photos, capped by
	// fetchEventPhotos' own `limit`, asserted below.
	"src/lib/core/data.ts :: .in('id', ownerIds)": 1,
	// The notification-context joins, each off one page of notifications
	// capped by fetchNotificationsWithError's own `limit`, asserted below.
	// Every id list is a column of that page, so none can exceed it.
	"src/lib/core/data.ts :: .in('id', actorIds)": 1,
	"src/lib/core/data.ts :: .in('id', runIds)": 2,
	"src/lib/core/data.ts :: .in('id', commentIds)": 1,
	"src/lib/core/data.ts :: .in('id', eventIds)": 1,
	"src/lib/core/data.ts :: .in('id', clubIds)": 1,
	// The two participants of one conversation (fetchDmThread): always
	// exactly two ids.
	"src/lib/core/data.ts :: .in('sender_id', pair)": 1,
	"src/lib/core/data.ts :: .in('recipient_id', pair)": 1,
	// The coach's plan weeks — one plan's, or a season's across every block,
	// drawn from one shared COACH_PLAN_WEEKS_CAP budget and each block read
	// with `.limit(COACH_PLAN_WEEKS_CAP)` — and its recent lift sessions,
	// capped by `.limit(COACH_LIFTS_CAP)`; both caps asserted below.
	"src/lib/coach/context.ts :: .in('week_id', weekIds)": 1,
	"src/lib/coach/context.ts :: .in('workout_id', ids)": 1,
};

test('every unchunked .in() in the web app carries a stated bound', () => {
	const found: Record<string, number> = {};
	for (const root of ROOTS) {
		for (const file of sourceFiles(resolve(root))) {
			const src = stripComments(readFileSync(file, 'utf-8'));
			const rel = relative(resolve('.'), file);
			for (let at = src.indexOf('.in('); at !== -1; at = src.indexOf('.in(', at + 1)) {
				const args = callArgs(src, at + 3);
				if (CHUNKED.test(args) || LITERAL_LIST.test(args)) continue;
				const key = `${rel} :: .in(${args})`;
				found[key] = (found[key] ?? 0) + 1;
			}
		}
	}
	assert.deepEqual(
		found,
		ALLOWED,
		'an `in` filter longer than FEED_FOLLOWEE_CHUNK can come back EMPTY instead of failing. ' +
			'Route the id list through queryChunked / readChunked (name the closure parameter `part`), ' +
			'or list the call above with the ceiling that keeps it under the bound.',
	);
});

function read(path: string): string {
	return readFileSync(resolve(path), 'utf-8');
}

/// From `decl` to the first closing brace at column 0 — one top-level function.
function body(src: string, decl: string): string {
	const start = src.indexOf(decl);
	assert.ok(start >= 0, `${decl} moved or was renamed`);
	// `\n}\n`, not `\n}`: a multi-line return type closes at column 0 too.
	const end = src.indexOf('\n}\n', start);
	return src.slice(start, end === -1 ? undefined : end);
}

/// The ceilings the allowlist leans on: `function -> the limit it declares`.
/// A bump past FEED_FOLLOWEE_CHUNK fails here rather than silently emptying
/// the join.
const LIMIT_CEILINGS: Array<[file: string, decl: string, declares: RegExp]> = [
	['src/lib/core/data.ts', 'export async function fetchPublicPlanLibrary(', /\blimit = (\d+)/],
	['src/lib/core/data.ts', 'export async function fetchPublicGymRoutineLibrary(', /\blimit = (\d+)/],
	['src/lib/core/data.ts', 'export async function fetchFollowingFeed(', /const limit = opts\?\.limit \?\? (\d+);/],
	['src/lib/core/data.ts', 'async function fetchFollowingLifts(', /const limit = opts\?\.limit \?\? (\d+);/],
	['src/lib/core/data.ts', 'export async function fetchEventPhotos(', /\blimit = (\d+)/],
	['src/lib/core/data.ts', 'export async function fetchNotificationsWithError(', /\blimit = (\d+)/],
];

test('the declared limits the allowlist leans on stay under the bound', () => {
	for (const [file, decl, declares] of LIMIT_CEILINGS) {
		const m = body(read(file), decl).match(declares);
		assert.ok(m, `${decl} no longer declares ${declares} — its id list is what the allowlist calls bounded`);
		assert.ok(Number(m[1]) <= FEED_FOLLOWEE_CHUNK, `${decl} defaults to ${m[1]}, past the in-filter bound`);
	}

	const data = read('src/lib/core/data.ts');
	const rsvp = data.match(/const RSVP_CANDIDATE_LIMIT = (\d+);/);
	assert.ok(rsvp, 'RSVP_CANDIDATE_LIMIT moved');
	assert.ok(Number(rsvp[1]) <= FEED_FOLLOWEE_CHUNK);
	assert.match(body(data, 'export async function fetchNextRsvpedEvent('), /\.limit\(RSVP_CANDIDATE_LIMIT\)/);

	const coach = read('src/lib/coach/context.ts');
	for (const cap of ['COACH_PLAN_WEEKS_CAP', 'COACH_LIFTS_CAP']) {
		const m = coach.match(new RegExp(`export const ${cap} = (\\d+);`));
		assert.ok(m, `${cap} moved`);
		assert.ok(Number(m[1]) <= FEED_FOLLOWEE_CHUNK, `${cap} is past the in-filter bound`);
		assert.match(coach, new RegExp(`\\.limit\\(${cap}\\)`), `the coach read no longer caps on ${cap}`);
	}
});

/// A default only bounds the callers that take it. Every literal limit a
/// caller passes to one of those functions has to clear the same bar.
test('no caller passes one of those functions a limit past the bound', () => {
	const fns = [
		'fetchPublicPlanLibrary',
		'fetchPublicGymRoutineLibrary',
		'fetchFollowingFeed',
		'fetchFollowingActivityFeed',
		'fetchEventPhotos',
		'fetchNotifications',
		'fetchNotificationsWithError',
	];
	for (const root of ROOTS) {
		for (const file of sourceFiles(resolve(root))) {
			const src = stripComments(readFileSync(file, 'utf-8'));
			for (const fn of fns) {
				const call = new RegExp(`\\b${fn}\\(`, 'g');
				for (let m = call.exec(src); m; m = call.exec(src)) {
					const args = callArgs(src, m.index + fn.length);
					for (const n of args.replace(/'[^']*'/g, '').match(/\b\d+\b/g) ?? []) {
						assert.ok(
							Number(n) <= FEED_FOLLOWEE_CHUNK,
							`${relative(resolve('.'), file)} calls ${fn}(${args}) — past the in-filter bound its id join relies on`,
						);
					}
				}
			}
		}
	}
});
