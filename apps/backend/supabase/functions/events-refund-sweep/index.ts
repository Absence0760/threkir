/// The event refund reconciliation sweep (club_events.md P2, M8; decisions
/// § 1839).
///
/// A paid order on an occurrence the host called off is owed a full refund.
/// Three paths issue it — `events-cancel`'s occurrence scope, the webhook's
/// cancelled-occurrence arm, and the host's "Refund now" — and each can fail
/// and leave it owed: a Stripe error, an unset key, a function killed between
/// the `refund_initiated_at` stamp and the Stripe call. Nothing retried any of
/// them. This does, hourly, through the same `refundOrder` and the same
/// per-order idempotency key, so a retry replays a refund that exists rather
/// than making a second one.
///
/// Invoked by pg_cron through `invoke_event_refund_sweep()` (migration
/// 20270726000001) with `Authorization: Bearer ${CRON_SECRET}`, and only when
/// an order is owed. Gates, each fail-closed, in this order: the cron bearer
/// (503 when CRON_SECRET is unset or short, 403 otherwise), then Stripe (503
/// `stripe_not_configured` before a row is read), then the worklist read (500).
/// A refund that fails again is reported, not raised: the run answers 200 with
/// the order ids, and the next run tries them again.
///
/// INITIATES only, like every refund in the tier: the webhook stays the sole
/// writer of `event_orders.status`, on the `charge.refunded` this produces.
///
/// The handler lives in handler.ts behind injected deps, so handler.test.ts can
/// drive it without a stack.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.110.0';
import type { Database } from '../_shared/database.ts';
import { withSentry } from '../_shared/sentry.ts';
import { secretKey } from '../_shared/api_keys.ts';
import { stripeRestRefundCreator } from '../events-cancel/refund.ts';
import { makeRefundSweepHandler } from './handler.ts';

Deno.serve(withSentry('events-refund-sweep', makeRefundSweepHandler({
  getEnv: (name) => Deno.env.get(name),
  serviceClient: () => createClient<Database>(Deno.env.get('SUPABASE_URL')!, secretKey()),
  transport: stripeRestRefundCreator,
})));
