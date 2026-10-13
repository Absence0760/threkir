/// `refundOrder` and its SDK-free transport, driven with a recording fake for
/// the database and for `fetch`. The webhook refunds a checkout that completed
/// on a cancelled occurrence through exactly these (decisions § 1833), and the
/// webhook's own handler needs a live Supabase plus `whsec_` keys to drive, so
/// this is where its refund is exercised.
///
/// Run with `cd apps/backend && deno test --no-check --allow-read
/// supabase/functions/events-cancel/refund.test.ts`.

import { assert, assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import type { DbClient } from '../_shared/database.ts';
import { buildRefundParams, isAlreadyRefundedError, refundIdempotencyKey } from './lib.ts';
import {
  type CreateRefund,
  refundFormBody,
  refundOrder,
  STRIPE_REFUNDS_URL,
  StripeRefundError,
  stripeRestRefundCreator,
} from './refund.ts';

type Op = [string, ...unknown[]];

/// A supabase-js stand-in that records every chained call per `.from()` and
/// resolves each awaited chain to `{ error }` from the queue (null when empty).
function fakeService(errors: Array<{ code: string } | null> = []) {
  const writes: Array<{ table: string; ops: Op[] }> = [];
  const client = {
    from(table: string) {
      const write = { table, ops: [] as Op[] };
      writes.push(write);
      const builder: Record<string, unknown> = {};
      for (const name of ['update', 'eq', 'is']) {
        builder[name] = (...args: unknown[]) => {
          write.ops.push([name, ...args]);
          return builder;
        };
      }
      builder.then = (
        resolve: (v: { error: { code: string } | null }) => unknown,
        reject: (e: unknown) => unknown,
      ) => Promise.resolve({ error: errors.shift() ?? null }).then(resolve, reject);
      return builder;
    },
  };
  return { writes, client: client as unknown as DbClient };
}

const ORDER = { id: 'order-1', status: 'paid', stripe_payment_intent_id: 'pi_123' };

function recordingCreator(fail?: unknown) {
  const calls: Array<{ params: unknown; key: string }> = [];
  const create: CreateRefund = (params, key) => {
    calls.push({ params, key });
    return fail === undefined ? Promise.resolve({}) : Promise.reject(fail);
  };
  return { calls, create };
}

Deno.test('refundOrder — one refund, built by buildRefundParams under the order key', async () => {
  const { writes, client } = fakeService();
  const { calls, create } = recordingCreator();
  const result = await refundOrder(create, client, ORDER);
  assertEquals(result, { orderId: 'order-1', outcome: 'initiated' });
  assertEquals(calls, [{ params: buildRefundParams('pi_123'), key: refundIdempotencyKey('order-1') }]);
  // The stamp lands first, only when absent, guarded on the status read.
  assertEquals(writes.length, 1);
  const [stamp] = writes;
  assertEquals(stamp.table, 'event_orders');
  assert(typeof (stamp.ops[0][1] as { refund_initiated_at: unknown }).refund_initiated_at === 'string');
  assertEquals(stamp.ops.slice(1), [
    ['eq', 'id', 'order-1'],
    ['eq', 'status', 'paid'],
    ['is', 'refund_initiated_at', null],
  ]);
});

Deno.test('refundOrder — the stamp is guarded on whatever status was read', async () => {
  const { writes, client } = fakeService();
  await refundOrder(recordingCreator().create, client, { ...ORDER, status: 'partially_refunded' });
  assert(writes[0].ops.some((op) => op[0] === 'eq' && op[1] === 'status' && op[2] === 'partially_refunded'));
});

Deno.test('refundOrder — no payment intent fails before anything is written or sent', async () => {
  const { writes, client } = fakeService();
  const { calls, create } = recordingCreator();
  const result = await refundOrder(create, client, { ...ORDER, stripe_payment_intent_id: null });
  assertEquals(result, { orderId: 'order-1', outcome: 'failed', code: 'missing_payment_intent' });
  assertEquals(writes, []);
  assertEquals(calls, []);
});

Deno.test('refundOrder — a failed stamp sends no refund', async () => {
  const { client } = fakeService([{ code: '57014' }]);
  const { calls, create } = recordingCreator();
  const result = await refundOrder(create, client, ORDER);
  assertEquals(result, { orderId: 'order-1', outcome: 'failed', code: 'stamp_failed' });
  assertEquals(calls, []);
});

Deno.test('refundOrder — a failed refund rolls back only the stamp this call wrote', async () => {
  const { writes, client } = fakeService();
  const result = await refundOrder(
    recordingCreator(new StripeRefundError('card_declined', 'card_declined')).create,
    client,
    ORDER,
  );
  assertEquals(result, { orderId: 'order-1', outcome: 'failed', code: 'stripe_refund_failed' });
  assertEquals(writes.length, 2);
  const stampedAt = (writes[0].ops[0][1] as { refund_initiated_at: string }).refund_initiated_at;
  assertEquals(writes[1].ops, [
    ['update', { refund_initiated_at: null }],
    ['eq', 'id', 'order-1'],
    ['eq', 'status', 'paid'],
    ['eq', 'refund_initiated_at', stampedAt],
  ]);
});

Deno.test('refundOrder — an already-refunded charge is done, and keeps its stamp', async () => {
  const { writes, client } = fakeService();
  const result = await refundOrder(
    recordingCreator(new StripeRefundError('already', 'charge_already_refunded')).create,
    client,
    ORDER,
  );
  assertEquals(result, { orderId: 'order-1', outcome: 'already_refunded' });
  assertEquals(writes.length, 1, 'no rollback: "refund in progress" is the truth');
});

// ── the one refund transport (decisions § 1839) ──────────────────────────────

function recordingFetch(response: Response) {
  const requests: Array<{ url: string; init: RequestInit }> = [];
  const impl = ((url: string, init: RequestInit) => {
    requests.push({ url, init });
    return Promise.resolve(response);
  }) as unknown as typeof fetch;
  return { requests, impl };
}

Deno.test('refundFormBody — exactly the builder keys, booleans as true', () => {
  const body = refundFormBody(buildRefundParams('pi_abc'));
  assertEquals([...body.entries()].sort(), [
    ['payment_intent', 'pi_abc'],
    ['refund_application_fee', 'true'],
    ['reverse_transfer', 'true'],
  ]);
});

Deno.test('stripeRestRefundCreator — POSTs the form body with the key it was given', async () => {
  const { requests, impl } = recordingFetch(Response.json({ id: 're_1' }));
  await stripeRestRefundCreator('sk_test_x', impl)(
    buildRefundParams('pi_abc'),
    refundIdempotencyKey('order-9'),
  );
  assertEquals(requests.length, 1);
  const [{ url, init }] = requests;
  assertEquals(url, STRIPE_REFUNDS_URL);
  assertEquals(init.method, 'POST');
  const headers = init.headers as Record<string, string>;
  assertEquals(headers['Idempotency-Key'], 'event-order-refund:order-9');
  assertEquals(headers['Authorization'], 'Bearer sk_test_x');
  assertEquals(headers['Content-Type'], 'application/x-www-form-urlencoded');
  assertEquals(String(init.body), String(refundFormBody(buildRefundParams('pi_abc'))));
});

Deno.test('stripeRestRefundCreator — charge_already_refunded reads as done, like the SDK error', async () => {
  const { impl } = recordingFetch(
    Response.json(
      { error: { code: 'charge_already_refunded', message: 'Charge has already been refunded.' } },
      { status: 400 },
    ),
  );
  let thrown: unknown;
  try {
    await stripeRestRefundCreator('sk_test_x', impl)(buildRefundParams('pi_abc'), 'k');
  } catch (e) {
    thrown = e;
  }
  assert(thrown instanceof StripeRefundError);
  assert(isAlreadyRefundedError(thrown));
});

Deno.test('stripeRestRefundCreator — any other non-2xx fails, with or without a JSON body', async () => {
  for (const response of [
    Response.json({ error: { code: 'resource_missing', message: 'No such payment_intent' } }, { status: 404 }),
    new Response('upstream timeout', { status: 502 }),
  ]) {
    let thrown: unknown;
    try {
      await stripeRestRefundCreator('sk_test_x', recordingFetch(response).impl)(
        buildRefundParams('pi_abc'),
        'k',
      );
    } catch (e) {
      thrown = e;
    }
    assert(thrown instanceof StripeRefundError, `a ${response.status} must throw`);
    assert(!isAlreadyRefundedError(thrown), `a ${response.status} is not an already-refunded charge`);
  }
});

Deno.test('every caller end to end: a REST refund through refundOrder', async () => {
  const { writes, client } = fakeService();
  const { requests, impl } = recordingFetch(Response.json({ id: 're_1' }));
  const result = await refundOrder(stripeRestRefundCreator('sk_test_x', impl), client, ORDER);
  assertEquals(result.outcome, 'initiated');
  assertEquals(writes.length, 1);
  const headers = requests[0].init.headers as Record<string, string>;
  assertEquals(headers['Idempotency-Key'], refundIdempotencyKey('order-1'));
});
