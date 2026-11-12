/// The hourly re-check of verified clubs' domain proof; the behaviour lives in
/// handler.ts behind injected deps, so handler.test.ts drives it without a
/// stack.

import { createClient } from 'npm:@supabase/supabase-js@2.119.0';
import type { Database } from '../_shared/database.ts';
import { withSentry } from '../_shared/sentry.ts';
import { secretKey } from '../_shared/api_keys.ts';
import { makeRecheckHandler } from './handler.ts';

Deno.serve(withSentry('club-verification-recheck', makeRecheckHandler({
	getEnv: (name) => Deno.env.get(name),
	serviceClient: () => createClient<Database>(Deno.env.get('SUPABASE_URL')!, secretKey()),
	proof: { fetch: (input, init) => fetch(input, init) },
})));
