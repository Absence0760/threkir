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

import type { DbClient } from '../_shared/database.ts';
import { discardBody } from '../_shared/body_limit.ts';
import { checkRateLimit, ipBucketKey } from '../_shared/rate_limit.ts';
import { cronGate } from '../events-refund-sweep/lib.ts';
import { providerRacesUrl, sweepWindowAt, UPSTREAM_TIMEOUT_MS } from '../race-listings-sync/lib.ts';
import { syncProviderPayload } from '../race-listings-sync/write.ts';

export interface RaceListingsSweepDeps {
  getEnv: (name: string) => string | undefined;
  serviceClient: () => DbClient;
  fetch: (input: string, init?: RequestInit) => Promise<Response>;
  now: () => number;
  /// Overrides `UPSTREAM_TIMEOUT_MS`, so a test can watch the bound fire.
  upstreamTimeoutMs?: number;
}

/// Whether a rejected fetch or body read is the request bound firing.
function timedOut(err: unknown): boolean {
  return err instanceof DOMException && err.name === 'TimeoutError';
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
      return timedOut(err)
        ? Response.json({ error: 'runsignup upstream timeout', window }, { status: 504 })
        : Response.json({ error: 'runsignup upstream unreachable', window }, { status: 502 });
    }
    if (!upstream.ok) {
      upstream.body?.cancel().catch(() => {});
      return Response.json({ error: `runsignup upstream ${upstream.status}`, window }, { status: 502 });
    }
    let payload: unknown;
    try {
      payload = await upstream.json();
    } catch (err) {
      return timedOut(err)
        ? Response.json({ error: 'runsignup upstream timeout', window }, { status: 504 })
        : Response.json({ error: 'runsignup upstream not JSON', window }, { status: 502 });
    }

    const outcome = await syncProviderPayload(deps.serviceClient(), 'runsignup', payload);
    if (!outcome.ok) {
      return Response.json({ error: outcome.error, window }, { status: outcome.status });
    }
    // A window that filled the page lost the races past it. That is the signal
    // to narrow SWEEP_WINDOW_DAYS, so it is said where the operator reads.
    if (!outcome.summary.complete) {
      console.error('race-listings-sweep: window filled the page', JSON.stringify(window));
    }
    return Response.json({ window, ...outcome.summary });
  };
}
