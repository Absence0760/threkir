// Thin SvelteKit wrapper around `#lib/training/plan_request/handler`.
// Dev-only — under @sveltejs/adapter-static this `+server.ts` is not
// built; in production the same handler is reached via the coach
// Lambda's `/plan-request` route (decisions.md § 53).
//
// Mirrors the bypass + body-cap + auth-header conventions of the sibling
// `/api/coach/route-request/+server.ts`.

import type { RequestHandler } from './$types';
import { PUBLIC_AI_PLAN_ENABLED, PUBLIC_SUPABASE_ANON_KEY, PUBLIC_SUPABASE_URL } from '$app/env/public';
import { isTruthyFlagValue } from '#lib/core/env_flag.ts';
import { ANTHROPIC_API_KEY, BYPASS_PAYWALL, NODE_ENV } from '$app/env/private';
import { handlePlanRequest } from '#lib/training/plan_request/handler.ts';
import { checkBodyByteLimit, PLAN_REQUEST_BODY_LIMIT_BYTES } from '#lib/coach/body.ts';

export const prerender = false;

export const POST: RequestHandler = async ({ request }) => {
	const rawArr = await request.arrayBuffer();
	const sizeCheck = checkBodyByteLimit(rawArr, PLAN_REQUEST_BODY_LIMIT_BYTES);
	if (!sizeCheck.ok) {
		return new Response(JSON.stringify({ error: sizeCheck.error }), {
			status: sizeCheck.status,
			headers: { 'content-type': 'application/json' },
		});
	}
	const rawText = new TextDecoder('utf-8').decode(rawArr);

	let rawBody: unknown;
	try {
		rawBody = rawText.length === 0 ? null : JSON.parse(rawText);
	} catch {
		return new Response(JSON.stringify({ error: 'invalid JSON' }), {
			status: 400,
			headers: { 'content-type': 'application/json' },
		});
	}

	// Same dev-only bypass gates as /api/coach (defence-in-depth — this
	// file is dropped from the static prod build):
	//   1. NODE_ENV must NOT be production.
	//   2. Supabase URL MUST point at the local stack.
	//   3. BYPASS_PAYWALL must be the literal string 'true'.
	const isLocalSupabase =
		PUBLIC_SUPABASE_URL.includes('127.0.0.1') ||
		PUBLIC_SUPABASE_URL.includes('localhost');
	const isProdEnv = NODE_ENV === 'production';
	const bypassPaywallEnabled =
		!isProdEnv && isLocalSupabase && BYPASS_PAYWALL === 'true';

	const result = await handlePlanRequest(
		request.headers.get('x-supabase-authorization'),
		rawBody,
		{
			enabled: isTruthyFlagValue(PUBLIC_AI_PLAN_ENABLED),
			anthropicApiKey: ANTHROPIC_API_KEY,
			publicSupabaseUrl: PUBLIC_SUPABASE_URL,
			publicSupabaseAnonKey: PUBLIC_SUPABASE_ANON_KEY,
			bypassPaywallEnabled,
		},
	);

	return new Response(result.body, { status: result.status, headers: result.headers });
};
