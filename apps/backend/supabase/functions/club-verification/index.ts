/// Wiring for `club-verification`; the behaviour and its rationale live in
/// handler.ts.
///
/// Two clients, on purpose: the request is read as the caller, so RLS decides
/// who may check it; only the result write uses the secret key, because
/// `record_club_verification_check` is granted to service_role alone.

import { createClient } from 'npm:@supabase/supabase-js@2.118.0';
import type { Database } from '../_shared/database.ts';
import { checkRateLimit } from '../_shared/rate_limit.ts';
import { withSentry } from '../_shared/sentry.ts';
import { withCors } from '../_shared/cors.ts';
import { publishableKey, secretKey } from '../_shared/api_keys.ts';
import { CHECKS_PER_HOUR, makeClubVerificationHandler, recordArgs } from './handler.ts';

Deno.serve(withCors(withSentry('club-verification', (req: Request) => {
	const url = Deno.env.get('SUPABASE_URL')!;
	const authHeader = req.headers.get('Authorization') ?? '';
	const userClient = createClient<Database>(url, publishableKey(), {
		global: { headers: { Authorization: authHeader } },
	});

	return makeClubVerificationHandler({
		authenticate: async () => {
			const { data } = await userClient.auth.getUser();
			return data.user?.id ?? null;
		},
		rateLimit: (userId) =>
			checkRateLimit(userClient, userId, 'club-verification:check', CHECKS_PER_HOUR, 3600, { failClosed: true }),
		loadRequest: async (requestId) => {
			const { data, error } = await userClient
				.from('club_verification_requests')
				.select('id, domain, token, status')
				.eq('id', requestId)
				.maybeSingle();
			if (error) console.error('club-verification: request read failed', { code: error.code });
			return data ?? null;
		},
		record: async (requestId, result) => {
			const args = recordArgs(result);
			const { data, error } = await createClient<Database>(url, secretKey()).rpc('record_club_verification_check', {
				p_request_id: requestId,
				p_method: args.method,
				p_ok: args.ok,
				p_detail: args.detail,
			});
			if (error) {
				console.error('club-verification: record failed', { code: error.code });
				return null;
			}
			return data;
		},
		proof: { fetch: (input, init) => fetch(input, init) },
	})(req);
})));
