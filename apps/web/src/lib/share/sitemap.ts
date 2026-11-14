/// Pure helpers for the prerendered /sitemap.xml endpoint. Split
/// out from `+server.ts` so unit tests can exercise the XML shape
/// without a SvelteKit build.
///
/// Sitemap spec: https://www.sitemaps.org/protocol.html
///   - Document declares xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"
///   - Each <url> carries <loc> (required) + <lastmod> (optional)
///   - Hard caps: 50,000 URLs per file, 50 MB uncompressed. A file over
///     either is rejected whole, so /sitemap.xml is an index of child
///     files (see `SITEMAP_KINDS` below) rather than one urlset.

import { buildClubShareCanonical } from './share_club_meta';
import { courseShareKey } from './share_course_lookup';
import { buildCourseShareCanonical } from './share_course_meta';
import { buildEventShareCanonical } from './share_event_meta';
import { buildRaceShareCanonical } from './share_race_meta';
import { buildRouteShareCanonical, buildRunShareCanonical } from './share_meta';
import { escapeXml } from '../util/html_escape';

export type SitemapEntry = {
	loc: string;
	lastmod?: string; // ISO 8601 (or any subset the spec accepts)
	changefreq?: 'always' | 'hourly' | 'daily' | 'weekly' | 'monthly' | 'yearly' | 'never';
	priority?: number; // 0.0..1.0
};

/// Strip the trailing slash from a base URL so concatenation with
/// `/share/...` yields a single-slash join. Idempotent.
export function normaliseBase(base: string): string {
	return base.replace(/\/+$/, '');
}

/// Build the sitemap XML body from an entries list. Stable ordering
/// — callers pass entries in the order they want them emitted; the
/// builder does not sort.
export function buildSitemap(entries: SitemapEntry[]): string {
	const lines: string[] = [];
	lines.push('<?xml version="1.0" encoding="UTF-8"?>');
	lines.push('<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">');
	for (const e of entries) {
		lines.push('  <url>');
		lines.push(`    <loc>${escapeXml(e.loc)}</loc>`);
		if (e.lastmod) lines.push(`    <lastmod>${escapeXml(e.lastmod)}</lastmod>`);
		if (e.changefreq) lines.push(`    <changefreq>${e.changefreq}</changefreq>`);
		if (e.priority != null) {
			lines.push(`    <priority>${e.priority.toFixed(1)}</priority>`);
		}
		lines.push('  </url>');
	}
	lines.push('</urlset>');
	return lines.join('\n') + '\n';
}

/// Bucket a route's run-count into a sitemap priority. Routes
/// without any recorded runs use the base 0.7; popular routes
/// bump up through 0.8 / 0.9 / 1.0 (cap matches the landing page).
/// Sub-linear (log-buckets) so a single hyper-popular route doesn't
/// drown the rest of the namespace.
export function priorityForRunCount(count: number): number {
	if (count >= 50) return 1.0;
	if (count >= 20) return 0.9;
	if (count >= 5) return 0.8;
	return 0.7;
}

/// changefreq for a route — popular routes get crawled more often.
/// Same bucketing as `priorityForRunCount` (a route popular enough
/// to bump priority is one where crawl freshness matters too).
export function changefreqForRunCount(
	count: number,
): 'daily' | 'weekly' | 'monthly' {
	if (count >= 20) return 'daily';
	if (count >= 5) return 'weekly';
	return 'monthly';
}

/// The top-level surfaces (landing, feed, explore, segment catalogue). They
/// head the `pages` child sitemap, ahead of the learn entries.
export function topLevelEntries(base: string): SitemapEntry[] {
	const b = normaliseBase(base);
	return [
		{ loc: `${b}/`, changefreq: 'weekly', priority: 1.0 },
		// /feed is auth-gated but the URL is well-known; let crawlers
		// know it exists so the login redirect resolves to a stable
		// destination.
		{ loc: `${b}/feed`, changefreq: 'daily', priority: 0.5 },
		// /routes?tab=explore is the public discovery entry point.
		{ loc: `${b}/routes?tab=explore`, changefreq: 'daily', priority: 0.6 },
		// The segment catalogue: world-readable curated content at a stable
		// URL, so the INDEX is listed. The per-segment pages are not — each
		// is a leaderboard of named runners, which is the people-directory
		// objection that keeps profiles out, and they are CSR besides, so a
		// crawler would only ever be handed the empty shell (decisions.md
		// § 677).
		{ loc: `${b}/segments`, changefreq: 'weekly', priority: 0.6 },
	];
}

