/// Request handler for the plan-calendar feed, factored out of index.ts
/// behind injected deps (the two rate limits, the feed-row read, the body
/// read) so `handler.test.ts` drives the whole auth path — valid, revoked,
/// rotated, wrong secret, malformed — with no stack.
///
/// The URL is the credential (a calendar client sends no header), so every
/// way of not being a live feed answers the same 404 with `no-store`: an
/// unknown id, a wrong secret, a revoked or rotated feed. Nothing tells a
/// prober which half of a guessed token was wrong. The secret is checked
/// against the stored SHA-256 in constant time, and the comparison also runs
/// when the id matches no row.
///
/// Order: the token's shape first, which costs nothing, so a malformed path
/// is a 404 that spends no bucket and reads no table; then a coarse per-IP
/// bucket, so the secret read cannot be ground at network rate from one
/// address; then the secret; then a per-feed bucket, so one leaked URL
/// hammered from many addresses is capped too. Both buckets fail closed.
/// A caller the trusted header does not name shares one high bucket instead
/// of the per-address one (planCalendarIpLimiter): calendar providers poll
/// from shared pools, and the low per-address bucket shared by every unnamed
/// caller would let one lock every feed out.

import {
  buildPlanFeedIcs,
  byteaHex,
  parseFeedDocument,
  parseFeedToken,
  secretMatches,
} from './lib.ts';

export interface PlanCalendarDeps {
  /// Null to proceed, or the 429/503 to return.
  limitByIp: (req: Request) => Promise<Response | null>;
  limitByFeed: (feedId: string) => Promise<Response | null>;
  /// The stored `secret_hash` (as PostgREST serialises a bytea) for a feed
  /// id; null when no such feed exists. Throws on a read failure.
  readSecretHash: (feedId: string) => Promise<unknown | null>;
  /// `plan_calendar_feed_events(feedId)`; null when the feed vanished between
  /// the two reads. Throws on a read failure.
  readFeedBody: (feedId: string) => Promise<unknown | null>;
  now?: () => number;
}

/// Per-user schedule: no shared cache may keep it, and a calendar re-reading
/// within five minutes may reuse its own copy. Kept short because a revoked
/// or rotated URL keeps serving from that copy until it expires; calendar
/// apps poll hourly or less often, so a longer age saves no requests.
const FEED_CACHE_CONTROL = 'private, max-age=300';

const BASE_HEADERS = {
  'X-Content-Type-Options': 'nosniff',
  'Referrer-Policy': 'no-referrer',
};

function notFound(): Response {
  return new Response('Not found', {
    status: 404,
    headers: { ...BASE_HEADERS, 'Content-Type': 'text/plain; charset=utf-8', 'Cache-Control': 'no-store' },
  });
}

function unavailable(): Response {
  return new Response('Temporarily unavailable', {
    status: 503,
    headers: {
      ...BASE_HEADERS,
      'Content-Type': 'text/plain; charset=utf-8',
      'Cache-Control': 'no-store',
      'Retry-After': '60',
    },
  });
}

export function makePlanCalendarHandler(deps: PlanCalendarDeps): (req: Request) => Promise<Response> {
  return async (req: Request) => {
    if (req.method !== 'GET' && req.method !== 'HEAD') {
      return new Response('Method not allowed', {
        status: 405,
        headers: { ...BASE_HEADERS, Allow: 'GET, HEAD', 'Cache-Control': 'no-store' },
      });
    }

    const token = parseFeedToken(req.url);
    if (!token) return notFound();

    const ipDenied = await deps.limitByIp(req);
    if (ipDenied) return ipDenied;

    let stored: string | null;
    try {
      stored = byteaHex(await deps.readSecretHash(token.feedId));
    } catch {
      return unavailable();
    }
    if (!(await secretMatches(token.secret, stored))) return notFound();

    const feedDenied = await deps.limitByFeed(token.feedId);
    if (feedDenied) return feedDenied;

    let raw: unknown;
    try {
      raw = await deps.readFeedBody(token.feedId);
    } catch {
      return unavailable();
    }
    if (raw === null) return notFound();
    const doc = parseFeedDocument(raw);
    if (!doc) return unavailable();

    const body = buildPlanFeedIcs(doc, (deps.now ?? Date.now)());
    return new Response(req.method === 'HEAD' ? null : body, {
      status: 200,
      headers: {
        ...BASE_HEADERS,
        'Content-Type': 'text/calendar; charset=utf-8',
        'Content-Disposition': 'inline; filename="threkir-plan.ics"',
        'Cache-Control': FEED_CACHE_CONTROL,
      },
    });
  };
}
