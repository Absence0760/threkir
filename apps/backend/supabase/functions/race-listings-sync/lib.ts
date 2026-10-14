// Pure helpers for the provider race-calendar sync.
//
// The function pulls a provider's upcoming-races feed and reconciles it into
// `race_listings`. Everything here is network-free and side-effect-free, so the
// envelope walk, the date and distance readings, the constraint-shaped field
// caps and the batch reconciliation are testable offline.
//
// **What each provider's reader is built against, stated rather than implied.**
// The RunSignUp reader is built against the live `GET /Rest/races` payload,
// observed 2026-10-14 and recorded in `fixtures/runsignup_races.json`. That feed
// is public — no API key — so observing it never needed a credential; the
// earlier reader was written against invented spellings (a race-level
// `distance`, `results_url`, `address.country`) and would have filed every race
// with no distance. The UltraSignup reader is still unverified, so it keeps
// the optional-with-drop rule: a row that does not yield a name and a date
// becomes nothing, and the response counts it, so a payload shaped differently
// answers `synced: 0` with `unusable` equal to the row count rather than writing
// junk into a calendar every user of the deployment reads.

import { isIsoCalendarDate } from '../_shared/calendar_date.ts';
import { clipText } from '../_shared/text_clip.ts';

/// Bound the batch independently of upstream input, the same rule the two
/// importers apply to theirs. A provider feed for one region is tens of races;
/// this is a ceiling on a hostile or misconfigured response, not a page size.
export const MAX_LISTING_ROWS = 500;

/// `race_listings.name` is `char_length <= 120`, `location_label <= 80`
/// (migration `20270503_001`). A row that busts either raises 23514 and, in a
/// single-statement insert, loses every other race in the batch — so the cap
/// is applied here rather than hoped for.
export const MAX_LISTING_NAME_LEN = 120;
export const MAX_LISTING_LOCATION_LEN = 80;

/// The providers whose feeds this function knows how to read. A subset of
/// `race_listings_provider_check` — `parkrun`, `manual`, `chronotrack` and
/// `raceresult` reach the calendar by other paths.
export type ListingSyncProvider = 'runsignup' | 'ultrasignup';

/// A provider row reduced to exactly what a listing needs. Each provider's
/// reader produces one of these or null; nothing downstream sees a provider's
/// own field names.
export interface NormalisedRace {
  providerRaceId: string | null;
  name: string;
  date: string;
  distanceM: number | null;
  locationLabel: string | null;
  /// The US ZIP the race is held in, when the feed names one: the key its
  /// `location_point` is looked up by (`us_zcta_points`, decisions § 1901).
  postalCode: string | null;
  entryUrl: string | null;
  resultsUrl: string | null;
}

/// The row shape written to `race_listings`. `is_verified` is true because the
/// provider is the authority on its own races, and only the service role may
/// set it (the `race_listings_force_unverified` trigger forces false for anyone
/// else) — which is why this sync must not run on the caller's client.
export interface RaceListingUpsert {
  provider: ListingSyncProvider;
  provider_race_id: string | null;
  name: string;
  race_date: string;
  distance_m: number | null;
  location_label: string | null;
  /// EWKT (`SRID=4326;POINT(lng lat)`), which PostgREST hands to the
  /// `geography` input function, or null when the race has no known point.
  location_point: string | null;
  entry_url: string | null;
  results_url: string | null;
  is_verified: true;
}

function text(raw: unknown, max: number): string | null {
  if (typeof raw === 'number' && Number.isFinite(raw)) return String(raw);
  if (typeof raw !== 'string') return null;
  const clipped = clipText(raw, max);
  return clipped ? clipped : null;
}

/// A URL only if it satisfies `race_listings_{entry,results}_url_scheme_check`.
/// Anything else is dropped rather than written: the CHECK would refuse it and
/// take the whole batch insert with it.
export function listingUrl(raw: unknown): string | null {
  const v = text(raw, 2048);
  if (!v) return null;
  return /^https?:\/\//i.test(v) ? v : null;
}

