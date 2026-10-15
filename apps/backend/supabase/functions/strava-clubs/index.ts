/// Wiring for `strava-clubs`; the behaviour and its rationale live in
/// handler.ts.
///
/// Two clients, on purpose. Everything that reads as the caller — who they
/// are, their own Strava tokens, which linked Threkir clubs they may see —
/// goes through the user-scoped client, so RLS decides. Only the link write
/// uses the secret key, because `set_club_strava_link` is granted to
/// service_role alone; it re-checks the caller's Threkir club role itself.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.110.0';
import type { Database } from '../_shared/database.ts';
import { checkRateLimit } from '../_shared/rate_limit.ts';
import { withSentry } from '../_shared/sentry.ts';
import { refreshStravaToken } from '../_shared/strava.ts';
import { publishableKey, secretKey } from '../_shared/api_keys.ts';
import { type LinkOutcome, makeStravaClubsHandler } from './handler.ts';

const LINK_OUTCOMES: readonly LinkOutcome[] = ['ok', 'not_club_admin', 'already_linked', 'invalid_strava_club'];

Deno.serve(withSentry('strava-clubs', (req: Request) => {
	const url = Deno.env.get('SUPABASE_URL')!;
	const authHeader = req.headers.get('Authorization') ?? '';
	const userClient = createClient<Database>(url, publishableKey(), {
		global: { headers: { Authorization: authHeader } },
	});
	const service = () => createClient<Database>(url, secretKey());

	return makeStravaClubsHandler({
		authenticate: async () => {
			const { data } = await userClient.auth.getUser();
			return data.user?.id ?? null;
		},
		rateLimit: (userId, bucket, max, windowSeconds) =>
			checkRateLimit(userClient, userId, bucket, max, windowSeconds, { failClosed: true }),
		getTokens: async (userId) => {
			const { data, error } = await userClient.rpc('get_integration_tokens', {
				p_user_id: userId,
				p_provider: 'strava',
			});
			if (error) return null;
			return data?.[0] ?? null;
		},
		refreshToken: (userId, refreshToken) => refreshStravaToken(userClient, userId, refreshToken),
		linkedClubs: async (ids) => {
			const { data, error } = await userClient
				.from('clubs')
				.select('id, slug, name, strava_club_id')
				.in('strava_club_id', ids);
			// The Strava list is still worth showing without the links, so a failed
			// lookup degrades to "nothing linked" rather than failing the request.
			if (error) console.warn('strava-clubs: linked-club lookup failed', { code: error.code });
			if (error || !data) return [];
			return data.flatMap((c) =>
				c.strava_club_id === null ? [] : [{ id: c.id, slug: c.slug, name: c.name, strava_club_id: c.strava_club_id }]
			);
		},
		setLink: async (userId, clubId, stravaClubId) => {
			const { data, error } = await service().rpc('set_club_strava_link', {
				p_actor: userId,
				p_club_id: clubId,
				p_strava_club_id: stravaClubId,
			});
			if (error) {
				console.error('strava-clubs: set_club_strava_link failed', { code: error.code });
				return 'error';
			}
			return (LINK_OUTCOMES as readonly string[]).includes(data) ? (data as LinkOutcome) : 'error';
		},
		fetch: (input, init) => fetch(input, init),
		now: () => Date.now(),
	})(req);
}));
