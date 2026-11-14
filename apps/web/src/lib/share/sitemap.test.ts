import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	allSitemapChildren,
	buildRunCountByRouteId,
	buildSitemap,
	buildSitemapIndex,
	changefreqForRunCount,
	clubEntries,
	courseEntries,
	eventEntries,
	learnEntries,
	normaliseBase,
	priorityForRunCount,
	parseSitemapChild,
	raceEntries,
	renderSitemapFile,
	routeEntries,
	runEntries,
	SITEMAP_KINDS,
	SITEMAP_MAX_BYTES,
	SITEMAP_MAX_URLS,
	SITEMAP_SHARDS,
	sitemapChildCanonical,
	sitemapChildName,
	sitemapShardOf,
	topLevelEntries,
} from './sitemap';
import { escapeHtml } from '../util/html_escape';
import { buildClubShareCanonical } from './share_club_meta';
import { buildEventShareCanonical } from './share_event_meta';
import { buildRaceShareCanonical } from './share_race_meta';
import { buildRouteShareCanonical, buildRunShareCanonical } from './share_meta';

// ---------------- escapeHtml ----------------

test('escapeHtml — escapes the five reserved characters', () => {
	assert.equal(escapeHtml(`a<b>c&d"e'f`), 'a&lt;b&gt;c&amp;d&quot;e&#39;f');
});

test('escapeHtml — passes through plain text + uuids untouched', () => {
	assert.equal(
		escapeHtml('550e8400-e29b-41d4-a716-446655440000'),
		'550e8400-e29b-41d4-a716-446655440000',
	);
	assert.equal(
		escapeHtml('https://threkir.com/share/run/abc'),
		'https://threkir.com/share/run/abc',
	);
});

// ---------------- normaliseBase ----------------

test('normaliseBase — strips a single trailing slash', () => {
	assert.equal(normaliseBase('https://threkir.com/'), 'https://threkir.com');
});

test('normaliseBase — strips multiple trailing slashes', () => {
	assert.equal(normaliseBase('https://threkir.com///'), 'https://threkir.com');
});

test('normaliseBase — is a no-op on a clean base', () => {
	assert.equal(normaliseBase('https://threkir.com'), 'https://threkir.com');
});

// ---------------- buildSitemap ----------------

test('buildSitemap — emits a valid xml declaration + urlset wrapper', () => {
	const xml = buildSitemap([]);
	assert.match(xml, /^<\?xml version="1\.0" encoding="UTF-8"\?>/);
	assert.ok(xml.includes('<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">'));
	assert.match(xml.trimEnd(), /<\/urlset>$/);
});

test('buildSitemap — one entry round-trips through loc + lastmod + changefreq + priority', () => {
	const xml = buildSitemap([
		{
			loc: 'https://threkir.com/share/route/abc',
			lastmod: '2026-05-11T00:00:00Z',
			changefreq: 'weekly',
			priority: 0.7,
		},
	]);
	assert.ok(xml.includes('<loc>https://threkir.com/share/route/abc</loc>'));
	assert.ok(xml.includes('<lastmod>2026-05-11T00:00:00Z</lastmod>'));
	assert.ok(xml.includes('<changefreq>weekly</changefreq>'));
	assert.ok(xml.includes('<priority>0.7</priority>'));
});

test('buildSitemap — omits optional fields when unset', () => {
	const xml = buildSitemap([{ loc: 'https://threkir.com/' }]);
	assert.ok(xml.includes('<loc>https://threkir.com/</loc>'));
	assert.ok(!xml.includes('<lastmod>'));
	assert.ok(!xml.includes('<changefreq>'));
	assert.ok(!xml.includes('<priority>'));
});

test('buildSitemap — escapes special chars in loc + lastmod', () => {
	const xml = buildSitemap([{ loc: 'https://threkir.com/q?x=1&y=2', lastmod: '<bad>' }]);
	assert.ok(xml.includes('<loc>https://threkir.com/q?x=1&amp;y=2</loc>'));
	assert.ok(xml.includes('<lastmod>&lt;bad&gt;</lastmod>'));
});

