import type { RequestHandler } from './$types';
import { webCheckoutAvailable } from '$lib/billing/revenuecat';
import { coachEnabled } from '$lib/coach/coach_flag';
import { routeGenEnabled } from '$lib/routes/route_gen_flag';

// Build-time capability manifest for the native clients. `adapter-static`
// prerenders this once (like /sitemap.xml) into a plain file in `build/`,
// so CloudFront serves it from S3 with no Lambda invocation.
//
// Why it exists: the Pro storefront is only honest when at least one Pro
// perk is actually live, and the two flags that decide that
// (PUBLIC_COACH_ENABLED, PUBLIC_ROUTE_GEN_ENABLED) are web-deploy env —
// baked into the web bundle, invisible to a Flutter binary sitting in the
// App Store. Without a channel the mobile storefront would sell a
// subscription the deploy can't deliver (decisions §466). This endpoint is
// that channel: the SAME two gate functions the /settings/upgrade card
// reads, published as JSON on the origin the app already talks to for
// /api/coach. There is no second flag to keep in sync — flipping the env
// and redeploying web moves both storefronts at once.
//
// `web_checkout` is the third answer the storefront reads: whether this
// deploy can take a Pro payment on the web (`webCheckoutAvailable()`, the
// same gate the /settings/upgrade buy button renders under). A mobile build
// that cannot sell through its own store falls back to the web page only
// when this is true; otherwise that page could only point at the iPhone app
// (decisions § 1826). It is not a perk and sells nothing on its own.
//
// Public by construction: every value derives from a PUBLIC_ var present in
// the client bundle every visitor downloads. Nothing here is a secret.
//
// The release workflow gives this file the short HTML-style cache-control
// rather than the immutable asset one, so turning a perk off propagates.
export const prerender = true;

export const GET: RequestHandler = () =>
	new Response(
		JSON.stringify({
			coach: coachEnabled(),
			route_gen: routeGenEnabled(),
			web_checkout: webCheckoutAvailable(),
		}),
		{
			headers: {
				'content-type': 'application/json',
				'cache-control': 'public, max-age=60, must-revalidate',
			},
		},
	);
