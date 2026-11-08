/// Server-side catalogue segment matching (issue #1313 Phase 1, decisions
/// § 2392). The Go job worker claims a `segment_match` job and POSTs its
/// payload here with its server key; this scores the run (or one backfill
/// batch) with the canonical web matcher and writes the efforts through
/// `record_segment_match`. `verify_jwt = false` because an `sb_secret_` key is
/// not a JWT; the server-key gate in handler.ts is the only way in.

import { createClient } from 'npm:@supabase/supabase-js@2.118.0';
import type { Database } from '../_shared/database.ts';
import { withSentry } from '../_shared/sentry.ts';
import { secretKey } from '../_shared/api_keys.ts';
import { makeSegmentMatchHandler } from './handler.ts';

Deno.serve(withSentry('segment-match', makeSegmentMatchHandler({
  getEnv: (name) => Deno.env.get(name),
  serviceClient: () => createClient<Database>(Deno.env.get('SUPABASE_URL')!, secretKey()),
})));
