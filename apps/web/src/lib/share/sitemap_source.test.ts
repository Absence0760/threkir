// The sitemap's reads walk every public row past `db.max-rows`. Invocation:
//   npx tsx --test src/lib/share/sitemap_source.test.ts
//
// PostgREST answers a `.limit(10_000)` with the first 1,000 rows and a 200,
// so a limited read listed 1,000 of each kind and dropped the rest without a
// word. The fake below caps every response at 1,000 the same way.

import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import type { SupabaseClient } from '@supabase/supabase-js';

import { stripComments } from '../core/strip_comments.ts';
import { loadSitemapKind } from './sitemap_source.ts';

type Row = Record<string, unknown> & { id: string };

const MAX_ROWS = 1_000;

function uuid(n: number): string {
	const hex = n.toString(16).padStart(12, '0');
	// Spread the leading digit so the rows fall into every shard.
	return `${hex.slice(-1)}${hex.slice(0, 7)}-0000-4000-8000-${hex}`;
}

interface Fake {
	client: SupabaseClient;
	calls: { table: string; eq: Array<[string, unknown]>; notNull: string[]; limit: number | null }[];
}

/// A PostgREST stand-in that understands exactly what the sitemap sends:
/// top-level `eq`, `not(col, 'is', null)`, the keyset `or` body for an
/// ascending id, `order('id')` and `limit`, and caps every page at MAX_ROWS.
/// `failOnPage` answers that page (0-based) with an error.
function fake(tables: Record<string, Row[]>, failOnPage: Record<string, number> = {}): Fake {
	const calls: Fake['calls'] = [];
	const pages = new Map<string, number>();
	const client = {
		from(table: string) {
			const call = { table, eq: [] as Array<[string, unknown]>, notNull: [] as string[], limit: null as number | null };
			calls.push(call);
			let after: string | null = null;
			const q = {
				select: () => q,
				eq(col: string, value: unknown) {
					call.eq.push([col, value]);
					return q;
				},
				not(col: string, op: string, value: unknown) {
					assert.equal(op, 'is');
					assert.equal(value, null);
					call.notNull.push(col);
					return q;
				},
				or(expr: string) {
					const m = /^or\(id\.gt\."([^"]+)",id\.is\.null\)$/.exec(expr);
					assert.ok(m, `unexpected keyset body: ${expr}`);
					after = m[1];
					return q;
				},
				order(col: string, opts: { ascending: boolean }) {
					assert.equal(col, 'id');
					assert.equal(opts.ascending, true);
					return q;
				},
				limit(n: number) {
					call.limit = n;
					return q;
				},
				then(resolve: (v: unknown) => unknown, reject?: (e: unknown) => unknown) {
					const page = pages.get(table) ?? 0;
					pages.set(table, page + 1);
					if (failOnPage[table] === page) {
						return Promise.resolve({ data: null, error: { message: 'boom' } }).then(resolve, reject);
					}
					const rows = (tables[table] ?? [])
						.filter((r) => call.eq.every(([c, v]) => c.includes('.') || r[c] === v))
						.filter((r) => call.notNull.every((c) => r[c] != null))
						.filter((r) => after === null || r.id > after)
						.sort((a, b) => (a.id < b.id ? -1 : a.id > b.id ? 1 : 0))
						.slice(0, Math.min(call.limit ?? Infinity, MAX_ROWS));
					return Promise.resolve({ data: rows, error: null }).then(resolve, reject);
				},
			};
			return q;
		},
	} as unknown as SupabaseClient;
	return { client, calls };
}

const BASE = 'https://threkir.com';

test('every public race past the 1,000-row cap is listed, each once', async () => {
	const races = Array.from({ length: 2_500 }, (_, i) => ({ id: uuid(i), updated_at: null }));
	const { client } = fake({ public_race_listings: races });
	const rows = await loadSitemapKind(client, BASE, 'races');
	assert.equal(rows.length, 2_500);
	assert.equal(new Set(rows.map((r) => r.id)).size, 2_500);
	assert.equal(rows[0].entry.loc, `${BASE}/share/race/${rows[0].id}`);
});

test('runs, routes and events are walked past the cap too', async () => {
	const many = (n: number) => Array.from({ length: n }, (_, i) => ({ id: uuid(i), updated_at: null, started_at: null, route_id: null }));
	const { client } = fake({ public_runs: many(1_500), public_routes: many(1_200), events: many(1_001) });
	assert.equal((await loadSitemapKind(client, BASE, 'runs')).length, 1_500);
	assert.equal((await loadSitemapKind(client, BASE, 'routes')).length, 1_200);
	assert.equal((await loadSitemapKind(client, BASE, 'events')).length, 1_001);
});