/// A provider's race date as an ISO `YYYY-MM-DD`, or null.
///
/// Two forms are accepted and the second is the interesting one. An ISO date is
/// unambiguous and is taken whole, with any time-of-day suffix discarded — the
/// column is a `date`. A slash date is read as **US month-first**, which is a
/// provider-specific reading (RunSignUp and UltraSignup are US platforms, and
/// `parseParkrunDate` already reads the UK site's slashes day-first for the
/// mirror-image reason) — but only when the first component can BE a month.
/// `13/06/2027` is refused rather than reinterpreted as 6 January, so a feed
/// that turns out to be day-first announces itself on the first race past the
/// 12th of a month instead of silently seeding the calendar with transposed
/// dates. Two same-month days under the 13th stay genuinely ambiguous and are
/// read US — that is the irreducible part, and it is why the refusal above
/// matters. Every refusal is counted in the response's `unusable`.
export function parseProviderRaceDate(raw: unknown): string | null {
  const v = text(raw, 64);
  if (!v) return null;
  const iso = /^(\d{4}-\d{2}-\d{2})(?:[T ].*)?$/.exec(v);
  if (iso) return isIsoCalendarDate(iso[1]) ? iso[1] : null;
  const slash = /^(\d{1,2})\/(\d{1,2})\/(\d{4})$/.exec(v);
  if (!slash) return null;
  const [month, day, year] = [slash[1], slash[2], slash[3]];
  // The calendar check is what refuses a day-first date: `20/06/2027` becomes
  // the candidate `2027-20-06`, whose month is 20. An explicit `month > 12`
  // test in front of it was written first and could never fail — it is not
  // here, and the mirror-image assertions in lib.test.ts pin the behaviour
  // against this line instead.
  const candidate = `${year}-${month.padStart(2, '0')}-${day.padStart(2, '0')}`;
  return isIsoCalendarDate(candidate) ? candidate : null;
}

/// Spellings that mean exactly one thing. `m` / `M` is deliberately ABSENT:
/// US race listings write miles as `M` while SI writes metres as `m`, and a
/// case-insensitive table collapses them — which files a 100-mile race as a
/// 100-metre one, at the wrong end of every distance band
/// `search_race_listings` sorts into. A case-SENSITIVE table would be worse
/// still, since it would silently pick one reading of a letter whose meaning in
/// this feed has not been observed. A null distance costs a race its band; a
/// wrong one puts it in somebody else's.
const UNIT_METRES: Record<string, number> = {
  meter: 1,
  meters: 1,
  metre: 1,
  metres: 1,
  k: 1000,
  km: 1000,
  kilometer: 1000,
  kilometers: 1000,
  kilometre: 1000,
  kilometres: 1000,
  mi: 1609.344,
  mile: 1609.344,
  miles: 1609.344,
  yd: 0.9144,
  yard: 0.9144,
  yards: 0.9144,
};

/// A nominal race distance in whole metres, or null when it cannot be read.
///
/// `race_listings.distance_m` is nullable and `search_race_listings` buckets it
/// into race-distance bands, so an absent distance costs a race its band while
/// a WRONG one files a 5K under "ultra". A unit this does not recognise is
/// therefore null rather than assumed — the one assumption made is that a bare
/// number with no unit is already metres, which is the column's own unit.
export function distanceMetresFrom(value: unknown, units: unknown): number | null {
  const n = typeof value === 'number' ? value : Number(text(value, 32) ?? NaN);
  if (!Number.isFinite(n) || n <= 0) return null;
  const rawUnit = text(units, 32);
  if (rawUnit === null) return Math.round(n);
  const factor = UNIT_METRES[rawUnit.toLowerCase()];
  if (factor === undefined) return null;
  const metres = Math.round(n * factor);
  return metres > 0 ? metres : null;
}

function joinLocation(city: unknown, state: unknown, country: unknown): string | null {
  const parts = [text(city, 80), text(state, 80), text(country, 80)].filter(
    (p): p is string => p !== null,
  );
  if (parts.length === 0) return null;
  return text(parts.join(', '), MAX_LISTING_LOCATION_LEN);
}

/// Named distances, read whole. RunSignUp's own feed writes every distance as a
/// number and a unit (`5K`, `13.1 Miles`); these cover a race director who typed
/// the name instead, which the field is free text enough to allow.
const NAMED_DISTANCE_M: Record<string, number> = {
  marathon: 42195,
  'half marathon': 21098,
};

