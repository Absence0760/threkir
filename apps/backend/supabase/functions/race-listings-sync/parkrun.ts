// Pure helpers for the parkrun leg of the race-calendar sync (issue #1148,
// decisions § 1958).
//
// parkrun publishes its whole event list as one public file,
// `images.parkrun.com/events.json`: a `countries` map (id → site host) and a
// GeoJSON `events` FeatureCollection whose features carry a point, a series
// (1 = the Saturday 5k, 2 = the Sunday 2k junior) and a country id. Recorded
// 2026-10-15 into `fixtures/parkrun_events.json` (2,997 events, 20 countries).
// The feed carries no dates, no start times and no cancellations, so a
// listing's date is DERIVED here from the series' weekday.
//
// The leg is OFF unless `PARKRUN_EVENTS_ENABLED` is exactly `true`: parkrun has
// not given written permission to list its events (#1148 step 1), and the
// compliance rule is that the sign-off gates the deploy, not the code.

import {
  listingUrl,
  MAX_LISTING_LOCATION_LEN,
  MAX_LISTING_NAME_LEN,
  MAX_LISTING_ROWS,
  type NormalisedRace,
} from './lib.ts';
import { clipText } from '../_shared/text_clip.ts';
import { embeddedHaversineM } from '../_shared/strava.ts';

export const PARKRUN_EVENTS_URL = 'https://images.parkrun.com/events.json';

/// Only the literal `true` turns the leg on; unset, empty, `1` or `TRUE` keep
/// it off, so a typo fails closed.
export function parkrunEventsEnabled(raw: string | undefined): boolean {
  return raw === 'true';
}

/// The series the feed carries, by id. The weekday is the series' fixed run
/// day (0 = Sunday … 6 = Saturday); a series not in this table is not dated at
/// all, because a guessed weekday is a wrong date on every listing it touches.
export const PARKRUN_SERIES: Readonly<Record<number, { weekday: number; distanceM: number }>> = {
  1: { weekday: 6, distanceM: 5000 },
  2: { weekday: 0, distanceM: 2000 },
};

type ZoneRule = string | ((lat: number, lng: number) => string);

/// The IANA zone each country's events run in, keyed by the feed's country id
/// (the id → host pairs are the feed's own `countries` map). The three
/// countries wide enough to straddle zones are split by coarse coordinate
/// bands. The zone decides only which local calendar day it is when the sync
/// runs, so a band edge that is off by a province moves the moment a listing
/// rolls to next week by the zone difference, never the weekday it lands on.
/// A country missing here is a new one the table has not met: its events are
/// counted unusable rather than dated in a guessed zone.
export const PARKRUN_COUNTRY_ZONES: Readonly<Record<number, ZoneRule>> = {
  3: australiaZone, // parkrun.com.au
  4: 'Europe/Vienna', // parkrun.co.at
  14: canadaZone, // parkrun.ca
  23: 'Europe/Copenhagen', // parkrun.dk
  30: 'Europe/Helsinki', // parkrun.fi
  32: 'Europe/Berlin', // parkrun.com.de
  42: 'Europe/Dublin', // parkrun.ie
  44: 'Europe/Rome', // parkrun.it
  46: 'Asia/Tokyo', // parkrun.jp
  54: 'Europe/Vilnius', // parkrun.lt
  57: 'Asia/Kuala_Lumpur', // parkrun.my
  64: 'Europe/Amsterdam', // parkrun.co.nl
  65: 'Pacific/Auckland', // parkrun.co.nz
  67: 'Europe/Oslo', // parkrun.no
  74: 'Europe/Warsaw', // parkrun.pl
  82: 'Asia/Singapore', // parkrun.sg
  85: 'Africa/Johannesburg', // parkrun.co.za
  88: 'Europe/Stockholm', // parkrun.se
  97: 'Europe/London', // parkrun.org.uk
  98: unitedStatesZone, // parkrun.us
};

function australiaZone(lat: number, lng: number): string {
  if (lng < 129) return 'Australia/Perth';
  if (lng < 138 && lat > -26) return 'Australia/Darwin';
  if (lng < 141 && lat <= -26) return 'Australia/Adelaide';
  if (lat > (lng >= 151 ? -28.17 : -29)) return 'Australia/Brisbane';
  return 'Australia/Sydney';
}

function canadaZone(lat: number, lng: number): string {
  if (lng < -118) return 'America/Vancouver';
  if (lng < -110) return 'America/Edmonton';
  if (lng < -102) return 'America/Regina';
  if (lng < -95) return 'America/Winnipeg';
  if (lng > -59.5) return 'America/St_Johns';
  if (lng > -67 && lat < 48) return 'America/Halifax';
  return 'America/Toronto';
}