test('buildSitemap — priority renders with one decimal place even when whole', () => {
	const xml = buildSitemap([{ loc: 'https://x/', priority: 1 }]);
	assert.ok(xml.includes('<priority>1.0</priority>'));
});

// ---------------- top-level, route and run entries ----------------

test('topLevelEntries — the four top-level surfaces, landing first', () => {
	const entries = topLevelEntries('https://threkir.com');
	assert.equal(entries.length, 4);
	assert.equal(entries[0].loc, 'https://threkir.com/');
	assert.equal(entries[1].loc, 'https://threkir.com/feed');
	assert.equal(entries[2].loc, 'https://threkir.com/routes?tab=explore');
	assert.equal(entries[3].loc, 'https://threkir.com/segments');
	assert.equal(entries[0].priority, 1.0);
});

// The catalogue index is crawlable content; a per-segment page is a
// leaderboard of named runners, which is the same people-directory
// objection that keeps profiles out of the manifest.
test('topLevelEntries — lists the segment catalogue index and no individual segment', () => {
	const entries = [
		...topLevelEntries('https://threkir.com'),
		...routeEntries('https://threkir.com', [{ id: 'route-1' }]),
		...runEntries('https://threkir.com', [{ id: 'run-1' }]),
	];
	const segmentLocs = entries.filter((e) => e.loc.includes('/segments'));
	assert.equal(segmentLocs.length, 1);
	assert.equal(segmentLocs[0].loc, 'https://threkir.com/segments');
});

test('routeEntries — strips trailing slash on the base before concatenating', () => {
	const entries = routeEntries('https://threkir.com/', [{ id: 'r1' }]);
	const routeEntry = entries.find((e) => e.loc.includes('/share/route/'));
	assert.equal(routeEntry?.loc, 'https://threkir.com/share/route/r1');
});

test('routeEntries + runEntries — /share/* entries with lastmod when available', () => {
	const entries = [
		...routeEntries('https://threkir.com', [{ id: 'route-1', updated_at: '2026-05-10T00:00:00Z' }]),
		...runEntries('https://threkir.com', [
			{ id: 'run-1', updated_at: '2026-05-11T00:00:00Z' },
			{ id: 'run-2', updated_at: null, started_at: '2026-05-09T00:00:00Z' },
		]),
	];
	assert.equal(entries.length, 3);
	const route1 = entries.find((e) => e.loc === 'https://threkir.com/share/route/route-1');
	assert.equal(route1?.lastmod, '2026-05-10T00:00:00Z');
	const run1 = entries.find((e) => e.loc === 'https://threkir.com/share/run/run-1');
	assert.equal(run1?.lastmod, '2026-05-11T00:00:00Z');
	// run-2 has no updated_at; falls back to started_at.
	const run2 = entries.find((e) => e.loc === 'https://threkir.com/share/run/run-2');
	assert.equal(run2?.lastmod, '2026-05-09T00:00:00Z');
});

test('runEntries — entries with neither updated_at nor started_at omit lastmod', () => {
	const entries = runEntries('https://threkir.com', [{ id: 'r' }]);
	const run = entries.find((e) => e.loc.includes('/share/run/r'));
	assert.equal(run?.lastmod, undefined);
});

test('routeEntries + runEntries — every share entry carries a priority and a changefreq', () => {
	const entries = [
		...routeEntries('https://threkir.com', [{ id: 'a' }]),
		...runEntries('https://threkir.com', [{ id: 'b' }]),
	];
	const route = entries.find((e) => e.loc.endsWith('/share/route/a'))!;
	const run = entries.find((e) => e.loc.endsWith('/share/run/b'))!;
	// Route with no popularity → cold base values.
	assert.equal(route.changefreq, 'monthly');
	assert.equal(route.priority, 0.7);
	assert.equal(run.changefreq, 'monthly');
	assert.equal(run.priority, 0.6);
});