/// A RunSignUp event's `distance` string in whole metres, or null.
///
/// The spellings the live feed uses (2026-10-14, 500 races around New York):
/// `5K`, `10K`, `50K`, `3.1K` (kilometres, capital K glued to the number),
/// `3.1 Miles`, `1 Miles`, `26.2 Miles`, `100 Yards`, and `100m` / `5000m` /
/// `1600m` — metres, LOWER-case `m` glued to the number. That last one is why
/// this reader exists beside `distanceMetresFrom`, whose shared table refuses a
/// bare `m` because a US listing could mean miles by it. In THIS feed miles are
/// always spelled `Miles`, so a glued lower-case `m` has been observed to mean
/// metres and is read so here and nowhere else. A capital `M` stays refused.
export function parseRunSignUpDistance(raw: unknown): number | null {
  const v = text(raw, 32)?.trim();
  if (!v) return null;
  const named = NAMED_DISTANCE_M[v.toLowerCase().replace(/\s+/g, ' ')];
  if (named !== undefined) return named;
  const m = /^(\d+(?:\.\d+)?)\s*([A-Za-z]+)$/.exec(v);
  if (!m) return null;
  const unit = m[2] === 'm' ? 'metres' : m[2];
  return distanceMetresFrom(m[1], unit);
}

/// The event types that put a runner on a course in person. `running_race`,
/// `running_only`, `trail_race` and `ultra` are the observed running spellings;
/// `virtual_race`, `walking_only`, `fundraising_ride`, `paddle_sports`,
/// `nonprofit_event`, `other` and the rest are what a race calendar for runners
/// should not file a distance from.
const IN_PERSON_RUNNING_EVENT_TYPES = new Set([
  'running_race',
  'running_only',
  'trail_race',
  'ultra',
]);

/// The message of a RunSignUp error envelope, or null when the payload is not
/// one. RunSignUp refuses a request with HTTP 200 and `{"error": {...}}` —
/// get-results without an `event_id`, a keyless `page` past the first 1,000
/// races — so a status check alone reads a refusal as a region, or a race,
/// with nothing in it.
export function runSignUpErrorOf(payload: unknown): string | null {
  if (!payload || typeof payload !== 'object') return null;
  const err = (payload as Record<string, unknown>).error;
  if (!err || typeof err !== 'object') return null;
  return text((err as Record<string, unknown>).error_msg, 120) ?? 'error';
}

/// Whether a payload is RunSignUp's race feed at all: an object carrying a
/// `races` array. An empty window answers `{"races":[]}` (measured 2026-10-14
/// for a state and a date range with no race), so a body without the array is
/// not "no races here" but a feed whose shape moved — and read through the
/// tolerant envelope walk it would answer `total: 0` on every five-minute run,
/// a calendar that stops filling while every sweep reports success.
export function isRunSignUpRaceFeed(payload: unknown): boolean {
  if (!payload || typeof payload !== 'object' || Array.isArray(payload)) return false;
  return Array.isArray((payload as Record<string, unknown>).races);
}

/// One event of a RunSignUp race (the `events=T` expansion, and the `events`
/// of `GET /Rest/race/{race_id}`).
export interface RunSignUpEventRow {
  event_id?: unknown;
  event_type?: unknown;
  distance?: unknown;
  volunteer?: unknown;
  start_time?: unknown;
}

/// Whether an event puts a runner on a course in person: a running event type,
/// and not a volunteer slot. The listing's distance and the results import's
/// choice of event both read it, so the two legs agree on what a race is.
export function isInPersonRunningEvent(ev: RunSignUpEventRow): boolean {
  if (ev.volunteer === 'T') return false;
  return typeof ev.event_type === 'string' && IN_PERSON_RUNNING_EVENT_TYPES.has(ev.event_type);
}

/// A RunSignUp race object, as `GET /Rest/races` carries it under `races[].race`.
/// Only the fields read below; the live object carries many more.
export interface RunSignUpRaceRow {
  race_id?: unknown;
  name?: unknown;
  next_date?: unknown;
  last_date?: unknown;
  is_draft_race?: unknown;
  is_private_race?: unknown;
  url?: unknown;
  external_results_url?: unknown;
  address?: unknown;
  events?: unknown;
}

/// A deliberate refusal — a race the feed describes correctly that the calendar
/// should not hold — as distinct from `null`, a row this reader could not read.
/// The response counts the two apart, so `unusable` keeps meaning "the shape
/// moved" and is not diluted by every walk-only fun run.
export const EXCLUDED = 'excluded' as const;
export type RaceReading = NormalisedRace | typeof EXCLUDED | null;

