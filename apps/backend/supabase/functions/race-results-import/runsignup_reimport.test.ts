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

interface State {
  listing: Row;
  runs: Row[];
  failRunsRead?: boolean;
  /// The caller; `runner-1` unless a test signs in as someone else.
  userId?: string;
}

/// `runs` keeps what was inserted. A select honours `eq` / `in` and returns the
/// columns it names; an insert or an update that would repeat a stored
/// `(user_id, external_id)` is refused whole with 23505, and an update writes
/// only the rows its `eq` filters reach.
function memoryClient(state: State) {
  const client = {
    auth: { getUser: () => Promise.resolve({ data: { user: { id: state.userId ?? 'runner-1' } } }) },
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
        update: (patch: unknown) => {
          verb = 'update';
          payload = patch;
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
        const hit = state.runs.filter((r) =>
          filters.every(([op, col, val]) =>
            op === 'eq' ? r[col] === val : (val as unknown[]).includes(r[col])
          )
        );
        if (verb === 'update') {
          const patch = payload as Row;
          const others = state.runs.filter((r) => !hit.includes(r));
          const clash = hit.some((r) =>
            'external_id' in patch &&
            others.some((o) => o.user_id === r.user_id && o.external_id === patch.external_id)
          );
          if (clash) return { data: null, error: { code: '23505', message: 'runs_user_external_id' } };
          for (const r of hit) Object.assign(r, patch);
          return { data: null, error: null };
        }
        if (state.failRunsRead) return { data: null, error: { code: '57014', message: 'canceling statement' } };
        const cols = columns.split(',').map((c) => c.trim());
        if (cols.every((c) => /^[a-z_]+$/.test(c))) {
          return {
            data: hit.map((r) => Object.fromEntries(cols.map((c) => [c, r[c] ?? null]))),
            error: null,
          };
        }
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

function importer(state: State) {
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

// ── A pasted result and a provider import of the same race (decisions § 1912) ──

function paste(result: Record<string, unknown>): Request {
  return new Request('http://localhost/race-results-import', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: 'Bearer user-jwt' },
    body: JSON.stringify({ provider: 'paste', listingId: LISTING_ID, result }),
  });
}

// Bib 336 in the recorded feed: place 10, chip 21:23.75, clock 21:41.08.

Deno.test('a bib-less paste and a later RunSignUp import of the same finish are one run, which gains the bib', async () => {
  const state: State = { listing: { ...LISTING }, runs: [] };
  // The runner typed the chip time as the results page rounded it.
  const pasted = await importer(state)(paste({ chip_time: '21:24' }));
  assertEquals((await pasted.json()).imported, 1);
  assertEquals(state.runs[0].external_id, 'race:Example 5K to Wellness:2026-09-19:');

  const imported = await importer(state)(call('336'));
  assertEquals(await imported.json(), { imported: 0, skipped: 0, enriched: 1, complete: true });
  assertEquals(state.runs.length, 1, 'one finish, one run');
  const run = state.runs[0];
  assertEquals(run.external_id, 'race:Example 5K to Wellness:2026-09-19:336');
  assertEquals((run.metadata as Row).bib, '336');
  assertEquals((run.metadata as Row).chip_time, '21:23.75');
  assertEquals((run.metadata as Row).overall_place, 10);
  assertEquals(run.duration_s, 21 * 60 + 24);

  // From here the run is the provider's, and the cheap rules see it.
  const again = await importer(state)(call('336'));
  assertEquals(await again.json(), { imported: 0, skipped: 1, enriched: 0, complete: true });
  assertEquals(state.runs.length, 1);
});

Deno.test('a bib-less paste after the RunSignUp import of the same finish is skipped, not filed again', async () => {
  const state: State = { listing: { ...LISTING }, runs: [] };
  await importer(state)(call('336'));
  // The clock time, cut to the second, in the gun box.
  const res = await importer(state)(paste({ gun_time: '21:41', overall_place: 10 }));
  assertEquals(await res.json(), { imported: 0, skipped: 1, enriched: 0, complete: true });
  assertEquals(state.runs.length, 1);
  assertEquals((state.runs[0].metadata as Row).bib, '336', 'the provider result is left as it was');
});

Deno.test('the same runner in two events of one race morning is two runs, whichever path each came by', async () => {
  const state: State = { listing: { ...LISTING }, runs: [] };
  // The kids' mile at 07:30, pasted with no bib, then the 5K by bib.
  await importer(state)(paste({ chip_time: '7:58', overall_place: 10 }));
  const res = await importer(state)(call('336'));
  assertEquals(await res.json(), { imported: 1, skipped: 0, enriched: 0, complete: true });
  assertEquals(state.runs.length, 2);
  assertEquals((state.runs[0].metadata as Row).bib, undefined, 'the mile keeps no bib it never had');
  assertEquals((state.runs[0].metadata as Row).chip_time, '7:58');
});

Deno.test('a matching clock under a different place is a different finisher, not this one', async () => {
  const state: State = { listing: { ...LISTING }, runs: [] };
  // A dead heat a place apart: same second, different finisher.
  await importer(state)(paste({ chip_time: '21:24', overall_place: 9 }));
  const res = await importer(state)(call('336'));
  assertEquals((await res.json()).imported, 1);
  assertEquals(state.runs.length, 2);
  assertEquals((state.runs[0].metadata as Row).overall_place, 9);
});

Deno.test('another runner\'s identical paste is never this runner\'s finish', async () => {
  const state: State = { listing: { ...LISTING }, runs: [], userId: 'runner-2' };
  await importer(state)(paste({ chip_time: '21:24' }));
  state.userId = 'runner-1';
  const res = await importer(state)(call('336'));
  assertEquals(await res.json(), { imported: 1, skipped: 0, enriched: 0, complete: true });
  assertEquals(state.runs.length, 2);
  const theirs = state.runs.find((r) => r.user_id === 'runner-2')!;
  assertEquals((theirs.metadata as Row).bib, undefined, 'the other runner\'s run is untouched');
  assertEquals(theirs.external_id, 'race:Example 5K to Wellness:2026-09-19:');
});
