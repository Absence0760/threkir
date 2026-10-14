/// The write half (write.ts) run the way the five-minute sweep runs it: against
/// a stateful in-memory `race_listings` and `us_zcta_points`, pass after pass.
///
/// write.test.ts pins one pass against a scripted answer. What these pin is
/// what only shows across passes or across odd inputs — the failure modes that
/// would corrupt or stall the calendar with nobody watching: a second pass of
/// the same page duplicating every race, an edited race inserted beside its old
/// self instead of rewriting it, and a ZIP read loosely enough to put a race in
/// somebody else's town. No stack, no network.
///
/// Run with `cd apps/backend && deno test --no-check --allow-read --allow-env
/// supabase/functions/race-listings-sync/robustness.test.ts`.

import { assert, assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import type { DbClient } from '../_shared/database.ts';
import { syncProviderPayload } from './write.ts';

type Row = Record<string, unknown>;
type Filter = { op: 'eq' | 'in'; col: string; val: unknown };

/// A PostgREST-shaped client over two in-memory tables. `select` honours `eq`
/// and `in`; `insert` appends with a generated id and enforces the partial
/// unique index `race_listings_provider_uniq` the way Postgres would (23505,
/// the whole statement refused); `update` patches by `eq`.
function memoryDb(zcta: Array<{ zcta: string; lat: number; lng: number }>) {
  const listings: Row[] = [];
  const statements: Array<{ table: string; verb: string; filters: Filter[]; payload?: unknown }> = [];
  let nextId = 1;
  const client = {
    from(table: string) {
      let verb = '';
      let payload: unknown;
      const filters: Filter[] = [];
      const builder: Record<string, unknown> = {
        select: () => {
          verb ||= 'select';
          return builder;
        },
        insert: (rows: unknown) => {
          verb = 'insert';
          payload = rows;
          return builder;
        },
        update: (patch: unknown) => {
          verb = 'update';
          payload = patch;
          return builder;
        },
        eq: (col: string, val: unknown) => {
          filters.push({ op: 'eq', col, val });
          return builder;
        },
        in: (col: string, val: unknown) => {
          filters.push({ op: 'in', col, val });
          return builder;
        },
      };
      const matches = (row: Row) =>
        filters.every((f) =>
          f.op === 'eq' ? row[f.col] === f.val : (f.val as unknown[]).includes(row[f.col])
        );
      const answer = () => {
        statements.push({ table, verb, filters: [...filters], payload });
        const source = table === 'us_zcta_points' ? zcta as unknown as Row[] : listings;
        if (verb === 'select') return { data: source.filter(matches).map((r) => ({ ...r })), error: null };
        if (verb === 'insert') {
          const rows = payload as Row[];
          const key = (r: Row) => `${r.provider}|${r.provider_race_id}`;
          const taken = new Set(listings.filter((r) => r.provider_race_id !== null).map(key));
          for (const r of rows) {
            if (r.provider_race_id === null) continue;
            if (taken.has(key(r))) {
              return { data: null, error: { code: '23505', message: 'race_listings_provider_uniq' } };
            }
            taken.add(key(r));
          }
          for (const r of rows) listings.push({ id: `L-${nextId++}`, ...r });
          return { data: null, error: null };
        }
        if (verb === 'update') {
          for (const r of listings.filter(matches)) Object.assign(r, payload as Row);
          return { data: null, error: null };
        }
        throw new Error(`unscripted ${verb} on ${table}`);
      };
      builder.then = (resolve: (v: unknown) => unknown, reject: (e: unknown) => unknown) =>
        Promise.resolve().then(answer).then(resolve, reject);
      return builder;
    },
  };
  return { listings, statements, client: client as unknown as DbClient };
}

function race(id: number | string, over: Row = {}, address: Row = {}): Row {
  return {
    race: {
      race_id: id,
      name: `Race ${id}`,
      next_date: '06/12/2027',
      is_draft_race: 'F',
      is_private_race: 'F',
      url: `https://runsignup.com/Race/${id}`,
      address: { city: 'Boston', state: 'MA', zipcode: '02134', country_code: 'US', ...address },
      events: [{ event_id: 1, event_type: 'running_race', distance: '5K', volunteer: 'F' }],
      ...over,
    },
  };
}

const ALLSTON = { zcta: '02134', lat: 42.3586, lng: -71.1316 };
/// A real Manhattan ZCTA that is also a real Berlin postcode.
const MANHATTAN = { zcta: '10115', lat: 40.8111, lng: -73.9642 };
const ALLSTON_EWKT = 'SRID=4326;POINT(-71.1316 42.3586)';

Deno.test('a second pass of the same page writes nothing: no insert, no update', async () => {
  const db = memoryDb([ALLSTON]);
  const page = { races: [race(1), race(2), race(3)] };

  const first = await syncProviderPayload(db.client, 'runsignup', page);
  assert(first.ok);
  assertEquals(first.summary.synced, 3);
  assertEquals(db.listings.length, 3);

  const before = db.statements.length;
  const second = await syncProviderPayload(db.client, 'runsignup', page);
  assert(second.ok);
  assertEquals([second.summary.synced, second.summary.updated], [0, 0]);
  assertEquals(db.listings.length, 3, 'a repeated page must never duplicate a race');
  const writes = db.statements.slice(before).filter((s) => s.verb !== 'select');
  assertEquals(writes, [], 'steady state is zero writes, not one rewrite per race');

  // What is stored is looked up by the conflict key the unique index guards —
  // (provider, provider_race_id) — so another provider's race 1 is not it.
  const read = db.statements.slice(before).find((s) => s.table === 'race_listings' && s.verb === 'select')!;
  assertEquals(read.filters, [
    { op: 'eq', col: 'provider', val: 'runsignup' },
    { op: 'in', col: 'provider_race_id', val: ['1', '2', '3'] },
  ]);
});

Deno.test('an edited race is rewritten in place on the next pass, never inserted beside itself', async () => {
  const db = memoryDb([ALLSTON]);
  await syncProviderPayload(db.client, 'runsignup', { races: [race(1), race(2)] });
  const id = db.listings.find((r) => r.provider_race_id === '1')!.id;

  const moved = race(1, { name: 'Race 1 (new date)', next_date: '06/19/2027' });
  const outcome = await syncProviderPayload(db.client, 'runsignup', { races: [moved, race(2)] });
  assert(outcome.ok);
  assertEquals([outcome.summary.synced, outcome.summary.updated], [0, 1]);
  assertEquals(db.listings.length, 2);
  const row = db.listings.find((r) => r.provider_race_id === '1')!;
  assertEquals(row.id, id, 'the same listing row, so links and imports keyed on it survive');
  assertEquals([row.name, row.race_date], ['Race 1 (new date)', '2027-06-19']);
  // The update is addressed to that one row, not to every row the filter
  // could reach.
  const update = db.statements.find((s) => s.verb === 'update')!;
  assertEquals(update.filters, [{ op: 'eq', col: 'id', val: id }]);
});

Deno.test('a race repeated inside one page, or keyed by a number one pass and a string the next, is one listing', async () => {
  const db = memoryDb([ALLSTON]);
  const outcome = await syncProviderPayload(db.client, 'runsignup', { races: [race(7), race(7), race(8)] });
  assert(outcome.ok);
  assertEquals([outcome.summary.synced, outcome.summary.skipped], [2, 1]);
  // RunSignUp writes `race_id` as a number; the column is text. Read as '7'
  // both times, so a feed that flips the JSON type is still the same race.
  const again = await syncProviderPayload(db.client, 'runsignup', { races: [race('7')] });
  assert(again.ok);
  assertEquals(again.summary.synced, 0);
  assertEquals(db.listings.filter((r) => r.provider_race_id === '7').length, 1);
});

Deno.test('ZIP+4, padding and a leading zero are one ZIP; a lost zero, foreign code or unknown ZIP is unplaced, never misplaced', async () => {
  const db = memoryDb([ALLSTON, MANHATTAN]);
  const page = {
    races: [
      race(1, {}, { zipcode: '02134-1234' }),
      race(2, {}, { zipcode: ' 02134 ' }),
      race(3, {}, { zipcode: '02134' }),
      // A JSON number has already lost its leading zero: '2134' is no ZIP at all,
      // and must not be padded into a guess.
      race(4, {}, { zipcode: 2134 }),
      race(5, {}, { zipcode: '2134' }),
      // Berlin-Mitte's postcode is also a Manhattan ZCTA. Only a US address is
      // looked up, so this race stays off the map rather than in New York.
      race(6, {}, { city: 'Berlin', state: 'BE', zipcode: '10115', country_code: 'DE' }),
      race(7, {}, { city: 'London', state: null, zipcode: 'SW1A 1AA', country_code: 'GB' }),
      // A five-digit ZIP with no ZCTA (a PO-box ZIP): written, not placed.
      race(8, {}, { zipcode: '02123' }),
      race(9, {}, { zipcode: null }),
    ],
  };
  const outcome = await syncProviderPayload(db.client, 'runsignup', page);
  assert(outcome.ok);
  assertEquals(outcome.summary.synced, 9, 'placing a race is never a reason not to list it');

  const pointOf = (id: string) => db.listings.find((r) => r.provider_race_id === id)!.location_point;
  assertEquals(['1', '2', '3'].map(pointOf), [ALLSTON_EWKT, ALLSTON_EWKT, ALLSTON_EWKT]);
  assertEquals(['4', '5', '6', '7', '8', '9'].map(pointOf), [null, null, null, null, null, null]);
  assertEquals(outcome.summary.unplaced, 6);

  // One lookup, of the distinct normalised US ZIPs only: neither the foreign
  // code nor the zero-stripped number is ever asked for.
  const lookups = db.statements.filter((s) => s.table === 'us_zcta_points');
  assertEquals(lookups.length, 1);
  assertEquals(lookups[0].filters, [{ op: 'in', col: 'zcta', val: ['02134', '02123'] }]);
});

Deno.test('a body that is not the race feed is a 502 that touches nothing; an empty window is an honest zero', async () => {
  // `{"races":[]}` is what RunSignUp answers for a window with no race. Any
  // other shape is the feed having moved, and reading it as zero races would
  // let every run report success while the calendar stops filling.
  for (const payload of [{}, null, [], 'races', { races: null }, { data: { races: [race(1)] } }, [race(1)]]) {
    const db = memoryDb([ALLSTON]);
    const outcome = await syncProviderPayload(db.client, 'runsignup', payload);
    assertEquals(outcome, { ok: false, status: 502, error: 'runsignup upstream shape' }, JSON.stringify(payload));
    assertEquals(db.statements, []);
  }
  const db = memoryDb([ALLSTON]);
  const empty = await syncProviderPayload(db.client, 'runsignup', { races: [] });
  assert(empty.ok);
  assertEquals([empty.summary.total, empty.summary.synced, empty.summary.complete], [0, 0, true]);
  assertEquals(db.statements, []);
});

Deno.test('a page with broken rows writes only the readable races, and says how many it could not read', async () => {
  const db = memoryDb([ALLSTON]);
  const outcome = await syncProviderPayload(db.client, 'runsignup', {
    races: [
      race(1),
      race(2, { name: null }),
      race(3, { next_date: '13/40/2027', last_date: null }),
      race(4, { events: [] }),
      race(5, { events: undefined }),
      'not a race',
      race(6, { events: [{ event_type: 'virtual_race', distance: '5K' }] }),
    ],
  });
  assert(outcome.ok);
  assertEquals(outcome.summary.unusable, 2, 'no name, and a date no calendar has');
  assertEquals(outcome.summary.excluded, 1, 'a virtual-only race has no start line');
  // A race listed before its events are published is still a race: filed with
  // no distance band rather than dropped.
  assertEquals(db.listings.map((r) => [r.provider_race_id, r.distance_m]), [['1', 5000], ['4', null], ['5', null]]);
  assertEquals(outcome.summary.synced, 3);
});
