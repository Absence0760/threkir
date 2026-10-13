/// race-results-import's handler (handler.ts) driven with a fake caller client
/// and a fake `fetch`: the auth gate, which rate-limit bucket each mode spends
/// (the UltraSignup lookup's own 20/hour one above all, decisions § 1841), and
/// the UltraSignup lookup and import error paths — each of which must answer
/// before anything is written, and most before anything is fetched. No stack,
/// no network.
///
/// Run with `cd apps/backend && deno test --allow-read --allow-env
/// supabase/functions/race-results-import/handler.test.ts`.

import { assert, assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import type { DbClient } from '../_shared/database.ts';
import { makeRaceResultsImportHandler } from './handler.ts';

const PAYLOAD_TEXT = Deno.readTextFileSync(
  new URL('./fixtures/ultrasignup_historybyname.json', import.meta.url),
);

const LISTING_ID = '11111111-2222-4333-8444-555555555555';
const LISTING = {
  id: LISTING_ID,
  provider: 'ultrasignup',
  provider_race_id: '500101',
  name: 'Example Peaks 100 Mile',
  race_date: '2025-06-20',
  distance_m: 160934,
};

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
        if (table === 'public_race_listings') return script.listing ?? { data: LISTING, error: null };
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
  upstream?: () => Response;
} = {}) {
  const env: Record<string, string | undefined> = {
    ULTRASIGNUP_RESULTS_ENABLED: 'true',
    ...(opts.env ?? {}),
  };
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
      return Promise.resolve(
        opts.upstream ? opts.upstream() : new Response(PAYLOAD_TEXT, { status: 200 }),
      );
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

const LOOKUP = { provider: 'ultrasignup', lookup: true, ultraSignUpFirstName: 'Alex', ultraSignUpLastName: 'Sample' };
const IMPORT = {
  provider: 'ultrasignup',
  listingId: LISTING_ID,
  ultraSignUpPersonId: '900001',
  ultraSignUpFirstName: 'Alex',
  ultraSignUpLastName: 'Sample',
};

const bucketOf = (rpcs: Rpc[]) =>
  rpcs.map((r) => [r.name, r.args.p_bucket, r.args.p_free_max, r.args.p_pro_max, r.args.p_window_seconds]);

// ── the auth gate ──

Deno.test('no Authorization header: 401 before a client exists', async () => {
  const h = harness();
  const res = await h.handler(call(LOOKUP, null));
  assertEquals(res.status, 401);
  assertEquals(h.clients(), 0);
  assertEquals(h.fetched, []);
});

Deno.test('a token that resolves to no user: 401, nothing spent', async () => {
  const h = harness({ script: { user: null } });
  const res = await h.handler(call(LOOKUP));
  assertEquals(res.status, 401);
  assertEquals(h.fake.rpcs, []);
  assertEquals(h.fetched, []);
});

// ── the buckets ──

Deno.test('a lookup spends its own 20-an-hour bucket (60 for Pro), and nothing else', async () => {
  const h = harness();
  const res = await h.handler(call(LOOKUP));
  assertEquals(res.status, 200);
  assertEquals(bucketOf(h.fake.rpcs), [
    ['check_rate_limit_tiered', 'race-results-import:lookup', 20, 60, 3600],
  ]);
  assertEquals(h.fetched.length, 1);
  const body = await res.json();
  assertEquals(
    body.candidates.map((c: { id: string }) => c.id),
    ['900001', '900002'],
    'the lookup answers with the people the name returns',
  );
});

Deno.test('an exhausted lookup bucket is a 429 with no call to UltraSignup', async () => {
  const h = harness({
    script: { limiter: { data: [{ allowed: false, retry_after_seconds: 120, tier: 'free' }], error: null } },
  });
  const res = await h.handler(call(LOOKUP));
  assertEquals(res.status, 429);
  const body = await res.json();
  assertEquals(body.bucket, 'race-results-import:lookup');
  assertEquals(h.fetched, []);
});

Deno.test('a limiter outage fails the lookup closed', async () => {
  const h = harness({ script: { limiter: { data: null, error: { code: '57014' } } } });
  const res = await h.handler(call(LOOKUP));
  assertEquals(res.status, 503);
  assertEquals(h.fetched, []);
});

Deno.test('an import and a probe each spend their own bucket', async () => {
  const imp = harness();
  await imp.handler(call(IMPORT));
  assertEquals(bucketOf(imp.fake.rpcs), [['check_rate_limit_tiered', 'race-results-import', 8, 32, 3600]]);

  const probe = harness();
  await probe.handler(call({ provider: 'ultrasignup', probe: true, ultraSignUpFlow: 'person' }));
  assertEquals(bucketOf(probe.fake.rpcs), [['check_rate_limit_tiered', 'race-results-import:probe', 60, 240, 3600]]);
});

Deno.test('a lookup flag on a probe is a probe, not a lookup', async () => {
  const h = harness();
  await h.handler(call({ ...LOOKUP, probe: true, ultraSignUpFlow: 'person' }));
  assertEquals(h.fake.rpcs[0].args.p_bucket, 'race-results-import:probe');
  assertEquals(h.fetched, []);
});

// ── the lookup's error paths ──

Deno.test('lookup: the deployment has not opted in — 503, nothing fetched', async () => {
  const h = harness({ env: { ULTRASIGNUP_RESULTS_ENABLED: 'yes' } });
  const res = await h.handler(call(LOOKUP));
  assertEquals(res.status, 503);
  assertEquals(await res.json(), { error: 'provider_not_configured' });
  assertEquals(h.fetched, []);
});

Deno.test('lookup: a missing or unusable name half is a 400, nothing fetched', async () => {
  for (const body of [
    { ...LOOKUP, ultraSignUpLastName: undefined },
    { ...LOOKUP, ultraSignUpFirstName: '..' },
  ]) {
    const h = harness();
    const res = await h.handler(call(body));
    assertEquals(res.status, 400);
    assertEquals(await res.json(), { error: 'ultrasignup_name_required' });
    assertEquals(h.fetched, []);
  }
});

Deno.test('lookup: an upstream error or a non-JSON page is a 502', async () => {
  const down = harness({ upstream: () => new Response('nope', { status: 503 }) });
  const r1 = await down.handler(call(LOOKUP));
  assertEquals(r1.status, 502);
  assertEquals(await r1.json(), { error: 'ultrasignup upstream 503' });

  const html = harness({ upstream: () => new Response('<html>', { status: 200 }) });
  const r2 = await html.handler(call(LOOKUP));
  assertEquals(r2.status, 502);
  assertEquals(await r2.json(), { error: 'ultrasignup upstream not JSON' });
});

// ── the import's error paths ──

Deno.test('import: a missing or malformed listing id is a 400 before the listing is read', async () => {
  for (const [listingId, error] of [[undefined, 'listingId required'], ['L-1', 'listingId must be a UUID']]) {
    const h = harness();
    const res = await h.handler(call({ ...IMPORT, listingId }));
    assertEquals(res.status, 400);
    assertEquals(await res.json(), { error });
    assert(!h.fake.calls.some((c) => c.table === 'public_race_listings'));
  }
});

Deno.test('import: an unreadable or missing listing is a 404', async () => {
  for (const listing of [{ data: null, error: null }, { data: null, error: { code: '57014' } }]) {
    const h = harness({ script: { listing } });
    const res = await h.handler(call(IMPORT));
    assertEquals(res.status, 404);
    assertEquals(h.fetched, []);
  }
});

Deno.test('import: not opted in, or a listing with no UltraSignup race id — refused, nothing fetched', async () => {
  const off = harness({ env: { ULTRASIGNUP_RESULTS_ENABLED: undefined } });
  assertEquals((await off.handler(call(IMPORT))).status, 503);
  assertEquals(off.fetched, []);

  const noRace = harness({ script: { listing: { data: { ...LISTING, provider_race_id: null }, error: null } } });
  const res = await noRace.handler(call(IMPORT));
  assertEquals(res.status, 400);
  assertEquals(await res.json(), { error: 'listing has no UltraSignup race id' });
  assertEquals(noRace.fetched, []);
});

Deno.test('import: without the picked person the name is never sent', async () => {
  const h = harness();
  const res = await h.handler(call({ ...IMPORT, ultraSignUpPersonId: undefined }));
  assertEquals(res.status, 400);
  assertEquals(await res.json(), { error: 'ultrasignup_person_required' });
  assertEquals(h.fetched, []);
});

Deno.test('import: an upstream error or a non-JSON page is a 502 that writes nothing', async () => {
  const down = harness({ upstream: () => new Response('nope', { status: 500 }) });
  const r1 = await down.handler(call(IMPORT));
  assertEquals(r1.status, 502);
  assertEquals(await r1.json(), { error: 'ultrasignup upstream 500' });
  assertEquals(down.inserts(), []);

  const html = harness({ upstream: () => new Response('<html>', { status: 200 }) });
  const r2 = await html.handler(call(IMPORT));
  assertEquals(r2.status, 502);
  assertEquals(html.inserts(), []);
});

Deno.test('import: a stored person the name no longer answers with is a 404, not "no result"', async () => {
  const h = harness();
  const res = await h.handler(call({ ...IMPORT, ultraSignUpPersonId: '123456' }));
  assertEquals(res.status, 404);
  assertEquals(await res.json(), { error: 'ultrasignup_person_not_found' });
  assertEquals(h.inserts(), []);
});

Deno.test('import: the picked person\'s result for this race is inserted as the caller\'s run', async () => {
  const h = harness();
  const res = await h.handler(call(IMPORT));
  assertEquals(res.status, 200);
  assertEquals(await res.json(), { imported: 1, skipped: 0, enriched: 0, complete: true });
  const [insert] = h.inserts();
  const rows = insert.ops[0][1] as Array<{ user_id: string; race_listing_id: string; duration_s: number }>;
  assertEquals(rows.map((r) => [r.user_id, r.race_listing_id, r.duration_s]), [
    ['runner-1', LISTING_ID, 28 * 3600 + 40 * 60 + 15],
  ]);
});

Deno.test('import: a failed insert is a 500, not a reported import', async () => {
  const h = harness({ script: { insertError: { code: '23505' } } });
  const res = await h.handler(call(IMPORT));
  assertEquals(res.status, 500);
  assertEquals(await res.json(), { error: 'race import failed to save' });
});
