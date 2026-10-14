/// The RunSignUp import run twice, against a stateful in-memory `runs` that
/// enforces the per-user unique index on `(user_id, external_id)` the way
/// Postgres would.
///
/// handler.test.ts answers every `runs` read with an empty history, so it can
/// only see a FIRST import. The question a runner asks twice is whether the
/// second press files the race again — including after the five-minute
/// calendar sweep has renamed the listing to follow RunSignUp (decisions
/// § 1902), which changes the `race:{name}:{date}:{bib}` id the first import
/// was stored under. No stack, no network.
///
/// Run with `cd apps/backend && deno test --no-check --allow-read --allow-env
/// supabase/functions/race-results-import/runsignup_reimport.test.ts`.

import { assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import type { DbClient } from '../_shared/database.ts';
import { makeRaceResultsImportHandler } from './handler.ts';

const RACE_TEXT = Deno.readTextFileSync(new URL('./fixtures/runsignup_race.json', import.meta.url));
const RESULTS = JSON.parse(
  Deno.readTextFileSync(new URL('./fixtures/runsignup_results.json', import.meta.url)),
);
const LISTING_ID = '11111111-2222-4333-8444-555555555555';
const LISTING = {
  id: LISTING_ID,
  provider: 'runsignup',
  provider_race_id: '108839',
  name: 'Example 5K to Wellness',
  race_date: '2026-09-19',
  distance_m: 5000,
};

type Row = Record<string, unknown>;

/// `runs` keeps what was inserted. A select honours `eq` / `in`, including
/// the JSON-path alias `bib:metadata->>bib`; an insert that repeats a stored
/// `(user_id, external_id)` is refused whole with 23505.
function memoryClient(state: { listing: Row; runs: Row[]; failRunsRead?: boolean }) {
  const client = {
    auth: { getUser: () => Promise.resolve({ data: { user: { id: 'runner-1' } } }) },
    rpc: () => Promise.resolve({ data: [{ allowed: true, retry_after_seconds: 0, tier: 'free' }], error: null }),
    from(table: string) {
      let verb = 'select';
      let columns = '';
      let payload: unknown;
      const filters: Array<[string, string, unknown]> = [];
      const builder: Record<string, unknown> = {
        select: (cols: string) => {
          columns = cols;
          return builder;
        },
        insert: (rows: unknown) => {
          verb = 'insert';
          payload = rows;
          return builder;
        },
        eq: (col: string, val: unknown) => {
          filters.push(['eq', col, val]);
          return builder;
        },
        in: (col: string, val: unknown) => {
          filters.push(['in', col, val]);
          return builder;
        },
      };
      const answer = () => {
        if (table === 'public_race_listings') return { data: state.listing, error: null };
        if (table === 'user_settings') return { data: null, error: null };
        if (table !== 'runs') throw new Error(`unscripted call on ${table}`);
        if (verb === 'insert') {
          const rows = payload as Row[];
          const key = (r: Row) => `${r.user_id}|${r.external_id}`;
          const taken = new Set(state.runs.map(key));
          if (rows.some((r) => taken.has(key(r)))) {
            return { data: null, error: { code: '23505', message: 'runs_user_external_id' } };
          }
          state.runs.push(...rows);
          return { data: null, error: null };
        }
        if (state.failRunsRead) return { data: null, error: { code: '57014', message: 'canceling statement' } };
        const hit = state.runs.filter((r) =>
          filters.every(([op, col, val]) =>
            op === 'eq' ? r[col] === val : (val as unknown[]).includes(r[col])
          )
        );
        if (columns === 'bib:metadata->>bib') {
          return { data: hit.map((r) => ({ bib: (r.metadata as Row).bib ?? null })), error: null };
        }
        if (columns === 'external_id') return { data: hit.map((r) => ({ external_id: r.external_id })), error: null };
        throw new Error(`unscripted runs select ${columns}`);
      };
      builder.maybeSingle = () => Promise.resolve(answer());
      builder.then = (resolve: (v: unknown) => unknown, reject: (e: unknown) => unknown) =>
        Promise.resolve().then(answer).then(resolve, reject);
      return builder;
    },
  };
  return client as unknown as DbClient;
}

function feed(url: string): Response {
  const u = new URL(url);
  if (u.pathname === '/Rest/race/108839') return new Response(RACE_TEXT, { status: 200 });
  const set = RESULTS.individual_results_sets[0];
  const results = set.results.filter((r: { bib: number }) => String(r.bib) === u.searchParams.get('bib_num'));
  return Response.json({ individual_results_sets: [{ ...set, results }] });
}

function importer(state: { listing: Row; runs: Row[]; failRunsRead?: boolean }) {
  return makeRaceResultsImportHandler({
    getEnv: () => undefined,
    userClient: () => memoryClient(state),
    fetch: (input) => Promise.resolve(feed(String(input))),
  });
}

function call(bib: string): Request {
  return new Request('http://localhost/race-results-import', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: 'Bearer user-jwt' },
    body: JSON.stringify({ provider: 'runsignup', listingId: LISTING_ID, bib }),
  });
}

Deno.test('importing the same bib twice files the race once, and says so', async () => {
  const state = { listing: { ...LISTING }, runs: [] as Row[] };
  const first = await importer(state)(call('336'));
  assertEquals(await first.json(), { imported: 1, skipped: 0, enriched: 0, complete: true });
  const second = await importer(state)(call('336'));
  assertEquals(second.status, 200);
  assertEquals(await second.json(), { imported: 0, skipped: 1, enriched: 0, complete: true });
  assertEquals(state.runs.length, 1);
  assertEquals(state.runs[0].external_id, 'race:Example 5K to Wellness:2026-09-19:336');
  // `runs.race_listing_id` is `on delete set null`, so a run can outlive its
  // listing. The same race re-listed under a new row still matches by its id.
  state.runs[0].race_listing_id = null;
  const third = await importer(state)(call('336'));
  assertEquals(await third.json(), { imported: 0, skipped: 1, enriched: 0, complete: true });
  assertEquals(state.runs.length, 1);
});

Deno.test('a re-import after the sweep renamed the listing is still the same race, not a second run', async () => {
  const state = { listing: { ...LISTING }, runs: [] as Row[] };
  await importer(state)(call('336'));
  // RunSignUp retitled the race; the next sweep rewrote the listing in place.
  state.listing = { ...LISTING, name: 'Example 5K to Wellness presented by Sponsor' };
  const again = await importer(state)(call('336'));
  assertEquals(await again.json(), { imported: 0, skipped: 1, enriched: 0, complete: true });
  assertEquals(state.runs.length, 1, 'one race, one run');
  // A different runner's bib on the same listing is a different result.
  const other = await importer(state)(call('337'));
  assertEquals((await other.json()).imported, 1);
  assertEquals(state.runs.length, 2);
});

Deno.test('a history that cannot be read refuses the import rather than risk a duplicate', async () => {
  const state = { listing: { ...LISTING }, runs: [] as Row[] };
  await importer(state)(call('336'));
  const res = await importer({ ...state, listing: { ...LISTING, name: 'Renamed' }, failRunsRead: true })(call('336'));
  assertEquals(res.status, 500);
  assertEquals(await res.json(), { error: 'race import could not check for duplicates' });
  assertEquals(state.runs.length, 1);
});
