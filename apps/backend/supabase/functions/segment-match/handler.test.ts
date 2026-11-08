/// The segment-match handler and its scoring pass, driven against a fake
/// service client (decisions § 2392). No stack, no network: the track is a
/// gzipped fixture served by the fake Storage, so the canonical matcher bundle
/// really runs and its result is what reaches `record_segment_match`.
///
/// Run with `cd apps/backend && deno test --allow-read --allow-env
/// supabase/functions/segment-match/handler.test.ts`.

import { assert, assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import type { DbClient } from '../_shared/database.ts';
import { makeSegmentMatchHandler } from './handler.ts';
import { BACKFILL_BATCH, type RunResult, scoreRun } from './lib.ts';

const KEY = 'sb_secret_worker_key';
const RUN = '5b000000-0000-4000-8000-000000000001';
const OWNER = '5a000000-0000-4000-8000-0000000000a1';
const SEG = '5a5a0000-0000-4000-8000-0000000000d1';
const COURSE = '5a5a0000-0000-4000-8000-0000000000d2';
const TRACK_URL = `${OWNER}/${RUN}.json.gz`;

type Res = { data: unknown; error: { code: string } | null };

async function gzip(value: unknown): Promise<Blob> {
  const stream = new Blob([JSON.stringify(value)]).stream().pipeThrough(new CompressionStream('gzip'));
  return await new Response(stream).blob();
}

/// A straight run north along -77.5 from 37.5, one fix every 5 s and 11 m.
function track(): unknown[] {
  const t0 = Date.parse('2026-09-01T09:00:00Z');
  const out = [];
  for (let i = 0; i <= 60; i++) {
    out.push({ lat: 37.5 + i * 0.0001, lng: -77.5, ts: new Date(t0 + i * 5000).toISOString() });
  }
  return out;
}

function fakeClient(opts: {
  rpcs?: Record<string, Res | ((args: Record<string, unknown>) => Res)>;
  objects?: Record<string, Blob>;
  checkpoints?: Res;
}) {
  const calls: { name: string; args: Record<string, unknown> }[] = [];
  const inLists: unknown[] = [];
  const client = {
    rpc(name: string, args: Record<string, unknown>) {
      calls.push({ name, args });
      const r = opts.rpcs?.[name];
      const res = typeof r === 'function' ? r(args) : r;
      return Promise.resolve(res ?? { data: null, error: { code: 'unscripted' } });
    },
    storage: {
      from(_bucket: string) {
        return {
          download(path: string) {
            const blob = opts.objects?.[path];
            return Promise.resolve(blob ? { data: blob, error: null } : { data: null, error: { message: 'not found' } });
          },
        };
      },
    },
    from(_table: string) {
      const builder = {
        select() {
          return builder;
        },
        in(_col: string, ids: unknown) {
          inLists.push(ids);
          return Promise.resolve(opts.checkpoints ?? { data: [], error: null });
        },
      };
      return builder;
    },
  };
  return { calls, inLists, client: client as unknown as DbClient };
}

function request(body: unknown, headers: Record<string, string> = { apikey: KEY }, method = 'POST'): Request {
  return new Request('http://localhost/segment-match', {
    method,
    headers: { 'content-type': 'application/json', ...headers },
    body: method === 'POST' ? JSON.stringify(body) : undefined,
  });
}

function handlerWith(client: DbClient, score?: (c: DbClient, id: string) => Promise<RunResult>) {
  return makeSegmentMatchHandler({
    getEnv: (n) => (n === 'SUPABASE_SECRET_KEYS' ? JSON.stringify({ default: KEY }) : undefined),
    serviceClient: () => client,
    scoreRun: score,
  });
}

const SOURCE: Res = {
  data: [{ user_id: OWNER, track_url: TRACK_URL, track_version: 'v1', metadata: {} }],
  error: null,
};

const NEAR_SEGMENTS: Res = {
  data: [
    { id: SEG, waypoints: [{ lat: 37.501, lng: -77.5 }, { lat: 37.505, lng: -77.5 }], distance_m: 445 },
    { id: COURSE, waypoints: [{ lat: 37.501, lng: -77.5 }, { lat: 37.505, lng: -77.5 }], distance_m: 445 },
  ],
  error: null,
};

Deno.test('a full pass times the run with the matcher and records it for the bytes read', async () => {
  const fake = fakeClient({
    rpcs: {
      segment_match_run_source: SOURCE,
      global_segments_in_bbox: NEAR_SEGMENTS,
      record_segment_match: { data: 'recorded', error: null },
    },
    objects: { [TRACK_URL]: await gzip(track()) },
    // The course has a checkpoint 900 m east of the line: the run misses it.
    checkpoints: { data: [{ global_segment_id: COURSE, checkpoints: [{ lat: 37.503, lng: -77.49 }] }], error: null },
  });
  const result = await scoreRun(fake.client, RUN);
  assertEquals(result, { outcome: 'recorded', matched: 1 });

  const bbox = fake.calls.find((c) => c.name === 'global_segments_in_bbox')!.args;
  assertEquals([bbox.p_min_lat, bbox.p_max_lat, bbox.p_min_lng, bbox.p_max_lng], [37.5, 37.506, -77.5, -77.5]);
  assertEquals(fake.inLists, [[SEG, COURSE]]);

  const rec = fake.calls.find((c) => c.name === 'record_segment_match')!.args;
  assertEquals(rec.p_track_version, 'v1');
  assertEquals(rec.p_candidates, [SEG, COURSE]);
  const efforts = rec.p_efforts as { global_segment_id: string; time_seconds: number; started_at: string }[];
  assertEquals(efforts.length, 1);
  assertEquals(efforts[0].global_segment_id, SEG);
  // 445 m at 11.1 m per 5 s, from the 37.501 crossing at 09:00:50.
  assert(Math.abs(efforts[0].time_seconds - 200) < 1, `time ${efforts[0].time_seconds}`);
  assert(efforts[0].started_at.startsWith('2026-09-01T09:00:5'), efforts[0].started_at);
});

Deno.test('a failed checkpoint read scores nothing and fails the pass', async () => {
  const fake = fakeClient({
    rpcs: { segment_match_run_source: SOURCE, global_segments_in_bbox: NEAR_SEGMENTS },
    objects: { [TRACK_URL]: await gzip(track()) },
    checkpoints: { data: null, error: { code: '57014' } },
  });
  let threw = false;
  try {
    await scoreRun(fake.client, RUN);
  } catch {
    threw = true;
  }
  assert(threw, 'a checkpoint read failure must throw (500, retried), never score without the rule');
  assert(!fake.calls.some((c) => c.name === 'record_segment_match'), 'nothing may be written');
});

Deno.test('outcomes that leave nothing to score are final, and stale bytes retry', async () => {
  const missing = fakeClient({ rpcs: { segment_match_run_source: { data: [], error: null } } });
  assertEquals((await scoreRun(missing.client, RUN)).outcome, 'missing');

  const noUpload = fakeClient({
    rpcs: { segment_match_run_source: { data: [{ ...(SOURCE.data as object[])[0], track_version: null }], error: null } },
  });
  assertEquals((await scoreRun(noUpload.client, RUN)).outcome, 'track_not_uploaded');

  const notGzip = fakeClient({
    rpcs: { segment_match_run_source: SOURCE },
    objects: { [TRACK_URL]: new Blob(['not gzip']) },
  });
  assertEquals((await scoreRun(notGzip.client, RUN)).outcome, 'unreadable');

  const stale = fakeClient({
    rpcs: {
      segment_match_run_source: SOURCE,
      global_segments_in_bbox: { data: [], error: null },
      record_segment_match: { data: 'stale', error: null },
    },
    objects: { [TRACK_URL]: await gzip(track()) },
  });
  assertEquals((await scoreRun(stale.client, RUN)).outcome, 'stale');
  const res = await handlerWith(stale.client)(request({ run_id: RUN }));
  assertEquals(res.status, 503, 'stale bytes must defer the job');
  const ok = await handlerWith(missing.client)(request({ run_id: RUN }));
  assertEquals([ok.status, await ok.json()], [200, { outcome: 'missing', matched: 0 }]);
});

Deno.test('gates: method, server key, payload', async () => {
  const fake = fakeClient({
    rpcs: { check_rate_limit: { data: [{ allowed: true, retry_after_seconds: 0 }], error: null } },
  });
  const handler = handlerWith(fake.client, () => Promise.resolve({ outcome: 'recorded', matched: 0 }));
  assertEquals((await handler(request(null, { apikey: KEY }, 'GET'))).status, 405);
  assertEquals((await handler(request({ run_id: RUN }, {}))).status, 403);
  assertEquals((await handler(request({ run_id: RUN }, { apikey: 'sb_publishable_x' }))).status, 403);
  assertEquals(
    fake.calls.filter((c) => c.name === 'check_rate_limit').length,
    1,
    'the limiter is spent on the wrong key only, never on a missing one',
  );
  assertEquals((await handler(request({ run_id: 'x' }))).status, 400);
  assertEquals((await handler(request({ run_id: RUN }))).status, 200);

  const unconfigured = makeSegmentMatchHandler({ getEnv: () => undefined, serviceClient: () => fake.client });
  assertEquals((await unconfigured(request({ run_id: RUN }))).status, 503);
});

Deno.test('a full backfill batch scores each run and queues the next from its last id', async () => {
  const ids = Array.from({ length: BACKFILL_BATCH }, (_, i) => `5b000000-0000-4000-8000-${String(i).padStart(12, '0')}`);
  const fake = fakeClient({
    rpcs: {
      segment_backfill_runs: { data: ids.map((run_id) => ({ run_id })), error: null },
      enqueue_segment_backfill: { data: 77, error: null },
    },
  });
  const scored: string[] = [];
  const handler = handlerWith(fake.client, (_c, id) => {
    scored.push(id);
    return Promise.resolve({ outcome: 'recorded', matched: 1 });
  });
  const res = await handler(request({ segment_id: SEG }));
  assertEquals([res.status, await res.json()], [200, { scored: BACKFILL_BATCH, matched: BACKFILL_BATCH, next_job: 77 }]);
  assertEquals(scored, ids);
  assertEquals(fake.calls.find((c) => c.name === 'enqueue_segment_backfill')!.args, {
    p_segment_id: SEG,
    p_after_run_id: ids[ids.length - 1],
  });
});

Deno.test('a short batch ends the walk, and a failed run reruns the batch', async () => {
  const short = fakeClient({ rpcs: { segment_backfill_runs: { data: [{ run_id: RUN }], error: null } } });
  const res = await handlerWith(short.client, () => Promise.resolve({ outcome: 'stale', matched: 0 }))(
    request({ segment_id: SEG, after_run_id: RUN }),
  );
  assertEquals([res.status, await res.json()], [200, { scored: 1, matched: 0, next_job: null }]);
  assert(!short.calls.some((c) => c.name === 'enqueue_segment_backfill'));
  assertEquals(short.calls[0].args.p_after_run_id, RUN);

  const failing = await handlerWith(short.client, () => Promise.reject(new Error('down')))(
    request({ segment_id: SEG }),
  );
  assertEquals(failing.status, 500);
});