/// Normalise one RunSignUp race.
///
/// - **One listing per RACE, not per event.** `provider_race_id` is the
///   RunSignUp race id and `race-results-import` fetches
///   `/Rest/race/{race_id}/results` with it; a per-event row would need a
///   composite id that endpoint cannot take.
/// - **The distance is the longest in-person running event.** A race carries
///   several (`5K RUN` + `1 Mile WALK`, or 5K / 10K / half on one morning), and
///   `distance_m` holds one number that `search_race_listings` bands. The
///   headline event is the longest one in practice, and a walk or a virtual
///   option never decides it. An event whose distance cannot be read is
///   skipped, not guessed; no readable one leaves the distance null.
/// - **Drafts, private races, and races with events but no in-person running
///   event are excluded.** The last covers virtual-only challenges, whose
///   address is the organiser's office rather than a start line.
/// - **The date is `next_date`, read as the race's own local calendar day.**
///   `race_date` is a `date`, and RunSignUp's `MM/DD/YYYY` is already the day in
///   the race's `timezone`, so no zone conversion applies — converting it would
///   move an early-morning race onto the previous day for anyone west of it.
///   `last_date` is the fallback for a race with no next running, so a past race
///   still files for a results import.
/// - **No `location_point`.** The feed carries an address and no coordinates,
///   and `search_race_listings`' proximity gate requires a point, so a synced
///   race is found by name, date and distance band, not by a "near me" search,
///   until something geocodes the address. That gap is recorded in decisions,
///   not papered over with the hint's centre, which is not where the race is.
export function readRunSignUpRace(row: RunSignUpRaceRow): RaceReading {
  const name = text(row.name, MAX_LISTING_NAME_LEN);
  const date = parseProviderRaceDate(row.next_date) ?? parseProviderRaceDate(row.last_date);
  if (!name || !date) return null;
  if (row.is_draft_race === 'T' || row.is_private_race === 'T') return EXCLUDED;

  let distanceM: number | null = null;
  if (Array.isArray(row.events) && row.events.length > 0) {
    let running = 0;
    for (const raw of row.events) {
      if (!raw || typeof raw !== 'object') continue;
      const ev = raw as RunSignUpEventRow;
      if (!isInPersonRunningEvent(ev)) continue;
      running++;
      const m = parseRunSignUpDistance(ev.distance);
      if (m !== null && (distanceM === null || m > distanceM)) distanceM = m;
    }
    if (running === 0) return EXCLUDED;
  }

  const address = (row.address && typeof row.address === 'object' ? row.address : {}) as Record<
    string,
    unknown
  >;
  return {
    providerRaceId: text(row.race_id, 200),
    name,
    date,
    distanceM,
    locationLabel: joinLocation(address.city, address.state, address.country_code),
    postalCode: address.country_code === 'US' ? usZip5(address.zipcode) : null,
    entryUrl: listingUrl(row.url),
    resultsUrl: listingUrl(row.external_results_url),
  };
}

/// A US ZIP as its five digits: `48060` and `48060-1234` both read as `48060`,
/// anything else as null. The feed writes the field as free text.
export function usZip5(raw: unknown): string | null {
  const v = text(raw, 16)?.trim();
  if (!v) return null;
  const m = /^(\d{5})(?:-\d{4})?$/.exec(v);
  return m ? m[1] : null;
}

/// A ZIP centroid as the EWKT `race_listings.location_point` accepts.
export function pointEwkt(lat: number, lng: number): string {
  return `SRID=4326;POINT(${lng} ${lat})`;
}

/// A stored `location_point` back as the EWKT `pointEwkt` writes, or null when
/// it is not a point this can read.
///
/// PostgREST renders a geography as hex EWKB (measured: `to_jsonb` of
/// `SRID=4326;POINT(-71.1316 42.3586)` is `0101000020E6100000` + the two
/// coordinates as little-endian doubles). The doubles round-trip exactly, so
/// re-encoding them gives the same string the sync wrote for the same ZCTA.
export function storedPointEwkt(raw: unknown): string | null {
  if (typeof raw !== 'string' || !/^(?:[0-9A-Fa-f]{2})+$/.test(raw)) return null;
  const bytes = new Uint8Array(raw.length / 2);
  for (let i = 0; i < bytes.length; i++) bytes[i] = parseInt(raw.slice(i * 2, i * 2 + 2), 16);
  if (bytes.length < 21) return null;
  const view = new DataView(bytes.buffer);
  const le = bytes[0] === 1;
  if (!le && bytes[0] !== 0) return null;
  const type = view.getUint32(1, le);
  if ((type & 0xffff) !== 1) return null;
  let at = 5;
  if (type & 0x20000000) {
    if (view.getUint32(at, le) !== 4326) return null;
    at += 4;
  }
  if (bytes.length !== at + 16) return null;
  return pointEwkt(view.getFloat64(at + 8, le), view.getFloat64(at, le));
}

