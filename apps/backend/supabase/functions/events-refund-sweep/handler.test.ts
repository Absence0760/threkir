/// The refund sweep's handler (handler.ts) driven through every gate and the
/// refund loop with a fake service client and a recording refund transport
/// (decisions § 1839). No stack, no network, no Stripe.
///
/// Run with `cd apps/backend && deno test --allow-read --allow-env
/// supabase/functions/events-refund-sweep/handler.test.ts`.

import { assert, assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import type { DbClient } from '../_shared/database.ts';
import { buildRefundParams, refundIdempotencyKey } from '../events-cancel/lib.ts';
import { type CreateRefund, StripeRefundError } from '../events-cancel/refund.ts';
import { makeRefundSweepHandler } from './handler.ts';
import { SWEEP_BATCH_LIMIT } from './lib.ts';

const SECRET = 'c'.repeat(40);

interface Rpc {
  name: string;
  args: Record<string, unknown>;
}
type RpcResult = { data: unknown; error: { code: string } | null };

/// `rpc()` answers from `rpcs[name]`; `.from()` (the refund stamp and its
/// rollback) resolves to no error and is recorded.
function fakeService(rpcs: Record<string, RpcResult>) {
  const rpcCalls: Rpc[] = [];
  const writes: string[] = [];
  const client = {
    rpc(name: string, args: Record<string, unknown>) {
      rpcCalls.push({ name, args });
      return Promise.resolve(rpcs[name] ?? { data: null, error: { code: 'unscripted' } });
    },
    from(table: string) {
      writes.push(table);
      const builder: Record<string, unknown> = {};
      for (const name of ['update', 'eq', 'is']) builder[name] = () => builder;
      builder.then = (resolve: (v: unknown) => unknown) => Promise.resolve({ error: null }).then(resolve);
      return builder;
    },
  };
  return { rpcCalls, writes, client: client as unknown as DbClient };
}

function harness(opts: {
  env?: Record<string, string | undefined>;
  rpcs?: Record<string, RpcResult>;
  failKeys?: Record<string, unknown>;
}) {
  const env: Record<string, string | undefined> = {
    CRON_SECRET: SECRET,
    STRIPE_SECRET_KEY: 'sk_test_sweep',
    ...(opts.env ?? {}),
  };
  const service = fakeService(opts.rpcs ?? {});
  let clientsBuilt = 0;
  const transportKeys: string[] = [];
  const refunds: Array<{ params: unknown; key: string }> = [];
  const handler = makeRefundSweepHandler({
    getEnv: (name) => env[name],
    serviceClient: () => {
      clientsBuilt += 1;
      return service.client;
    },
    transport: (key: string): CreateRefund => {
      transportKeys.push(key);
      return (params, idempotencyKey) => {
        refunds.push({ params, key: idempotencyKey });
        const fail = opts.failKeys?.[idempotencyKey];
        return fail === undefined ? Promise.resolve({}) : Promise.reject(fail);
      };
    },
  });
  return {
    handler,
    service,
    refunds,
    transportKeys,
    clientsBuilt: () => clientsBuilt,
  };
}

function post(authorization?: string): Request {
  const headers = new Headers();
  if (authorization !== undefined) headers.set('Authorization', authorization);
  return new Request('http://localhost/events-refund-sweep', { method: 'POST', headers, body: '{}' });
}

const allowed: RpcResult = { data: [{ allowed: true, retry_after_seconds: 0 }], error: null };

Deno.test('no bearer: 403, and nothing is built, counted or read', async () => {
  const h = harness({});
  const res = await h.handler(post());
  assertEquals(res.status, 403);
  assertEquals(await res.json(), { error: 'forbidden' });
  assertEquals(h.clientsBuilt(), 0);
  assertEquals(h.service.rpcCalls, []);
});

Deno.test('CRON_SECRET unset or short: 503 whatever the caller sent', async () => {
  for (const secret of [undefined, '', 'short-secret']) {
    const h = harness({ env: { CRON_SECRET: secret } });
    const res = await h.handler(post(`Bearer ${SECRET}`));
    assertEquals(res.status, 503, `secret ${JSON.stringify(secret)}`);
    assertEquals(await res.json(), { error: 'cron_not_configured' });
    assertEquals(h.clientsBuilt(), 0);
  }
});

Deno.test('a wrong bearer spends the anon bucket, then 403s', async () => {
  const h = harness({ rpcs: { check_rate_limit: allowed } });
  const res = await h.handler(post('Bearer ' + 'x'.repeat(40)));
  assertEquals(res.status, 403);
  assertEquals(h.service.rpcCalls.length, 1);
  const [call] = h.service.rpcCalls;
  assertEquals(call.name, 'check_rate_limit');
  assertEquals(
    { bucket: call.args.p_bucket, max: call.args.p_max, window: call.args.p_window_seconds },
    { bucket: 'events-refund-sweep:anon', max: 60, window: 3600 },
  );
  assert(!h.service.rpcCalls.some((c) => c.name === 'event_orders_owed_refund'));
});

Deno.test('a wrong bearer over the limit is 429, and a limiter outage fails closed', async () => {
  const limited = harness({
    rpcs: { check_rate_limit: { data: [{ allowed: false, retry_after_seconds: 30 }], error: null } },
  });
  assertEquals((await limited.handler(post('Bearer nope'))).status, 429);

  const down = harness({ rpcs: { check_rate_limit: { data: null, error: { code: '57014' } } } });
  assertEquals((await down.handler(post('Bearer nope'))).status, 503);
});

Deno.test('Stripe unset: 503 before a single row is read', async () => {
  const h = harness({ env: { STRIPE_SECRET_KEY: undefined } });
  const res = await h.handler(post(`Bearer ${SECRET}`));
  assertEquals(res.status, 503);
  assertEquals(await res.json(), { error: 'stripe_not_configured' });
  assertEquals(h.clientsBuilt(), 0, 'no client, so no read');
  assertEquals(h.transportKeys, []);
});

Deno.test('a worklist read error is a 500 that refunds nothing', async () => {
  const h = harness({
    rpcs: { event_orders_owed_refund: { data: null, error: { code: '57014' } } },
  });
  const res = await h.handler(post(`Bearer ${SECRET}`));
  assertEquals(res.status, 500);
  assertEquals(await res.json(), { error: 'sweep_read_failed' });
  assertEquals(h.refunds, []);
});

Deno.test('the worklist is read once, at SWEEP_BATCH_LIMIT', async () => {
  const h = harness({ rpcs: { event_orders_owed_refund: { data: [], error: null } } });
  await h.handler(post(`Bearer ${SECRET}`));
  assertEquals(h.service.rpcCalls, [
    { name: 'event_orders_owed_refund', args: { p_limit: SWEEP_BATCH_LIMIT } },
  ]);
});

Deno.test('an empty worklist is a 200 that sends nothing', async () => {
  const h = harness({ rpcs: { event_orders_owed_refund: { data: [], error: null } } });
  const res = await h.handler(post(`Bearer ${SECRET}`));
  assertEquals(res.status, 200);
  assertEquals(await res.json(), {
    ok: true,
    scanned: 0,
    refunds: {
      outcome: 'complete',
      initiated: 0,
      already_refunded: 0,
      released: 0,
      failed: 0,
      failed_order_ids: [],
    },
  });
  assertEquals(h.refunds, []);
});

Deno.test('a run refunds each owed order under its own key and counts every outcome', async () => {
  const h = harness({
    rpcs: {
      event_orders_owed_refund: {
        data: [
          { id: 'o-sent', status: 'paid', stripe_payment_intent_id: 'pi_sent' },
          { id: 'o-done', status: 'partially_refunded', stripe_payment_intent_id: 'pi_done' },
          { id: 'o-refused', status: 'paid', stripe_payment_intent_id: 'pi_refused' },
          { id: 'o-no-pi', status: 'paid', stripe_payment_intent_id: null },
        ],
        error: null,
      },
    },
    failKeys: {
      [refundIdempotencyKey('o-done')]: new StripeRefundError('already', 'charge_already_refunded'),
      [refundIdempotencyKey('o-refused')]: new StripeRefundError('declined', 'card_declined'),
    },
  });
  const res = await h.handler(post(`Bearer ${SECRET}`));
  assertEquals(res.status, 200, 'a refund that fails again is reported, not raised');
  assertEquals(await res.json(), {
    ok: true,
    scanned: 4,
    refunds: {
      outcome: 'incomplete',
      initiated: 1,
      already_refunded: 1,
      released: 0,
      failed: 2,
      failed_order_ids: ['o-refused', 'o-no-pi'],
    },
  });
  assertEquals(h.transportKeys, ['sk_test_sweep'], 'one transport for the run, from the real key');
  assertEquals(h.refunds, [
    { params: buildRefundParams('pi_sent'), key: refundIdempotencyKey('o-sent') },
    { params: buildRefundParams('pi_done'), key: refundIdempotencyKey('o-done') },
    { params: buildRefundParams('pi_refused'), key: refundIdempotencyKey('o-refused') },
  ]);
});
