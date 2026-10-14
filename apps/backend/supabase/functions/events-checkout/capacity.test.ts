/// `precheckCapacity` (capacity.ts) driven against a fake client: what counts
/// against capacity on a paid occurrence (seated, live checkout holds, other
/// people's waitlist offers), and that every failed read refuses the sale
/// rather than selling the seat (decisions § 1840).
///
/// Run with `cd apps/backend && deno test --allow-read
/// supabase/functions/events-checkout/capacity.test.ts`.

import { assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import type { DbClient } from '../_shared/database.ts';
import { precheckCapacity } from './capacity.ts';

type Op = [string, ...unknown[]];
interface Call {
  table: string;
  ops: Op[];
}
type Result = { data?: unknown; count?: number | null; error?: { code: string } | null };

interface Reads {
  going?: Result;
  pending?: Result;
  offers?: Result;
}

const NOW = Date.parse('2026-07-01T12:00:00Z');
const LATER = '2026-07-01T20:00:00Z';
const EARLIER = '2026-07-01T11:00:00Z';

/// Answers the three reads by what they select; records every chain.
function fakeDb(reads: Reads) {
  const calls: Call[] = [];
  const client = {
    from(table: string) {
      const call: Call = { table, ops: [] };
      calls.push(call);
      const builder: Record<string, unknown> = {};
      for (const name of ['select', 'eq', 'gt', 'not']) {
        builder[name] = (...args: unknown[]) => {
          call.ops.push([name, ...args]);
          return builder;
        };
      }
      const answer = (): Result => {
        const selected = call.ops[0]?.[1];
        if (table === 'event_attendees' && selected === 'event_id') return reads.going ?? { count: 0 };
        if (table === 'event_orders') return reads.pending ?? { data: [] };
        if (table === 'event_attendees') return reads.offers ?? { data: [] };
        throw new Error(`unscripted read on ${table}`);
      };
      builder.then = (resolve: (v: unknown) => unknown, reject: (e: unknown) => unknown) =>
        Promise.resolve({ data: null, count: null, error: null, ...answer() }).then(resolve, reject);
      return builder;
    },
  };
  return { calls, client: client as unknown as DbClient };
}

const check = (db: ReturnType<typeof fakeDb>, capacity: number | null, caller = 'me') =>
  precheckCapacity(db.client, 'event-1', '2026-07-08T18:00:00Z', capacity, caller, NOW);

Deno.test('an unlimited occurrence is available without a read', async () => {
  const db = fakeDb({});
  assertEquals(await check(db, null), 'available');
  assertEquals(db.calls, []);
});

Deno.test("a stranger's live offer holds the last seat against the caller", async () => {
  const db = fakeDb({
    going: { count: 1 },
    offers: { data: [{ user_id: 'stranger', offer_expires_at: LATER }] },
  });
  assertEquals(await check(db, 2), 'full');
});

Deno.test("the caller's own offer is the seat they came to claim", async () => {
  const db = fakeDb({
    going: { count: 1 },
    offers: { data: [{ user_id: 'me', offer_expires_at: LATER }] },
  });
  assertEquals(await check(db, 2), 'available');
});

Deno.test("a stranger's lapsed offer holds nothing, unless they are mid-checkout", async () => {
  const lapsed = fakeDb({
    going: { count: 1 },
    offers: { data: [{ user_id: 'stranger', offer_expires_at: EARLIER }] },
  });
  assertEquals(await check(lapsed, 2), 'available');

  const paying = fakeDb({
    going: { count: 1 },
    pending: { data: [{ buyer_user_id: 'stranger' }] },
    offers: { data: [{ user_id: 'stranger', offer_expires_at: EARLIER }] },
  });
  assertEquals(await check(paying, 2), 'full', 'their live checkout hold counts, once');
});

Deno.test('live checkout holds count, and only unexpired ones are asked for', async () => {
  const db = fakeDb({ going: { count: 1 }, pending: { data: [{ buyer_user_id: 'a' }] } });
  assertEquals(await check(db, 2), 'full');
  const pendingRead = db.calls.find((c) => c.table === 'event_orders');
  assertEquals(pendingRead?.ops.slice(1), [
    ['eq', 'event_id', 'event-1'],
    ['eq', 'instance_start', '2026-07-08T18:00:00Z'],
    ['eq', 'status', 'pending'],
    ['gt', 'reserved_until', new Date(NOW).toISOString()],
  ]);
});

Deno.test('a free seat with nothing holding it is available', async () => {
  assertEquals(await check(fakeDb({ going: { count: 1 } }), 2), 'available');
});

Deno.test('every failed read refuses the sale rather than selling the seat', async () => {
  const err = { code: '57014' };
  assertEquals(await check(fakeDb({ going: { error: err } }), 2), 'unknown', 'the seated count');
  assertEquals(await check(fakeDb({ pending: { error: err } }), 2), 'unknown', 'the checkout holds');
  assertEquals(await check(fakeDb({ offers: { error: err } }), 2), 'unknown', 'the waitlist offers');
});

Deno.test('a failed seated count stops before the holds are read', async () => {
  const db = fakeDb({ going: { error: { code: '57014' } } });
  await check(db, 2);
  assertEquals(db.calls.length, 1);
});
