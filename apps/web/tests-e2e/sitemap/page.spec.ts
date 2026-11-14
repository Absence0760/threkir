import { expect, test } from '../fixtures/test';

import { RUNNER_PUBLIC_ROUTE_ID, RUNNER_PUBLIC_RUN_ID } from '../fixtures/seeded-data';
import { allSitemapLocs, sitemapChildPaths } from '../fixtures/sitemap';

/**
 * /sitemap.xml — the prerendered, build-time sitemap index.
 *
 * Crawlers read this file to discover every public share URL the
 * app exposes. It is a <sitemapindex> (`src/routes/sitemap.xml/+server.ts`)
 * over child <urlset> files (`src/routes/sitemaps/[name].xml/+server.ts`),
 * all `prerender = true`, so they are baked into the static build (no
 * Lambda per-crawl). Test surface here pins:
 *   - The index exists at /sitemap.xml and every child it lists is a
 *     valid <urlset> on the same canonical origin.
 *   - Content-Type is application/xml.
 *   - Top-level surfaces (/, /feed, /routes?tab=explore, /segments) appear.
 *   - At least one seeded public run + route appear via their share URLs.
 *   - robots.txt advertises the sitemap by an absolute URL so crawlers find it.
 */

test.describe('/sitemap.xml — prerendered SEO sitemap', () => {
	// Anon by design — sitemap is public regardless of auth state.
	test.use({ storageState: { cookies: [], origins: [] } });

	test('the index is application/xml listing child sitemaps', async ({ request }) => {
		const res = await request.get('/sitemap.xml');
		expect(res.status()).toBe(200);
		expect(res.headers()['content-type'] ?? '').toMatch(/application\/xml/);
		const body = await res.text();
		expect(body).toMatch(/^<\?xml version="1\.0" encoding="UTF-8"\?>/);
		expect(body).toContain('<sitemapindex xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">');
		expect(body.trim()).toMatch(/<\/sitemapindex>$/);
		const locs = [...body.matchAll(/<loc>([^<]+)<\/loc>/g)].map((m) => m[1]);
		expect(locs[0]).toMatch(/^https?:\/\/[^/]+\/sitemaps\/pages\.xml$/);
		for (const loc of locs) expect(loc).toMatch(/^https?:\/\/[^/]+\/sitemaps\/[a-z]+(-[0-9a-f])?\.xml$/);
		// One canonical origin across the index, so no child points at www.
		expect(new Set(locs.map((l) => new URL(l).origin)).size).toBe(1);
	});

	test('every child is an application/xml <urlset>', async ({ request }) => {
		for (const path of await sitemapChildPaths(request)) {
			const res = await request.get(path);
			expect(res.status(), path).toBe(200);
			expect(res.headers()['content-type'] ?? '', path).toMatch(/application\/xml/);
			const body = await res.text();
			expect(body, path).toContain('<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">');
			expect(body.trim(), path).toMatch(/<\/urlset>$/);
		}
	});

	test('a child name outside the fixed set is a 404', async ({ request }) => {
		expect((await request.get('/sitemaps/profiles-a.xml')).status()).toBe(404);
	});

	test('top-level surfaces are present', async ({ request }) => {
		const body = (await allSitemapLocs(request)).map((l) => `<loc>${l}</loc>`).join('\n');
		// Each of the four top-level surfaces should appear. The host
		// is whatever PUBLIC_SITE_URL is set to at build time (defaults
		// to threkir.com); match the path suffix to stay env-agnostic.
		expect(body).toMatch(/<loc>https?:\/\/[^<]+\/<\/loc>/);
		expect(body).toMatch(/<loc>https?:\/\/[^<]+\/feed<\/loc>/);
		expect(body).toMatch(/<loc>https?:\/\/[^<]+\/routes\?tab=explore<\/loc>/);
		// The segment catalogue — world-readable curated content that was
		// crawl-invisible until decisions.md § 677.
		expect(body).toMatch(/<loc>https?:\/\/[^<]+\/segments<\/loc>/);
	});

	test('individual segment pages are NOT enumerated', async ({ request }) => {
		// A per-segment page is a leaderboard of named runners; enumerating
		// them builds the people-directory that keeps profiles out of the
		// manifest. Only the catalogue index is listed.
		const body = (await allSitemapLocs(request)).map((l) => `<loc>${l}</loc>`).join('\n');
		expect(body).not.toMatch(/<loc>https?:\/\/[^<]+\/segments\/[^<]+<\/loc>/);
	});

	test('seeded public run + route appear as share URLs', async ({ request }) => {
		const body = (await allSitemapLocs(request)).map((l) => `<loc>${l}</loc>`).join('\n');
		expect(body).toContain(`/share/run/${RUNNER_PUBLIC_RUN_ID}`);
		expect(body).toContain(`/share/route/${RUNNER_PUBLIC_ROUTE_ID}`);
	});

	test('robots.txt advertises the sitemap location', async ({ request }) => {
		const res = await request.get('/robots.txt');
		expect(res.status()).toBe(200);
		expect(res.headers()['content-type'] ?? '').toMatch(/text\/plain/);
		const body = await res.text();
		expect(body).toMatch(/^Disallow: \/dashboard$/m);
		// Absolute, per RFC 9309: a relative Sitemap line is ignored by crawlers.
		// Its origin is PUBLIC_SITE_URL's, not the dev host's, exactly like the
		// sitemap's own <loc>s.
		const lines = body.split('\n').filter((l) => l.startsWith('Sitemap:'));
		expect(lines).toHaveLength(1);
		const url = new URL(lines.join('').replace(/^Sitemap:\s*/, ''));
		expect(url.pathname).toBe('/sitemap.xml');
		expect(url.hostname.startsWith('www.')).toBe(false);
	});

	test('sitemap does NOT include private / signed-in surfaces', async ({ request }) => {
		// /dashboard, /history, /plans, /settings/* are auth-gated; they
		// must not appear in the crawler-visible sitemap. A regression
		// that listed them would invite Googlebot 401s + waste crawl
		// budget. Pin the negative — these stay out of /sitemap.xml.
		// /runs is the auth-gated run list (parallel to /history); it must
		// stay out too so crawlers never land on a 401.
		const body = (await allSitemapLocs(request)).map((l) => `<loc>${l}</loc>`).join('\n');
		expect(body).not.toMatch(/<loc>https?:\/\/[^<]+\/dashboard<\/loc>/);
		expect(body).not.toMatch(/<loc>https?:\/\/[^<]+\/history<\/loc>/);
		expect(body).not.toMatch(/<loc>https?:\/\/[^<]+\/runs<\/loc>/);
		expect(body).not.toMatch(/<loc>https?:\/\/[^<]+\/plans<\/loc>/);
		expect(body).not.toMatch(/<loc>https?:\/\/[^<]+\/settings/);
	});

	test('every <url> entry carries a single <loc>', async ({ request }) => {
		// Sitemaps spec requires one <loc> per <url>. A bug in the
		// builder that emitted two would still parse but confuse
		// crawlers. Pin the invariant by counting tags in every child.
		for (const path of await sitemapChildPaths(request)) {
			const body = await (await request.get(path)).text();
			const urlCount = (body.match(/<url>/g) ?? []).length;
			const locCount = (body.match(/<loc>/g) ?? []).length;
			expect(urlCount, path).toBe(locCount);
		}
	});

	test('no URL is listed twice', async ({ request }) => {
		const locs = await allSitemapLocs(request);
		expect(locs.length).toBeGreaterThan(0);
		expect(new Set(locs).size).toBe(locs.length);
	});

	test('every <loc> is a fully-qualified https URL', async ({ request }) => {
		// Sitemaps spec: each <loc> must be a fully-qualified URL.
		// Build-time path-only URLs slip through XML validation but
		// fail every major crawler.
		const body = (await allSitemapLocs(request)).map((l) => `<loc>${l}</loc>`).join('\n');
		const matches = body.match(/<loc>([^<]+)<\/loc>/g) ?? [];
		expect(matches.length).toBeGreaterThan(0);
		for (const m of matches) {
			expect(m).toMatch(/<loc>https?:\/\/[^<]+<\/loc>/);
		}
	});
});
