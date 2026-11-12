import type { PageLoad } from './$types';
import { PUBLIC_SITE_URL, PUBLIC_SUPABASE_ANON_KEY, PUBLIC_SUPABASE_URL } from '$app/env/public';
import { lookupSharedPlan } from '#lib/share/share_plan_lookup.ts';
import { siteOrigin } from '#lib/core/site_url.ts';

// Per-request SSR via the production entity-SSR Lambda: CloudFront routes
// /share/plan/* to the share-entity Function URL, which bakes the per-plan
// <title> + Open Graph + canonical + JSON-LD into the HTML before a crawler or
// chat-app unfurler (neither runs the SPA's JS) can see it.
//
// `prerender = false` opts out of adapter-static's build-time bake: a plan can
// be unpublished after the build. This PageLoad still runs under the dev
// server so /share/plan/[id] works locally without the Lambda; the plan is
// read through the redacted public_plan_share RPC, which anon may call.
export const prerender = false;

export const load: PageLoad = async ({ params }) => {
	const lookup = await lookupSharedPlan(
		params.id,
		PUBLIC_SUPABASE_URL && PUBLIC_SUPABASE_ANON_KEY
			? { supabaseUrl: PUBLIC_SUPABASE_URL, supabaseAnonKey: PUBLIC_SUPABASE_ANON_KEY }
			: null,
	);
	return {
		id: params.id,
		plan: lookup.plan,
		siteUrl: siteOrigin(PUBLIC_SITE_URL),
	};
};
