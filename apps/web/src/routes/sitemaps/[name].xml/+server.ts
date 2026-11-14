import { error } from '@sveltejs/kit';
import type { EntryGenerator, RequestHandler } from './$types';
import {
	allSitemapChildren,
	learnEntries,
	parseSitemapChild,
	renderSitemapFile,
	sitemapChildName,
	sitemapShardOf,
	topLevelEntries,
} from '#lib/share/sitemap.ts';
import { SITEMAP_HEADERS, sitemapBase, sitemapRows } from '#lib/share/sitemap_server.ts';
import { listGuides } from '#lib/learn/guides.ts';
import { CATEGORIES } from '#lib/learn/categories.ts';

// One child file of the /sitemap.xml index. `pages` holds the top-level
// surfaces and the learn hub; `<kind>-<hex>` holds the public rows of that
// kind whose uuid starts with that digit. The set of names is fixed, so the
// prerender enumerates every one without reading the database.
export const prerender = true;

export const entries: EntryGenerator = () =>
	allSitemapChildren().map((child) => ({ name: sitemapChildName(child) }));

export const GET: RequestHandler = async ({ params }) => {
	const child = parseSitemapChild(params.name);
	if (!child) error(404, 'Not found');
	const base = sitemapBase();
	if (child.kind === 'pages') {
		// Build-time constants from the static guide index, so they ship even
		// when the database is unreachable.
		const learn = learnEntries(
			base,
			listGuides().map((g) => ({ slug: g.slug, updated: g.updated })),
			CATEGORIES.map((c) => c.id),
		);
		return new Response(renderSitemapFile([...topLevelEntries(base), ...learn]), {
			headers: SITEMAP_HEADERS,
		});
	}
	const rows = (await sitemapRows(child.kind)).filter((r) => sitemapShardOf(r.id) === child.shard);
	return new Response(renderSitemapFile(rows.map((r) => r.entry)), { headers: SITEMAP_HEADERS });
};
