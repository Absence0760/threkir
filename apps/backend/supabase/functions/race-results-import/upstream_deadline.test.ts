/// race-results-import under the upstream failures a caller meets: a feed that
/// never answers, one that sends headers and stalls the body, one that cannot
/// be reached, and — the case a per-call bound cannot catch — a RunSignUp leg
/// whose calls each answer in time but together outlast the request's one
/// deadline (decisions § 1912). Each must end the request with a status that
/// says which, and none may write. No stack, no network.
///
/// Run with `cd apps/backend && deno test --no-check --allow-read --allow-env
/// supabase/functions/race-results-import/upstream_deadline.test.ts`.

import { assert, assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import type { DbClient } from '../_shared/database.ts';
import { UPSTREAM_TIMEOUT_MS } from '../_shared/upstream_deadline.ts';
import { makeRaceResultsImportHandler } from './handler.ts';

const LISTING_ID = '11111111-2222-4333-8444-555555555555';
const RUNSIGNUP_LISTING = {
  id: LISTING_ID,
  provider: 'runsignup',
  provider_race_id: '108839',
  name: 'Example Race Morning',
  race_date: '2026-09-19',
  distance_m: 21097,
};

/// Four running events on the listing's morning, so the bib is asked of each
/// in turn until one answers.
const RACE = {
  race: {
    race_id: 108839,
    name: 'Example Race Morning',
    events: [
      ['2001', 'Half Marathon', '13.1M'],
      ['2002', '10K', '10K'],
      ['2003', '5K', '5K'],
      ['2004', '1 Mile', '1M'],
    ].map(([id, name, distance]) => ({
      event_id: Number(id),
      name,
      start_time: '9/19/2026 08:00',
      distance,
      event_type: 'running_race',
    })),
  },
};

const NO_ROWS = { individual_results_sets: [{ results: [], results_headers: {} }] };
const ROW_336 = {
  individual_results_sets: [{
    results: [{ bib: 336, place: 12, chip_time: '', clock_time: '21:43.34' }],
    results_headers: {},
  }],
};

type FakeFetch = (input: string, init?: RequestInit) => Promise<Response>;

function harness(
  fetch: FakeFetch,
  opts: { upstreamTimeoutMs?: number; listing?: Record<string, unknown>; env?: Record<string, string> } = {},
) {
  const writes: string[] = [];
  const client = {
    auth: { getUser: () => Promise.resolve({ data: { user: { id: 'runner-1' } } }) },
    rpc: () => Promise.resolve({ data: [{ allowed: true, retry_after_seconds: 0, tier: 'free' }], error: null }),
    from(table: string) {
      const builder: Record<string, unknown> = {};
      for (const name of ['select', 'eq', 'in']) builder[name] = () => builder;
      for (const name of ['insert', 'update']) {
        builder[name] = () => {
          writes.push(`${name} ${table}`);
          return builder;
        };
      }
      const answer = () => {
        if (table === 'public_race_listings') {
          return { data: opts.listing ?? RUNSIGNUP_LISTING, error: null };
        }
        if (table === 'runs') return { data: [], error: null };
        return { data: null, error: null };
      };
      builder.maybeSingle = () => Promise.resolve(answer());
      builder.then = (resolve: (v: unknown) => unknown) => Promise.resolve(answer()).then(resolve);
      return builder;
    },
  };
  const handler = makeRaceResultsImportHandler({
    getEnv: (name) => opts.env?.[name],
    userClient: () => client as unknown as DbClient,
    fetch: (input, init) => fetch(String(input), init),
    upstreamTimeoutMs: opts.upstreamTimeoutMs,
  });
  return { handler, writes };
}

function call(body: unknown): Request {
  return new Request('http://localhost/race-results-import', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: 'Bearer user-jwt' },
    body: JSON.stringify(body),
  });
}

const RUNSIGNUP_IMPORT = { provider: 'runsignup', listingId: LISTING_ID, bib: '336' };

/// What a real `fetch` does with its signal: nothing until it aborts, then the
/// abort reason, which is a `TimeoutError` DOMException for a timeout signal.
function onAbort(init: RequestInit | undefined, fail: (reason: unknown) => void) {
  const signal = init?.signal;
  if (!signal) return;
  if (signal.aborted) return fail(signal.reason);
  signal.addEventListener('abort', () => fail(signal.reason), { once: true });
}

const hang = (init: RequestInit | undefined) =>
  new Promise<Response>((_resolve, reject) => onAbort(init, reject));

function stalledBody(init: RequestInit | undefined): Promise<Response> {
  const body = new ReadableStream<Uint8Array>({
    start(controller) {
      controller.enqueue(new TextEncoder().encode('{"individual_results_sets":[{"results":'));
      onAbort(init, (reason) => controller.error(reason));
    },
  });
  return Promise.resolve(new Response(body, { status: 200 }));
}

/// Answers like the feed, after `delayMs`, unless the signal fires first.
function slowFeed(delayMs: number, answer: (url: URL) => unknown): FakeFetch {
  return (input, init) =>
    new Promise<Response>((resolve, reject) => {
      const timer = setTimeout(() => resolve(Response.json(answer(new URL(input)))), delayMs);
      onAbort(init, (reason) => {
        clearTimeout(timer);
        reject(reason);
      });
    });
}

const isRace = (u: URL) => u.pathname === '/Rest/race/108839';

