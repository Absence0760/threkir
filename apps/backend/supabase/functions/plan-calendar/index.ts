/// Subscribable training-plan calendar feed:
///   GET /functions/v1/plan-calendar/<token>.ics
///
/// A calendar app (Google, Apple, Outlook) subscribes to this URL and polls
/// it. It cannot send a header, so the 96-hex token in the path is the whole
/// credential: a feed id plus a secret whose SHA-256 is all the database
/// keeps (migration 20270910000001). `verify_jwt = false` in config.toml,
/// because no Supabase JWT ever arrives; the handler's secret check is the
/// gate. Minted, rotated and revoked from Settings through
/// rotate_plan_calendar_feed / revoke_plan_calendar_feed.
///
/// The body is the owner's ACTIVE plan's non-rest workouts as all-day
/// entries — kind, date, prescribed target — and nothing else: no location,
/// notes, plan or race name (docs/features/training.md § Calendar feed).
///
/// Hosted here rather than as a SvelteKit route behind its own Lambda
/// because the read is one hop from Postgres with the service role this
/// runtime already holds, and the anonymous-caller posture it needs (per-IP
/// rate limit through check_rate_limit, constant-time URL secret) is the one
/// strava-webhook and clip-public-track already run; see decisions.md for
/// the comparison.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.110.0?target=deno';
import type { Database, DbClient } from '../_shared/database.ts';
import { checkRateLimit, ipBucketKey } from '../_shared/rate_limit.ts';
import { withSentry } from '../_shared/sentry.ts';
import { secretKey } from '../_shared/api_keys.ts';
import { feedBucketKey } from './lib.ts';
import { makePlanCalendarHandler } from './handler.ts';

let admin: DbClient | null = null;

function adminClient(): DbClient {
  if (!admin) {
    admin = createClient<Database>(Deno.env.get('SUPABASE_URL')!, secretKey());
  }
  return admin;
}

const handler = makePlanCalendarHandler({
  // 120 an hour per address: a calendar polls a feed a few times an hour at
  // most, and Google fetches every subscriber's feed from a shared pool, so
  // the per-address ceiling is set well above one client's need. The per-feed
  // bucket below is the tight one.
  limitByIp: async (req) =>
    checkRateLimit(adminClient(), await ipBucketKey(req), 'plan-calendar:anon', 120, 3600, {
      failClosed: true,
    }),
  limitByFeed: async (feedId) =>
    checkRateLimit(adminClient(), await feedBucketKey(feedId), 'plan-calendar:feed', 30, 3600, {
      failClosed: true,
    }),
  readSecretHash: async (feedId) => {
    const { data, error } = await adminClient()
      .from('plan_calendar_feeds')
      .select('secret_hash')
      .eq('id', feedId)
      .maybeSingle();
    if (error) throw new Error(error.code ?? 'feed_read_failed');
    return data?.secret_hash ?? null;
  },
  readFeedBody: async (feedId) => {
    const { data, error } = await adminClient().rpc('plan_calendar_feed_events', { p_feed_id: feedId });
    if (error) throw new Error(error.code ?? 'feed_body_failed');
    return data ?? null;
  },
});

Deno.serve(withSentry('plan-calendar', handler));