/// An UltraSignup event row. Unverified against a live payload (see the module
/// header), so every field is optional and a mismatch drops and counts the row.
export interface UltraSignUpRaceRow {
  eventid?: unknown;
  eventname?: unknown;
  eventdate?: unknown;
  url?: unknown;
  city?: unknown;
  state?: unknown;
  distance?: unknown;
  distance_units?: unknown;
}

export function readUltraSignUpRace(row: UltraSignUpRaceRow): NormalisedRace | null {
  const name = text(row.eventname, MAX_LISTING_NAME_LEN);
  const date = parseProviderRaceDate(row.eventdate);
  if (!name || !date) return null;
  return {
    providerRaceId: text(row.eventid, 200),
    name,
    date,
    distanceM: distanceMetresFrom(row.distance, row.distance_units),
    locationLabel: joinLocation(row.city, row.state, null),
    postalCode: null,
    entryUrl: listingUrl(row.url),
    resultsUrl: null,
  };
}

/// Pull the flat race array out of a provider envelope, capped.
///
/// Tolerant of the nestings a REST feed of this shape uses, in the same
/// defensive style as `extractRunSignUpResults`: a bare array, a `races` array
/// whose members either ARE the race or wrap one under `race`, or a top-level
/// `events` array. Anything else yields nothing, which the caller reports.
export function extractProviderRaces(payload: unknown): Record<string, unknown>[] {
  const out: Record<string, unknown>[] = [];
  const push = (v: unknown): boolean => {
    if (!v || typeof v !== 'object' || Array.isArray(v)) return true;
    const obj = v as Record<string, unknown>;
    const inner = obj.race;
    out.push(
      inner && typeof inner === 'object' && !Array.isArray(inner)
        ? inner as Record<string, unknown>
        : obj,
    );
    return out.length < MAX_LISTING_ROWS;
  };
  const walk = (rows: unknown): boolean => {
    if (!Array.isArray(rows)) return true;
    for (const r of rows) if (!push(r)) return false;
    return true;
  };
  if (Array.isArray(payload)) {
    walk(payload);
    return out;
  }
  if (!payload || typeof payload !== 'object') return out;
  const obj = payload as Record<string, unknown>;
  if (!walk(obj.races)) return out;
  if (out.length === 0) walk(obj.events);
  return out;
}

export function readProviderRace(
  provider: ListingSyncProvider,
  row: Record<string, unknown>,
): RaceReading {
  return provider === 'ultrasignup' ? readUltraSignUpRace(row) : readRunSignUpRace(row);
}

export function listingUpsertFrom(
  provider: ListingSyncProvider,
  race: NormalisedRace,
  locationPoint: string | null,
): RaceListingUpsert {
  return {
    provider,
    provider_race_id: race.providerRaceId,
    name: race.name,
    race_date: race.date,
    distance_m: race.distanceM,
    location_label: race.locationLabel,
    location_point: locationPoint,
    entry_url: race.entryUrl,
    results_url: race.resultsUrl,
    is_verified: true,
  };
}

export interface ListingBatch {
  /// Rows to INSERT: a provider race id this deployment has not stored.
  fresh: RaceListingUpsert[];
  /// Rows to UPDATE in place, keyed by their provider race id — a race whose
  /// date or venue moved must follow the provider rather than stay as first
  /// seen, which is the whole point of a sync over a one-time seed.
  existing: RaceListingUpsert[];
  /// Rows dropped because the feed named the same race twice, or because the
  /// row carries no provider race id at all.
  skipped: number;
}

/// Split mapped rows against what is already stored, and against the batch
/// itself.
///
/// The insert below is ONE statement against the partial unique index
/// `race_listings_provider_uniq`, so a feed that repeats a race would raise
/// 23505 and lose every OTHER race in it — the same failure `reconcileImportBatch`
/// exists to stop on the two importers.
///
/// A row with NO provider race id is dropped rather than inserted: the unique
/// index does not cover nulls, so such a row would be re-inserted on every sync
/// and the calendar would grow a duplicate an hour.
export function reconcileListingBatch(
  rows: RaceListingUpsert[],
  storedIds: readonly string[],
): ListingBatch {
  const stored = new Set(storedIds);
  const seen = new Set<string>();
  const fresh: RaceListingUpsert[] = [];
  const existing: RaceListingUpsert[] = [];
  let skipped = 0;
  for (const row of rows) {
    const id = row.provider_race_id;
    if (id === null || seen.has(id)) {
      skipped++;
      continue;
    }
    seen.add(id);
    if (stored.has(id)) existing.push(row);
    else fresh.push(row);
  }
  return { fresh, existing, skipped };
}

