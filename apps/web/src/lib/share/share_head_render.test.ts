import { test } from 'node:test';
import assert from 'node:assert/strict';

import { buildShareRunMeta, renderShareRunHeadTags } from './share_run_meta';
import { buildShareRouteHead, renderShareRouteHeadTags } from './share_route_meta';
import { buildShareBadgeMeta } from './share_badge_meta';
import type { SharedRun } from './share_run_lookup';

// These heads are spliced, as raw HTML, into the page a share Lambda serves
// to anyone, crawler or person. Run captions, display names and route names
// are user-controlled, so the whole rendered string is the XSS boundary; the
// JSON-LD escaping alone is tested in share_meta.test.ts.

const SITE = 'https://threkir.com';
const ID = '11111111-1111-4111-8111-111111111111';
const EVIL = '"><script>alert(1)</script><img src=x onerror=alert(2)>';

/** Every <script> the head opens is the one JSON-LD block, and it closes once. */
function assertOnlyJsonLdScript(html: string) {
	const opens = html.match(/<script\b[^>]*>/g) ?? [];
	assert.deepEqual(opens, ['<script type="application/ld+json">']);
	assert.equal((html.match(/<\/script>/g) ?? []).length, 1);
	assert.ok(!/<img\b/i.test(html), 'no injected element');
	// Escaped hostile text may still READ "onerror=" inside <title> or an
	// attribute value; what must never exist is a real tag carrying it.
	const tags = html.replace(/<title>[^<]*<\/title>/g, '').replace(/"[^"]*"/g, '""');
	assert.ok(!/<[^>]*\sonerror=/i.test(tags), 'no injected attribute');
}

/** Each `content="..."` attribute holds no raw quote or angle bracket. */
function assertAttributesClosed(html: string) {
	for (const m of html.matchAll(/<meta [^>]*>/g)) {
		assert.match(m[0], /^<meta (name|property)="[^"<>]+" content="[^"<>]*">$/, m[0]);
	}
}

function run(over: Partial<SharedRun> = {}): SharedRun {
	return {
		id: ID,
		user_id: null,
		distance_m: 5000,
		duration_s: 1500,
		started_at: '2026-10-01T07:00:00Z',
		source: 'app',
		metadata: null,
		concluded_at: '2026-10-01T07:25:00Z',
		...over,
	};
}

test('run head: a hostile display name cannot open a tag or leave its attribute', () => {
	const html = renderShareRunHeadTags(
		buildShareRunMeta({ id: ID, run: run(), displayName: EVIL, siteUrl: SITE }),
	);
	assertOnlyJsonLdScript(html);
	assertAttributesClosed(html);
});

test('run head: a hostile run caption cannot close the JSON-LD block early', () => {
	const html = renderShareRunHeadTags(
		buildShareRunMeta({
			id: ID,
			run: run({ metadata: { title: '</script><script>alert(1)</script>' } }),
			displayName: 'Ana',
			siteUrl: SITE,
		}),
	);
	assertOnlyJsonLdScript(html);
	assertAttributesClosed(html);
});

test('run head: a non-string caption is ignored rather than stringified', () => {
	const meta = buildShareRunMeta({
		id: ID,
		run: run({ metadata: { title: { toString: () => 'injected' } } as unknown as Record<string, unknown> }),
		displayName: 'Ana',
		siteUrl: SITE,
	});
	assert.ok(!meta.title.includes('injected'));
	assert.ok(!meta.title.includes('[object'));
});

test('run head: canonical, og:url and og:image are absolute and single-slashed', () => {
	const meta = buildShareRunMeta({ id: ID, run: run(), displayName: null, siteUrl: `${SITE}//` });
	assert.equal(meta.canonical, `${SITE}/share/run/${ID}`);
	assert.equal(meta.ogImageUrl, `${SITE}/og/run/${ID}.png`);
	const html = renderShareRunHeadTags(meta);
	assert.ok(html.includes(`<link rel="canonical" href="${SITE}/share/run/${ID}">`));
	assert.ok(html.includes(`<meta property="og:url" content="${SITE}/share/run/${ID}">`));
});

test('run head: the same title reaches <title>, og:title and twitter:title', () => {
	const html = renderShareRunHeadTags(
		buildShareRunMeta({ id: ID, run: run(), displayName: 'Ana & Bo', siteUrl: SITE }),
	);
	const title = html.match(/<title>([^<]*)<\/title>/)?.[1];
	assert.ok(title && title.includes('Ana &amp; Bo'), title);
	assert.ok(html.includes(`<meta property="og:title" content="${title}">`));
	assert.ok(html.includes(`<meta name="twitter:title" content="${title}">`));
});

test('run head: a run with no data still renders a complete, safe head', () => {
	const html = renderShareRunHeadTags(
		buildShareRunMeta({ id: ID, run: null, displayName: null, siteUrl: SITE }),
	);
	assert.match(html, /<title>[^<]+<\/title>/);
	assert.ok(html.includes('og:image'));
	assertAttributesClosed(html);
});

