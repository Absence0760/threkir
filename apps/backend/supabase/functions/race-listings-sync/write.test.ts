/// The shared write half (write.ts) driven with a fake service client against
/// the recorded RunSignUp feed: each race is placed from its ZIP through
/// `us_zcta_points`, a race the table cannot place is still written and counted
/// `unplaced`, and a failed read of what is stored refuses rather than
/// duplicating the calendar. No stack, no network.
///
/// Run with `cd apps/backend && deno test --allow-read --allow-env
/// supabase/functions/race-listings-sync/write.test.ts`.

import { assert, assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import type { DbClient } from '../_shared/database.ts';
import { syncProviderPayload } from './write.ts';

const FEED = JSON.parse(
  Deno.readTextFileSync(new URL('./fixtures/runsignup_races.json', import.meta.url)),
);

type Op = [string, ...unknown[]];
interface Call {
  table: string;
  ops: Op[];
}

interface Script {
  zips?: { data: Array<{ zcta: string; lat: number; lng: number }> | null; error: { message: string } | null };
  stored?: { data: unknown[] | null; error: { message: string } | null };
  insertError?: { message: string } | null;
}

function fakeService(script: Script = {}) {
  const calls: Call[] = [];
  const client = {
    from(table: string) {
      const call: Call = { table, ops: [] };
      calls.push(call);
      const builder: Record<string, unknown> = {};
      for (const name of ['select', 'insert', 'update', 'eq', 'in']) {
        builder[name] = (...args: unknown[]) => {
          call.ops.push([name, ...args]);
          return builder;
        };
      }
      const answer = () => {
        const first = call.ops[0]?.[0];
        if (table === 'us_zcta_points') {
          return script.zips ?? { data: [{ zcta: '48060', lat: 42.9836, lng: -82.4583 }], error: null };
        }
        if (table === 'race_listings' && first === 'select') {
          return script.stored ?? { data: [], error: null };
        }
        if (table === 'race_listings' && first === 'insert') {
          return { data: null, error: script.insertError ?? null };
        }
        if (table === 'race_listings' && first === 'update') return { data: null, error: null };
        throw new Error(`unscripted call on ${table}`);
      };
      builder.then = (resolve: (v: unknown) => unknown, reject: (e: unknown) => unknown) =>
        Promise.resolve(answer()).then(resolve, reject);
      return builder;
    },
  };
  const inserted = () =>
    calls
      .filter((c) => c.table === 'race_listings' && c.ops[0]?.[0] === 'insert')
      .flatMap((c) => c.ops[0][1] as Array<Record<string, unknown>>);
  return { calls, inserted, client: client as unknown as DbClient };
}

Deno.test('each race is placed from its ZIP, and one the table cannot place is still written', async () => {
  const fake = fakeService();
  const outcome = await syncProviderPayload(fake.client, 'runsignup', FEED);
  assert(outcome.ok);
  const rows = fake.inserted();
  assert(rows.length > 0);
  assertEquals(outcome.summary.synced, rows.length);
  const placed = rows.filter((r) => r.location_point !== null);
  assertEquals(placed.map((r) => r.location_point), ['SRID=4326;POINT(-82.4583 42.9836)']);
  assertEquals(outcome.summary.unplaced, rows.length - 1);
  assert(rows.every((r) => r.is_verified === true), 'a provider row is verified');
  // One lookup for the whole batch, keyed by distinct ZIPs.
  const lookups = fake.calls.filter((c) => c.table === 'us_zcta_points');
  assertEquals(lookups.length, 1);
  const zips = lookups[0].ops.find((op) => op[0] === 'in')![2] as string[];
  assertEquals(zips.length, new Set(zips).size);
  assert(zips.includes('48060'));
});

Deno.test('a failed ZIP lookup writes every listing without a point, counted', async () => {
  const fake = fakeService({ zips: { data: null, error: { message: 'boom' } } });
  const outcome = await syncProviderPayload(fake.client, 'runsignup', FEED);
  assert(outcome.ok);
  const rows = fake.inserted();
  assert(rows.length > 0);
  assert(rows.every((r) => r.location_point === null));
  assertEquals(outcome.summary.unplaced, rows.length);
});

Deno.test('a stored race without a point gains one, and its verified flag rides along', async () => {
  const fake = fakeService({ stored: { data: null, error: null } });
  const first = await syncProviderPayload(fake.client, 'runsignup', FEED);
  assert(first.ok);
  const placedRow = fake.inserted().find((r) => r.location_point !== null)!;
  const stored = {
    ...placedRow,
    id: 'L-1',
    location_point: null,
  };
  const again = fakeService({ stored: { data: [stored], error: null } });
  const outcome = await syncProviderPayload(again.client, 'runsignup', FEED);
  assert(outcome.ok);
  assertEquals(outcome.summary.updated, 1);
  const update = again.calls.find((c) => c.table === 'race_listings' && c.ops[0]?.[0] === 'update')!;
  const patch = update.ops[0][1] as Record<string, unknown>;
  assertEquals(patch.location_point, 'SRID=4326;POINT(-82.4583 42.9836)');
  assertEquals(patch.is_verified, true);
});

Deno.test('a failed read of what is stored is an error, not an empty calendar', async () => {
  // Treating a read error as "nothing stored" re-inserts every race in the feed
  // and duplicates the calendar on the next sync.
  const fake = fakeService({ stored: { data: null, error: { message: 'boom' } } });
  const outcome = await syncProviderPayload(fake.client, 'runsignup', FEED);
  assertEquals(outcome, { ok: false, status: 500, error: 'listing_read_failed' });
  assertEquals(fake.inserted(), []);
});

Deno.test('a RunSignUp refusal answered with HTTP 200 is an upstream error, and writes nothing', async () => {
  const fake = fakeService();
  const outcome = await syncProviderPayload(fake.client, 'runsignup', {
    error: { error_code: 13, error_msg: 'You must be logged in to the API as a user' },
  });
  assertEquals(outcome, { ok: false, status: 502, error: 'runsignup upstream error' });
  assertEquals(fake.calls, []);
});

Deno.test('a payload of the wrong shape answers what it could not read, and writes nothing', async () => {
  const fake = fakeService();
  const outcome = await syncProviderPayload(fake.client, 'runsignup', {
    races: [{ race: { race_id: 1 } }, { race: { name: 'No date' } }],
  });
  assertEquals(outcome, {
    ok: true,
    summary: {
      synced: 0,
      updated: 0,
      skipped: 0,
      unusable: 2,
      excluded: 0,
      unplaced: 0,
      total: 2,
      complete: true,
    },
  });
  assertEquals(fake.calls, []);
});