// ---------------- end-to-end ----------------

// ---------------- priorityForRunCount + changefreqForRunCount ----------------

test('priorityForRunCount — bucket boundaries', () => {
	assert.equal(priorityForRunCount(0), 0.7);
	assert.equal(priorityForRunCount(4), 0.7);
	assert.equal(priorityForRunCount(5), 0.8);
	assert.equal(priorityForRunCount(19), 0.8);
	assert.equal(priorityForRunCount(20), 0.9);
	assert.equal(priorityForRunCount(49), 0.9);
	assert.equal(priorityForRunCount(50), 1.0);
	assert.equal(priorityForRunCount(1000), 1.0);
});

test('changefreqForRunCount — bucket boundaries', () => {
	assert.equal(changefreqForRunCount(0), 'monthly');
	assert.equal(changefreqForRunCount(4), 'monthly');
	assert.equal(changefreqForRunCount(5), 'weekly');
	assert.equal(changefreqForRunCount(19), 'weekly');
	assert.equal(changefreqForRunCount(20), 'daily');
});

// ---------------- buildRunCountByRouteId ----------------

test('buildRunCountByRouteId — tallies repeated ids', () => {
	const m = buildRunCountByRouteId([
		{ route_id: 'a' },
		{ route_id: 'a' },
		{ route_id: 'b' },
		{ route_id: 'a' },
	]);
	assert.equal(m.get('a'), 3);
	assert.equal(m.get('b'), 1);
	assert.equal(m.size, 2);
});

test('buildRunCountByRouteId — ignores null + undefined route_ids', () => {
	const m = buildRunCountByRouteId([
		{ route_id: null },
		{ route_id: undefined },
		{ route_id: 'real' },
		{},
	]);
	assert.equal(m.size, 1);
	assert.equal(m.get('real'), 1);
});

test('buildRunCountByRouteId — empty input returns empty map', () => {
	const m = buildRunCountByRouteId([]);
	assert.equal(m.size, 0);
});

// ---------------- routeEntries popularity ----------------

test('routeEntries — popular route bumps priority + changefreq', () => {
	const popularity = new Map<string, number>([
		['hot', 25], // → daily / 0.9
		['warm', 7], // → weekly / 0.8
	]);
	const entries = routeEntries('https://x', [{ id: 'hot' }, { id: 'warm' }, { id: 'cold' }], popularity);
	const hot = entries.find((e) => e.loc.endsWith('/share/route/hot'))!;
	const warm = entries.find((e) => e.loc.endsWith('/share/route/warm'))!;
	const cold = entries.find((e) => e.loc.endsWith('/share/route/cold'))!;
	assert.equal(hot.priority, 0.9);
	assert.equal(hot.changefreq, 'daily');
	assert.equal(warm.priority, 0.8);
	assert.equal(warm.changefreq, 'weekly');
	assert.equal(cold.priority, 0.7);
	assert.equal(cold.changefreq, 'monthly');
});

test('routeEntries — popularity map omitted → all routes use base values', () => {
	const entries = routeEntries('https://x', [{ id: 'a' }, { id: 'b' }]);
	const a = entries.find((e) => e.loc.endsWith('/share/route/a'))!;
	assert.equal(a.priority, 0.7);
	assert.equal(a.changefreq, 'monthly');
});

// ---------------- end-to-end ----------------

