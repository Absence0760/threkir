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

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.110.0';
import type { Database } from '../_shared/database.ts';
import { discardBody } from '../_shared/body_limit.ts';
import { checkRateLimit, ipBucketKey } from '../_shared/rate_limit.ts';
import { withSentry } from '../_shared/sentry.ts';
import { secretKey } from '../_shared/api_keys.ts';
import { summarizeOccurrenceRefunds } from '../events-cancel/lib.ts';
import { refundOrder, stripeRestRefundCreator } from '../events-cancel/refund.ts';
import { cronGate, refundOwedOrders, SWEEP_BATCH_LIMIT } from './lib.ts';

Deno.serve(withSentry('events-refund-sweep', async (req: Request) => {
  // No body input; drop the stream before the gate so a chunked POST cannot
  // hold the connection open.
  discardBody(req);

  const gate = cronGate(Deno.env.get('CRON_SECRET'), req.headers.get('Authorization'));
  if (gate === 'not_configured') {
    return Response.json({ error: 'cron_not_configured' }, { status: 503 });
  }
  if (gate !== 'ok') {
    // Spent only on a wrong bearer, never in front of the compare, for the
    // reason refresh-tokens gives (decisions § 973): a limiter there would let
    // an unidentified caller starve the cron out of a shared bucket.
    if (gate === 'mismatch') {
      const admin = createClient<Database>(Deno.env.get('SUPABASE_URL')!, secretKey());
      const denied = await checkRateLimit(
        admin,
        await ipBucketKey(req),
        'events-refund-sweep:anon',
        60,
        3600,
        { failClosed: true },
      );
      if (denied) return denied;
    }
    return Response.json({ error: 'forbidden' }, { status: 403 });
  }

  const stripeSecretKey = Deno.env.get('STRIPE_SECRET_KEY') || null;
  if (!stripeSecretKey) {
    return Response.json({ error: 'stripe_not_configured' }, { status: 503 });
  }

  const service = createClient<Database>(Deno.env.get('SUPABASE_URL')!, secretKey());
  const { data: owed, error: owedErr } = await service.rpc('event_orders_owed_refund', {
    p_limit: SWEEP_BATCH_LIMIT,
  });
  if (owedErr) {
    console.error('refund sweep: worklist read failed (code):', owedErr?.code ?? 'unknown');
    return Response.json({ error: 'sweep_read_failed' }, { status: 500 });
  }

  const createRefund = stripeRestRefundCreator(stripeSecretKey);
  const results = await refundOwedOrders(
    owed ?? [],
    (order) => refundOrder(createRefund, service, order),
  );
  const summary = summarizeOccurrenceRefunds(results);
  if (summary.failed > 0) {
    console.error(
      'refund sweep: refunds still owed after this run. orders:',
      summary.failed_order_ids.join(','),
    );
  }
  return Response.json({ ok: true, scanned: results.length, refunds: summary });
}));
