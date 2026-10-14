/// race-listings-sweep's handler (handler.ts) driven with a fake service client,
/// a fake `fetch` and a fixed clock: the cron bearer gate, the one request a run
/// makes (the slot's state and window, no key unless both halves are set), the
/// upstream refusals, and the write through race-listings-sync's write half.
/// The schedule and its Vault guard are pinned from the migration source. No
/// stack, no network.
///
/// Run with `cd apps/backend && deno test --allow-read --allow-env
/// supabase/functions/race-listings-sweep/handler.test.ts`.

import { assert, assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import type { DbClient } from '../_shared/database.ts';
import { CRON_SECRET_MIN_CHARS } from '../events-refund-sweep/lib.ts';
import { SWEEP_PERIOD_S, SWEEP_STATES, SWEEP_WINDOWS } from '../race-listings-sync/lib.ts';
import { makeRaceListingsSweepHandler } from './handler.ts';

const SECRET = 's'.repeat(CRON_SECRET_MIN_CHARS);
const FEED_TEXT = Deno.readTextFileSync(
  new URL('../race-listings-sync/fixtures/runsignup_races.json', import.meta.url),
);
const SQL = Deno.readTextFileSync(
  new URL('../../migrations/20270805000002_race_listings_sweep_schedule.sql', import.meta.url),
);
const CONFIG = Deno.readTextFileSync(new URL('../../config.toml', import.meta.url));

/// 2026-10-14T12:00:00Z — slot (epoch / 300) mod 306.
const NOW = Date.UTC(2026, 9, 14, 12, 0, 0);

function fakeService() {
  const tables: string[] = [];
  const rpcs: string[] = [];
  const client = {
    rpc(name: string) {
      rpcs.push(name);
      return Promise.resolve({ data: [{ allowed: true, retry_after_seconds: 0 }], error: null });
    },
    from(table: string) {
      tables.push(table);
      const ops: string[] = [];
      const builder: Record<string, unknown> = {};
      for (const name of ['select', 'insert', 'update', 'eq', 'in']) {
        builder[name] = () => {
          ops.push(name);
          return builder;
        };
      }
      builder.then = (resolve: (v: unknown) => unknown) =>
        Promise.resolve(
          table === 'us_zcta_points' ? { data: [], error: null } : { data: ops[0] === 'select' ? [] : null, error: null },
        ).then(resolve);
      return builder;
    },
  };
  return { tables, rpcs, client: client as unknown as DbClient };
}

function harness(opts: { env?: Record<string, string | undefined>; upstream?: () => Response } = {}) {
  const env: Record<string, string | undefined> = { CRON_SECRET: SECRET, ...(opts.env ?? {}) };
  const fake = fakeService();
  const fetched: string[] = [];
  const handler = makeRaceListingsSweepHandler({
    getEnv: (name) => env[name],
    serviceClient: () => fake.client,
    fetch: (input) => {
      fetched.push(input);
      return Promise.resolve(opts.upstream ? opts.upstream() : new Response(FEED_TEXT, { status: 200 }));
    },
    now: () => NOW,
  });
  return { handler, fake, fetched };
}

function call(auth: string | null = `Bearer ${SECRET}`): Request {
  const headers = new Headers();
  if (auth) headers.set('Authorization', auth);
  return new Request('http://localhost/race-listings-sweep', { method: 'POST', headers, body: '{}' });
}

Deno.test('an unset or short CRON_SECRET is a 503, whatever the caller sent', async () => {
  for (const secret of [undefined, 'short']) {
    const h = harness({ env: { CRON_SECRET: secret } });
    const res = await h.handler(call());
    assertEquals(res.status, 503);
    assertEquals(await res.json(), { error: 'cron_not_configured' });
    assertEquals(h.fetched, []);
  }
});

Deno.test('no bearer is a free 403; a wrong one spends the anonymous bucket; neither fetches', async () => {
  const none = harness();
  assertEquals((await none.handler(call(null))).status, 403);
  assertEquals(none.fake.rpcs, []);
  const wrong = harness();
  assertEquals((await wrong.handler(call(`Bearer ${'t'.repeat(CRON_SECRET_MIN_CHARS)}`))).status, 403);
  assertEquals(wrong.fake.rpcs.length, 1);
  assertEquals([...none.fetched, ...wrong.fetched], []);
});

Deno.test('a run makes one keyless request for its slot\'s state and window', async () => {
  const h = harness();
  const res = await h.handler(call());
  assertEquals(res.status, 200);
  assertEquals(h.fetched.length, 1);
  const url = new URL(h.fetched[0]);
  const slot = Math.floor(NOW / 1000 / SWEEP_PERIOD_S) % (SWEEP_STATES.length * SWEEP_WINDOWS);
  assertEquals(url.origin + url.pathname, 'https://runsignup.com/Rest/races');
  assertEquals(url.searchParams.get('state'), SWEEP_STATES[Math.floor(slot / SWEEP_WINDOWS)]);
  assertEquals(url.searchParams.get('country_code'), 'US');
  assertEquals(url.searchParams.get('events'), 'T');
  assert(/^\d{4}-\d{2}-\d{2}$/.test(url.searchParams.get('start_date')!));
  assert(/^\d{4}-\d{2}-\d{2}$/.test(url.searchParams.get('end_date')!));
  assertEquals(url.searchParams.has('api_key'), false);
  const body = await res.json();
  assertEquals(body.window.slot, slot);
  assert(body.synced > 0, 'the recorded feed writes listings');
  assert(h.fake.tables.includes('race_listings'));
});

Deno.test('the key pair rides along only when both halves are set', async () => {
  const both = harness({ env: { RUNSIGNUP_API_KEY: 'k', RUNSIGNUP_API_SECRET: 's' } });
  await both.handler(call());
  assertEquals(new URL(both.fetched[0]).searchParams.get('api_key'), 'k');
  const half = harness({ env: { RUNSIGNUP_API_KEY: 'k' } });
  await half.handler(call());
  assertEquals(new URL(half.fetched[0]).searchParams.has('api_key'), false);
});

Deno.test('a non-2xx, a non-JSON body and the HTTP-200 refusal are 502s that write nothing', async () => {
  const cases: Array<[() => Response, string]> = [
    [() => new Response('nope', { status: 503 }), 'runsignup upstream 503'],
    [() => new Response('<html>', { status: 200 }), 'runsignup upstream not JSON'],
    [
      () => Response.json({ error: { error_code: 13, error_msg: 'Pagination beyond 1,000 results requires authentication.' } }),
      'runsignup upstream error',
    ],
  ];
  for (const [upstream, error] of cases) {
    const h = harness({ upstream });
    const res = await h.handler(call());
    assertEquals(res.status, 502);
    assertEquals((await res.json()).error, error);
    assertEquals(h.fake.tables, []);
  }
});

Deno.test('the schedule runs every five minutes and calls nothing until both Vault secrets exist', () => {
  assert(
    /select cron\.schedule\(\s*'race-listings-sweep',\s*'\*\/5 \* \* \* \*',\s*\$\$select public\.invoke_race_listings_sweep\(\)\$\$/
      .test(SQL),
  );
  const fn = SQL.slice(SQL.indexOf('create or replace function public.invoke_race_listings_sweep('));
  const guard = fn.indexOf('if v_url is null or v_secret is null then');
  const post = fn.indexOf('net.http_post(');
  assert(guard >= 0 && post > guard, 'the Vault guard must precede the POST');
  assert(fn.includes("'Authorization', 'Bearer ' || v_secret"));
  for (const name of ['race_listings_sweep_url', 'cron_secret']) {
    assert(fn.includes(`where name = '${name}'`), `the ${name} Vault secret is no longer read`);
  }
  assert(
    SQL.includes(
      'revoke execute on function public.invoke_race_listings_sweep() from public, anon, authenticated;',
    ),
    'the invoker must be withheld from every client role',
  );
});

Deno.test('config.toml turns the platform JWT gate off, so the cron bearer can reach the handler', () => {
  const section = CONFIG.split(/^\[/m).find((s) => s.startsWith('functions.race-listings-sweep]'));
  assert(section, 'no [functions.race-listings-sweep] section in config.toml');
  assertEquals(/^\s*verify_jwt\s*=\s*false\s*$/m.test(section), true);
});