test('entries → buildSitemap produces a well-formed XML body the spec accepts', () => {
	const xml = buildSitemap([
		...topLevelEntries('https://threkir.com'),
		...routeEntries('https://threkir.com', [{ id: 'route-uuid-1', updated_at: '2026-05-10T00:00:00Z' }]),
		...runEntries('https://threkir.com', [{ id: 'run-uuid-1', started_at: '2026-05-09T00:00:00Z' }]),
	]);
	assert.match(xml, /^<\?xml version="1\.0" encoding="UTF-8"\?>/);
	assert.ok(xml.includes('xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"'));
	assert.match(xml, /<\/urlset>\s*$/);
	assert.ok(xml.includes('<loc>https://threkir.com/</loc>'));
	assert.ok(xml.includes('<loc>https://threkir.com/share/route/route-uuid-1</loc>'));
	assert.ok(xml.includes('<loc>https://threkir.com/share/run/run-uuid-1</loc>'));
});

// ---------------- learnEntries ----------------

test('learnEntries — emits the hub, each category, and each guide', () => {
	const entries = learnEntries(
		'https://threkir.com/',
		[
			{ slug: 'road-running-101', updated: '2026-06-15' },
			{ slug: 'couch-to-5k', updated: '2026-06-15' },
		],
		['getting-started', 'gear'],
	);
	const locs = new Set(entries.map((e) => e.loc));
	assert.ok(locs.has('https://threkir.com/learn'));
	assert.ok(locs.has('https://threkir.com/learn/category/getting-started'));
	assert.ok(locs.has('https://threkir.com/learn/category/gear'));
	assert.ok(locs.has('https://threkir.com/learn/road-running-101'));
	assert.ok(locs.has('https://threkir.com/learn/couch-to-5k'));
});

test('learnEntries — hub/category/guide carry the documented priorities + lastmod', () => {
	const entries = learnEntries(
		'https://threkir.com',
		[{ slug: 'road-running-101', updated: '2026-06-15' }],
		['getting-started'],
	);
	const hub = entries.find((e) => e.loc.endsWith('/learn'));
	const category = entries.find((e) => e.loc.endsWith('/category/getting-started'));
	const guide = entries.find((e) => e.loc.endsWith('/road-running-101'));
	assert.equal(hub?.priority, 0.8);
	assert.equal(category?.priority, 0.6);
	assert.equal(guide?.priority, 0.7);
	assert.equal(guide?.lastmod, '2026-06-15');
	assert.equal(guide?.changefreq, 'monthly');
});

test('learnEntries → buildSitemap emits the guide lastmod', () => {
	const xml = buildSitemap(
		learnEntries('https://threkir.com', [{ slug: 'road-running-101', updated: '2026-06-15' }], [
			'getting-started',
		]),
	);
	assert.ok(xml.includes('<loc>https://threkir.com/learn/road-running-101</loc>'));
	assert.ok(xml.includes('<lastmod>2026-06-15</lastmod>'));
});

// ---------------- event / club / race entries ----------------

function allEntityEntries(
	base: string,
	events: Array<{ id: string; updated_at?: string | null }>,
	clubs: Array<{ slug: string; updated_at?: string | null }>,
	races: Array<{ id: string; updated_at?: string | null }>,
) {
	return [...eventEntries(base, events), ...clubEntries(base, clubs), ...raceEntries(base, races)];
}

test('eventEntries / clubEntries / raceEntries — share/event, share/club (by slug), share/race', () => {
	const entries = allEntityEntries(
		'https://threkir.com',
		[{ id: 'e-1', updated_at: '2026-05-01T00:00:00Z' }],
		[{ slug: 'hampstead-runners', updated_at: '2026-04-01T00:00:00Z' }],
		[{ id: 'r-1', updated_at: '2026-03-01T00:00:00Z' }]
	);
	const locs = entries.map((e) => e.loc);
	assert.deepEqual(locs, [
		'https://threkir.com/share/event/e-1',
		'https://threkir.com/share/club/hampstead-runners',
		'https://threkir.com/share/race/r-1',
	]);
	assert.equal(entries[0].lastmod, '2026-05-01T00:00:00Z');
});

