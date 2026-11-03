import type { RequestHandler } from './$types';
import { PUBLIC_SUPABASE_ANON_KEY, PUBLIC_SUPABASE_URL } from '$app/env/public';
import { renderChallengeOgPng } from '#lib/share/og_challenge_png.ts';

// Per-challenge og:image PNG, rendered at request time. In prod CloudFront
// routes /og/challenge/* to the share-entity Lambda (same renderChallengeOgPng
// helper); this endpoint owns the path under the dev server.
export const prerender = false;

export const GET: RequestHandler = async ({ params }) => {
	// A challenge that can't be loaded renders the generic branded card, so
	// the image is a 200 and an unfurl never breaks.
	const png = await renderChallengeOgPng(
		params.id,
		PUBLIC_SUPABASE_URL && PUBLIC_SUPABASE_ANON_KEY
			? { supabaseUrl: PUBLIC_SUPABASE_URL, supabaseAnonKey: PUBLIC_SUPABASE_ANON_KEY }
			: null,
	);
	return new Response(new Uint8Array(png), {
		headers: {
			'content-type': 'image/png',
			'cache-control': 'public, max-age=300, s-maxage=300, stale-while-revalidate=60',
		},
	});
};
