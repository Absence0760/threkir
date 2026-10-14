/// Race-result import: RunSignUp, UltraSignup, ChronoTrack, or a pasted
/// result, onto the caller's own runs (docs/features/integrations.md). The
/// handler lives in handler.ts behind injected deps, so handler.test.ts can
/// drive it without a stack.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.110.0';
import type { Database } from '../_shared/database.ts';
import { withSentry } from '../_shared/sentry.ts';
import { publishableKey } from '../_shared/api_keys.ts';
import { makeRaceResultsImportHandler } from './handler.ts';

Deno.serve(withSentry('race-results-import', makeRaceResultsImportHandler({
  getEnv: (name) => Deno.env.get(name),
  userClient: (authHeader) =>
    createClient<Database>(
      Deno.env.get('SUPABASE_URL')!,
      publishableKey(),
      { global: { headers: { Authorization: authHeader } } },
    ),
  fetch: (input, init) => fetch(input, init),
})));
