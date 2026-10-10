// Source guards for the list-snapshot freshness contract (decisions § 1822).
//
// /runs, /history, /plans and /routes restore a captured list on back-
// navigation instead of refetching; the restore is only right while no
// write has landed since the list was loaded. That holds only if every
// write to a table those lists show bumps the lists' tokens — so the set of
// writers is DERIVED here from the source, not listed: any `.from(<table>)`
// followed by insert / update / upsert / delete on a table in
// LISTS_BY_TABLE must sit after a markListsStale(...) naming every list that
// table maps to. A new write function, or a page that writes the table
// directly, fails this file until it marks.
//
// Runs with cwd = apps/web (the `test:unit` script).

import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync, readdirSync } from 'node:fs';
import { join, relative, resolve } from 'node:path';

import { stripComments, stripSvelteComments } from './strip_comments';
import { LISTS_BY_TABLE, SNAPSHOT_LISTS } from './list_freshness';

type Table = keyof typeof LISTS_BY_TABLE;

const WRITE = /\.from\(\s*(?:TABLES\.(\w+)|'(\w+)')\s*\)\s*\.(?:insert|update|upsert|delete)\(/g;

/// Writes that deliberately do not mark, each with the reason. Kept honest
/// below: an entry whose function is gone, or no longer writes, fails.
const EXEMPT: Record<string, string> = {
	computeGlobalSegmentEffortsForRun:
		'runs on every first view of a run detail page and stamps a scoring bookkeeping key in runs.metadata that no list renders; marking would throw away the /runs snapshot (and its scroll) on every click-through',
};

function read(path: string): string {
	return readFileSync(resolve(path), 'utf-8');
}

function writesIn(code: string): { table: Table; at: number }[] {
	const out: { table: Table; at: number }[] = [];
	for (const m of code.matchAll(WRITE)) {
		const table = (m[1] ?? m[2]) as string;
		if (table in LISTS_BY_TABLE) out.push({ table: table as Table, at: m.index! });
	}
	return out;
}

/// Lists named by the markListsStale calls in `code` that start before `before`.
function markedBefore(code: string, before: number): Set<string> {
	const marked = new Set<string>();
	for (const m of code.matchAll(/markListsStale\(([^)]*)\)/g)) {
		if (m.index! > before) continue;
		for (const k of m[1].matchAll(/'(\w+)'/g)) marked.add(k[1]);
	}
	return marked;
}

function exportedFunctions(source: string): Map<string, string> {
	const out = new Map<string, string>();
	const starts = [...source.matchAll(/^export async function (\w+)/gm)];
	for (let i = 0; i < starts.length; i++) {
		const from = starts[i].index!;
		const to = i + 1 < starts.length ? starts[i + 1].index! : source.length;
		out.set(starts[i][1], source.slice(from, to));
	}
	return out;
}

const dataSource = stripComments(read('src/lib/core/data.ts'));
const dataFunctions = exportedFunctions(dataSource);

test('the guard finds the data layer writes it exists to police', () => {
	// A regex that stopped matching would pass every assertion below vacuously.
	const writers = [...dataFunctions].filter(([, body]) => writesIn(body).length > 0);
	assert.ok(writers.length >= 30, `only ${writers.length} writers found — did the write pattern drift?`);
	for (const table of Object.keys(LISTS_BY_TABLE)) {
		assert.ok(
			writers.some(([, body]) => writesIn(body).some((w) => w.table === table)),
			`no data.ts write to ${table} found`,
		);
	}
});

test('every data.ts write to a snapshotted table marks each list that shows it, before the write', () => {
	const failures: string[] = [];
	for (const [name, body] of dataFunctions) {
		if (name in EXEMPT) continue;
		for (const { table, at } of writesIn(body)) {
			const marked = markedBefore(body, at);
			const missing = LISTS_BY_TABLE[table].filter((l) => !marked.has(l));
			if (missing.length > 0) failures.push(`${name} writes ${table} without marking ${missing.join(', ')}`);
		}
	}
	assert.deepEqual(
		failures,
		[],
		'Mark before the write — a write whose response is lost may still have committed. See lib/core/list_freshness.ts.',
	);
});

