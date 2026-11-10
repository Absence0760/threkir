/// park-closures-sweep's handler driven with a fake service client and a fake
/// NPS that serves the recorded alerts answer: the cron gate, the unset key
/// doing nothing, the key in its header, a chunk per ten parks with a pause
/// between, paging, and a failed chunk that records nothing (so an outage
/// never reads as an alert gone). The schedule and its Vault guard are pinned
/// from the migration source and the gate from config.toml.
///
/// Run with `cd apps/backend && deno test --allow-read --allow-env
/// supabase/functions/park-closures-sweep/handler.test.ts`.

import { assert, assertEquals, assertMatch } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import type { DbClient } from '../_shared/database.ts';
import { CRON_SECRET_MIN_CHARS } from '../events-refund-sweep/lib.ts';
import { makeParkClosuresSweepHandler } from './handler.ts';
import { NPS_ALERTS_URL, REQUEST_GAP_MS } from './lib.ts';

const SECRET = 's'.repeat(CRON_SECRET_MIN_CHARS);
const KEY = 'nps-test-key';
const RECORDED = Deno.readTextFileSync(new URL('./fixtures/nps_alerts_2026-11-10.json', import.meta.url));
const SQL = Deno.readTextFileSync(
  new URL('../../migrations/20271214131303_park_course_nps_alerts.sql', import.meta.url),
);
const CONFIG = Deno.readTextFileSync(new URL('../../config.toml', import.meta.url));

interface Target {
  park_id: string;
  nps_park_code: string;
  courses: Array<{ id: string; name: string }>;
}

const SHEN: Target = { park_id: 'park-shen', nps_park_code: 'shen', courses: [{ id: 'big-meadows', name: 'Big Meadows Loop' }] };
const PRWI: Target = { park_id: 'park-prwi', nps_park_code: 'prwi', courses: [{ id: 'mary-byrd', name: 'Mary Byrd Branch Trail' }] };

function harness(opts: {
  targets?: Target[];
  env?: Record<string, string | undefined>;
  npsAnswer?: (url: URL, call: number) => Response | Promise<Response>;
  targetsError?: boolean;
} = {}) {
  const rpcs: Array<{ name: string; args: Record<string, unknown> }> = [];
  const requests: Array<{ url: URL; headers: Headers }> = [];
  const sleeps: number[] = [];
  const client = {
    rpc(name: string, args: Record<string, unknown> = {}) {
      rpcs.push({ name, args });
      if (name === 'park_nps_sweep_targets') {
        return Promise.resolve(
          opts.targetsError ? { data: null, error: { code: '57014' } } : { data: opts.targets ?? [SHEN, PRWI], error: null },
        );
      }
      if (name === 'record_park_nps_alerts') return Promise.resolve({ data: [{ created: 0, seen: 0, gone: 0 }], error: null });
      return Promise.resolve({ data: [{ allowed: true, retry_after_seconds: 0 }], error: null });
    },
  } as unknown as DbClient;
  const env: Record<string, string | undefined> = { CRON_SECRET: SECRET, NPS_API_KEY: KEY, ...(opts.env ?? {}) };
  const handler = makeParkClosuresSweepHandler({
    getEnv: (n) => env[n],
    serviceClient: () => client,
    fetch: (input: string, init?: RequestInit) => {
      const url = new URL(input);
      requests.push({ url, headers: new Headers(init?.headers) });
      if (!input.startsWith(NPS_ALERTS_URL)) return Promise.reject(new TypeError('no host'));
      return Promise.resolve(
        opts.npsAnswer ? opts.npsAnswer(url, requests.length) : new Response(RECORDED, { status: 200 }),
      );
    },
    sleep: (ms) => {
      sleeps.push(ms);
      return Promise.resolve();
    },
    upstreamTimeoutMs: 1_000,
  });
  const records = () => rpcs.filter((r) => r.name === 'record_park_nps_alerts');
  return { handler, rpcs, records, requests, sleeps };
}

const cron = (bearer = SECRET) =>
  new Request('http://x/', { method: 'POST', headers: { Authorization: `Bearer ${bearer}` } });

Deno.test('an unset cron secret is 503 and does no work', async () => {
  const h = harness({ env: { CRON_SECRET: undefined } });
  const res = await h.handler(cron());
  assertEquals(res.status, 503);
  assertEquals(h.rpcs.length, 0);
  assertEquals(h.requests.length, 0);
});

Deno.test('a wrong bearer is 403 after a rate-limit check, and a missing one is 403 without', async () => {
  const wrong = harness();
  assertEquals((await wrong.handler(cron('x'.repeat(CRON_SECRET_MIN_CHARS)))).status, 403);
  assertEquals(wrong.rpcs.map((r) => r.name), ['check_rate_limit']);
  const none = harness();
  assertEquals((await none.handler(new Request('http://x/', { method: 'POST' }))).status, 403);
  assertEquals(none.rpcs.length, 0);
  assertEquals(wrong.requests.length + none.requests.length, 0);
});