Deno.test('every call in one request carries the same deadline, and a feed that answers imports', async () => {
  const seen: Array<AbortSignal | null | undefined> = [];
  const h = harness((input, init) => {
    seen.push(init?.signal);
    const u = new URL(input);
    if (isRace(u)) return Promise.resolve(Response.json(RACE));
    // Only the 5K holds the runner.
    return Promise.resolve(Response.json(u.searchParams.get('event_id') === '2003' ? ROW_336 : NO_ROWS));
  });
  const res = await h.handler(call(RUNSIGNUP_IMPORT));
  assertEquals(res.status, 200);
  assertEquals((await res.json()).imported, 1);
  assertEquals(h.writes, ['insert runs']);
  // The race, then the half (the listing's distance), the 10K and the 5K.
  assertEquals(seen.length, 4);
  assert(seen[0] instanceof AbortSignal, 'the fetch must be given a signal');
  assert(seen.every((s) => s === seen[0]), 'one deadline for the whole request, not one per call');
  assertEquals(seen[0]!.aborted, false);
  // Comfortably inside the runtime's 150 s request clock.
  assert(UPSTREAM_TIMEOUT_MS >= 10_000 && UPSTREAM_TIMEOUT_MS <= 60_000);
});

Deno.test('a RunSignUp feed that never answers is a 504, writing nothing', async () => {
  const h = harness((_, init) => hang(init), { upstreamTimeoutMs: 20 });
  const res = await h.handler(call(RUNSIGNUP_IMPORT));
  assertEquals(res.status, 504);
  assertEquals(await res.json(), { error: 'runsignup upstream timeout' });
  assertEquals(h.writes, []);
});

Deno.test('a results call that sends headers and stalls the body is the same 504, not "not JSON"', async () => {
  const h = harness((input, init) => {
    if (isRace(new URL(input))) return Promise.resolve(Response.json(RACE));
    return stalledBody(init);
  }, { upstreamTimeoutMs: 20 });
  const res = await h.handler(call(RUNSIGNUP_IMPORT));
  assertEquals(res.status, 504);
  assertEquals(await res.json(), { error: 'runsignup upstream timeout' });
  assertEquals(h.writes, []);
});

Deno.test('calls that each answer in time but together outlast the deadline end in a 504, not an import', async () => {
  // Every call answers in 30 ms against a 100 ms deadline, so a bound per call
  // would never fire. The runner is in the last event asked, the fifth call,
  // which the request's budget is spent before reaching.
  const fetched: string[] = [];
  const feed = slowFeed(30, (u) => {
    fetched.push(u.searchParams.get('event_id') ?? 'race');
    if (isRace(u)) return RACE;
    return u.searchParams.get('event_id') === '2004' ? ROW_336 : NO_ROWS;
  });
  const h = harness(feed, { upstreamTimeoutMs: 100 });
  const res = await h.handler(call(RUNSIGNUP_IMPORT));
  assertEquals(res.status, 504);
  assertEquals(await res.json(), { error: 'runsignup upstream timeout' });
  assertEquals(h.writes, [], 'a deadline mid-loop must insert nothing');
  assert(fetched.length >= 2 && fetched.length < 5, `the loop got ${fetched.length} answers in`);

  // The positive control: the same feed under a budget it fits imports.
  const roomy = harness(slowFeed(30, (u) => {
    if (isRace(u)) return RACE;
    return u.searchParams.get('event_id') === '2004' ? ROW_336 : NO_ROWS;
  }), { upstreamTimeoutMs: 2_000 });
  const ok = await roomy.handler(call(RUNSIGNUP_IMPORT));
  assertEquals(ok.status, 200);
  assertEquals((await ok.json()).imported, 1);
});

Deno.test('an unreachable RunSignUp feed is a 502 the request answers, not an exception it throws', async () => {
  const h = harness(() => Promise.reject(new TypeError('error sending request: dns error')));
  const res = await h.handler(call(RUNSIGNUP_IMPORT));
  assertEquals(res.status, 502);
  assertEquals(await res.json(), { error: 'runsignup upstream unreachable' });
  assertEquals(h.writes, []);
});

Deno.test('the UltraSignup lookup and import and the ChronoTrack import read through the same deadline', async () => {
  const ultra = { ULTRASIGNUP_RESULTS_ENABLED: 'true' };
  const ct = { CHRONOTRACK_CLIENT_ID: 'c', CHRONOTRACK_USER_ID: 'u', CHRONOTRACK_PASSWORD: 'p' };
  const cases: Array<[string, unknown, Record<string, string>, Record<string, unknown>]> = [
    ['ultrasignup', {
      provider: 'ultrasignup',
      lookup: true,
      ultraSignUpFirstName: 'Alex',
      ultraSignUpLastName: 'Sample',
    }, ultra, RUNSIGNUP_LISTING],
    ['ultrasignup', {
      provider: 'ultrasignup',
      listingId: LISTING_ID,
      ultraSignUpPersonId: '900001',
      ultraSignUpFirstName: 'Alex',
      ultraSignUpLastName: 'Sample',
    }, ultra, { ...RUNSIGNUP_LISTING, provider: 'ultrasignup', provider_race_id: '500101' }],
    ['chronotrack', { provider: 'chronotrack', listingId: LISTING_ID, bib: '336' }, ct, {
      ...RUNSIGNUP_LISTING,
      provider: 'chronotrack',
      provider_race_id: '77',
    }],
  ];
  for (const [provider, body, env, listing] of cases) {
    const hung = harness((_, init) => hang(init), { upstreamTimeoutMs: 20, env, listing });
    const res = await hung.handler(call(body));
    assertEquals(res.status, 504, JSON.stringify(body));
    assertEquals(await res.json(), { error: `${provider} upstream timeout` });
    assertEquals(hung.writes, []);

    const gone = harness(() => Promise.reject(new TypeError('connection refused')), { env, listing });
    const down = await gone.handler(call(body));
    assertEquals(down.status, 502, JSON.stringify(body));
    assertEquals(await down.json(), { error: `${provider} upstream unreachable` });
    assertEquals(gone.writes, []);
  }
});