test('every exemption still names a function that writes a snapshotted table', () => {
	for (const name of Object.keys(EXEMPT)) {
		const body = dataFunctions.get(name);
		assert.ok(body, `${name} is exempt but no longer exported from data.ts — drop the exemption`);
		assert.ok(writesIn(body).length > 0, `${name} no longer writes a snapshotted table — drop the exemption`);
		assert.doesNotMatch(body, /markListsStale\(/, `${name} marks now — drop the exemption`);
	}
});

test('a write outside data.ts to a snapshotted table marks the lists too', () => {
	// Page-level writes are how the run-detail edit used to bypass the data
	// layer; anything that still writes directly carries the same obligation.
	const failures: string[] = [];
	let scanned = 0;
	(function walk(dir: string): void {
		for (const entry of readdirSync(dir, { withFileTypes: true })) {
			const path = join(dir, entry.name);
			if (entry.isDirectory()) {
				walk(path);
				continue;
			}
			if (!/\.(ts|svelte)$/.test(entry.name) || /\.test\.ts$/.test(entry.name)) continue;
			const rel = relative(resolve('.'), resolve(path));
			if (rel === join('src', 'lib', 'core', 'data.ts')) continue;
			const raw = readFileSync(path, 'utf-8');
			const code = entry.name.endsWith('.svelte') ? stripSvelteComments(raw) : stripComments(raw);
			scanned++;
			for (const { table, at } of writesIn(code)) {
				const marked = markedBefore(code, at);
				const missing = LISTS_BY_TABLE[table].filter((l) => !marked.has(l));
				if (missing.length > 0) failures.push(`${rel} writes ${table} without marking ${missing.join(', ')}`);
			}
		}
	})('src');
	assert.ok(scanned > 100, 'walked too few files to mean anything');
	assert.deepEqual(failures, []);
});

test('writes that go through an RPC or an Edge Function mark the lists they change', () => {
	// The table these reach is not visible in the call, so they cannot be
	// derived; each is pinned by name.
	const cases: { file: string; fn: string; call: RegExp; lists: readonly string[] }[] = [
		{ file: 'src/lib/core/data.ts', fn: 'clonePlanTemplate', call: /rpc\('clone_plan_template'/, lists: LISTS_BY_TABLE.training_plans },
		{ file: 'src/lib/core/data.ts', fn: 'clonePublicPlan', call: /rpc\('clone_public_plan'/, lists: LISTS_BY_TABLE.training_plans },
		{ file: 'src/lib/core/data.ts', fn: 'importRaceResult', call: /invoke\('race-results-import'/, lists: LISTS_BY_TABLE.runs },
		{ file: 'src/lib/integrations/strava.ts', fn: 'completeStravaOAuth', call: /invoke\('strava-import'/, lists: LISTS_BY_TABLE.runs },
		{ file: 'src/lib/integrations/strava.ts', fn: 'syncStrava', call: /invoke\('strava-import'/, lists: LISTS_BY_TABLE.runs },
	];
	for (const c of cases) {
		const body = exportedFunctions(stripComments(read(c.file))).get(c.fn);
		assert.ok(body, `${c.fn} not found in ${c.file} — rename?`);
		const at = body.search(c.call);
		assert.ok(at >= 0, `${c.fn} no longer makes the call this case pins`);
		const marked = markedBefore(body, at);
		for (const list of c.lists) assert.ok(marked.has(list), `${c.fn} must mark '${list}' before the call`);
	}
});

test('every page that exports a snapshot is a registered list, captures its load token and checks it on restore', () => {
	const pages: string[] = [];
	(function walk(dir: string): void {
		for (const entry of readdirSync(dir, { withFileTypes: true })) {
			const path = join(dir, entry.name);
			if (entry.isDirectory()) walk(path);
			else if (entry.name === '+page.svelte' && /export const snapshot\b/.test(readFileSync(path, 'utf-8')))
				pages.push(path);
		}
	})('src/routes');
	assert.ok(pages.length >= SNAPSHOT_LISTS.length, 'found fewer snapshot pages than registered lists');

	const seen = new Set<string>();
	for (const page of pages) {
		const key = relative('src/routes', page).split(/[\\/]/)[0];
		assert.ok(
			(SNAPSHOT_LISTS as readonly string[]).includes(key),
			`${page} snapshots a list that SNAPSHOT_LISTS does not know — register it and mark its writes`,
		);
		seen.add(key);
		const code = stripSvelteComments(readFileSync(page, 'utf-8'));
		assert.match(code, /listToken: loadedToken\b/, `${page} must capture the token its list was LOADED under`);
		assert.match(code, new RegExp(`const token = listToken\\('${key}'\\)`), `${page} must note the token as its load starts`);
		assert.match(code, new RegExp(`isListStale\\('${key}', s\\.listToken\\)`), `${page} restore must check its token`);
		const restore = code.slice(code.indexOf('restore: (s) =>'));
		const staleAt = restore.indexOf('isListStale(');
		const firstListWrite = restore.search(/\b(runs|activityFeed|plans|routes) = s\./);
		assert.ok(
			staleAt >= 0 && firstListWrite > staleAt,
			`${page} restore must decide staleness before it puts the captured list back`,
		);
	}
	assert.deepEqual([...seen].sort(), [...SNAPSHOT_LISTS].sort(), 'a registered list has no snapshot page');
});
