/// The parkrun leg's pure half (parkrun.ts) against the recorded events file:
/// the next-date rule per series and zone, the country → zone table, the
/// reading of one event into a listing, and the two scopes a sync writes. No
/// stack, no network.
///
/// Run with `cd apps/backend && deno test --allow-read --allow-env
/// supabase/functions/race-listings-sync/parkrun.test.ts`.

import { assert, assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import {
  nextParkrunDate,
  PARKRUN_SWEEP_CHUNKS,
  PARKRUN_SWEEP_STRIDE,
  parkrunChunkAt,
  parkrunEventsEnabled,
  parkrunTimeZone,
  type ParkrunFeature,
  readParkrunEvent,
  readParkrunFeed,
  readParkrunSlice,
  scopeParkrunFeatures,
} from './parkrun.ts';
import { nearHintError, SWEEP_STATES, SWEEP_WINDOWS } from './lib.ts';

const FEED = JSON.parse(
  Deno.readTextFileSync(new URL('./fixtures/parkrun_events.json', import.meta.url)),
);

/// Wednesday 2026-10-14 12:00 UTC.
const WED = Date.UTC(2026, 9, 14, 12, 0);
/// Saturday 2026-10-17 22:30 UTC: still Saturday in London (23:30 BST) and New
/// York (18:30 EDT), already Sunday in Sydney (09:30 AEDT).
const SAT_LATE = Date.UTC(2026, 9, 17, 22, 30);

const SAT = 6;
const SUN = 0;

function feature(id: number): ParkrunFeature {
  const f = (FEED.events.features as ParkrunFeature[]).find((x) => x.id === id);
  assert(f, `fixture has no event ${id}`);
  return f;
}

Deno.test('only the literal "true" turns the leg on', () => {
  assertEquals(parkrunEventsEnabled('true'), true);
  for (const raw of [undefined, '', 'TRUE', '1', 'yes', ' true']) {
    assertEquals(parkrunEventsEnabled(raw), false, String(raw));
  }
});

Deno.test('the 5k is dated to the next Saturday and the junior run to the next Sunday', () => {
  assertEquals(nextParkrunDate(SAT, 'Europe/London', WED), '2026-10-17');
  assertEquals(nextParkrunDate(SUN, 'Europe/London', WED), '2026-10-18');
});

Deno.test('the run day counts until local midnight, in the event\'s own zone', () => {
  assertEquals(nextParkrunDate(SAT, 'Europe/London', SAT_LATE), '2026-10-17');
  assertEquals(nextParkrunDate(SAT, 'America/New_York', SAT_LATE), '2026-10-17');
  // Sunday morning in Sydney: this Saturday has gone, the junior run is today.
  assertEquals(nextParkrunDate(SAT, 'Australia/Sydney', SAT_LATE), '2026-10-24');
  assertEquals(nextParkrunDate(SUN, 'Australia/Sydney', SAT_LATE), '2026-10-18');
  // An hour later it is Sunday in London too.
  assertEquals(nextParkrunDate(SAT, 'Europe/London', SAT_LATE + 3_600_000), '2026-10-24');
});

Deno.test('the next date crosses a month and a year', () => {
  assertEquals(nextParkrunDate(SAT, 'Europe/London', Date.UTC(2026, 11, 30, 12)), '2027-01-02');
  assertEquals(nextParkrunDate(SUN, 'Pacific/Auckland', Date.UTC(2026, 9, 31, 12)), '2026-11-01');
});

Deno.test('each country maps to a zone, the wide ones by coordinate band', () => {
  assertEquals(parkrunTimeZone(97, 51.41, -0.34), 'Europe/London');
  assertEquals(parkrunTimeZone(42, 53.52, -6.1), 'Europe/Dublin');
  assertEquals(parkrunTimeZone(46, 35.61, 139.62), 'Asia/Tokyo');
  assertEquals(parkrunTimeZone(3, -31.95, 115.86), 'Australia/Perth');
  assertEquals(parkrunTimeZone(3, -34.93, 138.6), 'Australia/Adelaide');
  assertEquals(parkrunTimeZone(3, -12.46, 130.84), 'Australia/Darwin');
  assertEquals(parkrunTimeZone(3, -27.47, 153.03), 'Australia/Brisbane');
  assertEquals(parkrunTimeZone(3, -33.91, 151.18), 'Australia/Sydney');
  assertEquals(parkrunTimeZone(3, -37.84, 144.96), 'Australia/Sydney');
  assertEquals(parkrunTimeZone(14, 51.13, -114.13), 'America/Edmonton');
  assertEquals(parkrunTimeZone(14, 49.28, -123.12), 'America/Vancouver');
  assertEquals(parkrunTimeZone(14, 43.65, -79.38), 'America/Toronto');
  assertEquals(parkrunTimeZone(98, 38.9, -77.06), 'America/New_York');
  assertEquals(parkrunTimeZone(98, 33.45, -112.07), 'America/Phoenix');
  assertEquals(parkrunTimeZone(98, 37.77, -122.42), 'America/Los_Angeles');
  assertEquals(parkrunTimeZone(98, 41.88, -87.63), 'America/Chicago');
  assertEquals(parkrunTimeZone(98, 39.74, -104.99), 'America/Denver');
});

Deno.test('a country the table has not met gets no zone, so its events are not dated', () => {
  assertEquals(parkrunTimeZone(999, 0, 0), null);
  const f = structuredClone(feature(1)) as { properties: Record<string, unknown> };
  f.properties.countrycode = 999;
  assertEquals(readParkrunEvent(f, new Map(), WED), null);
});

Deno.test('every country in the recorded feed has a zone', () => {
  const full = readParkrunFeed(FEED)!;
  for (const id of full.hosts.keys()) {
    assert(parkrunTimeZone(id, 0, 0) !== null, `country ${id} has no zone`);
  }
});

Deno.test('the recorded feed reads: hosts from its country map, every event a listing', () => {
  const feed = readParkrunFeed(FEED);
  assert(feed);
  assertEquals(feed.hosts.get(97), 'www.parkrun.org.uk');
  assertEquals(feed.features.length, 11);
  const { races, unusable } = readParkrunSlice(feed.features, feed.hosts, WED);
  assertEquals(unusable, 0);
  assertEquals(races.length, 11);
});

Deno.test('a 5k reads as a 5,000 m Saturday listing placed at the feed\'s own point', () => {
  const feed = readParkrunFeed(FEED)!;
  assertEquals(readParkrunEvent(feature(1), feed.hosts, WED), {
    providerRaceId: '1',
    name: 'Bushy parkrun',
    date: '2026-10-17',
    distanceM: 5000,
    locationLabel: 'Bushy Park, Teddington',
    postalCode: null,
    point: { lat: 51.410992, lng: -0.335791 },
    entryUrl: 'https://www.parkrun.org.uk/bushy/',
    resultsUrl: null,
  });
});

Deno.test('a junior run reads as a 2,000 m Sunday listing', () => {
  const feed = readParkrunFeed(FEED)!;
  const junior = readParkrunEvent(feature(1363), feed.hosts, WED);
  assert(junior);
  assertEquals(junior.name, 'Rush junior parkrun');
  assertEquals(junior.distanceM, 2000);
  assertEquals(junior.date, '2026-10-18');
  assertEquals(junior.entryUrl, 'https://www.parkrun.ie/rush-juniors/');
});

Deno.test('an event is unusable without an id, a point, a name or a known series; nothing is guessed', () => {
  const feed = readParkrunFeed(FEED)!;
  const mutate = (fn: (f: Record<string, any>) => void) => {
    const f = structuredClone(feature(1)) as Record<string, any>;
    fn(f);
    return readParkrunEvent(f, feed.hosts, WED);
  };
  assertEquals(mutate((f) => delete f.id), null);
  assertEquals(mutate((f) => (f.id = '1')), null);
  assertEquals(mutate((f) => (f.geometry = { type: 'Point', coordinates: [200, 51] })), null);
  assertEquals(mutate((f) => (f.geometry = null)), null);
  assertEquals(mutate((f) => (f.properties.EventLongName = '  ')), null);
  assertEquals(mutate((f) => (f.properties.seriesid = 3)), null);
  // A slug that is not one cannot build a link, but the listing still stands.
  assertEquals(mutate((f) => (f.properties.eventname = '../x'))?.entryUrl, null);
});

Deno.test('a payload that is not the events file reads as nothing, not as no events', () => {
  for (const p of [null, [], {}, { events: {} }, { events: { features: {} } }, { races: [] }]) {
    assertEquals(readParkrunFeed(p), null, JSON.stringify(p));
  }
  assertEquals(readParkrunFeed({ events: { features: [] } })?.features.length, 0);
});

Deno.test('a near scope keeps the events within the radius, nearest first', () => {
  const feed = readParkrunFeed(FEED)!;
  const london = { kind: 'near' as const, lat: 51.5074, lng: -0.1278, radiusM: 25_000 };
  const { features, complete } = scopeParkrunFeatures(feed.features, london);
  assertEquals(features.map((f) => f.id), [2, 32, 1]);
  assertEquals(complete, true);
  const tight = scopeParkrunFeatures(feed.features, { ...london, radiusM: 12_000 });
  assertEquals(tight.features.map((f) => f.id), [2]);
});

Deno.test('the sweep\'s chunks partition the feed: every event in exactly one', () => {
  const feed = readParkrunFeed(FEED)!;
  const seen: unknown[] = [];
  for (let index = 0; index < PARKRUN_SWEEP_CHUNKS; index++) {
    const chunk = scopeParkrunFeatures(feed.features, { kind: 'chunk', index, count: PARKRUN_SWEEP_CHUNKS });
    seen.push(...chunk.features.map((f) => f.id));
  }
  assertEquals(seen.length, feed.features.length);
  assertEquals(new Set(seen).size, feed.features.length);
});

Deno.test('a parkrun sync needs a point: no hint, or a postal code alone, is refused', () => {
  assertEquals(nearHintError('parkrun', null), 'near_point_required');
  assertEquals(
    nearHintError('parkrun', { point: null, postalCode: 'SW1A 1AA', radiusM: 50_000 }),
    'near_point_required',
  );
  assertEquals(
    nearHintError('parkrun', { point: { lat: 51.5, lng: -0.1 }, postalCode: null, radiusM: 50_000 }),
    null,
  );
});

Deno.test('nine slots of each sweep cycle carry a parkrun chunk, each chunk once', () => {
  const cycle = SWEEP_STATES.length * SWEEP_WINDOWS;
  assertEquals(PARKRUN_SWEEP_CHUNKS * PARKRUN_SWEEP_STRIDE, cycle);
  const chunks: number[] = [];
  for (let slot = 0; slot < cycle; slot++) {
    const c = parkrunChunkAt(slot);
    if (c !== null) chunks.push(c);
  }
  assertEquals(chunks, [...Array(PARKRUN_SWEEP_CHUNKS).keys()]);
});
