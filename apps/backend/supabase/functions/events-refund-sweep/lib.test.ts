/// The sweep's pure half: the cron gate and the per-order loop, and the loop
/// driven end to end through the shared `refundOrder` over the one REST
/// transport with recording fakes for the database and `fetch`. The handler
/// itself needs a served function host plus operator keys.
///
/// Run with `cd apps/backend && deno test --no-check --allow-read
/// supabase/functions/events-refund-sweep/lib.test.ts`.

import { assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import type { DbClient } from '../_shared/database.ts';
import { type OrderRefundResult, refundIdempotencyKey } from '../events-cancel/lib.ts';
import { refundOrder, type RefundableOrder, stripeRestRefundCreator } from '../events-cancel/refund.ts';
import { CRON_SECRET_MIN_CHARS, cronGate, refundOwedOrders } from './lib.ts';

const SECRET = 's'.repeat(CRON_SECRET_MIN_CHARS);

Deno.test('cronGate — an unset or short secret is not configured, whatever the caller sends', () => {
  assertEquals(cronGate(undefined, `Bearer ${SECRET}`), 'not_configured');
  assertEquals(cronGate('', `Bearer ${SECRET}`), 'not_configured');
  const short = 's'.repeat(CRON_SECRET_MIN_CHARS - 1);
  assertEquals(cronGate(short, `Bearer ${short}`), 'not_configured');
});

Deno.test('cronGate — no bearer is a probe, a wrong one a mismatch, the secret ok', () => {
  assertEquals(cronGate(SECRET, null), 'no_bearer');
  assertEquals(cronGate(SECRET, ''), 'no_bearer');
  assertEquals(cronGate(SECRET, 'Bearer '), 'no_bearer');
  assertEquals(cronGate(SECRET, SECRET), 'no_bearer', 'a bare secret without the scheme is not a bearer');
  assertEquals(cronGate(SECRET, `Basic ${SECRET}`), 'no_bearer');
  assertEquals(cronGate(SECRET, `Bearer ${SECRET}x`), 'mismatch');
  assertEquals(cronGate(SECRET, `Bearer ${'t'.repeat(CRON_SECRET_MIN_CHARS)}`), 'mismatch');
  assertEquals(cronGate(SECRET, `Bearer ${SECRET}`), 'ok');
});

const ORDERS: RefundableOrder[] = [
  { id: 'o-1', status: 'paid', stripe_payment_intent_id: 'pi_1' },
  { id: 'o-2', status: 'partially_refunded', stripe_payment_intent_id: 'pi_2' },
  { id: 'o-3', status: 'paid', stripe_payment_intent_id: 'pi_3' },
];

Deno.test('refundOwedOrders — every order, in order, one at a time', async () => {
  const seen: string[] = [];
  let inFlight = 0;
  let maxInFlight = 0;
  const results = await refundOwedOrders(ORDERS, async (order) => {
    inFlight += 1;
    maxInFlight = Math.max(maxInFlight, inFlight);
    seen.push(order.id);
    await Promise.resolve();
    inFlight -= 1;
    return { orderId: order.id, outcome: 'initiated' };
  });
  assertEquals(seen, ['o-1', 'o-2', 'o-3']);
  assertEquals(maxInFlight, 1);
  assertEquals(results.map((r) => r.outcome), ['initiated', 'initiated', 'initiated']);
});

Deno.test('refundOwedOrders — a failure or a throw costs that order, never the rest', async () => {
  const results = await refundOwedOrders(ORDERS, (order): Promise<OrderRefundResult> => {
    if (order.id === 'o-1') return Promise.reject(new Error('socket hang up'));
    if (order.id === 'o-2') {
      return Promise.resolve({ orderId: order.id, outcome: 'failed', code: 'stripe_refund_failed' });
    }
    return Promise.resolve({ orderId: order.id, outcome: 'already_refunded' });
  });
  assertEquals(results, [
    { orderId: 'o-1', outcome: 'failed', code: 'sweep_refund_threw' },
    { orderId: 'o-2', outcome: 'failed', code: 'stripe_refund_failed' },
    { orderId: 'o-3', outcome: 'already_refunded' },
  ]);
});

Deno.test('refundOwedOrders — an empty worklist sends nothing', async () => {
  let calls = 0;
  const results = await refundOwedOrders([], () => {
    calls += 1;
    return Promise.resolve({ orderId: 'x', outcome: 'initiated' });
  });
  assertEquals(results, []);
  assertEquals(calls, 0);
});

/// A supabase-js stand-in whose every awaited chain resolves `{ error: null }`.
function okService(): DbClient {
  const builder: Record<string, unknown> = {};
  for (const name of ['update', 'eq', 'is']) builder[name] = () => builder;
  builder.then = (resolve: (v: { error: null }) => unknown) => Promise.resolve({ error: null }).then(resolve);
  return { from: () => builder } as unknown as DbClient;
}

Deno.test('the sweep end to end: each owed order replays refundOrder under its own key', async () => {
  const keys: string[] = [];
  const fetchImpl = ((_url: string, init: RequestInit) => {
    keys.push((init.headers as Record<string, string>)['Idempotency-Key']);
    // The second order was refunded by an earlier attempt whose webhook never
    // landed: Stripe says so, and that is done rather than failed.
    return Promise.resolve(
      keys.length === 2
        ? Response.json({ error: { code: 'charge_already_refunded' } }, { status: 400 })
        : Response.json({ id: `re_${keys.length}` }),
    );
  }) as unknown as typeof fetch;
  const service = okService();
  const createRefund = stripeRestRefundCreator('sk_test_x', fetchImpl);
  const results = await refundOwedOrders(ORDERS, (order) => refundOrder(createRefund, service, order));
  assertEquals(keys, ORDERS.map((o) => refundIdempotencyKey(o.id)));
  assertEquals(results.map((r) => r.outcome), ['initiated', 'already_refunded', 'initiated']);
});
