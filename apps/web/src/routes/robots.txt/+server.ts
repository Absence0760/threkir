import type { RequestHandler } from './$types';
import { buildRobotsTxt, ROBOTS_HEADERS } from '#lib/share/robots.ts';
import { sitemapBase } from '#lib/share/sitemap_server.ts';

// Prerendered into `build/robots.txt`, a plain file served from S3 like
// /sitemap.xml. Its Sitemap line is built on the same origin as the sitemap's
// own <loc>s.
export const prerender = true;

export const GET: RequestHandler = () =>
	new Response(buildRobotsTxt(sitemapBase()), { headers: ROBOTS_HEADERS });
