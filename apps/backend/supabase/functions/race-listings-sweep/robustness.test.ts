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
import {
  SWEEP_PERIOD_S,
  SWEEP_STATES,
  SWEEP_WINDOW_DAYS,
  SWEEP_WINDOWS,
  sweepWindowAt,
} from '../race-listings-sync/lib.ts';
import { UPSTREAM_TIMEOUT_MS } from '../_shared/upstream_deadline.ts';
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

Deno.test('each state\'s six windows tile 84 unbroken days, because no state\'s run straddles a UTC midnight', () => {
  // Every window counts its dates from the day the run fires. If a state's six
  // runs straddled 00:00 UTC, the windows after midnight would start a day
  // later and one day of that state's horizon would never be asked for in that
  // pass. It cannot happen only because a day (288 periods) and a pass (306)
  // are both whole multiples of a state's block of six, so a midnight always
  // falls between two states. Changing the period or the window count can break
  // that silently, so the premise and its consequence are both pinned.
  assertEquals((86_400 / SWEEP_PERIOD_S) % SWEEP_WINDOWS, 0, 'a day must hold whole state blocks');
  assertEquals((SWEEP_STATES.length * SWEEP_WINDOWS) % SWEEP_WINDOWS, 0);
  const day = 86_400_000;
  const slots = SWEEP_STATES.length * SWEEP_WINDOWS;
  // Two passes from an arbitrary minute: each crosses at least one midnight.
  const start = Date.UTC(2026, 11, 31, 17, 3, 0);
  const runs = Array.from({ length: 2 * slots }, (_, i) => sweepWindowAt(start + i * SWEEP_PERIOD_S * 1000));
  let blocks = 0;
  for (let i = 0; i < runs.length; i++) {
    if (runs[i].slot % SWEEP_WINDOWS !== 0 || i + SWEEP_WINDOWS > runs.length) continue;
    const block = runs.slice(i, i + SWEEP_WINDOWS);
    assert(block.every((w) => w.state === block[0].state));
    for (let k = 1; k < SWEEP_WINDOWS; k++) {
      const prevEnd = Date.parse(`${block[k - 1].endDate}T00:00:00Z`);
      assertEquals(
        Date.parse(`${block[k].startDate}T00:00:00Z`),
        prevEnd + day,
        `${block[0].state} window ${k} must start the day after window ${k - 1} ends`,
      );
    }
    const span = (Date.parse(`${block[5].endDate}T00:00:00Z`) - Date.parse(`${block[0].startDate}T00:00:00Z`)) / day + 1;
    assertEquals(span, SWEEP_WINDOWS * SWEEP_WINDOW_DAYS);
    blocks++;
  }
  assert(blocks >= 2 * SWEEP_STATES.length - 1, 'the walk must have seen every state twice');
});
