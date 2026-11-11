/// race-results-import's handler (handler.ts) driven with a fake caller client
/// and a fake `fetch`: the auth gate, which rate-limit bucket each mode spends,
/// the import's error paths, the keyless RunSignUp leg against its recorded
/// feed, and the refusal of the retired UltraSignup leg — each of which must
/// answer before anything is written, and most before anything is fetched. No
/// stack, no network.
///
/// Run with `cd apps/backend && deno test --allow-read --allow-env
/// supabase/functions/race-results-import/handler.test.ts`.

import { assert, assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import type { DbClient } from '../_shared/database.ts';
import { makeRaceResultsImportHandler } from './handler.ts';

const LISTING_ID = '11111111-2222-4333-8444-555555555555';
const RSU_RACE_TEXT = Deno.readTextFileSync(new URL('./fixtures/runsignup_race.json', import.meta.url));
const RSU_RESULTS = JSON.parse(
  Deno.readTextFileSync(new URL('./fixtures/runsignup_results.json', import.meta.url)),
);
const RSU_LISTING = {
  id: LISTING_ID,
  provider: 'runsignup',
  provider_race_id: '108839',
  name: 'Example 5K to Wellness',
  race_date: '2026-09-19',
  distance_m: 5000,
};
const RSU_IMPORT = { provider: 'runsignup', listingId: LISTING_ID, bib: '336' };

/// The two RunSignUp endpoints, answered as the live feed answers them: the race
/// with its editions, and get-results narrowed by `bib_num`.
function runSignUpFeed(url: string): Response {
  const u = new URL(url);
  if (u.pathname === '/Rest/race/108839') return new Response(RSU_RACE_TEXT, { status: 200 });
  const bib = u.searchParams.get('bib_num');
  const set = RSU_RESULTS.individual_results_sets[0];
  const results = set.results.filter((r: { bib: number }) => String(r.bib) === bib);
  return Response.json({ individual_results_sets: [{ ...set, results }] });
}


type Op = [string, ...unknown[]];
interface Call {
  table: string;
  ops: Op[];
}
interface Rpc {
  name: string;
  args: Record<string, unknown>;
}

interface Script {
  user?: { id: string } | null;
  limiter?: { data: unknown; error: { code: string } | null };
  listing?: { data: unknown; error: { code: string } | null };
  insertError?: { code: string } | null;
}

/// A caller-scoped client: `auth.getUser`, the tiered limiter RPC, and the
/// listing / settings / runs reads and the runs insert.
function fakeClient(script: Script) {
  const rpcs: Rpc[] = [];
  const calls: Call[] = [];
  const client = {
    auth: {
      getUser: () =>
        Promise.resolve({ data: { user: script.user === undefined ? { id: 'runner-1' } : script.user } }),
    },
    rpc(name: string, args: Record<string, unknown>) {
      rpcs.push({ name, args });
      return Promise.resolve(
        script.limiter ?? { data: [{ allowed: true, retry_after_seconds: 0, tier: 'free' }], error: null },
      );
    },
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
        if (table === 'public_race_listings') return script.listing ?? { data: RSU_LISTING, error: null };
        if (table === 'user_settings') return { data: null, error: null };
        if (table === 'runs' && call.ops[0]?.[0] === 'insert') {
          return { data: null, error: script.insertError ?? null };
        }
        if (table === 'runs') return { data: [], error: null };
        throw new Error(`unscripted call on ${table}`);
      };
      builder.maybeSingle = () => Promise.resolve(answer());
      builder.then = (resolve: (v: unknown) => unknown, reject: (e: unknown) => unknown) =>
        Promise.resolve(answer()).then(resolve, reject);
      return builder;
    },
  };
  return { rpcs, calls, client: client as unknown as DbClient };
}

function harness(opts: {
  script?: Script;
  env?: Record<string, string | undefined>;
  upstream?: (url: string) => Response;
} = {}) {
  const env: Record<string, string | undefined> = { ...(opts.env ?? {}) };
  const fake = fakeClient(opts.script ?? {});
  const fetched: string[] = [];
  let clients = 0;
  const handler = makeRaceResultsImportHandler({
    getEnv: (name) => env[name],
    userClient: () => {
      clients += 1;
      return fake.client;
    },
    fetch: (input) => {
      fetched.push(String(input));
      return Promise.resolve((opts.upstream ?? runSignUpFeed)(String(input)));
    },
  });
  const inserts = () => fake.calls.filter((c) => c.table === 'runs' && c.ops[0]?.[0] === 'insert');
  return { handler, fake, fetched, inserts, clients: () => clients };
}

function call(body: unknown, auth: string | null = 'Bearer user-jwt'): Request {
  const headers = new Headers({ 'Content-Type': 'application/json' });
  if (auth) headers.set('Authorization', auth);
  return new Request('http://localhost/race-results-import', {
    method: 'POST',
    headers,
    body: JSON.stringify(body),
  });
}