Deno.test('with no NPS key it asks nothing, flags nothing, and says so', async () => {
  for (const key of [undefined, '', '   ']) {
    const h = harness({ env: { NPS_API_KEY: key } });
    const logged: string[] = [];
    const log = console.log;
    console.log = (...args: unknown[]) => logged.push(args.join(' '));
    try {
      const res = await h.handler(cron());
      assertEquals(res.status, 200);
      assertEquals(await res.json(), { configured: false });
    } finally {
      console.log = log;
    }
    assertEquals(h.rpcs.length, 0, 'not even the target list');
    assertEquals(h.requests.length, 0);
    assert(logged.some((l) => l.includes('NPS_API_KEY is not set')), 'the log says why');
  }
});

Deno.test('one request for both parks, the key in its header, each park recorded with its own alerts', async () => {
  const h = harness();
  const res = await h.handler(cron());
  assertEquals(res.status, 200);
  const body = await res.json();
  assertEquals(body, { configured: true, parks: 2, requests: 1, alerts: 11, flagged: 3, failed_parks: 0, errors: 0 });
  assertEquals(h.requests.length, 1);
  assertEquals(h.requests[0].url.searchParams.get('parkCode'), 'shen,prwi');
  assertEquals(h.requests[0].headers.get('X-Api-Key'), KEY);
  assert(!h.requests[0].url.toString().includes(KEY), 'the key never rides in the URL');

  const [shen, prwi] = h.records();
  assertEquals(shen.args.p_park_id, 'park-shen');
  assertEquals(
    (shen.args.p_flags as Array<{ course_id: string; title: string }>).map((f) => f.title),
    ['Prescribed Fire in Big Meadows', 'Active Closure'],
  );
  assertEquals((shen.args.p_seen_alert_ids as string[]).length, 7, 'every Shenandoah alert counts as seen');
  assertEquals(prwi.args.p_park_id, 'park-prwi');
  assertEquals((prwi.args.p_flags as Array<{ course_id: string }>).map((f) => f.course_id), ['mary-byrd']);
  assertEquals((prwi.args.p_seen_alert_ids as string[]).length, 2);
});

Deno.test('ten parks a request, with a pause before each later one', async () => {
  const targets = Array.from({ length: 23 }, (_, i): Target => ({
    park_id: `p${i}`,
    nps_park_code: `pk${String(i).padStart(2, '0')}`,
    courses: [{ id: `c${i}`, name: 'Loop' }],
  }));
  const h = harness({ targets, npsAnswer: () => Response.json({ total: '0', start: '0', data: [] }) });
  assertEquals((await h.handler(cron())).status, 200);
  assertEquals(h.requests.map((r) => r.url.searchParams.get('parkCode')!.split(',').length), [10, 10, 3]);
  assertEquals(h.sleeps, [REQUEST_GAP_MS, REQUEST_GAP_MS]);
  assertEquals(h.records().length, 23, 'a park with no alerts is still recorded, so its old flags go');
});

Deno.test('a chunk spread over two pages is read to its total', async () => {
  const page = (start: number, ids: string[]) =>
    Response.json({
      total: '3',
      start: String(start),
      data: ids.map((id) => ({ id, parkCode: 'shen', title: 'Big Meadows closed', category: 'Park Closure' })),
    });
  const h = harness({
    targets: [SHEN],
    npsAnswer: (url) => (url.searchParams.get('start') === '2' ? page(2, ['C']) : page(0, ['A', 'B'])),
  });
  assertEquals((await h.handler(cron())).status, 200);
  assertEquals(h.requests.map((r) => r.url.searchParams.get('start')), [null, '2']);
  assertEquals(h.records()[0].args.p_seen_alert_ids, ['A', 'B', 'C']);
});

Deno.test('a failed chunk records nothing for its parks and answers 502, so no flag reads as gone', async () => {
  const answers: Array<() => Response> = [
    () => new Response('rate limited', { status: 429 }),
    () => Response.json({ error: { code: 'OVER_RATE_LIMIT' } }),
    () => new Response('<html>', { status: 200, headers: { 'Content-Type': 'text/html' } }),
  ];
  for (const answer of answers) {
    const h = harness({ npsAnswer: answer });
    const res = await h.handler(cron());
    assertEquals(res.status, 502);
    assertMatch(JSON.stringify(await res.json()), /"failed_parks":2/);
    assertEquals(h.records().length, 0);
  }
  const down = harness({ npsAnswer: () => Promise.reject(new TypeError('connection refused')) });
  assertEquals((await down.handler(cron())).status, 502);
  assertEquals(down.records().length, 0);
});

Deno.test('a failed target list is 500 and asks NPS nothing', async () => {
  const h = harness({ targetsError: true });
  assertEquals((await h.handler(cron())).status, 500);
  assertEquals(h.requests.length, 0);
});

Deno.test('no NPS park with a course is a quiet 200 with no request', async () => {
  const h = harness({ targets: [] });
  const res = await h.handler(cron());
  assertEquals(res.status, 200);
  assertEquals((await res.json()).parks, 0);
  assertEquals(h.requests.length, 0);
});

Deno.test('the schedule is daily, fail-closed on its Vault entries, and the gate is the handler\'s own', () => {
  assertMatch(SQL, /cron\.schedule\(\s*'park-closures-sweep',\s*'41 11 \* \* \*'/);
  assertMatch(SQL, /name = 'park_closures_sweep_url'/);
  assertMatch(SQL, /if v_url is null or v_secret is null then\s+return null;/);
  assertMatch(CONFIG, /\[functions\.park-closures-sweep\]\s+verify_jwt = false/);
});
