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
import { syncParkrunPayload, syncProviderPayload } from './write.ts';

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

const PARKRUN = JSON.parse(
  Deno.readTextFileSync(new URL('./fixtures/parkrun_events.json', import.meta.url)),
);
/// Wednesday 2026-10-14 12:00 UTC.
const WED = Date.UTC(2026, 9, 14, 12, 0);
const ALL_CHUNK = { kind: 'chunk' as const, index: 0, count: 1 };

Deno.test('parkrun events are written at the feed\'s own point, with no ZIP lookup', async () => {
  const fake = fakeService();
  const outcome = await syncParkrunPayload(fake.client, PARKRUN, ALL_CHUNK, WED);
  assert(outcome.ok);
  const rows = fake.inserted();
  assertEquals(rows.length, 11);
  assertEquals(outcome.summary.synced, 11);
  assertEquals(outcome.summary.unplaced, 0);
  assertEquals(fake.calls.filter((c) => c.table === 'us_zcta_points'), []);
  const bushy = rows.find((r) => r.provider_race_id === '1')!;
  assertEquals(bushy, {
    provider: 'parkrun',
    provider_race_id: '1',
    name: 'Bushy parkrun',
    race_date: '2026-10-17',
    distance_m: 5000,
    location_label: 'Bushy Park, Teddington',
    location_point: 'SRID=4326;POINT(-0.335791 51.410992)',
    entry_url: 'https://www.parkrun.org.uk/bushy/',
    results_url: null,
    is_verified: true,
  });
  const read = fake.calls.find((c) => c.table === 'race_listings' && c.ops[0]?.[0] === 'select')!;
  assert(read.ops.some((op) => op[0] === 'eq' && op[1] === 'provider' && op[2] === 'parkrun'));
});

Deno.test('a near scope writes only the events around the point', async () => {
  const fake = fakeService();
  const outcome = await syncParkrunPayload(
    fake.client,
    PARKRUN,
    { kind: 'near', lat: 51.5074, lng: -0.1278, radiusM: 25_000 },
    WED,
  );
  assert(outcome.ok);
  assertEquals(fake.inserted().map((r) => r.provider_race_id), ['2', '32', '1']);
  assertEquals(outcome.summary.total, 3);
});

Deno.test('a body that is not parkrun\'s events file is a 502 that writes nothing', async () => {
  const fake = fakeService();
  const outcome = await syncParkrunPayload(fake.client, { races: [] }, ALL_CHUNK, WED);
  assertEquals(outcome, { ok: false, status: 502, error: 'parkrun upstream shape' });
  assertEquals(fake.calls, []);
});