test('entity entries — never emit a profile URL (no people enumeration)', () => {
	const entries = allEntityEntries(
		'https://threkir.com',
		[{ id: 'e-1' }],
		[{ slug: 'c' }],
		[{ id: 'r' }]
	);
	assert.ok(entries.every((e) => !e.loc.includes('/share/profile/')));
});

test('entity entries — empty inputs yield no entries', () => {
	assert.deepEqual(allEntityEntries('https://threkir.com', [], [], []), []);
});

// ---------------- the sitemap advertises exactly the canonical ----------------

// A <loc> and the target page's <link rel="canonical"> have to be the same
// string. If the sitemap spells the path itself and the two ever drift, the
// crawler is handed a manifest of URLs that each point somewhere else — worse
// than either mistake alone, and invisible until indexing stalls.

test('every share <loc> equals the entity builder canonical for the same base', () => {
	const base = 'https://threkir.com';
	const entries = [...routeEntries(base, [{ id: 'rt-1' }]), ...runEntries(base, [{ id: 'r-1' }])];
	const locs = entries.map((e) => e.loc);
	assert.ok(locs.includes(buildRouteShareCanonical(base, 'rt-1')));
	assert.ok(locs.includes(buildRunShareCanonical(base, 'r-1')));

	const ent = allEntityEntries(base, [{ id: 'e-1' }], [{ slug: 'club-a' }], [{ id: 'ra-1' }]).map(
		(e) => e.loc,
	);
	assert.deepEqual(ent, [
		buildEventShareCanonical(base, 'e-1'),
		buildClubShareCanonical(base, 'club-a'),
		buildRaceShareCanonical(base, 'ra-1'),
	]);
});

test('a trailing slash on the base is normalised the same way the builders do', () => {
	const entries = allEntityEntries('https://threkir.com/', [], [{ slug: 'club-a' }], []);
	assert.equal(entries[0].loc, buildClubShareCanonical('https://threkir.com', 'club-a'));
});

// The sitemap is XML a crawler parses whole; a control character in one <loc>
// (a slug built from an imported name) would make it refuse every URL in it.
test('buildSitemap — a character XML forbids becomes U+FFFD, never reaches the document', () => {
	const xml = buildSitemap([{ loc: 'https://threkir.com/share/club/a\u0001b', lastmod: '2026-01-01\u000B' }]);
	assert.ok(!/[\u0000-\u0008\u000B\u000C\u000E-\u001F]/.test(xml));
	assert.ok(xml.includes('<loc>https://threkir.com/share/club/a�b</loc>'));
});

test('courseEntries — one /share/course entry per course, keyed by region, park and course slugs', () => {
	const entries = courseEntries('https://threkir.com/', [
		{ slug: 'lake-loop', park_slug: 'fixture-state-park', region_code: 'US-VA', updated_at: '2027-01-02T00:00:00Z' },
		{ slug: 'ridge', park_slug: 'other', region_code: 'US-NC', updated_at: null },
	]);
	assert.deepEqual(entries, [
		{
			loc: 'https://threkir.com/share/course/us-va/fixture-state-park/lake-loop',
			lastmod: '2027-01-02T00:00:00Z',
			changefreq: 'monthly',
			priority: 0.7,
		},
		{
			loc: 'https://threkir.com/share/course/us-nc/other/ridge',
			lastmod: undefined,
			changefreq: 'monthly',
			priority: 0.7,
		},
	]);
	assert.deepEqual(courseEntries('https://threkir.com', []), []);
});

// ---------------- the index and its child files ----------------

test('sitemapShardOf — the first hex digit of the uuid, case-folded', () => {
	assert.equal(sitemapShardOf('0b2c7d3e-0000-4000-8000-000000000000'), '0');
	assert.equal(sitemapShardOf('F00DCAFE-0000-4000-8000-000000000000'), 'f');
});

test('sitemapShardOf — an id that is not a uuid throws rather than fall into no shard', () => {
	assert.throws(() => sitemapShardOf('club-slug'), /not a uuid/);
	assert.throws(() => sitemapShardOf(''), /not a uuid/);
});