/// The stored columns a sync may rewrite, as PostgREST returns them.
export interface StoredListing {
  id: string;
  provider_race_id: string | null;
  name: string | null;
  race_date: string | null;
  distance_m: number | null;
  location_label: string | null;
  /// PostgREST renders a geography as hex EWKB, so only null-or-not is read.
  location_point: unknown;
  entry_url: string | null;
  results_url: string | null;
  is_verified: boolean | null;
}

/// Whether the provider's current answer differs from what is stored.
///
/// A sync that rewrote every matched row would issue one UPDATE per race on
/// every call — the partial unique index `race_listings_provider_uniq` cannot
/// be an `ON CONFLICT` arbiter through PostgREST (the predicate is
/// unexpressible, 42P10), so there is no single-statement upsert to fall back
/// on and each rewrite is its own round trip. In steady state a feed answers the
/// same thing it answered last hour, so comparing first makes the common case
/// zero writes and keeps the ones that do happen meaningful in the log.
///
/// `pointKnown` says whether `next.location_point` is the ZIP table's answer
/// for this race, or merely what a failed lookup left behind. Only a known
/// answer may move or clear a stored point.
export function listingDiffers(
  stored: StoredListing,
  next: RaceListingUpsert,
  pointKnown = false,
): boolean {
  return stored.name !== next.name ||
    stored.race_date !== next.race_date ||
    stored.distance_m !== next.distance_m ||
    stored.location_label !== next.location_label ||
    stored.entry_url !== next.entry_url ||
    stored.results_url !== next.results_url ||
    listingPointMoved(stored.location_point, next.location_point, pointKnown) ||
    // A race a user submitted first lands unverified (the
    // `race_listings_force_unverified` trigger), and the provider catching up
    // with it is exactly when that should change.
    stored.is_verified !== true;
}

/// Whether the stored point must be rewritten: a race synced before its ZIP
/// could be placed gains one; a race whose ZIP moved — within one city, so
/// the label alone would not notice — is re-placed; and a race whose new
/// address has no US ZIP, or one with no ZCTA, loses the old point, because
/// a point at the race's previous venue is a race on the map where it is not.
/// A failed lookup (`pointKnown` false) never moves or clears anything, and a
/// stored value this cannot read is left alone rather than overwritten blind.
export function listingPointMoved(
  storedPoint: unknown,
  nextPoint: string | null,
  pointKnown: boolean,
): boolean {
  if (storedPoint == null) return nextPoint !== null;
  const stored = storedPointEwkt(storedPoint);
  if (stored === null) return false;
  if (nextPoint === null) return pointKnown;
  return stored !== nextPoint;
}

/// The optional region a sync is scoped to: a point, a postal code, or both,
/// plus a radius. The two forms exist because the providers search differently.
///
/// RunSignUp has NO coordinate search. Its documented location parameters
/// (`GET /Rest/races`, read 2026-10-14) are `city`, `state`, `country`, and
/// `zipcode` + `radius` in miles — US only. `lat` / `lng` / `radius` are
/// ignored without an error: measured, a New York point returned races in
/// Michigan, Florida and Pennsylvania, while `zipcode=10001&radius=10` returned
/// New York and Jersey City. The response carries no coordinates either, so
/// "fetch nationally, filter by distance here" has nothing to filter on. A
/// point hint for RunSignUp is therefore refused rather than sent — sending it
/// is a national pull filed as if it were local, which is exactly what
/// `parseNearHint` exists to stop. The caller that has a location is a client
/// with the device's postal code or the runner's profile region; nothing in the
/// tree calls the sync today, so the contract is set here, not inherited.
export interface NearHint {
  point: { lng: number; lat: number } | null;
  postalCode: string | null;
  radiusM: number;
}

/// The default radius when a caller gives a point and no radius, in metres.
/// `search_race_listings` defaults its own proximity gate to 50 km; a discovery
/// sync that pulled a wider net than the search can show would write races
/// nobody can find.
export const DEFAULT_NEAR_RADIUS_M = 50_000;
export const MAX_NEAR_RADIUS_M = 200_000;

