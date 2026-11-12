/// The seat confirm arm (`handleCompleted`, completed.ts) driven end to end
/// against a scripted database client and a recording refund transport: the
/// cancelled-occurrence branch on both sides of the `pending -> paid` CAS
/// (decisions § 1833, § 1839), every way its refund can come out, and the read
/// errors that decide between a retry and a 200. No stack, no network.
///
/// Run with `cd apps/backend && deno test --allow-read
/// supabase/functions/stripe-events-webhook/completed.test.ts`.

import { assert, assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import type { DbClient } from '../_shared/database.ts';
import { buildRefundParams, refundIdempotencyKey } from '../events-cancel/lib.ts';
import { type CreateRefund, StripeRefundError } from '../events-cancel/refund.ts';
import { type CancelledOccurrenceRefunds, handleCompleted } from './completed.ts';
import { type CheckoutSession, STRIPE_EVENT } from './lib.ts';

type Op = [string, ...unknown[]];
interface Call {
  table: string;
  ops: Op[];
}
type Result = { data?: unknown; error?: { code: string } | null; count?: number | null };

/// A supabase-js stand-in: every `.from()` chain is recorded, and whatever ends
/// it (`maybeSingle()` or a bare `await`) resolves to `respond(call)`.
function fakeDb(respond: (call: Call) => Result) {
  const calls: Call[] = [];
  const client = {
    from(table: string) {
      const call: Call = { table, ops: [] };
      calls.push(call);
      const builder: Record<string, unknown> = {};
      for (const name of ['select', 'update', 'upsert', 'eq', 'neq', 'is']) {
        builder[name] = (...args: unknown[]) => {
          call.ops.push([name, ...args]);
          return builder;
        };
      }
      const settle = () => Promise.resolve({ data: null, error: null, count: null, ...respond(call) });
      builder.maybeSingle = () => {
        call.ops.push(['maybeSingle']);
        return settle();
      };
      builder.then = (resolve: (v: unknown) => unknown, reject: (e: unknown) => unknown) =>
        settle().then(resolve, reject);
      return builder;
    },
  };
  return { calls, client: client as unknown as DbClient };
}

const first = (call: Call) => call.ops[0]?.[0];
const payload = (call: Call) => call.ops[0]?.[1] as Record<string, unknown>;

const ORDER_ROW = {
  id: 'order-1',
  status: 'pending',
  event_id: 'event-1',
  instance_start: '2026-07-01T18:00:00+00:00',
  buyer_user_id: 'buyer-1',
  stripe_payment_intent_id: null,
};

const SESSION: CheckoutSession = {
  paymentIntentId: 'pi_live',
  paymentStatus: 'paid',
  metadata: {
    event_id: 'event-1',
    buyer_user_id: 'buyer-1',
    instance_start: '2026-07-01T18:00:00+00:00',
    order_id: 'order-1',
  },
};

interface Script {
  orderRead?: Result;
  /// The exception reads in order: the pre-CAS read, then the post-CAS re-read.
  exceptionReads?: Result[];
  cas?: Result;
  stamp?: Result;
  capacity?: number | null;
  seat?: Result;
}

/// The happy path unless a step is overridden: the order is pending, the
/// occurrence is on, the CAS wins, the event is unlimited, the seat lands.
function scripted(script: Script) {
  const exceptionReads = [...(script.exceptionReads ?? [{ data: null }, { data: null }])];
  return fakeDb((call) => {
    if (call.table === 'event_orders' && first(call) === 'select') {
      return script.orderRead ?? { data: ORDER_ROW };
    }
    if (call.table === 'event_exceptions') return exceptionReads.shift() ?? { data: null };
    if (call.table === 'event_orders' && first(call) === 'update') {
      const set = payload(call);
      if ('status' in set) return script.cas ?? { data: { id: 'order-1', status: 'paid' } };
      return set.refund_initiated_at === null ? {} : (script.stamp ?? {});
    }
    if (call.table === 'events') return { data: { capacity: script.capacity ?? null } };
    if (call.table === 'event_attendees' && first(call) === 'select') return { count: 0 };
    if (call.table === 'event_attendees' && first(call) === 'upsert') {
      return script.seat ?? { data: { status: 'going' } };
    }
    throw new Error(`unscripted call on ${call.table}: ${JSON.stringify(call.ops)}`);
  });
}

function recordingTransport(fail?: unknown) {
  const keys: string[] = [];
  const refunds: Array<{ params: unknown; key: string }> = [];
  const deps = (stripeSecretKey: string | null): CancelledOccurrenceRefunds => ({
    stripeSecretKey,
    transport: (key: string): CreateRefund => {
      keys.push(key);
      return (params, idempotencyKey) => {
        refunds.push({ params, key: idempotencyKey });
        return fail === undefined ? Promise.resolve({}) : Promise.reject(fail);
      };
    },
  });
  return { keys, refunds, deps };
}

const tables = (calls: Call[]) => calls.map((c) => `${c.table}:${first(c)}`);
const casCount = (calls: Call[]) =>
  calls.filter((c) => c.table === 'event_orders' && first(c) === 'update' && 'status' in payload(c)).length;
const isStampWrite = (c: Call) =>
  c.table === 'event_orders' && first(c) === 'update' && 'refund_initiated_at' in payload(c);
const seated = (calls: Call[]) => calls.some((c) => c.table === 'event_attendees' && first(c) === 'upsert');

async function run(script: Script, refunds: CancelledOccurrenceRefunds) {
  const db = scripted(script);
  const res = await handleCompleted(db.client, SESSION, STRIPE_EVENT.checkoutCompleted, refunds);
  return { status: res.status, body: await res.json(), calls: db.calls };
}

Deno.test('cancelled before the CAS: marked paid, never seated, refunded under the order key', async () => {
  const t = recordingTransport();
  const { status, body, calls } = await run(
    { exceptionReads: [{ data: { event_id: 'event-1' } }] },
    t.deps('sk_test_x'),
  );
  assertEquals(status, 200);
  assertEquals(body, { ok: true, occurrence_cancelled: true, refund: 'initiated', order_id: 'order-1' });
  assertEquals(casCount(calls), 1, 'the money arrived, so the order is paid first');
  assert(!seated(calls), 'a cancelled occurrence seats nobody');
  assertEquals(
    calls.filter((c) => c.table === 'event_exceptions').length,
    1,
    'a cancel seen before the CAS needs no second read',
  );
  assertEquals(t.keys, ['sk_test_x']);
  assertEquals(t.refunds, [{ params: buildRefundParams('pi_live'), key: refundIdempotencyKey('order-1') }]);
  const stamp = calls.find(isStampWrite);
  assert(stamp, 'the refund is stamped before it is sent');
  assert(
    stamp.ops.some((op) => op[0] === 'eq' && op[1] === 'status' && op[2] === 'paid'),
    'the stamp is guarded on the status the CAS wrote',
  );
});

Deno.test('cancelled only by the re-read after the CAS: still refunded, still not seated', async () => {
  const t = recordingTransport();
  const { body, calls } = await run(
    { exceptionReads: [{ data: null }, { data: { event_id: 'event-1' } }] },
    t.deps('sk_test_x'),
  );
  assertEquals(body.occurrence_cancelled, true);
  assertEquals(body.refund, 'initiated');
  assertEquals(t.refunds.length, 1);
  assert(!seated(calls));
  const order = tables(calls);
  assert(
    order.indexOf('event_orders:update') < order.lastIndexOf('event_exceptions:select'),
    'the second read happens after the CAS',
  );
  const reread = calls.filter((c) => c.table === 'event_exceptions')[1];
  assertEquals(reread.ops.filter((op) => op[0] === 'eq'), [
    ['eq', 'event_id', 'event-1'],
    ['eq', 'instance_start', '2026-07-01T18:00:00+00:00'],
  ]);
});

Deno.test('a re-read that errors seats the buyer and refunds nothing', async () => {
  const t = recordingTransport();
  const { status, body, calls } = await run(
    { exceptionReads: [{ data: null }, { error: { code: '57014' } }] },
    t.deps('sk_test_x'),
  );
  assertEquals(status, 200, 'the order is paid: a 500 would buy no retry');
  assertEquals(body, { ok: true, seated: true, order_id: 'order-1' });
  assert(seated(calls));
  assertEquals(t.refunds, [], 'a read error is not a cancellation');
});

Deno.test('the occurrence is on: seated, no refund', async () => {
  const t = recordingTransport();
  const { body, calls } = await run({}, t.deps('sk_test_x'));
  assertEquals(body, { ok: true, seated: true, order_id: 'order-1' });
  assertEquals(calls.filter((c) => c.table === 'event_exceptions').length, 2);
  assertEquals(t.keys, []);
});

Deno.test('Stripe unset on a cancelled occurrence: paid, unseated, reported owed, nothing sent', async () => {
  const t = recordingTransport();
  const { status, body, calls } = await run(
    { exceptionReads: [{ data: { event_id: 'event-1' } }] },
    t.deps(null),
  );
  assertEquals(status, 200);
  assertEquals(body, { ok: true, occurrence_cancelled: true, refund: 'owed', order_id: 'order-1' });
  assertEquals(casCount(calls), 1);
  assert(!seated(calls));
  assertEquals(t.keys, [], 'no transport is built without a key');
  assert(
    !calls.some(isStampWrite),
    'no stamp: the order stays listed as owed with nothing in flight',
  );
});

Deno.test('Stripe refuses the refund: reported owed with a 200, and the stamp rolled back', async () => {
  const t = recordingTransport(new StripeRefundError('declined', 'card_declined'));
  const { status, body, calls } = await run(
    { exceptionReads: [{ data: { event_id: 'event-1' } }] },
    t.deps('sk_test_x'),
  );
  assertEquals(status, 200, 'a retry finds no transition; the sweep is the retry');
  assertEquals(body, { ok: true, occurrence_cancelled: true, refund: 'owed', order_id: 'order-1' });
  assertEquals(t.refunds.length, 1);
  const stampWrites = calls.filter(isStampWrite);
  assertEquals(stampWrites.map((c) => payload(c).refund_initiated_at === null), [false, true]);
  assert(!seated(calls));
});

Deno.test('a charge Stripe already refunded reads as done', async () => {
  const t = recordingTransport(new StripeRefundError('already', 'charge_already_refunded'));
  const { status, body } = await run(
    { exceptionReads: [{ data: { event_id: 'event-1' } }] },
    t.deps('sk_test_x'),
  );
  assertEquals(status, 200);
  assertEquals(body, {
    ok: true,
    occurrence_cancelled: true,
    refund: 'already_refunded',
    order_id: 'order-1',
  });
});

Deno.test('the first cancellation read errors: 500 before any write, so Stripe retries', async () => {
  const t = recordingTransport();
  const { status, body, calls } = await run(
    { exceptionReads: [{ error: { code: '57014' } }] },
    t.deps('sk_test_x'),
  );
  assertEquals(status, 500);
  assertEquals(body, { ok: false, error: 'occurrence_read_failed' });
  assertEquals(casCount(calls), 0, 'the order stays pending for the retry to transition');
  assert(!seated(calls));
  assertEquals(t.keys, []);
});

Deno.test('a lost CAS refunds nothing and seats nothing: the winning delivery owns the order', async () => {
  const t = recordingTransport();
  const { body, calls } = await run(
    { exceptionReads: [{ data: { event_id: 'event-1' } }], cas: { data: null } },
    t.deps('sk_test_x'),
  );
  assertEquals(body, { ok: true, skipped: 'cas_lost' });
  assertEquals(t.keys, []);
  assert(!seated(calls));
});

Deno.test('an unsettled payment writes nothing at all', async () => {
  const t = recordingTransport();
  const db = scripted({});
  const res = await handleCompleted(
    db.client,
    { ...SESSION, paymentStatus: 'unpaid' },
    STRIPE_EVENT.checkoutCompleted,
    t.deps('sk_test_x'),
  );
  assertEquals(await res.json(), { ok: true, skipped: 'payment_not_settled' });
  assertEquals(db.calls, []);
});
