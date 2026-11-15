/// The body of the prerendered /robots.txt (`src/routes/robots.txt/+server.ts`).
///
/// It is built rather than served from `static/` because the `Sitemap:` line
/// must be an absolute URL (RFC 9309 § 2.4, sitemaps.org § "Specifying the
/// Sitemap location in your robots.txt file"), and the origin is
/// `PUBLIC_SITE_URL` folded through `siteOrigin` — the same base every
/// sitemap `<loc>` is built on, so robots.txt and the sitemap cannot name two
/// different hosts.

import { normaliseBase } from './sitemap';

/// Paths every crawler is kept out of. The authenticated surfaces bounce an
/// anonymous visitor to /login, so disallowing them costs nothing and trims
/// crawl budget. /help and /nutrition are readable signed out (in-app help; the
/// fuelling planner a Coach hands off to) but carry `noindex`; the indexable
/// guides are /learn.
export const ROBOTS_DISALLOW = [
	'/dashboard',
	'/settings',
	'/coach',
	'/plans',
	'/runs',
	'/clubs',
	'/help',
	'/nutrition',
	'/auth',
] as const;

export function buildRobotsTxt(origin: string): string {
	const lines = [
		'User-agent: *',
		'Allow: /',
		...ROBOTS_DISALLOW.map((path) => `Disallow: ${path}`),
		'',
		`Sitemap: ${normaliseBase(origin)}/sitemap.xml`,
	];
	return lines.join('\n') + '\n';
}

export const ROBOTS_HEADERS = {
	'content-type': 'text/plain; charset=utf-8',
	'cache-control': 'public, max-age=3600',
};