function unitedStatesZone(lat: number, lng: number): string {
  if (lng < -154 && lat < 23) return 'Pacific/Honolulu';
  if (lng < -129 && lat > 51) return 'America/Anchorage';
  if (lng >= -114.8 && lng < -109.05 && lat >= 31.3 && lat < 37) return 'America/Phoenix';
  if (lng < -114.5) return 'America/Los_Angeles';
  if (lng < -102) return 'America/Denver';
  if (lng < -87) return 'America/Chicago';
  return 'America/New_York';
}

/// The zone an event runs in, or null for a country the table does not know.
export function parkrunTimeZone(countryId: number, lat: number, lng: number): string | null {
  const rule = PARKRUN_COUNTRY_ZONES[countryId];
  if (rule === undefined) return null;
  return typeof rule === 'string' ? rule : rule(lat, lng);
}

const WEEKDAYS: Record<string, number> = { Sun: 0, Mon: 1, Tue: 2, Wed: 3, Thu: 4, Fri: 5, Sat: 6 };

/// The next date, as ISO `YYYY-MM-DD`, on which an event that runs every
/// `weekday` takes place: today when today IS that weekday in `zone`, else the
/// next one.
///
/// The run day itself counts for its whole local day. The feed carries no
/// start time and `race_date` is a `date`, so dropping today's run at its start
/// would need a per-event time nobody has published; keeping it until local
/// midnight is a few hours of a run that has finished, against a guessed time
/// that would be wrong somewhere every week. Christmas Day and New Year's Day
/// runs are not derived: the feed does not say which events hold them, and
/// many do not.
export function nextParkrunDate(weekday: number, zone: string, nowMs: number): string {
  const parts = new Intl.DateTimeFormat('en-US', {
    timeZone: zone,
    year: 'numeric',
    month: 'numeric',
    day: 'numeric',
    weekday: 'short',
  }).formatToParts(new Date(nowMs));
  const get = (type: string) => parts.find((p) => p.type === type)?.value ?? '';
  const today = WEEKDAYS[get('weekday')];
  const ahead = (weekday - today + 7) % 7;
  const day = new Date(Date.UTC(Number(get('year')), Number(get('month')) - 1, Number(get('day')) + ahead));
  return day.toISOString().slice(0, 10);
}

export interface ParkrunFeature {
  id?: unknown;
  geometry?: unknown;
  properties?: unknown;
}

export interface ParkrunFeed {
  /// Country id → the country's parkrun site host, from the feed's own map.
  hosts: Map<number, string>;
  features: ParkrunFeature[];
}

/// The feed's two halves, or null when the payload is not parkrun's events
/// file at all. A body without a feature array is a feed whose shape moved,
/// and reading it as "no events" would answer success on every sweep while
/// the calendar stopped filling.
export function readParkrunFeed(payload: unknown): ParkrunFeed | null {
  if (!payload || typeof payload !== 'object' || Array.isArray(payload)) return null;
  const root = payload as Record<string, unknown>;
  const events = root.events;
  if (!events || typeof events !== 'object') return null;
  const features = (events as Record<string, unknown>).features;
  if (!Array.isArray(features)) return null;
  const hosts = new Map<number, string>();
  const countries = root.countries;
  if (countries && typeof countries === 'object' && !Array.isArray(countries)) {
    for (const [id, raw] of Object.entries(countries as Record<string, unknown>)) {
      const url = raw && typeof raw === 'object' ? (raw as Record<string, unknown>).url : null;
      if (typeof url === 'string' && /^[a-z0-9.-]+$/i.test(url)) hosts.set(Number(id), url);
    }
  }
  return { hosts, features: features as ParkrunFeature[] };
}

function featureId(f: ParkrunFeature): number | null {
  return typeof f.id === 'number' && Number.isInteger(f.id) && f.id > 0 ? f.id : null;
}

function featurePoint(f: ParkrunFeature): { lat: number; lng: number } | null {
  const g = f.geometry;
  if (!g || typeof g !== 'object') return null;
  const geo = g as Record<string, unknown>;
  if (geo.type !== 'Point' || !Array.isArray(geo.coordinates)) return null;
  const [lng, lat] = geo.coordinates;
  if (typeof lng !== 'number' || typeof lat !== 'number') return null;
  if (!Number.isFinite(lng) || !Number.isFinite(lat)) return null;
  if (lng < -180 || lng > 180 || lat < -90 || lat > 90) return null;
  return { lat, lng };
}

function label(raw: unknown, max: number): string | null {
  if (typeof raw !== 'string') return null;
  const clipped = clipText(raw, max);
  return clipped ? clipped : null;
}

