import type { RequestHandler } from './$types';
import {
	buildSitemapIndex,
	SITEMAP_KINDS,
	SITEMAP_SHARDS,
	sitemapShardOf,
	type SitemapChild,
} from '#lib/share/sitemap.ts';
import { SITEMAP_HEADERS, sitemapBase, sitemapRows } from '#lib/share/sitemap_server.ts';

// Build-time sitemap index. `adapter-static` runs this once during the
// production build because of `prerender = true`; the resulting
// /sitemap.xml is a plain file in `build/`, served from S3 by CloudFront.
//
// It lists the child files under /sitemaps/ (`[name].xml/+server.ts`): the
// fixed pages, then each kind split by the first hex digit of the row id, so
// no one file can pass the protocol's 50,000-URL / 50 MB limit. A shard with
// no rows is left out of the index; its file is still emitted, empty.
export const prerender = true;

export const GET: RequestHandler = async () => {
	const children: SitemapChild[] = [{ kind: 'pages' }];
	const loaded = await Promise.all(SITEMAP_KINDS.map((kind) => sitemapRows(kind)));
	SITEMAP_KINDS.forEach((kind, i) => {
		const present = new Set(loaded[i].map((r) => sitemapShardOf(r.id)));
		for (const shard of SITEMAP_SHARDS) {
			if (present.has(shard)) children.push({ kind, shard });
		}
	});
	return new Response(buildSitemapIndex(sitemapBase(), children), { headers: SITEMAP_HEADERS });
};