/// Public route share pages. `runCountByRouteId` is an optional popularity
/// map from a `public_runs.route_id` aggregation — present values bump the
/// route's <priority> + <changefreq>.
export function routeEntries(
	base: string,
	routes: Array<{ id: string; updated_at?: string | null }>,
	runCountByRouteId?: Map<string, number>,
): SitemapEntry[] {
	const b = normaliseBase(base);
	return routes.map((r) => {
		const count = runCountByRouteId?.get(r.id) ?? 0;
		return {
			loc: buildRouteShareCanonical(b, r.id),
			lastmod: r.updated_at ?? undefined,
			changefreq: changefreqForRunCount(count),
			priority: priorityForRunCount(count),
		};
	});
}

/// Public run share pages.
export function runEntries(
	base: string,
	runs: Array<{ id: string; updated_at?: string | null; started_at?: string | null }>,
): SitemapEntry[] {
	const b = normaliseBase(base);
	return runs.map((r) => ({
		loc: buildRunShareCanonical(b, r.id),
		lastmod: r.updated_at ?? r.started_at ?? undefined,
		changefreq: 'monthly',
		priority: 0.6,
	}));
}

/// The public entity share pages served by the entity-SSR Lambda: club
/// events, public clubs, and race-calendar listings. There is deliberately
/// no profile builder — enumerating every runner in a sitemap is an
/// aggressive people-directory the app doesn't want; profiles are
/// discoverable via links, not a crawl manifest. Pure — the caller passes
/// the anon-readable rows.
export function eventEntries(
	base: string,
	events: Array<{ id: string; updated_at?: string | null }>,
): SitemapEntry[] {
	const b = normaliseBase(base);
	return events.map((e) => ({
		loc: buildEventShareCanonical(b, e.id),
		lastmod: e.updated_at ?? undefined,
		changefreq: 'weekly',
		priority: 0.6,
	}));
}

export function clubEntries(
	base: string,
	clubs: Array<{ slug: string; updated_at?: string | null }>,
): SitemapEntry[] {
	const b = normaliseBase(base);
	return clubs.map((c) => ({
		loc: buildClubShareCanonical(b, c.slug),
		lastmod: c.updated_at ?? undefined,
		changefreq: 'weekly',
		priority: 0.6,
	}));
}

export function raceEntries(
	base: string,
	races: Array<{ id: string; updated_at?: string | null }>,
): SitemapEntry[] {
	const b = normaliseBase(base);
	return races.map((r) => ({
		loc: buildRaceShareCanonical(b, r.id),
		lastmod: r.updated_at ?? undefined,
		changefreq: 'weekly',
		priority: 0.6,
	}));
}

/// Park course pages (`/share/course/<region>/<park>/<course>`). A course
/// page names the course and its park, never a runner, so it is not a
/// people-directory and is enumerated like a club. Pure — the caller passes
/// the anon-readable rows (inactive parks and pulled segments are already
/// hidden by RLS).
export function courseEntries(
	base: string,
	courses: Array<{
		slug: string;
		park_slug: string;
		region_code: string;
		updated_at?: string | null;
	}>,
): SitemapEntry[] {
	const b = normaliseBase(base);
	return courses.map((c) => ({
		loc: buildCourseShareCanonical(b, courseShareKey(c.region_code, c.park_slug, c.slug)),
		lastmod: c.updated_at ?? undefined,
		changefreq: 'monthly',
		priority: 0.7,
	}));
}

/// Learn-hub sitemap entries: the hub, one per category, one per guide.
/// Pure — the caller passes plain `{ slug, updated, category }` rows (the
/// build-time guide index from `#lib/learn/guides`) + the category ids so
/// this module stays import.meta.glob-free and tsx-testable. The Learn
/// entries are build-time constants, so the endpoint emits them even when
/// the Supabase fetch for routes/runs fails.
export function learnEntries(
	base: string,
	guides: Array<{ slug: string; updated?: string | null }>,
	categoryIds: string[],
): SitemapEntry[] {
	const b = normaliseBase(base);
	const entries: SitemapEntry[] = [
		{ loc: `${b}/learn`, changefreq: 'weekly', priority: 0.8 },
	];
	for (const id of categoryIds) {
		entries.push({ loc: `${b}/learn/category/${id}`, changefreq: 'weekly', priority: 0.6 });
	}
	for (const g of guides) {
		entries.push({
			loc: `${b}/learn/${g.slug}`,
			lastmod: g.updated ?? undefined,
			changefreq: 'monthly',
			priority: 0.7,
		});
	}
	return entries;
}