/// Read the optional region hint. `undefined` means "no hint" and is valid;
/// anything present but unusable is an ERROR rather than a silent fall back to
/// no hint, because a typo in a radius would otherwise pull the provider's
/// whole national feed and write it into the calendar as if it were local.
export function parseNearHint(
  raw: unknown,
): { ok: true; near: NearHint | null } | { ok: false; error: string } {
  if (raw === undefined || raw === null) return { ok: true, near: null };
  if (typeof raw !== 'object' || Array.isArray(raw)) {
    return { ok: false, error: 'invalid_near' };
  }
  const o = raw as Record<string, unknown>;
  let point: NearHint['point'] = null;
  if (o.lng !== undefined || o.lat !== undefined) {
    const lng = o.lng;
    const lat = o.lat;
    if (typeof lng !== 'number' || !Number.isFinite(lng) || lng < -180 || lng > 180) {
      return { ok: false, error: 'invalid_near_lng' };
    }
    if (typeof lat !== 'number' || !Number.isFinite(lat) || lat < -90 || lat > 90) {
      return { ok: false, error: 'invalid_near_lat' };
    }
    point = { lng, lat };
  }
  let postalCode: string | null = null;
  if (o.postal_code !== undefined) {
    const pc = typeof o.postal_code === 'string' ? o.postal_code.trim() : '';
    if (!/^[A-Za-z0-9][A-Za-z0-9 -]{1,9}$/.test(pc)) {
      return { ok: false, error: 'invalid_near_postal_code' };
    }
    postalCode = pc;
  }
  if (point === null && postalCode === null) return { ok: false, error: 'invalid_near' };
  let radiusM = DEFAULT_NEAR_RADIUS_M;
  if (o.radius_m !== undefined) {
    const r = o.radius_m;
    if (typeof r !== 'number' || !Number.isFinite(r) || r <= 0 || r > MAX_NEAR_RADIUS_M) {
      return { ok: false, error: 'invalid_near_radius' };
    }
    radiusM = Math.round(r);
  }
  return { ok: true, near: { point, postalCode, radiusM } };
}

/// Whether `provider` can search by the hint it was given. RunSignUp needs a
/// US ZIP (see `NearHint`); UltraSignup's endpoint is declared with a point.
export function nearHintError(
  provider: ListingSyncProvider,
  near: NearHint | null,
): string | null {
  if (near === null) return null;
  if (provider === 'runsignup') {
    if (near.postalCode === null) return 'near_postal_code_required';
    return /^\d{5}$/.test(near.postalCode) ? null : 'near_postal_code_not_us';
  }
  return near.point === null ? 'near_point_required' : null;
}

/// RunSignUp's `results_per_page` accepts the whole cap in one request
/// (measured: 500 races, ~2.9 MB with `events=T`), so a sync is ONE upstream
/// call. Further pages are deliberately not walked: the response's `complete`
/// says when the cap was hit, and a sync is bounded at 2 per caller per hour.
const MILES_M = 1609.344;

/// Build the provider's upcoming-races URL.
///
/// RunSignUp's listings feed is PUBLIC: `GET /Rest/races` answers 200 with no
/// key (2026-10-14). The key and secret are sent only when BOTH are set — they
/// buy partner-scoped extras, not access — so a deployment without them still
/// syncs. Results are sorted by date so the cap trims the far future, not an
/// alphabetical slice. UltraSignup's endpoint stays unverified and keyed; the
/// caller refuses it without a credential before this is built.
export function providerRacesUrl(opts: {
  provider: ListingSyncProvider;
  apiKey: string | null;
  apiSecret: string | null;
  near: NearHint | null;
  /// RunSignUp only: one state over one date window — the scheduled sweep's
  /// unit (`race-listings-sweep`, decisions § 1902). Replaces `start_date=today`.
  window?: SweepWindow;
}): string {
  const radiusMi = opts.near
    ? String(Math.max(1, Math.round(opts.near.radiusM / MILES_M)))
    : null;
  if (opts.provider === 'ultrasignup') {
    const u = new URL('https://ultrasignup.com/service/events.svc/upcomingevents');
    u.searchParams.set('format', 'json');
    if (opts.apiKey) u.searchParams.set('api_key', opts.apiKey);
    if (opts.apiSecret) u.searchParams.set('api_secret', opts.apiSecret);
    u.searchParams.set('results_per_page', String(MAX_LISTING_ROWS));
    if (opts.near?.point && radiusMi) {
      u.searchParams.set('lat', String(opts.near.point.lat));
      u.searchParams.set('lng', String(opts.near.point.lng));
      u.searchParams.set('radius', radiusMi);
    }
    return u.toString();
  }
  const u = new URL('https://runsignup.com/Rest/races');
  u.searchParams.set('format', 'json');
  if (opts.apiKey && opts.apiSecret) {
    u.searchParams.set('api_key', opts.apiKey);
    u.searchParams.set('api_secret', opts.apiSecret);
  }
  u.searchParams.set('events', 'T');
  if (opts.window) {
    u.searchParams.set('country_code', 'US');
    u.searchParams.set('state', opts.window.state);
    u.searchParams.set('start_date', opts.window.startDate);
    u.searchParams.set('end_date', opts.window.endDate);
  } else {
    u.searchParams.set('start_date', 'today');
  }
  u.searchParams.set('sort', 'date ASC');
  u.searchParams.set('results_per_page', String(MAX_LISTING_ROWS));
  if (opts.near?.postalCode && radiusMi) {
    u.searchParams.set('zipcode', opts.near.postalCode);
    u.searchParams.set('radius', radiusMi);
  }
  return u.toString();
}

