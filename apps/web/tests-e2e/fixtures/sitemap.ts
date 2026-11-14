import { expect, type APIRequestContext } from '@playwright/test';

/**
 * /sitemap.xml is a <sitemapindex>; the URLs live in its child files under
 * /sitemaps/. The child <loc>s carry PUBLIC_SITE_URL's origin, not the dev
 * server's, so each is fetched by its path against the lane's baseURL.
 */
export async function sitemapChildPaths(request: APIRequestContext): Promise<string[]> {
	const res = await request.get('/sitemap.xml');
	expect(res.status()).toBe(200);
	const body = await res.text();
	return [...body.matchAll(/<loc>([^<]+)<\/loc>/g)].map((m) => new URL(m[1]).pathname);
}

/** Every <loc> across every child the index lists, in index order. */
export async function allSitemapLocs(request: APIRequestContext): Promise<string[]> {
	const locs: string[] = [];
	for (const path of await sitemapChildPaths(request)) {
		const res = await request.get(path);
		expect(res.status(), path).toBe(200);
		const body = await res.text();
		locs.push(...[...body.matchAll(/<loc>([^<]+)<\/loc>/g)].map((m) => m[1]));
	}
	return locs;
}
