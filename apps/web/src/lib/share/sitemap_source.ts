/// The anon reads behind the sitemap's child files, one kind at a time.
///
/// Every list is walked by keyset cursor rather than read with a `.limit()`:
/// PostgREST cuts a response at `db.max-rows` (1,000) with a 200 and no flag,
/// so a limited read lists the first 1,000 rows of a kind and silently drops
/// the rest. A walk that ends short (a page error, or a server that stops
/// advancing) is logged and keeps the rows it read, the same graceful
/// degradation the build applies to an unreachable Supabase.
///
/// Pure of SvelteKit — the client is passed in — so it runs under
/// `tsx --test` against a fake PostgREST.

import type { SupabaseClient } from '@supabase/supabase-js';

import { walkKeyset, type KeysetKey } from '../core/keyset_page';
import { TABLES } from '../core/schema';
import {
	buildRunCountByRouteId,
	clubEntries,
	courseEntries,
	eventEntries,
	raceEntries,
	routeEntries,
	runEntries,
	type SitemapEntry,
	type SitemapKind,
} from './sitemap';

/// Every kind is keyed on its uuid primary key, which is unique, so the order
/// is total and a walk reads each row once.
const ID_ORDER: readonly KeysetKey[] = [{ column: 'id', ascending: true, nullsFirst: false }];

/// A sitemap entry with the id of the row it came from, which picks its shard.
export interface SitemapRow {
	id: string;
	entry: SitemapEntry;
}

interface Page<T> {
	data: T[] | null;
	error: unknown;
}

type Client = SupabaseClient;

/// The part of a PostgREST select builder a walk drives once the caller has
/// applied its filters and the keyset `or`.
interface Pageable<T> {
	order(column: string, opts: { ascending: boolean; nullsFirst: boolean }): Pageable<T>;
	limit(n: number): PromiseLike<Page<T>>;
}

/// Walks one list by `ID_ORDER`; `filtered(after)` returns the read with its
/// filters and the cursor applied, and the walk sorts and pages it.
async function walkIds<T extends { id: string }>(
	label: string,
	filtered: (after: string | null) => unknown,
): Promise<T[]> {
	const walk = await walkKeyset<T>(ID_ORDER, (after, limit) => {
		let q = filtered(after) as Pageable<T>;
		for (const k of ID_ORDER) {
			q = q.order(k.column, { ascending: k.ascending, nullsFirst: k.nullsFirst });
		}
		return q.limit(limit);
	});
	if (!walk.complete) {
		console.warn(`sitemap: ${label} walk ended short after ${walk.rows.length} rows`, walk.error);
	}
	return walk.rows;
}

function zip<T extends { id: string }>(rows: T[], entries: SitemapEntry[]): SitemapRow[] {
	return rows.map((r, i) => ({ id: r.id, entry: entries[i] }));
}

async function routeRows(client: Client, base: string): Promise<SitemapRow[]> {
	const [routes, popular] = await Promise.all([
		walkIds<{ id: string; updated_at: string | null }>('public_routes', (after) => {
			let q = client.from('public_routes').select('id, updated_at');
			if (after) q = q.or(after);
			return q;
		}),
		// public_runs.route_id is nulled out unless the linked route is itself
		// public (migration 20260626_001), so the popularity signal only counts
		// public-on-public matches.
		walkIds<{ id: string; route_id: string | null }>('popularity', (after) => {
			let q = client.from('public_runs').select('id, route_id').not('route_id', 'is', null);
			if (after) q = q.or(after);
			return q;
		}),
	]);
	return zip(routes, routeEntries(base, routes, buildRunCountByRouteId(popular)));
}

async function runRows(client: Client, base: string): Promise<SitemapRow[]> {
	// public_runs deliberately omits `updated_at` (migration 20260807_001 —
	// the value leaks last-edit / last-sync cadence to share-link viewers).
	// `started_at` is the only timestamp the view publishes.
	const runs = await walkIds<{ id: string; started_at: string | null }>(
		'public_runs',
		(after) => {
			let q = client.from('public_runs').select('id, started_at');
			if (after) q = q.or(after);
			return q;
		},
	);
	return zip(runs, runEntries(base, runs));
}

