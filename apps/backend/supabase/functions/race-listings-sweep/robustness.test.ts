/// The scheduled sweep under the upstream failures it meets unattended, every
/// five minutes: a feed that never answers, one that sends headers and then
/// stalls the body, one that cannot be reached, and one whose body is valid
/// JSON but not the race feed. Each must end the run with a status that says
/// which, and none may write. handler.test.ts covers the gates and the happy
/// path; this file covers the stalls. No stack, no network.
///
/// Run with `cd apps/backend && deno test --no-check --allow-read --allow-env
/// supabase/functions/race-listings-sweep/robustness.test.ts`.

import { assert, assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import type { DbClient } from '../_shared/database.ts';
import { CRON_SECRET_MIN_CHARS } from '../events-refund-sweep/lib.ts';
import { UPSTREAM_TIMEOUT_MS } from '../race-listings-sync/lib.ts';
import { makeRaceListingsSweepHandler } from './handler.ts';

const SECRET = 's'.repeat(CRON_SECRET_MIN_CHARS);
const NOW = Date.UTC(2026, 9, 14, 12, 0, 0);

type FakeFetch = (input: string, init?: RequestInit) => Promise<Response>;

function harness(fetch: FakeFetch, upstreamTimeoutMs?: number) {
  const tables: string[] = [];
  const client = {
    rpc: () => Promise.resolve({ data: [{ allowed: true, retry_after_seconds: 0 }], error: null }),
    from(table: string) {
      tables.push(table);
      const builder: Record<string, unknown> = {};
      for (const name of ['select', 'insert', 'update', 'eq', 'in']) builder[name] = () => builder;
      builder.then = (resolve: (v: unknown) => unknown) => Promise.resolve({ data: [], error: null }).then(resolve);
      return builder;
    },
  };
  const handler = makeRaceListingsSweepHandler({
    getEnv: (name) => (name === 'CRON_SECRET' ? SECRET : undefined),
    serviceClient: () => client as unknown as DbClient,
    fetch,
    now: () => NOW,
    upstreamTimeoutMs,
  });
  return { handler, tables };
}

function call(): Request {
  return new Request('http://localhost/race-listings-sweep', {
    method: 'POST',
    headers: { Authorization: `Bearer ${SECRET}` },
    body: '{}',
  });
}

/// What a real `fetch` does with its signal: nothing until it aborts, then the
/// abort reason. Measured against Deno's own fetch, a timed-out request and a
/// timed-out body read both reject with a `TimeoutError` DOMException.
function onAbort(init: RequestInit | undefined, fail: (reason: unknown) => void) {
  const signal = init?.signal;
  if (!signal) return;
  signal.addEventListener('abort', () => fail(signal.reason), { once: true });
}

Deno.test('the upstream request carries a bound, and the default is the shared one', async () => {
  const seen: Array<AbortSignal | null | undefined> = [];
  const h = harness((_, init) => {
    seen.push(init?.signal);
    return Promise.resolve(Response.json({ races: [] }));
  });
  assertEquals((await h.handler(call())).status, 200);
  assertEquals(seen.length, 1);
  assert(seen[0] instanceof AbortSignal, 'the fetch must be given a signal');
  assertEquals(seen[0]!.aborted, false);
  // Inside the pg_net side's 60 s, and far past a 2.9 MB page's few seconds.
  assert(UPSTREAM_TIMEOUT_MS > 5_000 && UPSTREAM_TIMEOUT_MS < 60_000);
});

Deno.test('a feed that never answers ends the run as a 504, writing nothing', async () => {
  const h = harness((_, init) => new Promise((_resolve, reject) => onAbort(init, reject)), 20);
  const res = await h.handler(call());
  assertEquals(res.status, 504);
  const body = await res.json();
  assertEquals(body.error, 'runsignup upstream timeout');
  assert(typeof body.window?.state === 'string', 'the run says which window it lost');
  assertEquals(h.tables, []);
});

Deno.test('a feed that sends headers and stalls the body is the same 504, not "not JSON"', async () => {
  const h = harness((_, init) => {
    const body = new ReadableStream<Uint8Array>({
      start(controller) {
        controller.enqueue(new TextEncoder().encode('{"races":[{"race":'));
        onAbort(init, (reason) => controller.error(reason));
      },
    });
    return Promise.resolve(new Response(body, { status: 200 }));
  }, 20);
  const res = await h.handler(call());
  assertEquals(res.status, 504);
  assertEquals((await res.json()).error, 'runsignup upstream timeout');
  assertEquals(h.tables, []);
});

Deno.test('an unreachable feed is a 502 the run answers, not an exception it throws', async () => {
  const h = harness(() => Promise.reject(new TypeError('error sending request: dns error')));
  const res = await h.handler(call());
  assertEquals(res.status, 502);
  assertEquals((await res.json()).error, 'runsignup upstream unreachable');
  assertEquals(h.tables, []);
});

Deno.test('valid JSON that is not the race feed is a 502, not a window with no races', async () => {
  for (const shape of [{}, { data: { races: [] } }, [], null]) {
    const h = harness(() => Promise.resolve(Response.json(shape)));
    const res = await h.handler(call());
    assertEquals(res.status, 502, JSON.stringify(shape));
    assertEquals((await res.json()).error, 'runsignup upstream shape');
    assertEquals(h.tables, []);
  }
  // The positive control: the empty window really is an empty window.
  const empty = harness(() => Promise.resolve(Response.json({ races: [] })));
  const res = await empty.handler(call());
  assertEquals(res.status, 200);
  const body = await res.json();
  assertEquals([body.total, body.synced, body.complete], [0, 0, true]);
});