test('run head: no start position or coordinate reaches the page', () => {
	const html = renderShareRunHeadTags(
		buildShareRunMeta({
			id: ID,
			run: run({ metadata: { title: 'Easy', start_lat: 51.5, start_lng: -0.12, lat: 51.5 } }),
			displayName: 'Ana',
			siteUrl: SITE,
		}),
	);
	assert.ok(!/51\.5|-0\.12|\b(latitude|longitude|geo)\b/i.test(html), 'location leaked into the head');
});

test('route head: a hostile route name cannot open a tag or leave its attribute', () => {
	const html = renderShareRouteHeadTags(
		buildShareRouteHead({ id: ID, route: { name: EVIL, distance_m: 5000 }, siteUrl: SITE }),
	);
	assertOnlyJsonLdScript(html);
	assertAttributesClosed(html);
});

test('route head: a name built to close the JSON-LD block cannot', () => {
	const html = renderShareRouteHeadTags(
		buildShareRouteHead({
			id: ID,
			route: { name: '</SCRIPT ><script>alert(1)</script>', distance_m: 5000 },
			siteUrl: SITE,
		}),
	);
	assertOnlyJsonLdScript(html);
	assert.ok(!/<\/script\s*>/i.test(html.slice(0, html.lastIndexOf('</script>'))));
});

test('route head: canonical and og:image are absolute and single-slashed', () => {
	const head = buildShareRouteHead({ id: ID, route: { name: 'Loop' }, siteUrl: `${SITE}/` });
	assert.equal(head.canonical, `${SITE}/share/route/${ID}`);
	assert.equal(head.ogImageUrl, `${SITE}/og/route/${ID}.png`);
	assert.ok(renderShareRouteHeadTags(head).includes(`content="${SITE}/og/route/${ID}.png"`));
});

test('route head: a null route still renders a complete, safe head', () => {
	const html = renderShareRouteHeadTags(buildShareRouteHead({ id: ID, route: null, siteUrl: SITE }));
	assert.match(html, /<title>[^<]+<\/title>/);
	assertOnlyJsonLdScript(html);
	assertAttributesClosed(html);
});

test('route head: an enormous name is clipped, not served whole', () => {
	const head = buildShareRouteHead({ id: ID, route: { name: 'x'.repeat(5000) }, siteUrl: SITE });
	assert.ok(head.title.length < 300, `title is ${head.title.length} chars`);
	assert.ok(head.jsonLd.length < 2000, `JSON-LD is ${head.jsonLd.length} chars`);
});

test('route head: og:type is website and the card is a large image', () => {
	const html = renderShareRouteHeadTags(
		buildShareRouteHead({ id: ID, route: { name: 'Loop' }, siteUrl: SITE }),
	);
	assert.ok(html.includes('<meta property="og:type" content="website">'));
	assert.ok(html.includes('<meta name="twitter:card" content="summary_large_image">'));
});

const BADGE = {
	id: ID,
	user_id: null,
	badge_key: 'distance_single',
	tier: 'gold',
	value_num: 42195,
	earned_at: '2026-10-01T00:00:00Z',
};

test('badge head: a hostile display name is escaped once rendered', () => {
	const html = renderShareRunHeadTags(
		buildShareBadgeMeta({ id: ID, badge: BADGE, displayName: EVIL, siteUrl: SITE }),
	);
	assert.ok(!/<script\b/i.test(html), 'a badge head carries no script at all');
	assert.ok(!/<img\b/i.test(html));
	assertAttributesClosed(html);
});

test('badge head: the title names the person and the badge, trimmed', () => {
	const meta = buildShareBadgeMeta({ id: ID, badge: BADGE, displayName: '  Ana  ', siteUrl: SITE });
	assert.match(meta.title, /^Ana earned the .+ badge$/);
	const anon = buildShareBadgeMeta({ id: ID, badge: BADGE, displayName: '   ', siteUrl: SITE });
	assert.match(anon.title, / — Achievement$/);
});

test('badge head: an unknown badge key or tier falls back to the generic page', () => {
	for (const badge of [{ ...BADGE, badge_key: 'not_a_badge' }, { ...BADGE, tier: 'diamond' }, null]) {
		const meta = buildShareBadgeMeta({ id: ID, badge, displayName: 'Ana', siteUrl: SITE });
		assert.equal(meta.title, 'Achievements — Threkir');
		assert.equal(meta.description, "This badge isn't available.");
	}
});

test('badge head: canonical and og:image are absolute and single-slashed', () => {
	const meta = buildShareBadgeMeta({ id: ID, badge: BADGE, displayName: null, siteUrl: `${SITE}/` });
	assert.equal(meta.canonical, `${SITE}/share/badge/${ID}`);
	assert.equal(meta.ogImageUrl, `${SITE}/og/badge/${ID}.png`);
});
