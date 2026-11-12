/// Request handler for `segment-match`, behind injected deps so handler.test.ts
/// can drive it against a fake client (decisions § 2392).
///
/// Called only by the Go job worker for a claimed `segment_match` job, with the
/// job's payload as the body and the worker's server key on `apikey`. Gates,
/// each fail-closed, in this order: POST (405), the server key (503 when the
/// function has none configured, 403 otherwise, a rate limit spent only on a
/// wrong key), the body (413 / 400). Then the work.
///
/// The status is the worker's verdict: 2xx finishes the job, 5xx defers it for
/// a retry, any other 4xx fails it. A failed read is a 500; bytes that changed
/// under the pass are a 503; nothing to score is a 200.

import type { DbClient } from '../_shared/database.ts';
import { readJsonWithLimit } from '../_shared/body_limit.ts';
import { checkRateLimit, ipBucketKey } from '../_shared/rate_limit.ts';
import { BACKFILL_BATCH, parsePayload, type RunResult, scoreRun, serviceGate, serviceKeys } from './lib.ts';

export interface SegmentMatchDeps {
  getEnv: (name: string) => string | undefined;
  serviceClient: () => DbClient;
  scoreRun?: (client: DbClient, runId: string) => Promise<RunResult>;
}

/// The two payload shapes are a few hundred bytes; anything near this is not
/// the worker.
const MAX_BODY_BYTES = 4096;

export function makeSegmentMatchHandler(deps: SegmentMatchDeps): (req: Request) => Promise<Response> {
  const score = deps.scoreRun ?? scoreRun;
  return async (req: Request) => {
    if (req.method !== 'POST') {
      return Response.json({ error: 'method_not_allowed' }, { status: 405 });
    }

    const gate = serviceGate(
      serviceKeys(deps.getEnv),
      req.headers.get('apikey'),
      req.headers.get('Authorization'),
    );
    if (gate === 'not_configured') {
      return Response.json({ error: 'not_configured' }, { status: 503 });
    }
    if (gate !== 'ok') {
      if (gate === 'mismatch') {
        const denied = await checkRateLimit(
          deps.serviceClient(),
          await ipBucketKey(req),
          'segment-match:anon',
          60,
          3600,
          { failClosed: true },
        );
        if (denied) return denied;
      }
      return Response.json({ error: 'forbidden' }, { status: 403 });
    }

    const guarded = await readJsonWithLimit(req, MAX_BODY_BYTES);
    if ('tooLarge' in guarded) return guarded.tooLarge;
    const payload = parsePayload(guarded.body);
    if (!payload) {
      return Response.json({ error: 'bad_payload' }, { status: 400 });
    }

    const client = deps.serviceClient();
    try {
      if (payload.kind === 'run') {
        const result = await score(client, payload.runId);
        if (result.outcome === 'stale') {
          return Response.json({ outcome: result.outcome }, { status: 503 });
        }
        return Response.json(result);
      }

      const { data: batch, error: batchErr } = await client.rpc('segment_backfill_runs', {
        p_segment_id: payload.segmentId,
        p_after_run_id: payload.afterRunId ?? undefined,
        p_limit: BACKFILL_BATCH,
      });
      if (batchErr) {
        console.error('segment-match: backfill batch read failed (code):', batchErr.code ?? 'unknown');
        return Response.json({ error: 'batch_read_failed' }, { status: 500 });
      }
      const runIds = (batch ?? []).map((r: { run_id: string }) => r.run_id);
      let matched = 0;
      // A run whose bytes changed mid-pass already has its own per-run job
      // queued by the rewrite; the walk moves on. A throw (a failed read)
      // fails the whole batch, which reruns from the same cursor.
      for (const runId of runIds) {
        matched += (await score(client, runId)).matched;
      }

      let next: number | null = null;
      if (runIds.length === BACKFILL_BATCH) {
        const { data: jobId, error: nextErr } = await client.rpc('enqueue_segment_backfill', {
          p_segment_id: payload.segmentId,
          p_after_run_id: runIds[runIds.length - 1],
        });
        if (nextErr) {
          console.error('segment-match: next batch not queued (code):', nextErr.code ?? 'unknown');
          return Response.json({ error: 'continuation_failed' }, { status: 500 });
        }
        next = typeof jobId === 'number' ? jobId : null;
      }
      return Response.json({ scored: runIds.length, matched, next_job: next });
    } catch (e) {
      console.error('segment-match: pass failed:', e instanceof Error ? e.message : 'unknown');
      return Response.json({ error: 'pass_failed' }, { status: 500 });
    }
  };
}
