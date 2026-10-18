/// The plan-calendar request path, driven with a fake feed table: a valid
/// token serves the calendar; a wrong secret, an unknown id, a revoked feed
/// and a rotated-away token all answer the same uncacheable 404; both rate
/// limits run, in order, and a read failure is a 503 rather than an empty
/// calendar.
///
/// Run with:
///   cd apps/backend && deno test --no-check --allow-read supabase/functions/plan-calendar/handler.test.ts

import { assert, assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { makePlanCalendarHandler, type PlanCalendarDeps } from './handler.ts';
import { sha256Hex } from './lib.ts';

const BASE = 'http://127.0.0.1:24321/plan-calendar';

interface Feed {
  idHex: string;
  secret: string;
}

/// An in-memory stand-in for plan_calendar_feeds keyed the way the real table
/// is: by row id, holding only the SHA-256 of the secret.
class FakeFeeds {
  rows = new Map<string, string>();
  calls: string[] = [];
  failSecretRead = false;
  failBodyRead = false;

  async mint(): Promise<Feed> {
    const idHex = crypto.randomUUID().replaceAll('-', '');
    const secret = (crypto.randomUUID() + crypto.randomUUID()).replaceAll('-', '');
    this.rows.set(uuidOf(idHex), `\\x${await sha256Hex(secret)}`);
    return { idHex, secret };
  }

  deps(over: Partial<PlanCalendarDeps> = {}): PlanCalendarDeps {
    return {
      limitByIp: () => {
        this.calls.push('ip');
        return Promise.resolve(null);
      },
      limitByFeed: (id) => {
        this.calls.push(`feed:${id}`);
        return Promise.resolve(null);
      },
      readSecretHash: (id) => {
        this.calls.push(`hash:${id}`);
        if (this.failSecretRead) return Promise.reject(new Error('boom'));
        return Promise.resolve(this.rows.get(id) ?? null);
      },
      readFeedBody: (id) => {
        this.calls.push(`body:${id}`);
        if (this.failBodyRead) return Promise.reject(new Error('boom'));
        if (!this.rows.has(id)) return Promise.resolve(null);
        return Promise.resolve({
          unit: 'km',
          locale: 'en',
          workouts: [{
            id: '11111111-1111-4111-8111-111111111111',
            date: '2026-10-05',
            kind: 'easy',
            target_distance_m: 6000,
          }],
        });
      },
      now: () => Date.UTC(2026, 9, 16),
      ...over,
    };
  }
}

function uuidOf(h: string): string {
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20)}`;
}

const url = (f: Feed) => `${BASE}/${f.idHex}${f.secret}.ics`;

async function assertNotFound(res: Response) {
  assertEquals(res.status, 404);
  assertEquals(res.headers.get('cache-control'), 'no-store');
  assertEquals(await res.text(), 'Not found');
}

Deno.test('a valid token serves the calendar as private, cacheable text/calendar', async () => {
  const feeds = new FakeFeeds();
  const feed = await feeds.mint();
  const res = await makePlanCalendarHandler(feeds.deps())(new Request(url(feed)));
  assertEquals(res.status, 200);
  assertEquals(res.headers.get('content-type'), 'text/calendar; charset=utf-8');
  assertEquals(res.headers.get('cache-control'), 'private, max-age=300');
  assertEquals(res.headers.get('x-content-type-options'), 'nosniff');
  const body = await res.text();
  assert(body.startsWith('BEGIN:VCALENDAR\r\n'));
  assert(body.includes('SUMMARY:Easy · 6 km\r\n'));
});

Deno.test('HEAD answers the same headers with no body', async () => {
  const feeds = new FakeFeeds();
  const feed = await feeds.mint();
  const res = await makePlanCalendarHandler(feeds.deps())(new Request(url(feed), { method: 'HEAD' }));
  assertEquals(res.status, 200);
  assertEquals(res.headers.get('content-type'), 'text/calendar; charset=utf-8');
  assertEquals(await res.text(), '');
});

Deno.test('a wrong secret for a real feed id is a 404 and never reads the body', async () => {
  const feeds = new FakeFeeds();
  const feed = await feeds.mint();
  const wrong = { ...feed, secret: feed.secret.slice(0, 63) + (feed.secret.endsWith('0') ? '1' : '0') };
  const res = await makePlanCalendarHandler(feeds.deps())(new Request(url(wrong)));
  await assertNotFound(res);
  assert(!feeds.calls.some((c) => c.startsWith('body:')), 'read the feed body on a wrong secret');
  assert(!feeds.calls.some((c) => c.startsWith('feed:')), 'spent the feed bucket on a wrong secret');
});

Deno.test('a revoked feed answers 404', async () => {
  const feeds = new FakeFeeds();
  const feed = await feeds.mint();
  feeds.rows.delete(uuidOf(feed.idHex));
  await assertNotFound(await makePlanCalendarHandler(feeds.deps())(new Request(url(feed))));
});

Deno.test('a rotated-away token answers 404 while the new one serves', async () => {
  const feeds = new FakeFeeds();
  const old = await feeds.mint();
  feeds.rows.delete(uuidOf(old.idHex));
  const fresh = await feeds.mint();
  const handler = makePlanCalendarHandler(feeds.deps());
  await assertNotFound(await handler(new Request(url(old))));
  assertEquals((await handler(new Request(url(fresh)))).status, 200);
});

Deno.test('the old secret under the new id does not serve', async () => {
  const feeds = new FakeFeeds();
  const old = await feeds.mint();
  feeds.rows.delete(uuidOf(old.idHex));
  const fresh = await feeds.mint();
  const handler = makePlanCalendarHandler(feeds.deps());
  await assertNotFound(await handler(new Request(url({ idHex: fresh.idHex, secret: old.secret }))));
});

Deno.test('a feed revoked between the secret check and the body read answers 404, not an empty calendar', async () => {
  const feeds = new FakeFeeds();
  const feed = await feeds.mint();
  const deps = feeds.deps({ readFeedBody: () => Promise.resolve(null) });
  await assertNotFound(await makePlanCalendarHandler(deps)(new Request(url(feed))));
});

Deno.test('a malformed token is a 404 that spends no bucket and reads no table', async () => {
  const feeds = new FakeFeeds();
  const res = await makePlanCalendarHandler(feeds.deps())(new Request(`${BASE}/not-a-token.ics`));
  await assertNotFound(res);
  assertEquals(feeds.calls, []);
});

Deno.test('the per-IP limit runs before the secret is read', async () => {
  const feeds = new FakeFeeds();
  const feed = await feeds.mint();
  const denied = new Response('slow down', { status: 429 });
  const res = await makePlanCalendarHandler(feeds.deps({
    limitByIp: () => Promise.resolve(denied),
  }))(new Request(url(feed)));
  assertEquals(res.status, 429);
  assertEquals(feeds.calls, []);
});

Deno.test('the per-feed limit runs after the secret check and before the body read', async () => {
  const feeds = new FakeFeeds();
  const feed = await feeds.mint();
  const id = uuidOf(feed.idHex);
  const res = await makePlanCalendarHandler(feeds.deps({
    limitByFeed: (fid) => {
      feeds.calls.push(`feed:${fid}`);
      return Promise.resolve(new Response('slow down', { status: 429 }));
    },
  }))(new Request(url(feed)));
  assertEquals(res.status, 429);
  assertEquals(feeds.calls, ['ip', `hash:${id}`, `feed:${id}`]);
});

Deno.test('a failed feed-row read is a 503, not a 404 that would read as revoked', async () => {
  const feeds = new FakeFeeds();
  const feed = await feeds.mint();
  feeds.failSecretRead = true;
  const res = await makePlanCalendarHandler(feeds.deps())(new Request(url(feed)));
  assertEquals(res.status, 503);
  assertEquals(res.headers.get('cache-control'), 'no-store');
});

Deno.test('a failed body read is a 503, not an empty calendar that would wipe the subscriber', async () => {
  const feeds = new FakeFeeds();
  const feed = await feeds.mint();
  feeds.failBodyRead = true;
  const res = await makePlanCalendarHandler(feeds.deps())(new Request(url(feed)));
  assertEquals(res.status, 503);
});

Deno.test('only GET and HEAD are served', async () => {
  const feeds = new FakeFeeds();
  const feed = await feeds.mint();
  const res = await makePlanCalendarHandler(feeds.deps())(new Request(url(feed), { method: 'POST' }));
  assertEquals(res.status, 405);
  assertEquals(res.headers.get('allow'), 'GET, HEAD');
  assertEquals(feeds.calls, []);
});

Deno.test('an unknown id runs the same secret comparison as a known one', async () => {
  // Reason: returning before the compare when the row is missing makes an
  // unknown id measurably faster than a known id with a wrong secret, which
  // tells a prober which half of a guessed token was right.
  const src = await Deno.readTextFile(new URL('./handler.ts', import.meta.url));
  const between = src.slice(src.indexOf('stored = byteaHex('), src.indexOf('const feedDenied'));
  assert(!/if \(!?stored/.test(between), 'the handler branches on the stored hash before comparing');
  assert(between.includes('secretMatches(token.secret, stored)'));
});
