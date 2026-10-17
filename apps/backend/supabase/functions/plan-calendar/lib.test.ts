/// The pure halves of the plan-calendar feed: token parsing, the
/// constant-time secret check and the VCALENDAR body.
///
/// Run with:
///   cd apps/backend && deno test --no-check --allow-read supabase/functions/plan-calendar/lib.test.ts

import { assert, assertEquals, assertMatch } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import {
  buildPlanFeedIcs,
  byteaHex,
  feedBucketKey,
  type FeedDocument,
  type FeedWorkout,
  KIND_LABELS,
  parseFeedDocument,
  parseFeedToken,
  planCalendarIpLimiter,
  secretMatches,
  sha256Hex,
  targetPaceText,
  unnamedBucketKey,
  WORKOUT_KINDS,
  workoutText,
} from './lib.ts';

const ID_HEX = '0f1e2d3c4b5a69788796a5b4c3d2e1f0';
const FEED_ID = '0f1e2d3c-4b5a-6978-8796-a5b4c3d2e1f0';
const SECRET = 'a'.repeat(32) + 'b'.repeat(32);
const TOKEN = ID_HEX + SECRET;
const BASE = 'http://127.0.0.1:24321/functions/v1/plan-calendar';

Deno.test('parseFeedToken reads the id and secret out of the .ics path', () => {
  assertEquals(parseFeedToken(`${BASE}/${TOKEN}.ics`), { feedId: FEED_ID, secret: SECRET });
});

Deno.test('parseFeedToken accepts the path without .ics, and upper-case hex', () => {
  assertEquals(parseFeedToken(`${BASE}/${TOKEN}`), { feedId: FEED_ID, secret: SECRET });
  assertEquals(parseFeedToken(`${BASE}/${TOKEN.toUpperCase()}.ICS`), { feedId: FEED_ID, secret: SECRET });
});

Deno.test('parseFeedToken refuses every other shape', () => {
  for (const url of [
    `${BASE}`,
    `${BASE}/`,
    `${BASE}/${TOKEN.slice(1)}.ics`,
    `${BASE}/${TOKEN}0.ics`,
    `${BASE}/${TOKEN.slice(0, 95)}g.ics`,
    `${BASE}/${TOKEN}.ics/extra`,
    `${BASE}?token=${TOKEN}`,
    `http://127.0.0.1/functions/v1/other/${TOKEN}.ics`,
    'not a url',
  ]) {
    assertEquals(parseFeedToken(url), null, url);
  }
});

Deno.test('secretMatches accepts the secret whose SHA-256 is stored, and nothing else', async () => {
  const stored = await sha256Hex(SECRET);
  assert(await secretMatches(SECRET, stored));
  assert(!(await secretMatches('c'.repeat(64), stored)));
  assert(!(await secretMatches(SECRET.slice(0, 63) + 'c', stored)));
});

Deno.test('secretMatches refuses when there is no feed, even for a secret hashing to the placeholder', async () => {
  assert(!(await secretMatches(SECRET, null)));
  assert(!(await secretMatches('0'.repeat(64), null)));
  assert(await secretMatches(SECRET, await sha256Hex(SECRET)), 'positive control');
});

Deno.test('the stored hash is compared in constant time, not with ===', async () => {
  // Reason: an early-exit compare leaks how many leading hash characters a
  // guess got right. The compare must go through timingSafeEqual.
  const src = await Deno.readTextFile(new URL('./lib.ts', import.meta.url));
  const body = src.slice(src.indexOf('export async function secretMatches'));
  const fn = body.slice(0, body.indexOf('\n}\n'));
  assertMatch(fn, /timingSafeEqual\(supplied, storedHashHex \?\? NO_FEED_HASH\)/);
  assert(!/supplied\s*===|===\s*supplied/.test(fn), 'secretMatches compares with ===');
});

Deno.test('byteaHex reads the PostgREST bytea serialisation', () => {
  const hex = 'ab'.repeat(32);
  assertEquals(byteaHex(`\\x${hex}`), hex);
  assertEquals(byteaHex(`\\x${hex.toUpperCase()}`), hex);
  assertEquals(byteaHex('\\xab'), null);
  assertEquals(byteaHex(null), null);
  assertEquals(byteaHex(42), null);
});

