/// `park-closures-sweep`: the daily read of NPS alerts for every active
/// National Park Service park with a course (issue #1313 Phase 6, decisions
/// § 2453). pg_cron (`invoke_park_closures_sweep`, through pg_net) calls it
/// with the CRON_SECRET bearer.
///
/// It never changes a course. Each alert that may affect a course (./lib.ts)
/// is written by `record_park_nps_alerts` as a flag for operator review, read
/// at /admin/park-alerts, where the operator closes the course from the admin
/// queue if the alert really shuts it.
///
/// Gates, fail-closed, in order:
///   1. the cron bearer: 503 when CRON_SECRET is unset or short, 403 on a
///      missing or wrong bearer (rate-limited per IP only on a wrong one);
///   2. the NPS key: with NPS_API_KEY unset it asks NPS nothing, writes
///      nothing, says so in its log, and answers 200 `{ configured: false }`
///      so arming the schedule before the key exists is not an error;
///   3. each chunk of parks: a request that fails, times out or returns
///      something other than the alerts envelope records nothing for those
///      parks, so an outage never reads as "the alert is gone". The answer is
///      502 when any chunk failed, with the summary.
///
/// The key goes in the `X-Api-Key` header. Requests are sequential with a
/// pause between them (`REQUEST_GAP_MS`), ten parks a request.

import type { DbClient } from '../_shared/database.ts';
import { discardBody } from '../_shared/body_limit.ts';
import { checkRateLimit, ipBucketKey } from '../_shared/rate_limit.ts';
import { cronGate } from '../events-refund-sweep/lib.ts';
import { UPSTREAM_TIMEOUT_MS } from '../_shared/upstream_deadline.ts';
import {
  alertsUrl,
  chunk,
  flagsForPark,
  MAX_PAGES,
  type NpsAlert,
  PARKS_PER_REQUEST,
  parseAlertsPage,
  REQUEST_GAP_MS,
  type SweepCourse,
} from './lib.ts';

/// The whole run's budget, inside the Edge runtime's 150 s wall clock, so a
/// slow NPS cannot get the request killed with nothing recorded.
export const SWEEP_BUDGET_MS = 120_000;

export interface ParkClosuresSweepDeps {
  getEnv: (name: string) => string | undefined;
  serviceClient: () => DbClient;
  fetch: (input: string, init?: RequestInit) => Promise<Response>;
  sleep: (ms: number) => Promise<void>;
  /// Overrides the per-request and whole-run bounds in tests.
  upstreamTimeoutMs?: number;
  budgetMs?: number;
}

interface Target {
  park_id: string;
  nps_park_code: string;
  courses: SweepCourse[];
}

export function makeParkClosuresSweepHandler(
  deps: ParkClosuresSweepDeps,
): (req: Request) => Promise<Response> {
  return async (req: Request) => {
    discardBody(req);

    const gate = cronGate(deps.getEnv('CRON_SECRET'), req.headers.get('Authorization'));
    if (gate === 'not_configured') return Response.json({ error: 'cron_not_configured' }, { status: 503 });
    if (gate !== 'ok') {
      if (gate === 'mismatch') {
        const denied = await checkRateLimit(
          deps.serviceClient(),
          await ipBucketKey(req),
          'park-closures-sweep:anon',
          60,
          3600,
          { failClosed: true },
        );
        if (denied) return denied;
      }
      return Response.json({ error: 'forbidden' }, { status: 403 });
    }

    const apiKey = deps.getEnv('NPS_API_KEY')?.trim();
    if (!apiKey) {
      console.log('park-closures-sweep: NPS_API_KEY is not set; no park was checked and nothing was flagged');
      return Response.json({ configured: false }, { status: 200 });
    }

    const db = deps.serviceClient();
    const { data, error } = await db.rpc('park_nps_sweep_targets');
    if (error) {
      console.error('park-closures-sweep: target list failed', { code: error.code });
      return Response.json({ error: 'targets_failed' }, { status: 500 });
    }
    const targets = (data ?? []) as unknown as Target[];
    const summary = { configured: true, parks: targets.length, requests: 0, alerts: 0, flagged: 0, failed_parks: 0, errors: 0 };
    if (targets.length === 0) return Response.json(summary, { status: 200 });

    const budget = AbortSignal.timeout(deps.budgetMs ?? SWEEP_BUDGET_MS);
    const chunks = chunk(targets, PARKS_PER_REQUEST);
    for (const [i, parks] of chunks.entries()) {
      if (i > 0) await deps.sleep(REQUEST_GAP_MS);
      const codes = parks.map((p) => p.nps_park_code);
      const alerts = await fetchChunk(deps, apiKey, codes, budget, summary);
      if (alerts === null) {
        summary.failed_parks += parks.length;
        continue;
      }
      summary.alerts += alerts.length;
      for (const park of parks) {
        const own = alerts.filter((a) => a.parkCode === park.nps_park_code);
        const flags = flagsForPark(own, park.courses);
        const { error: recordError } = await db.rpc('record_park_nps_alerts', {
          p_park_id: park.park_id,
          p_flags: flags,
          p_seen_alert_ids: own.map((a) => a.id),
        });
        if (recordError) {
          console.error('park-closures-sweep: record failed', { code: recordError.code });
          summary.errors++;
          continue;
        }
        summary.flagged += flags.length;
      }
    }
    const failed = summary.failed_parks > 0 || summary.errors > 0;
    return Response.json(summary, { status: failed ? 502 : 200 });
  };
}

/// Every page of one chunk's alerts, or null when any page failed.
async function fetchChunk(
  deps: ParkClosuresSweepDeps,
  apiKey: string,
  codes: string[],
  budget: AbortSignal,
  summary: { requests: number },
): Promise<NpsAlert[] | null> {
  const out: NpsAlert[] = [];
  let start = 0;
  for (let page = 0; page < MAX_PAGES; page++) {
    if (page > 0) await deps.sleep(REQUEST_GAP_MS);
    if (budget.aborted) {
      console.error('park-closures-sweep: run budget spent before a chunk', { parks: codes.length });
      return null;
    }
    const signal = AbortSignal.any([budget, AbortSignal.timeout(deps.upstreamTimeoutMs ?? UPSTREAM_TIMEOUT_MS)]);
    let res: Response;
    summary.requests++;
    try {
      res = await deps.fetch(alertsUrl(codes, start), { headers: { 'X-Api-Key': apiKey, Accept: 'application/json' }, signal });
    } catch (err) {
      console.error('park-closures-sweep: NPS unreachable', { name: (err as Error)?.name ?? 'error' });
      return null;
    }
    if (!res.ok) {
      res.body?.cancel().catch(() => {});
      console.error('park-closures-sweep: NPS answered', { status: res.status });
      return null;
    }
    let payload: unknown;
    try {
      payload = await res.json();
    } catch (err) {
      console.error('park-closures-sweep: NPS body unreadable', { name: (err as Error)?.name ?? 'error' });
      return null;
    }
    const parsed = parseAlertsPage(payload);
    if (parsed === null) {
      console.error('park-closures-sweep: NPS body is not an alerts page');
      return null;
    }
    out.push(...parsed.alerts);
    start = parsed.start + parsed.count;
    if (parsed.count === 0 || start >= parsed.total) return out;
  }
  console.error('park-closures-sweep: a chunk ran past its page cap', { parks: codes.length });
  return null;
}
