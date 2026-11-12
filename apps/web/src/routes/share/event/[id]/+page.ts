import type { PageLoad } from './$types';
import { PUBLIC_SITE_URL, PUBLIC_SUPABASE_ANON_KEY, PUBLIC_SUPABASE_URL } from '$app/env/public';
import { lookupSharedEvent } from '#lib/share/share_event_lookup.ts';
import { siteOrigin } from '#lib/core/site_url.ts';

// Per-request SSR via the production entity-SSR Lambda — CloudFront
// routes /share/event/* to the Lambda Function URL, which fetches the
// public event + bakes the per-event <title> + Open Graph + canonical +
// Event JSON-LD into the response HTML before crawlers can see it. This
// PageLoad still runs under the SvelteKit dev server so the page works
// locally without the Lambda.
//
// `prerender = false` opts out of the module-level `prerender: { default:
// true }` so adapter-static doesn't bake per-id HTML at build time (an
// event flips public/private after the build, and there's no bounded set).
export const prerender = false;


export const load: PageLoad = async ({ params }) => {
	const lookup = await lookupSharedEvent(
		params.id,
		PUBLIC_SUPABASE_URL && PUBLIC_SUPABASE_ANON_KEY
			? { supabaseUrl: PUBLIC_SUPABASE_URL, supabaseAnonKey: PUBLIC_SUPABASE_ANON_KEY }
			: null,
	);
	const siteUrl = siteOrigin(PUBLIC_SITE_URL);
	return { id: params.id, event: lookup.event, siteUrl };
};
