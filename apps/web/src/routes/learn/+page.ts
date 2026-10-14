import type { PageLoad } from './$types';
import { PUBLIC_SITE_URL } from '$app/env/public';
import { listGuides, nonEmptyCategories } from '#lib/learn/guides.ts';
import { siteOrigin } from '#lib/core/site_url.ts';

// The Learn hub is finite, evergreen, and known at build time, so it
// prerenders to a single static HTML file served by CloudFront from S3
// with zero runtime cost — unlike /share/*, whose per-id content is
// mutable and Lambda-rendered. See docs/features/learn.md.
export const prerender = true;


export const load: PageLoad = () => {
	const siteUrl = siteOrigin(PUBLIC_SITE_URL);
	return {
		siteUrl,
		guides: listGuides(),
		categories: nonEmptyCategories(),
	};
};
