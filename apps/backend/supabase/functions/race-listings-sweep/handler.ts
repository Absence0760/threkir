/// Request handler for the scheduled RunSignUp race-calendar sweep, factored
/// out of index.ts behind injected deps (env lookup, the service client,
/// `fetch`, the clock) so handler.test.ts can drive every gate and the write
/// against fakes (decisions § 1902).
///
/// pg_cron (`invoke_race_listings_sweep`, through pg_net) calls it every five
/// minutes with the CRON_SECRET bearer. Each run reads ONE slot — one state
/// over one 14-day window — computed from the clock (`sweepWindowAt`), makes
/// ONE request to RunSignUp's public race feed, and hands the payload to the
/// write half `race-listings-sync` uses (./write.ts there), so a swept race and
/// a caller-synced race are the same listing.
///
/// Gates, each fail-closed, in this order: the cron bearer (503 when
/// CRON_SECRET is unset or short, 403 otherwise, a rate limit spent only on a
/// wrong bearer), then the upstream (504 when it has not answered in
/// `UPSTREAM_TIMEOUT_MS`; 502 when it cannot be reached, on a non-2xx, a
/// non-JSON body, a body that is not the race feed, or RunSignUp's HTTP-200
/// error envelope), then the write (500).
///
/// Nine slots a cycle also carry a parkrun leg (`parkrunChunkAt`, decisions
/// § 1958): one read of parkrun's events file, one ninth of it written. It is
/// OFF unless `PARKRUN_EVENTS_ENABLED` is exactly `true`, and then makes no
/// request at all and answers `parkrun: { enabled: false }`. It runs after the
/// RunSignUp leg whatever that leg answered, and its outcome rides in the body
/// under `parkrun` without changing the status, which stays RunSignUp's — so a
/// parkrun failure is read in the body and the log, not the status line.

import type { DbClient } from '../_shared/database.ts';
import { discardBody } from '../_shared/body_limit.ts';
import { checkRateLimit, ipBucketKey } from '../_shared/rate_limit.ts';
import { cronGate } from '../events-refund-sweep/lib.ts';
import { isUpstreamTimeout, UPSTREAM_TIMEOUT_MS } from '../_shared/upstream_deadline.ts';
import { providerRacesUrl, type SweepWindow, sweepWindowAt } from '../race-listings-sync/lib.ts';
import {
  PARKRUN_EVENTS_URL,
  PARKRUN_SWEEP_CHUNKS,
  parkrunChunkAt,
  parkrunEventsEnabled,
} from '../race-listings-sync/parkrun.ts';
import { syncParkrunPayload, syncProviderPayload } from '../race-listings-sync/write.ts';

export interface RaceListingsSweepDeps {
  getEnv: (name: string) => string | undefined;
  serviceClient: () => DbClient;
  fetch: (input: string, init?: RequestInit) => Promise<Response>;
  now: () => number;
  /// Overrides `UPSTREAM_TIMEOUT_MS`, so a test can watch the bound fire.
  upstreamTimeoutMs?: number;
}

export function makeRaceListingsSweepHandler(
  deps: RaceListingsSweepDeps,
): (req: Request) => Promise<Response> {
  return async (req: Request) => {
    // No body input; drop the stream before the gate so a chunked POST cannot
    // hold the connection open.
    discardBody(req);

    const gate = cronGate(deps.getEnv('CRON_SECRET'), req.headers.get('Authorization'));
    if (gate === 'not_configured') {
      return Response.json({ error: 'cron_not_configured' }, { status: 503 });
    }
    if (gate !== 'ok') {
      // Spent only on a wrong bearer, never in front of the compare, for the
      // reason refresh-tokens gives (decisions § 973): a limiter there would let
      // an unidentified caller starve the cron out of a shared bucket.
      if (gate === 'mismatch') {
        const denied = await checkRateLimit(
          deps.serviceClient(),
          await ipBucketKey(req),
          'race-listings-sweep:anon',
          60,
          3600,
          { failClosed: true },
        );
        if (denied) return denied;
      }
      return Response.json({ error: 'forbidden' }, { status: 403 });
    }

    const window = sweepWindowAt(deps.now());
    const runsignup = await runSignUpLeg(deps, window);
    const chunk = parkrunChunkAt(window.slot);
    if (chunk === null) return Response.json(runsignup.body, { status: runsignup.status });
    const parkrun = await parkrunLeg(deps, chunk);
    return Response.json({ ...runsignup.body, parkrun }, { status: runsignup.status });
  };
}