Deno.test('feedBucketKey is a stable UUIDv8-shaped key per feed', async () => {
  const a = await feedBucketKey(FEED_ID);
  assertMatch(a, /^[0-9a-f]{8}-[0-9a-f]{4}-8[0-9a-f]{3}-[0-9a-f]{4}-[0-9a-f]{12}$/);
  assertEquals(a, await feedBucketKey(FEED_ID));
  assert(a !== (await feedBucketKey('00000000-0000-4000-8000-000000000000')));
});

const W = (over: Partial<FeedWorkout> = {}): FeedWorkout => ({
  id: '11111111-1111-4111-8111-111111111111',
  date: '2026-10-05',
  kind: 'tempo',
  targetDistanceM: 8000,
  targetDurationS: null,
  targetPaceSecPerKm: 290,
  targetPaceEndSecPerKm: null,
  targetPaceToleranceSec: 5,
  ...over,
});

Deno.test('parseFeedDocument narrows the RPC result and drops rows it cannot read', () => {
  const doc = parseFeedDocument({
    unit: 'mi',
    locale: 'de-AT',
    workouts: [
      { id: W().id, date: '2026-10-05', kind: 'tempo', target_distance_m: 8000, target_pace_sec_per_km: 290 },
      { id: 'not-a-uuid', date: '2026-10-06', kind: 'easy' },
      { id: W().id, date: '2026-02-30', kind: 'easy' },
      { id: W().id, date: '2026-10-07', kind: 'rest' },
      { id: W().id, date: '2026-10-08', kind: 'yoga' },
      null,
    ],
  });
  assertEquals(doc?.unit, 'mi');
  assertEquals(doc?.locale, 'de');
  assertEquals(doc?.workouts.length, 1);
  assertEquals(doc?.workouts[0].targetDurationS, null);
});

Deno.test('parseFeedDocument falls back to km and English, and refuses a non-object', () => {
  assertEquals(parseFeedDocument({ workouts: [] }), { unit: 'km', locale: 'en', workouts: [] });
  assertEquals(parseFeedDocument(null), null);
  assertEquals(parseFeedDocument([]), null);
});

Deno.test('targetPaceText converts pace and tolerance to the owner unit', () => {
  assertEquals(targetPaceText(W(), 'km'), '4:50/km ±5s');
  // 290 s/km = 466.7 s/mi; 5 s/km = 8.0 s/mi.
  assertEquals(targetPaceText(W(), 'mi'), '7:47/mi ±8s');
  assertEquals(targetPaceText(W({ targetPaceToleranceSec: null }), 'km'), '4:50/km');
  assertEquals(targetPaceText(W({ targetPaceEndSecPerKm: 270 }), 'km'), '4:50–4:30/km');
  assertEquals(targetPaceText(W({ targetPaceSecPerKm: null }), 'km'), null);
});

Deno.test('workoutText leads with the kind and the distance, else the duration', () => {
  assertEquals(workoutText(W(), { unit: 'km', locale: 'en' }), {
    summary: 'Tempo · 8 km',
    description: '8 km · 4:50/km ±5s',
  });
  assertEquals(
    workoutText(W({ kind: 'easy', targetDistanceM: null, targetDurationS: 2700, targetPaceSecPerKm: null }), {
      unit: 'km',
      locale: 'en',
    }),
    { summary: 'Easy · 45 min', description: '45 min' },
  );
  assertEquals(
    workoutText(W({ kind: 'race', targetDistanceM: null, targetPaceSecPerKm: null }), { unit: 'km', locale: 'en' }),
    { summary: 'Race', description: null },
  );
});

Deno.test('workoutText speaks the owner language and unit', () => {
  assertEquals(workoutText(W({ kind: 'long', targetDistanceM: 21097.5 }), { unit: 'mi', locale: 'de' }).summary, 'Langer Lauf · 13,1 mi');
  // French separates a number from its unit with a narrow no-break space.
  assertEquals(workoutText(W({ kind: 'interval' }), { unit: 'km', locale: 'fr' }).summary, 'Fractionné · 8\u202fkm');
});