const bucketOf = (rpcs: Rpc[]) =>
  rpcs.map((r) => [r.name, r.args.p_bucket, r.args.p_free_max, r.args.p_pro_max, r.args.p_window_seconds]);

// ── the auth gate ──

Deno.test('no Authorization header: 401 before a client exists', async () => {
  const h = harness();
  const res = await h.handler(call(RSU_IMPORT, null));
  assertEquals(res.status, 401);
  assertEquals(h.clients(), 0);
  assertEquals(h.fetched, []);
});

Deno.test('a token that resolves to no user: 401, nothing spent', async () => {
  const h = harness({ script: { user: null } });
  const res = await h.handler(call(RSU_IMPORT));
  assertEquals(res.status, 401);
  assertEquals(h.fake.rpcs, []);
  assertEquals(h.fetched, []);
});

// ── the buckets ──

Deno.test('an import and a probe each spend their own bucket', async () => {
  const imp = harness();
  await imp.handler(call(RSU_IMPORT));
  assertEquals(bucketOf(imp.fake.rpcs), [['check_rate_limit_tiered', 'race-results-import', 8, 32, 3600]]);

  const probe = harness();
  await probe.handler(call({ provider: 'runsignup', probe: true }));
  assertEquals(bucketOf(probe.fake.rpcs), [['check_rate_limit_tiered', 'race-results-import:probe', 60, 240, 3600]]);
});

Deno.test('an exhausted import bucket is a 429 with no upstream call', async () => {
  const h = harness({
    script: { limiter: { data: [{ allowed: false, retry_after_seconds: 120, tier: 'free' }], error: null } },
  });
  const res = await h.handler(call(RSU_IMPORT));
  assertEquals(res.status, 429);
  const body = await res.json();
  assertEquals(body.bucket, 'race-results-import');
  assertEquals(h.fetched, []);
});

Deno.test('a limiter outage fails the import closed', async () => {
  const h = harness({ script: { limiter: { data: null, error: { code: '57014' } } } });
  const res = await h.handler(call(RSU_IMPORT));
  assertEquals(res.status, 503);
  assertEquals(h.fetched, []);
});

// ── the retired UltraSignup leg (decisions § SCRAPER_ADR) ──

Deno.test('ultrasignup: a probe, a lookup and an import are all refused, nothing fetched', async () => {
  const probe = harness();
  const p = await probe.handler(call({ provider: 'ultrasignup', probe: true, ultraSignUpFlow: 'person' }));
  assertEquals(p.status, 400);
  assertEquals(await p.json(), { error: 'unknown_provider' });

  const lookup = harness();
  const l = await lookup.handler(
    call({ provider: 'ultrasignup', lookup: true, ultraSignUpFirstName: 'Alex', ultraSignUpLastName: 'Sample' }),
  );
  assertEquals(l.status, 400);
  assertEquals(lookup.fake.rpcs[0].args.p_bucket, 'race-results-import');

  const imp = harness({
    script: { listing: { data: { ...RSU_LISTING, provider: 'ultrasignup', provider_race_id: '500101' }, error: null } },
  });
  const i = await imp.handler(call({
    provider: 'ultrasignup',
    listingId: LISTING_ID,
    ultraSignUpPersonId: '900001',
    ultraSignUpFirstName: 'Alex',
    ultraSignUpLastName: 'Sample',
  }));
  assertEquals(i.status, 400);
  assertEquals(await i.json(), { error: 'unsupported provider' });

  for (const h of [probe, lookup, imp]) {
    assertEquals(h.fetched, []);
    assertEquals(h.inserts(), []);
  }
});

// ── the import's error paths ──

Deno.test('import: a missing or malformed listing id is a 400 before the listing is read', async () => {
  for (const [listingId, error] of [[undefined, 'listingId required'], ['L-1', 'listingId must be a UUID']]) {
    const h = harness();
    const res = await h.handler(call({ ...RSU_IMPORT, listingId }));
    assertEquals(res.status, 400);
    assertEquals(await res.json(), { error });
    assert(!h.fake.calls.some((c) => c.table === 'public_race_listings'));
  }
});

Deno.test('import: an unreadable or missing listing is a 404', async () => {
  for (const listing of [{ data: null, error: null }, { data: null, error: { code: '57014' } }]) {
    const h = harness({ script: { listing } });
    const res = await h.handler(call(RSU_IMPORT));
    assertEquals(res.status, 404);
    assertEquals(h.fetched, []);
  }
});

Deno.test('import: a listing with no RunSignUp race id is refused, nothing fetched', async () => {
  const h = harness({ script: { listing: { data: { ...RSU_LISTING, provider_race_id: null }, error: null } } });
  const res = await h.handler(call(RSU_IMPORT));
  assertEquals(res.status, 400);
  assertEquals(await res.json(), { error: 'listing has no RunSignUp race id' });
  assertEquals(h.fetched, []);
});

