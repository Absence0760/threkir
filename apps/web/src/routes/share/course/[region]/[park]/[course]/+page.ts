import type { PageLoad } from './$types';
import { PUBLIC_SITE_URL, PUBLIC_SUPABASE_ANON_KEY, PUBLIC_SUPABASE_URL } from '$app/env/public';
import { courseShareKey, lookupSharedCourse } from '#lib/share/share_course_lookup.ts';
import { siteOrigin } from '#lib/core/site_url.ts';

// Per-request SSR via the production entity-SSR Lambda — CloudFront
// routes /share/course/* to the Lambda Function URL, which fetches the
// public park course + bakes the per-course <title> + Open Graph +
// canonical + SportsActivityLocation JSON-LD into the response HTML before
// crawlers can see it. This PageLoad still runs under the SvelteKit dev
// server so the page works locally without the Lambda.
export const prerender = false;

export const load: PageLoad = async ({ params }) => {
	const key = `${params.region}/${params.park}/${params.course}`;
	const lookup = await lookupSharedCourse(
		key,
		PUBLIC_SUPABASE_URL && PUBLIC_SUPABASE_ANON_KEY
			? { supabaseUrl: PUBLIC_SUPABASE_URL, supabaseAnonKey: PUBLIC_SUPABASE_ANON_KEY }
			: null,
	);
	const siteUrl = siteOrigin(PUBLIC_SITE_URL);
	const course = lookup.course;
	return {
		key: course ? courseShareKey(course.park.region_code, course.park.slug, course.slug) : key,
		course,
		siteUrl,
	};
};