Deno.test('the kind labels are the web catalogue workoutKind.* strings, in every locale', async () => {
  // Reason: a calendar entry that names a workout differently from the plan
  // page reads as a different workout.
  for (const locale of Object.keys(KIND_LABELS)) {
    const src = await Deno.readTextFile(
      new URL(`../../../../web/src/lib/i18n/locales/${locale}.ts`, import.meta.url),
    );
    for (const kind of WORKOUT_KINDS) {
      const m = new RegExp(`["']workoutKind\\.${kind}["']:\\s*["']([^"']+)["']`).exec(src);
      assert(m, `${locale}.ts has no workoutKind.${kind}`);
      assertEquals(KIND_LABELS[locale][kind], m[1], `${locale} ${kind}`);
    }
  }
  const locales = [...Deno.readDirSync(new URL('../../../../web/src/lib/i18n/locales/', import.meta.url))]
    .map((e) => e.name.replace(/\.ts$/, ''))
    .sort();
  assertEquals(Object.keys(KIND_LABELS).sort(), locales, 'a web locale has no calendar labels');
});

const DOC: FeedDocument = { unit: 'km', locale: 'en', workouts: [W()] };
const NOW = Date.UTC(2026, 9, 16, 12, 0, 0);

Deno.test('buildPlanFeedIcs writes one all-day, transparent VEVENT per workout', () => {
  const ics = buildPlanFeedIcs(DOC, NOW);
  const lines = ics.split('\r\n');
  assertEquals(lines.slice(0, 8), [
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//Threkir//Run App//EN',
    'CALSCALE:GREGORIAN',
    'METHOD:PUBLISH',
    'X-WR-CALNAME:Threkir',
    'REFRESH-INTERVAL;VALUE=DURATION:PT6H',
    'X-PUBLISHED-TTL:PT6H',
  ]);
  assertEquals(lines.slice(8, 18), [
    'BEGIN:VEVENT',
    'UID:plan-workout-11111111-1111-4111-8111-111111111111@threkir.com',
    'DTSTAMP:20261016T120000Z',
    'DTSTART;VALUE=DATE:20261005',
    'DTEND;VALUE=DATE:20261006',
    'SUMMARY:Tempo · 8 km',
    'DESCRIPTION:8 km · 4:50/km ±5s',
    'TRANSP:TRANSPARENT',
    'END:VEVENT',
    'END:VCALENDAR',
  ]);
  assert(ics.endsWith('\r\n'));
});

Deno.test('buildPlanFeedIcs ends an entry on the next day across a month and year end', () => {
  const ics = buildPlanFeedIcs({ ...DOC, workouts: [W({ date: '2026-12-31' })] }, NOW);
  assert(ics.includes('DTSTART;VALUE=DATE:20261231\r\nDTEND;VALUE=DATE:20270101\r\n'));
});

Deno.test('buildPlanFeedIcs carries no location, URL or organiser', () => {
  const ics = buildPlanFeedIcs({ ...DOC, workouts: WORKOUT_KINDS.map((kind) => W({ kind })) }, NOW);
  for (const prop of ['LOCATION', 'GEO', 'URL', 'ORGANIZER', 'ATTENDEE', 'ATTACH']) {
    assert(!new RegExp(`^${prop}[:;]`, 'm').test(ics), `${prop} in the feed`);
  }
});

Deno.test('an empty plan is a valid, empty calendar', () => {
  const ics = buildPlanFeedIcs({ ...DOC, workouts: [] }, NOW);
  assert(!ics.includes('BEGIN:VEVENT'));
  assert(ics.trimEnd().endsWith('END:VCALENDAR'));
});

Deno.test('the per-IP limiter checks a named caller by address and every unnamed caller in one shared bucket', async () => {
  const checked: string[] = [];
  const limiter = planCalendarIpLimiter(
    (req) => req.headers.get('cf-connecting-ip'),
    (req) => {
      checked.push(`named:${req.headers.get('cf-connecting-ip')}`);
      return Promise.resolve(null);
    },
    () => {
      checked.push('unnamed');
      return Promise.resolve(new Response('slow down', { status: 429 }));
    },
  );
  const unnamed = await limiter(new Request('http://x/a.ics'));
  assertEquals(unnamed?.status, 429);
  assertEquals(await limiter(new Request('http://x/a.ics', { headers: { 'cf-connecting-ip': '203.0.113.7' } })), null);
  assertEquals(checked, ['unnamed', 'named:203.0.113.7']);
});

Deno.test('every unnamed caller shares one stable UUIDv8-shaped bucket key', async () => {
  const key = await unnamedBucketKey();
  assertEquals(key, await unnamedBucketKey());
  assertMatch(key, /^[0-9a-f]{8}-[0-9a-f]{4}-8[0-9a-f]{3}-[0-9a-f]{4}-[0-9a-f]{12}$/);
  assert(key !== (await feedBucketKey('plan-calendar-unnamed-v1')));
});
