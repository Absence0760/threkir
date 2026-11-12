/// `gateOccurrence` (occurrence.ts) driven against a fake client: a session
/// the series never produces is refused, a cancelled or past-the-end one is
/// refused, and every failed read refuses rather than selling (decisions
/// § 1921).
///
/// Run with `cd apps/backend && deno test --allow-read
/// supabase/functions/events-checkout/occurrence.test.ts`.

import { assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import type { DbClient } from '../_shared/database.ts';
import { gateOccurrence } from './occurrence.ts';

type Result = { data?: unknown; error?: { code: string } | null };

interface Reads {
  exists?: Result;
  exception?: Result;
}

const INSTANCE = '2026-07-11T09:00:00Z';

function fakeDb(reads: Reads) {
  const rpcCalls: Array<[string, unknown]> = [];
  const exceptionOps: unknown[][] = [];
  const client = {
    rpc(name: string, args: unknown) {
      rpcCalls.push([name, args]);
      return Promise.resolve({ data: null, error: null, ...(reads.exists ?? { data: true }) });
    },
    from(table: string) {
      if (table !== 'event_exceptions') throw new Error(`unscripted read on ${table}`);
      const builder: Record<string, unknown> = {};
      for (const name of ['select', 'eq']) {
        builder[name] = (...args: unknown[]) => {
          exceptionOps.push([name, ...args]);
          return builder;
        };
      }
      builder.maybeSingle = () =>
        Promise.resolve({ data: null, error: null, ...(reads.exception ?? {}) });
      return builder;
    },
  };
  return { rpcCalls, exceptionOps, client: client as unknown as DbClient };
}

Deno.test('a live occurrence passes, and the database is asked about exactly that instant', async () => {
  const db = fakeDb({});
  assertEquals(await gateOccurrence(db.client, 'event-1', INSTANCE, null), null);
  assertEquals(db.rpcCalls, [[
    'event_occurrence_exists',
    { p_event_id: 'event-1', p_instance: INSTANCE },
  ]]);
  assertEquals(db.exceptionOps, [
    ['select', 'event_id'],
    ['eq', 'event_id', 'event-1'],
    ['eq', 'instance_start', INSTANCE],
  ]);
});

Deno.test('an instant the series never produces is instance_not_found, before any other read', async () => {
  const db = fakeDb({ exists: { data: false } });
  assertEquals(
    await gateOccurrence(db.client, 'event-1', '2026-07-08T03:17:00Z', null),
    { status: 404, error: 'instance_not_found' },
  );
  assertEquals(db.exceptionOps, []);
});

Deno.test('a null answer is not taken as yes', async () => {
  const db = fakeDb({ exists: { data: null } });
  assertEquals(
    await gateOccurrence(db.client, 'event-1', INSTANCE, null),
    { status: 404, error: 'instance_not_found' },
  );
});

Deno.test('a failed occurrence check refuses the sale', async () => {
  const db = fakeDb({ exists: { data: null, error: { code: '57014' } } });
  assertEquals(
    await gateOccurrence(db.client, 'event-1', INSTANCE, null),
    { status: 500, error: 'checkout_failed' },
  );
});

Deno.test('a cancelled occurrence is instance_cancelled', async () => {
  const db = fakeDb({ exception: { data: { event_id: 'event-1' } } });
  assertEquals(
    await gateOccurrence(db.client, 'event-1', INSTANCE, null),
    { status: 409, error: 'instance_cancelled' },
  );
});

Deno.test('a failed cancellation read refuses rather than selling a session that may be off', async () => {
  const db = fakeDb({ exception: { data: null, error: { code: '08006' } } });
  assertEquals(
    await gateOccurrence(db.client, 'event-1', INSTANCE, null),
    { status: 500, error: 'checkout_failed' },
  );
});

Deno.test('an occurrence past the series end is instance_cancelled', async () => {
  const db = fakeDb({});
  assertEquals(
    await gateOccurrence(db.client, 'event-1', INSTANCE, '2026-07-04T09:00:00Z'),
    { status: 409, error: 'instance_cancelled' },
  );
  assertEquals(
    await gateOccurrence(db.client, 'event-1', INSTANCE, INSTANCE),
    null,
  );
});