test('clubs list only public, unhidden clubs, by slug', async () => {
	const clubs = Array.from({ length: 1_300 }, (_, i) => ({
		id: uuid(i),
		slug: `club-${i}`,
		updated_at: null,
		is_public: i % 3 !== 0,
		shadow_hidden: i % 5 === 0,
	}));
	const { client, calls } = fake({ clubs });
	const rows = await loadSitemapKind(client, BASE, 'clubs');
	const expected = clubs.filter((c) => c.is_public && !c.shadow_hidden);
	assert.equal(rows.length, expected.length);
	assert.ok(rows.every((r) => /\/share\/club\/club-\d+$/.test(r.entry.loc)));
	for (const call of calls) {
		assert.deepEqual(call.eq, [
			['is_public', true],
			['shadow_hidden', false],
		]);
	}
});

test('events exclude a shadow-hidden club through the inner-join filter', async () => {
	const { client, calls } = fake({ events: [{ id: uuid(1), updated_at: null }] });
	await loadSitemapKind(client, BASE, 'events');
	assert.deepEqual(calls[0].eq, [['clubs.shadow_hidden', false]]);
});

test('route popularity counts every public run past the cap', async () => {
	const route = uuid(7);
	// The sixty runs on the route are the last sixty in id order, so a read
	// cut at the first 1,000 counts none of them.
	const runs = Array.from({ length: 1_200 }, (_, i) => ({ id: uuid(10_000 + i), route_id: null as string | null }))
		.sort((a, b) => (a.id < b.id ? -1 : 1))
		.map((r, i) => ({ ...r, route_id: i >= 1_140 ? route : null }));
	const { client, calls } = fake({ public_routes: [{ id: route, updated_at: null }], public_runs: runs });
	const [row] = await loadSitemapKind(client, BASE, 'routes');
	assert.equal(row.entry.priority, 1.0, 'sixty runs is the top popularity bucket');
	assert.equal(row.entry.changefreq, 'daily');
	assert.ok(calls.filter((c) => c.table === 'public_runs').every((c) => c.notNull.includes('route_id')));
});

test('park courses carry their park slugs into the share key', async () => {
	const courses = [
		{
			id: uuid(3),
			slug: 'lake-loop',
			created_at: '2027-01-01T00:00:00Z',
			status_checked_at: null,
			parks: { slug: 'fixture-state-park', region_code: 'US-VA' },
		},
	];
	const { client } = fake({ park_courses: courses });
	const rows = await loadSitemapKind(client, BASE, 'courses');
	assert.equal(rows[0].entry.loc, `${BASE}/share/course/us-va/fixture-state-park/lake-loop`);
	assert.equal(rows[0].entry.lastmod, '2027-01-01T00:00:00Z');
});

test('a walk that fails part-way keeps what it read and says so', async () => {
	const races = Array.from({ length: 2_500 }, (_, i) => ({ id: uuid(i), updated_at: null }));
	const { client } = fake({ public_race_listings: races }, { public_race_listings: 1 });
	const warnings: unknown[][] = [];
	const warn = console.warn;
	console.warn = (...args: unknown[]) => warnings.push(args);
	try {
		const rows = await loadSitemapKind(client, BASE, 'races');
		assert.equal(rows.length, 1_000);
	} finally {
		console.warn = warn;
	}
	assert.equal(warnings.length, 1);
	assert.match(String(warnings[0][0]), /public_race_listings walk ended short after 1000 rows/);
});

test('no sitemap read asks for a fixed row count', () => {
	// Every list goes through walkIds; a `.limit()` with anything but the
	// walk's page size would put the silent 1,000-row cut back.
	const files = [
		resolve(import.meta.dirname, 'sitemap_source.ts'),
		resolve(import.meta.dirname, 'sitemap_server.ts'),
		resolve(import.meta.dirname, '../../routes/sitemap.xml/+server.ts'),
		resolve(import.meta.dirname, '../../routes/sitemaps/[name].xml/+server.ts'),
	];
	for (const file of files) {
		const src = stripComments(readFileSync(file, 'utf-8'));
		for (const m of src.matchAll(/\.limit\(([^)]*)\)/g)) {
			assert.equal(m[1], 'limit', `${file}: .limit(${m[1]})`);
		}
		assert.doesNotMatch(src, /\.range\(/, file);
	}
	const source = stripComments(readFileSync(files[0], 'utf-8'));
	const reads = (source.match(/\.from\(/g) ?? []).length;
	const walks = (source.match(/(?<!function )walkIds</g) ?? []).length;
	assert.equal(reads, walks, 'every .from() read sits inside its own walk');
});