Deno.test('import: an upstream error or a non-JSON page is a 502 that writes nothing', async () => {
  const down = harness({ upstream: () => new Response('nope', { status: 500 }) });
  const r1 = await down.handler(call(RSU_IMPORT));
  assertEquals(r1.status, 502);
  assertEquals(await r1.json(), { error: 'runsignup upstream 500' });
  assertEquals(down.inserts(), []);

  const html = harness({ upstream: () => new Response('<html>', { status: 200 }) });
  const r2 = await html.handler(call(RSU_IMPORT));
  assertEquals(r2.status, 502);
  assertEquals(html.inserts(), []);
});

Deno.test('import: a failed insert is a 500, not a reported import', async () => {
  const h = harness({ script: { insertError: { code: '23505' } } });
  const res = await h.handler(call(RSU_IMPORT));
  assertEquals(res.status, 500);
  assertEquals(await res.json(), { error: 'race import failed to save' });
});

// ── RunSignUp: keyless, bib-scoped, event-resolved ──

Deno.test('runsignup probe: configured on a deployment with no RunSignUp key', async () => {
  const h = harness();
  const res = await h.handler(call({ provider: 'runsignup', probe: true }));
  assertEquals(res.status, 200);
  assertEquals(await res.json(), { configured: true });
});

Deno.test('runsignup import: no bib is a 400 before anything is fetched', async () => {
  const h = harness();
  const res = await h.handler(call({ provider: 'runsignup', listingId: LISTING_ID, runSignUpUserId: '42' }));
  assertEquals(res.status, 400);
  assertEquals(await res.json(), { error: 'runsignup_bib_required' });
  assertEquals(h.fetched, []);
});

Deno.test('runsignup import: keyless, the bib\'s result from the listing-day event is inserted', async () => {
  const h = harness();
  const res = await h.handler(call(RSU_IMPORT));
  assertEquals(res.status, 200);
  assertEquals(await res.json(), { imported: 1, skipped: 0, enriched: 0, complete: true });
  assertEquals(h.fetched.length, 2);
  for (const url of h.fetched) assertEquals(new URL(url).searchParams.has('api_key'), false);
  const results = new URL(h.fetched[1]);
  assertEquals(results.searchParams.get('event_id'), '1117350');
  assertEquals(results.searchParams.get('bib_num'), '336');
  const rows = h.inserts()[0].ops[0][1] as Array<{ duration_s: number; distance_m: number; metadata: Record<string, unknown> }>;
  assertEquals(rows.map((r) => [r.duration_s, r.distance_m, r.metadata.bib, r.metadata.age_group]), [
    [21 * 60 + 24, 5000, '336', 'M2029'],
  ]);
});

Deno.test('runsignup import: the key pair rides along when both halves are set', async () => {
  const h = harness({
    script: { listing: { data: RSU_LISTING, error: null } },
    env: { RUNSIGNUP_API_KEY: 'k', RUNSIGNUP_API_SECRET: 's' },
    upstream: runSignUpFeed,
  });
  await h.handler(call(RSU_IMPORT));
  for (const url of h.fetched) assertEquals(new URL(url).searchParams.get('api_key'), 'k');
});

Deno.test('runsignup import: a bib nobody ran under imports nothing, honestly complete', async () => {
  const h = harness();
  const res = await h.handler(call({ ...RSU_IMPORT, bib: '99999' }));
  assertEquals(await res.json(), { imported: 0, skipped: 0, enriched: 0, complete: true });
  assertEquals(h.inserts(), []);
});

Deno.test('runsignup import: a listing day with no event of the race is a 404', async () => {
  const h = harness({
    script: { listing: { data: { ...RSU_LISTING, race_date: '2020-01-01' }, error: null } },
    upstream: runSignUpFeed,
  });
  const res = await h.handler(call(RSU_IMPORT));
  assertEquals(res.status, 404);
  assertEquals(await res.json(), { error: 'runsignup_event_not_found' });
  assertEquals(h.fetched.length, 1);
});

Deno.test('runsignup import: the HTTP-200 error envelope is a 502, not an empty field', async () => {
  const h = harness({
    script: { listing: { data: RSU_LISTING, error: null } },
    upstream: (url) =>
      new URL(url).pathname.endsWith('/get-results')
        ? Response.json({ error: { error_code: 3, error_msg: 'Invalid parameters' } })
        : runSignUpFeed(url),
  });
  const res = await h.handler(call(RSU_IMPORT));
  assertEquals(res.status, 502);
  assertEquals(await res.json(), { error: 'runsignup upstream error' });
  assertEquals(h.inserts(), []);
});