test('allSitemapChildren — pages first, then sixteen shards per kind, every name parsing back', () => {
	const children = allSitemapChildren();
	assert.equal(children.length, 1 + SITEMAP_KINDS.length * 16);
	assert.deepEqual(children[0], { kind: 'pages' });
	const names = children.map(sitemapChildName);
	assert.equal(new Set(names).size, names.length);
	for (const child of children) assert.deepEqual(parseSitemapChild(sitemapChildName(child)), child);
	assert.ok(names.includes('runs-a') && names.includes('courses-0'));
});

test('parseSitemapChild — rejects anything outside the fixed set', () => {
	for (const name of ['profiles-a', 'runs-g', 'runs-ab', 'runs', 'runs-A', '', '../pages']) {
		assert.equal(parseSitemapChild(name), null, name);
	}
});

test('every row lands in exactly one shard, so the shards together are the whole list', () => {
	const ids = Array.from({ length: 2_500 }, (_, i) => `${i.toString(16).padStart(8, '0').split('').reverse().join('')}-0000-4000-8000-000000000000`);
	const byShard = new Map<string, string[]>();
	for (const id of ids) {
		const shard = sitemapShardOf(id);
		byShard.set(shard, [...(byShard.get(shard) ?? []), id]);
	}
	assert.deepEqual([...byShard.keys()].sort(), [...SITEMAP_SHARDS]);
	assert.equal([...byShard.values()].flat().length, ids.length);
});

test('buildSitemapIndex — a <sitemapindex> of child URLs on the normalised base', () => {
	const xml = buildSitemapIndex('https://threkir.com/', [{ kind: 'pages' }, { kind: 'races', shard: 'c' }]);
	assert.match(xml, /^<\?xml version="1\.0" encoding="UTF-8"\?>/);
	assert.ok(xml.includes('<sitemapindex xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">'));
	assert.deepEqual(
		[...xml.matchAll(/<loc>([^<]+)<\/loc>/g)].map((m) => m[1]),
		['https://threkir.com/sitemaps/pages.xml', 'https://threkir.com/sitemaps/races-c.xml'],
	);
	assert.equal(sitemapChildCanonical('https://threkir.com', { kind: 'runs', shard: '0' }), 'https://threkir.com/sitemaps/runs-0.xml');
	assert.match(xml, /<\/sitemapindex>\s*$/);
});

test('renderSitemapFile — 50,000 of the longest entries a kind produces fit the byte limit', () => {
	const loc = buildRunShareCanonical('https://threkir.com', 'ffffffff-ffff-4fff-bfff-ffffffffffff').replace('/run/', '/course/us-va/' + 'p'.repeat(60) + '/' + 'c'.repeat(60) + '/');
	const entries = Array.from({ length: SITEMAP_MAX_URLS }, () => ({
		loc,
		lastmod: '2027-01-02T00:00:00.000000+00:00',
		changefreq: 'monthly' as const,
		priority: 0.7,
	}));
	const body = renderSitemapFile(entries);
	assert.ok(new TextEncoder().encode(body).length < SITEMAP_MAX_BYTES);
});

test('renderSitemapFile — refuses a file past 50,000 URLs rather than cut it', () => {
	const entries = Array.from({ length: SITEMAP_MAX_URLS + 1 }, (_, i) => ({ loc: `https://threkir.com/share/run/${i}` }));
	assert.throws(() => renderSitemapFile(entries), /exceeds the 50000 limit/);
});

test('renderSitemapFile — refuses a file past 50 MB', () => {
	const entries = Array.from({ length: 1_000 }, (_, i) => ({ loc: `https://threkir.com/${i}/${'x'.repeat(60_000)}` }));
	assert.throws(() => renderSitemapFile(entries), /bytes in one file exceeds/);
});
