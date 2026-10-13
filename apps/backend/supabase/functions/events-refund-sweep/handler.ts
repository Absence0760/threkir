/// Request handler for the event refund reconciliation sweep, factored out of
/// index.ts behind injected deps (env lookup, the service client, the refund
/// transport) so a deno test can drive every gate and the refund loop against
/// a fake client, the way auth-email/handler.ts is driven. index.ts passes the
/// real environment, `createClient` and `stripeRestRefundCreator`.
///
/// Gates, each fail-closed, in this order: the cron bearer (503 when
/// CRON_SECRET is unset or short, 403 otherwise, a rate limit spent only on a
/// wrong bearer), then Stripe (503 `stripe_not_configured` before a row is
/// read), then the worklist read (500). A refund that fails again is reported,
/// not raised: the run answers 200 with the order ids, and the next run tries
/// them again (decisions § 1839).

import type { DbClient } from '../_shared/database.ts';
import { discardBody } from '../_shared/body_limit.ts';
import { checkRateLimit, ipBucketKey } from '../_shared/rate_limit.ts';
import { summarizeOccurrenceRefunds } from '../events-cancel/lib.ts';
import { type CreateRefund, refundOrder } from '../events-cancel/refund.ts';
import { cronGate, refundOwedOrders, SWEEP_BATCH_LIMIT } from './lib.ts';

export interface RefundSweepDeps {
  getEnv: (name: string) => string | undefined;
  serviceClient: () => DbClient;
  transport: (stripeSecretKey: string) => CreateRefund;
}

export function makeRefundSweepHandler(
  deps: RefundSweepDeps,
): (req: Request) => Promise<Response> {
  return async (req: Request) => {
    // No body input; drop the stream before the gate so a chunked POST cannot
    // hold the connection open.
    discardBody(req);

    const gate = cronGate(deps.getEnv('CRON_SECRET'), req.headers.get('Authorization'));
    if (gate === 'not_configured') {
      return Response.json({ error: 'cron_not_configured' }, { status: 503 });
    }
    if (gate !== 'ok') {
      // Spent only on a wrong bearer, never in front of the compare, for the
      // reason refresh-tokens gives (decisions § 973): a limiter there would let
      // an unidentified caller starve the cron out of a shared bucket.
      if (gate === 'mismatch') {
        const denied = await checkRateLimit(
          deps.serviceClient(),
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

    const stripeSecretKey = deps.getEnv('STRIPE_SECRET_KEY') || null;
    if (!stripeSecretKey) {
      return Response.json({ error: 'stripe_not_configured' }, { status: 503 });
    }

    const service = deps.serviceClient();
    const { data: owed, error: owedErr } = await service.rpc('event_orders_owed_refund', {
      p_limit: SWEEP_BATCH_LIMIT,
    });
    if (owedErr) {
      console.error('refund sweep: worklist read failed (code):', owedErr?.code ?? 'unknown');
      return Response.json({ error: 'sweep_read_failed' }, { status: 500 });
    }

    const createRefund = deps.transport(stripeSecretKey);
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
  };
}