interface LegResult {
  status: number;
  body: Record<string, unknown>;
}

async function runSignUpLeg(deps: RaceListingsSweepDeps, window: SweepWindow): Promise<LegResult> {
  const apiKey = deps.getEnv('RUNSIGNUP_API_KEY') ?? null;
  const apiSecret = deps.getEnv('RUNSIGNUP_API_SECRET') ?? null;
  // One signal bounds the headers AND the body: a feed that sends its headers
  // and then trickles the 2.9 MB page is as stuck as one that never answers.
  const signal = AbortSignal.timeout(deps.upstreamTimeoutMs ?? UPSTREAM_TIMEOUT_MS);
  let upstream: Response;
  try {
    upstream = await deps.fetch(
      providerRacesUrl({ provider: 'runsignup', apiKey, apiSecret, near: null, window }),
      { headers: { 'User-Agent': deps.getEnv('RACE_IMPORT_USER_AGENT') || 'RunApp/1.0' }, signal },
    );
  } catch (err) {
    return isUpstreamTimeout(err)
      ? { status: 504, body: { error: 'runsignup upstream timeout', window } }
      : { status: 502, body: { error: 'runsignup upstream unreachable', window } };
  }
  if (!upstream.ok) {
    upstream.body?.cancel().catch(() => {});
    return { status: 502, body: { error: `runsignup upstream ${upstream.status}`, window } };
  }
  let payload: unknown;
  try {
    payload = await upstream.json();
  } catch (err) {
    return isUpstreamTimeout(err)
      ? { status: 504, body: { error: 'runsignup upstream timeout', window } }
      : { status: 502, body: { error: 'runsignup upstream not JSON', window } };
  }

  const outcome = await syncProviderPayload(deps.serviceClient(), 'runsignup', payload);
  if (!outcome.ok) {
    return { status: outcome.status, body: { error: outcome.error, window } };
  }
  // A window that filled the page lost the races past it. That is the signal
  // to narrow SWEEP_WINDOW_DAYS, so it is said where the operator reads.
  if (!outcome.summary.complete) {
    console.error('race-listings-sweep: window filled the page', JSON.stringify(window));
  }
  return { status: 200, body: { window, ...outcome.summary } };
}

/// One chunk of parkrun's events file. Disabled answers without a request.
async function parkrunLeg(deps: RaceListingsSweepDeps, chunk: number): Promise<Record<string, unknown>> {
  if (!parkrunEventsEnabled(deps.getEnv('PARKRUN_EVENTS_ENABLED'))) return { enabled: false, chunk };
  const signal = AbortSignal.timeout(deps.upstreamTimeoutMs ?? UPSTREAM_TIMEOUT_MS);
  const fail = (error: string, status: number) => {
    console.error('race-listings-sweep: parkrun leg failed', error);
    return { enabled: true, chunk, error, status };
  };
  let upstream: Response;
  try {
    upstream = await deps.fetch(PARKRUN_EVENTS_URL, {
      headers: {
        'User-Agent': deps.getEnv('PARKRUN_USER_AGENT') || deps.getEnv('RACE_IMPORT_USER_AGENT') || 'RunApp/1.0',
      },
      signal,
    });
  } catch (err) {
    return isUpstreamTimeout(err) ? fail('parkrun upstream timeout', 504) : fail('parkrun upstream unreachable', 502);
  }
  if (!upstream.ok) {
    upstream.body?.cancel().catch(() => {});
    return fail(`parkrun upstream ${upstream.status}`, 502);
  }
  let payload: unknown;
  try {
    payload = await upstream.json();
  } catch (err) {
    return isUpstreamTimeout(err) ? fail('parkrun upstream timeout', 504) : fail('parkrun upstream not JSON', 502);
  }
  const outcome = await syncParkrunPayload(
    deps.serviceClient(),
    payload,
    { kind: 'chunk', index: chunk, count: PARKRUN_SWEEP_CHUNKS },
    deps.now(),
  );
  if (!outcome.ok) return fail(outcome.error, outcome.status);
  return { enabled: true, chunk, ...outcome.summary };
}
