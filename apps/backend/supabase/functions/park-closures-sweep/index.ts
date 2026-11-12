/// The daily NPS alerts sweep over national-park courses; the behaviour lives
/// in handler.ts behind injected deps, so handler.test.ts drives it without a
/// stack or a network.

import { createClient } from 'npm:@supabase/supabase-js@2.119.0';
import type { Database } from '../_shared/database.ts';
import { withSentry } from '../_shared/sentry.ts';
import { secretKey } from '../_shared/api_keys.ts';
import { makeParkClosuresSweepHandler } from './handler.ts';

Deno.serve(withSentry('park-closures-sweep', makeParkClosuresSweepHandler({
  getEnv: (name) => Deno.env.get(name),
  serviceClient: () => createClient<Database>(Deno.env.get('SUPABASE_URL')!, secretKey()),
  fetch: (input, init) => fetch(input, init),
  sleep: (ms) => new Promise((resolve) => setTimeout(resolve, ms)),
})));