/// One feed event as a listing, dated for the run at `nowMs`.
///
/// - `provider_race_id` is the feed's numeric event id, stable across renames.
/// - The point is the feed's own, so a parkrun is found by "near me" with no
///   geocoding step.
/// - The entry link is the event's page on its country's site, built from the
///   feed's host and the event's slug; there is no registration per event.
/// - No results link: the results path is not in the feed, and a built one
///   would be a guess.
/// - An event with no id, name, point, known series or known country is
///   unusable and counted; nothing here guesses a missing field.
export function readParkrunEvent(
  f: ParkrunFeature,
  hosts: Map<number, string>,
  nowMs: number,
): NormalisedRace | null {
  if (!f || typeof f !== 'object') return null;
  const id = featureId(f);
  const point = featurePoint(f);
  const props = (f.properties && typeof f.properties === 'object' ? f.properties : {}) as Record<
    string,
    unknown
  >;
  const name = label(props.EventLongName, MAX_LISTING_NAME_LEN);
  const series = typeof props.seriesid === 'number' ? PARKRUN_SERIES[props.seriesid] : undefined;
  const countryId = typeof props.countrycode === 'number' ? props.countrycode : null;
  if (id === null || point === null || !name || !series || countryId === null) return null;
  const zone = parkrunTimeZone(countryId, point.lat, point.lng);
  if (zone === null) return null;

  const host = hosts.get(countryId);
  const slug = typeof props.eventname === 'string' && /^[a-z0-9-]+$/i.test(props.eventname)
    ? props.eventname
    : null;
  return {
    providerRaceId: String(id),
    name,
    date: nextParkrunDate(series.weekday, zone, nowMs),
    distanceM: series.distanceM,
    locationLabel: label(props.EventLocation, MAX_LISTING_LOCATION_LEN),
    postalCode: null,
    point,
    entryUrl: host && slug ? listingUrl(`https://${host}/${slug}/`) : null,
    resultsUrl: null,
  };
}

/// Which slice of the feed one sync writes.
///
/// - `near`: the caller-driven sync, events within `radiusM` of a point, the
///   nearest first. The feed is one global file, so the region is applied here.
/// - `chunk`: the scheduled sweep, the events whose id falls in residue class
///   `index` of `count`. Keying on the id keeps an event in the same chunk as
///   the feed grows, so no event is skipped by a shift.
export type ParkrunScope =
  | { kind: 'near'; lat: number; lng: number; radiusM: number }
  | { kind: 'chunk'; index: number; count: number };

/// The features a sync of `scope` covers, capped at `MAX_LISTING_ROWS`, and
/// whether the cap cut any off. A feature with no usable id falls in chunk 0
/// and one with no point is outside every `near` slice, so the sweep still
/// reads it once a cycle and counts it unusable.
export function scopeParkrunFeatures(
  features: readonly ParkrunFeature[],
  scope: ParkrunScope,
): { features: ParkrunFeature[]; complete: boolean } {
  let picked: ParkrunFeature[];
  if (scope.kind === 'chunk') {
    picked = features.filter((f) => (featureId(f) ?? 0) % scope.count === scope.index);
  } else {
    picked = features
      .map((f) => ({ f, p: featurePoint(f) }))
      .filter((x): x is { f: ParkrunFeature; p: { lat: number; lng: number } } => x.p !== null)
      .map((x) => ({ f: x.f, d: embeddedHaversineM(scope.lat, scope.lng, x.p.lat, x.p.lng) }))
      .filter((x) => x.d <= scope.radiusM)
      .sort((a, b) => a.d - b.d)
      .map((x) => x.f);
  }
  return { features: picked.slice(0, MAX_LISTING_ROWS), complete: picked.length <= MAX_LISTING_ROWS };
}

/// Read a scoped slice into listings, counting the events that could not be read.
export function readParkrunSlice(
  features: readonly ParkrunFeature[],
  hosts: Map<number, string>,
  nowMs: number,
): { races: NormalisedRace[]; unusable: number } {
  const races: NormalisedRace[] = [];
  let unusable = 0;
  for (const f of features) {
    const r = readParkrunEvent(f, hosts, nowMs);
    if (r === null) unusable++;
    else races.push(r);
  }
  return { races, unusable };
}

// ── The sweep's parkrun slots (race-listings-sweep) ─────────────────────────

/// The feed is cut into nine chunks of ~333 events (2,997 on 2026-10-15), far
/// under the 500-row cap with room for the feed to grow by half.
export const PARKRUN_SWEEP_CHUNKS = 9;
/// One chunk every 34 sweep slots: 9 × 34 = 306, the RunSignUp cycle, so the
/// whole feed is re-read once a cycle (25.5 h) with nine fetches of one file.
export const PARKRUN_SWEEP_STRIDE = 34;

/// The chunk the sweep run at `slot` covers, or null for a slot with none.
export function parkrunChunkAt(slot: number): number | null {
  if (slot % PARKRUN_SWEEP_STRIDE !== 0) return null;
  const chunk = slot / PARKRUN_SWEEP_STRIDE;
  return chunk < PARKRUN_SWEEP_CHUNKS ? chunk : null;
}