async function eventRows(client: Client, base: string): Promise<SitemapRow[]> {
	// Events inherit public-club visibility via RLS. They have no
	// shadow_hidden column (moderation auto-hide, migration 20270218_001), so
	// the parent club's gates them through an inner-join filter.
	const events = await walkIds<{ id: string; updated_at: string | null }>(
		'events',
		(after) => {
			let q = client
				.from('events')
				.select('id, updated_at, clubs!inner(shadow_hidden)')
				.eq('clubs.shadow_hidden', false);
			if (after) q = q.or(after);
			return q;
		},
	);
	return zip(events, eventEntries(base, events));
}

async function clubRows(client: Client, base: string): Promise<SitemapRow[]> {
	const clubs = await walkIds<{ id: string; slug: string; updated_at: string | null }>(
		'clubs',
		(after) => {
			let q = client
				.from('clubs')
				.select('id, slug, updated_at')
				.eq('is_public', true)
				.eq('shadow_hidden', false);
			if (after) q = q.or(after);
			return q;
		},
	);
	return zip(clubs, clubEntries(base, clubs));
}

async function raceRows(client: Client, base: string): Promise<SitemapRow[]> {
	// Anon reads go through the redacted public_race_listings view, not the
	// base table (migration 20270320_001 dropped the base-table anon policy to
	// strip submitted_by).
	const races = await walkIds<{ id: string; updated_at: string | null }>(
		'public_race_listings',
		(after) => {
			let q = client.from('public_race_listings').select('id, updated_at');
			if (after) q = q.or(after);
			return q;
		},
	);
	return zip(races, raceEntries(base, races));
}

type CourseRow = {
	id: string;
	slug: string;
	created_at: string;
	status_checked_at: string | null;
	parks: { slug: string; region_code: string } | Array<{ slug: string; region_code: string }>;
};

async function courseRows(client: Client, base: string): Promise<SitemapRow[]> {
	// Park courses (decisions § 2394): curated catalogue pages that name no
	// runner. `parks` RLS hides an inactive park and `global_segments` a
	// pulled segment, so the inner joins drop both.
	const rows = await walkIds<CourseRow>(TABLES.park_courses, (after) => {
		let q = client
			.from(TABLES.park_courses)
			.select(
				'id, slug, created_at, status_checked_at, parks!inner(slug, region_code), global_segments!inner(id)',
			);
		if (after) q = q.or(after);
		return q;
	});
	const out: SitemapRow[] = [];
	for (const c of rows) {
		// A to-one embed; the untyped client types it as a list.
		const park = Array.isArray(c.parks) ? c.parks[0] : c.parks;
		if (!park) continue;
		const [entry] = courseEntries(base, [
			{
				slug: c.slug,
				park_slug: park.slug,
				region_code: park.region_code,
				updated_at: c.status_checked_at ?? c.created_at,
			},
		]);
		out.push({ id: c.id, entry });
	}
	return out;
}

const LOADERS: Record<SitemapKind, (client: Client, base: string) => Promise<SitemapRow[]>> = {
	routes: routeRows,
	runs: runRows,
	events: eventRows,
	clubs: clubRows,
	races: raceRows,
	courses: courseRows,
};

/// Every public row of `kind` as a sitemap entry. Never throws for a read
/// failure: a failed or short walk is logged and yields the rows it read.
export async function loadSitemapKind(
	client: Client,
	base: string,
	kind: SitemapKind,
): Promise<SitemapRow[]> {
	try {
		return await LOADERS[kind](client, base);
	} catch (err) {
		console.warn(`sitemap: ${kind} fetch failed; listing none`, err);
		return [];
	}
}
