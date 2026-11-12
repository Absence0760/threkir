/// Pure helpers for the event refund reconciliation sweep (decisions § 1839).
///
/// Keep this file free of `Deno.env`, `createClient`, `fetch` and Stripe: the
/// handler in index.ts does the I/O, and refunds go through the shared
/// `refundOrder` (events-cancel/refund.ts), never anything built here.

import { timingSafeEqual } from '../_shared/webhook_security.ts';
import type { OrderRefundResult } from '../events-cancel/lib.ts';
import type { RefundableOrder } from '../events-cancel/refund.ts';

/// Orders one run may refund. Sequential calls at Stripe's pace keep a run well
/// inside the 150 s request clock, and an hourly schedule clears a backlog of
/// hundreds within a day; the worklist itself caps at 100.
export const SWEEP_BATCH_LIMIT = 25;

/// The same floor `refresh-tokens` and `strava-webhook` hold the cron secret
/// to (§ 937): this function is `verify_jwt = false`, so the bearer is its only
/// gate, and the short secret that actually happens is a misconfigured deploy.
export const CRON_SECRET_MIN_CHARS = 32;

export type CronGate =
  /// CRON_SECRET unset or too short — a 503, whatever the caller sent.
  | 'not_configured'
  /// No `Bearer` token at all — a probe, refused for free.
  | 'no_bearer'
  /// A bearer that is not the secret — refused, and worth rate-limiting.
  | 'mismatch'
  | 'ok';

export function cronGate(secret: string | undefined, authorization: string | null): CronGate {
  if (!secret || secret.length < CRON_SECRET_MIN_CHARS) return 'not_configured';
  const auth = authorization ?? '';
  const token = auth.startsWith('Bearer ') ? auth.slice(7) : '';
  if (!token) return 'no_bearer';
  return timingSafeEqual(token, secret) ? 'ok' : 'mismatch';
}

/// Refund each owed order in turn. Sequential on purpose, as in the host's
/// occurrence cancel: a burst would turn a Stripe rate limit into a run of
/// half-recorded failures. One order's failure never stops the next.
export async function refundOwedOrders(
  orders: readonly RefundableOrder[],
  refund: (order: RefundableOrder) => Promise<OrderRefundResult>,
): Promise<OrderRefundResult[]> {
  const results: OrderRefundResult[] = [];
  for (const order of orders) {
    try {
      results.push(await refund(order));
    } catch (e) {
      // refundOrder reports rather than throws; a throw here is a bug or a
      // dropped connection, and it is still one order, not the run.
      console.error(
        'refund sweep: refund threw:',
        e instanceof Error ? e.message : 'unknown',
        'order:',
        order.id,
      );
      results.push({ orderId: order.id, outcome: 'failed', code: 'sweep_refund_threw' });
    }
  }
  return results;
}