// ── The scheduled sweep (race-listings-sweep, decisions § 1902) ─────────────

/// The jurisdictions RunSignUp's `state` filter is swept over: the fifty states
/// and DC, as the feed spells them in `address.state`.
export const SWEEP_STATES = [
  'AK', 'AL', 'AR', 'AZ', 'CA', 'CO', 'CT', 'DC', 'DE', 'FL', 'GA', 'HI', 'IA',
  'ID', 'IL', 'IN', 'KS', 'KY', 'LA', 'MA', 'MD', 'ME', 'MI', 'MN', 'MO', 'MS',
  'MT', 'NC', 'ND', 'NE', 'NH', 'NJ', 'NM', 'NV', 'NY', 'OH', 'OK', 'OR', 'PA',
  'RI', 'SC', 'SD', 'TN', 'TX', 'UT', 'VA', 'VT', 'WA', 'WI', 'WV', 'WY',
] as const;

/// Each state's horizon is cut into windows short enough that one window's
/// races fit one keyless request. Keyless pagination stops at the first page
/// (`page=2` answers "Pagination beyond 1,000 results requires authentication"),
/// and `MAX_LISTING_ROWS` caps a page at 500: measured 2026-10-14, California
/// carries 576 races over three months, so a 14-day window holds ~100 and
/// leaves the cap far off. Six windows reach 84 days out.
export const SWEEP_WINDOW_DAYS = 14;
export const SWEEP_WINDOWS = 6;

/// How long one request to a provider feed may take, headers and body
/// together. Nothing else bounds it: the runtime's wall clock is minutes, and
/// pg_net drops its side of the sweep call after 60 s while the worker keeps
/// waiting, so a feed that accepts the connection and never answers would hold
/// a worker per five-minute run until the runtime killed it, writing nothing
/// and saying nothing. A 500-race page with events is ~2.9 MB and answers in
/// seconds; a run that has not finished in this long is not going to.
export const UPSTREAM_TIMEOUT_MS = 30_000;

/// The cron's period, in seconds, which is also the width of one slot: every
/// run computes its slot from the clock, so the sweep needs no cursor table,
/// a late or repeated run re-reads the same slot rather than skipping one, and
/// no window can be asked for twice inside one period. 51 × 6 = 306 slots at
/// five minutes is a full pass every 25.5 hours — one request per run.
export const SWEEP_PERIOD_S = 300;

export interface SweepWindow {
  slot: number;
  state: string;
  startDate: string;
  endDate: string;
}

function isoDay(ms: number): string {
  return new Date(ms).toISOString().slice(0, 10);
}

/// The state and date window the run at `nowMs` sweeps. A state's six windows
/// run back to back, nearest first, and the dates are UTC calendar days
/// counted from the run's own day, so the horizon rolls forward with the clock.
export function sweepWindowAt(nowMs: number): SweepWindow {
  const slots = SWEEP_STATES.length * SWEEP_WINDOWS;
  const slot = Math.floor(nowMs / 1000 / SWEEP_PERIOD_S) % slots;
  const state = SWEEP_STATES[Math.floor(slot / SWEEP_WINDOWS)];
  const window = slot % SWEEP_WINDOWS;
  const today = Date.UTC(
    new Date(nowMs).getUTCFullYear(),
    new Date(nowMs).getUTCMonth(),
    new Date(nowMs).getUTCDate(),
  );
  const day = 86_400_000;
  const start = today + window * SWEEP_WINDOW_DAYS * day;
  const end = start + (SWEEP_WINDOW_DAYS - 1) * day;
  return { slot, state, startDate: isoDay(start), endDate: isoDay(end) };
}
