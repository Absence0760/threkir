/// The scheduled RunSignUp race-calendar sweep (decisions § 1901): pg_cron
/// calls it every five minutes through pg_net with the CRON_SECRET bearer, and
/// each run syncs one state over one 14-day window into `race_listings`.
///
/// The handler lives in handler.ts behind injected deps, so handler.test.ts can
/// drive it without a stack.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.110.0';
import type { Database } from '../_shared/database.ts';
import { withSentry } from '../_shared/sentry.ts';
import { secretKey } from '../_shared/api_keys.ts';
import { makeRaceListingsSweepHandler } from './handler.ts';

Deno.serve(withSentry('race-listings-sweep', makeRaceListingsSweepHandler({
  getEnv: (name) => Deno.env.get(name),
  serviceClient: () => createClient<Database>(Deno.env.get('SUPABASE_URL')!, secretKey()),
  fetch: (input, init) => fetch(input, init),
  now: () => Date.now(),
})));
