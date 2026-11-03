import type { PageLoad } from './$types';
import { PUBLIC_SITE_URL, PUBLIC_SUPABASE_ANON_KEY, PUBLIC_SUPABASE_URL } from '$app/env/public';
import { lookupSharedChallenge } from '#lib/share/share_challenge_lookup.ts';
import { siteOrigin } from '#lib/core/site_url.ts';

// Per-request SSR via the production share-entity Lambda — CloudFront routes
// /share/challenge/* to it, and it bakes the per-challenge <title>, Open Graph,
// canonical and Event JSON-LD into the HTML before a crawler sees it. This
// PageLoad runs under the SvelteKit dev server so the page works locally.
export const prerender = false;

export const load: PageLoad = async ({ params }) => {
	const lookup = await lookupSharedChallenge(
		params.id,
		PUBLIC_SUPABASE_URL && PUBLIC_SUPABASE_ANON_KEY
			? { supabaseUrl: PUBLIC_SUPABASE_URL, supabaseAnonKey: PUBLIC_SUPABASE_ANON_KEY }
			: null,
	);
	const siteUrl = siteOrigin(PUBLIC_SITE_URL);
	return {
		id: params.id,
		challenge: lookup.challenge,
		creatorName: lookup.creatorName,
		leaders: lookup.leaders,
		siteUrl,
	};
};