/// Tally `public_runs.route_id` into a Map keyed by route_id. Used
/// by the sitemap endpoint to popularity-weight routes. Rows with a
/// null `route_id` (the most common case — most runs aren't matched
/// to a saved route) are ignored.
export function buildRunCountByRouteId(
	rows: Array<{ route_id?: string | null }>,
): Map<string, number> {
	const out = new Map<string, number>();
	for (const r of rows) {
		const id = r.route_id;
		if (!id) continue;
		out.set(id, (out.get(id) ?? 0) + 1);
	}
	return out;
}

/// Protocol limits per file (sitemaps.org). Search engines reject a file over
/// either one outright, so `renderSitemapFile` throws rather than emit it.
export const SITEMAP_MAX_URLS = 50_000;
export const SITEMAP_MAX_BYTES = 50 * 1024 * 1024;

/// The row-backed kinds, each split into child files by the first hex digit of
/// the row's uuid. The split is a pure function of the id, so the set of child
/// files is known without reading a row: the prerender's `entries()` runs in a
/// separate process from the render, and a split by count would have to agree
/// across two reads of a moving table. Sixteen shards hold 800,000 URLs a
/// kind; past that `renderSitemapFile` throws, and the fix is a second digit.
export const SITEMAP_KINDS = ['routes', 'runs', 'events', 'clubs', 'races', 'courses'] as const;
export type SitemapKind = (typeof SITEMAP_KINDS)[number];
export const SITEMAP_SHARDS: readonly string[] = [...'0123456789abcdef'];

/// The child that holds the fixed pages: top-level surfaces and learn.
export const SITEMAP_PAGES_CHILD = 'pages';

export type SitemapChild = { kind: 'pages' } | { kind: SitemapKind; shard: string };

/// The shard a row with this uuid belongs to. Throws on an id that is not a
/// uuid, which would otherwise fall into no shard and drop silently.
export function sitemapShardOf(id: string): string {
	if (!UUID.test(id)) throw new Error(`sitemap: not a uuid: ${id}`);
	return id.charAt(0).toLowerCase();
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export function sitemapChildName(child: SitemapChild): string {
	return child.kind === 'pages' ? SITEMAP_PAGES_CHILD : `${child.kind}-${child.shard}`;
}

/// Every child file the build can emit, in index order.
export function allSitemapChildren(): SitemapChild[] {
	return [
		{ kind: 'pages' },
		...SITEMAP_KINDS.flatMap((kind) => SITEMAP_SHARDS.map((shard) => ({ kind, shard }))),
	];
}

export function parseSitemapChild(name: string): SitemapChild | null {
	if (name === SITEMAP_PAGES_CHILD) return { kind: 'pages' };
	const m = /^([a-z]+)-([0-9a-f])$/.exec(name);
	if (!m) return null;
	const kind = SITEMAP_KINDS.find((k) => k === m[1]);
	return kind ? { kind, shard: m[2] } : null;
}

/// The URL of one child file, under the same normalised base as every <loc>.
export function sitemapChildCanonical(base: string, child: SitemapChild): string {
	return `${normaliseBase(base)}/sitemaps/${sitemapChildName(child)}.xml`;
}

/// A <sitemapindex> listing `children`. Pure; the caller decides which
/// children are worth listing (the empty ones are left out).
export function buildSitemapIndex(base: string, children: SitemapChild[]): string {
	const lines: string[] = [];
	lines.push('<?xml version="1.0" encoding="UTF-8"?>');
	lines.push('<sitemapindex xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">');
	for (const child of children) {
		lines.push('  <sitemap>');
		lines.push(`    <loc>${escapeXml(sitemapChildCanonical(base, child))}</loc>`);
		lines.push('  </sitemap>');
	}
	lines.push('</sitemapindex>');
	return lines.join('\n') + '\n';
}

/// One child file's body, refusing to emit a file past the protocol limits:
/// a crawler rejects such a file whole, and cutting it is the silent loss the
/// index exists to prevent.
export function renderSitemapFile(entries: SitemapEntry[]): string {
	if (entries.length > SITEMAP_MAX_URLS) {
		throw new Error(
			`sitemap: ${entries.length} URLs in one file exceeds the ${SITEMAP_MAX_URLS} limit; shard by more id digits`,
		);
	}
	const body = buildSitemap(entries);
	const bytes = new TextEncoder().encode(body).length;
	if (bytes > SITEMAP_MAX_BYTES) {
		throw new Error(`sitemap: ${bytes} bytes in one file exceeds the ${SITEMAP_MAX_BYTES} limit`);
	}
	return body;
}
