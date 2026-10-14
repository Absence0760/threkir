// Pure helpers for the race-results importer.
//
// Import modes:
//   - 'runsignup'   — finds the listing's event(s) in RunSignUp's public race
//                     feed and maps the runner's bib-filtered result onto a
//                     runs row; keyless (the key pair is sent when set).
//   - 'chronotrack' — maps the ChronoTrack Live (CTLive) results JSON onto runs
//                     rows; gated fail-closed on its own CHRONOTRACK_* creds.
//   - 'ultrasignup' — picks the runner out of UltraSignup's name-keyed history
//                     feed and keeps only their result for the listing's race;
//                     opt-in per deployment (ULTRASIGNUP_RESULTS_ENABLED).
//   - 'paste'       — maps a single user-pasted result row (any timing site that
//                     has no API) onto one runs row.
//
// Everything here is network-free + side-effect-free so the mapping, the field
// caps, and the external_id shape are unit-testable without live credentials
// (the EF itself returns 503 when a provider's creds are unset or, for
// UltraSignup, when the deployment has not opted in — see index.ts).

import type { Json } from '../_shared/database.ts';
import { isIsoCalendarDate } from '../_shared/calendar_date.ts';
import { clipText } from '../_shared/text_clip.ts';
import { SYNTHETIC_START_TIME_UTC } from '../_shared/synthetic_start_time.ts';
import {
  isInPersonRunningEvent,
  parseProviderRaceDate,
  parseRunSignUpDistance,
  type RunSignUpEventRow,
  runSignUpErrorOf,
} from '../race-listings-sync/lib.ts';

export { runSignUpErrorOf };

export const MAX_FIELD_LEN = 200;
export const MAX_RESULTS_ROWS = 2000;

/**
 * Whether a provider fetch may have been cut off by `MAX_RESULTS_ROWS`.
 *
 * The three extractors stop pushing at the cap and return a plain array, so the
 * only evidence of a truncation is the length — and a page carrying exactly
 * `MAX_RESULTS_ROWS` results is indistinguishable from one that carried more.
 * This reads that ambiguity the fail-closed way: exactly-at-the-cap is
 * "possibly truncated", because a false "possibly" costs a caller one honest
 * sentence while a false "complete" costs them the belief that they were not in
 * a race they finished.
 *
 * It matters most on a path whose upstream filter is not honoured: a bib-scoped
 * request that the feed answers with the whole field truncates at 2,000 BEFORE
 * `filterResultsByBib` runs, and a runner whose bib sits past that slice would
 * be told nothing was found (decisions § 976). RunSignUp's `bib_num` narrows
 * upstream today, so there it is the guard for the day it stops.
 */
export function resultsPossiblyTruncated(rowCount: number): boolean {
  return rowCount >= MAX_RESULTS_ROWS;
}

/** Trim + truncate an untrusted text field. Non-strings become ''. */
export function capField(raw: unknown, max: number = MAX_FIELD_LEN): string {
  if (typeof raw !== 'string') return '';
  return clipText(raw, max);
}

/**
 * Parse "H:MM:SS" / "MM:SS" / "SS" into whole seconds. 0 on garbage.
 *
 * Chip-timed feeds carry hundredths (`21:43.34` — every RunSignUp result
 * observed 2026-10-14), and `runs.duration_s` is an integer: a fractional value
 * fails the batch insert, losing the import rather than the fraction. Fractions
 * round UP to the next whole second, which is how road-race times are reported.
 */
export function parseClockToSeconds(time: unknown): number {
  return Math.ceil(parseClock(time));
}

/** The clock reading in seconds, fraction kept. 0 on garbage. */
function parseClock(time: unknown): number {
  const s = capField(time);
  if (!s) return 0;
  const parts = s.split(':').map((p) => Number(p));
  if (parts.some((n) => !Number.isFinite(n) || n < 0)) return 0;
  if (parts.length === 3) return parts[0] * 3600 + parts[1] * 60 + parts[2];
  if (parts.length === 2) return parts[0] * 60 + parts[1];
  if (parts.length === 1) return parts[0];
  return 0;
}

/** A result field that may arrive as a number (RunSignUp's `bib`) or text. */
function resultText(raw: unknown, max: number = MAX_FIELD_LEN): string {
  if (typeof raw === 'number' && Number.isFinite(raw)) return String(raw);
  return capField(raw, max);
}

/**
 * Build the cross-source dedup external_id for a race result.
 * Shape: `race:{name}:{date}:{bib}` (integrations.md dedup table). The pieces
 * are capped + colon-stripped so a scraped value can't break the delimiter or
 * grow the id past the per-user index's reach.
 */
export function raceExternalId(name: string, date: string, bib: string): string {
  const clean = (v: string) => capField(v, 80).replace(/:/g, ' ');
  return `race:${clean(name)}:${clean(date)}:${clean(bib)}`;
}

/**
 * One result in the provider-neutral shape every leg is read into before
 * `mapRaceResult` shapes it — and the shape a pasted result arrives in.
 */
export interface RaceResultFields {
  bib?: unknown;
  chip_time?: unknown;
  gun_time?: unknown;
  overall_place?: unknown;
  age_group_place?: unknown;
  age_group?: unknown;
}

export interface MappedRaceRun {
  started_at: string;
  duration_s: number;
  distance_m: number;
  source: 'race';
  activity_type: 'run';
  is_public: boolean;
  followers_only: boolean;
  external_id: string;
  race_listing_id: string;
  metadata: Record<string, Json>;
}

/**
 * Map one provider-neutral result onto a runs row for `userId`. `raceName` +
 * `raceDate` + `distanceM` come from the race_listings row being imported;
 * `chip_time` is authoritative for duration_s, falling back to clock (gun)
 * time when chip is absent. Returns null when the result can't become a valid
 * runs row: no usable time (a DNS/DNF row with no result is not a run), or a
 * null `distanceM` — `runs.distance_m` is NOT NULL, so a listing with no
 * stored distance would otherwise produce a row that fails the batch insert
 * (23502) and silently imports nothing for the whole race.
 */
export function mapRaceResult(
  r: RaceResultFields,
  opts: {
    userId: string;
    listingId: string;
    raceName: string;
    raceDate: string;
    distanceM: number | null;
    isPublic: boolean;
    followersOnly?: boolean;
  },
): MappedRaceRun | null {
  const chip = capField(r.chip_time);
  const gun = capField(r.gun_time);
  const durationS = parseClockToSeconds(chip || gun);
  if (durationS <= 0) return null;
  // runs.distance_m is NOT NULL. A listing with no stored distance can't yield
  // a valid run; drop the result rather than emit a row that 23502s the batch.
  if (opts.distanceM == null || !Number.isFinite(opts.distanceM) || opts.distanceM <= 0) {
    return null;
  }
  // Same rule for the date. `public_race_listings` is a view, so the generated
  // type cannot carry the base table's NOT NULL and the caller resolves it
  // with `?? ''` — which appended to the synthetic clock gives the literal
  // `T10:00:00Z`, a value `timestamptz` cannot parse. That 22007s the batch
  // insert, so ONE unattributable date loses the whole race rather than one
  // result.
  if (!isIsoCalendarDate(opts.raceDate)) return null;

  const bib = resultText(r.bib);
  // The RunSignUp / ChronoTrack / UltraSignup feeds carry a race date with no
  // start clock, so synthesise a UTC time-of-day. The 10:00 UTC choice + its
  // worldwide-timezone rationale live in the shared constant so this path and
  // parkrun-import's parseParkrunDate can't silently diverge.
  const startedAt = `${opts.raceDate}${SYNTHETIC_START_TIME_UTC}`;

  const metadata: Record<string, Json> = {
    race_name: capField(opts.raceName),
  };
  if (bib) metadata.bib = bib;
  if (chip) metadata.chip_time = chip;
  if (gun) metadata.gun_time = gun;
  const place = toPositiveInt(r.overall_place);
  if (place != null) metadata.overall_place = place;
  const agPlace = toPositiveInt(r.age_group_place);
  if (agPlace != null) metadata.age_group_place = agPlace;
  const ag = capField(r.age_group, 40);
  if (ag) metadata.age_group = ag;

  return {
    started_at: startedAt,
    duration_s: durationS,
    distance_m: opts.distanceM,
    source: 'race',
    activity_type: 'run',
    is_public: opts.isPublic,
    followers_only: !opts.isPublic && opts.followersOnly === true,
    external_id: raceExternalId(opts.raceName, opts.raceDate, bib),
    race_listing_id: opts.listingId,
    metadata,
  };
}

// ── One finish, two paths (decisions § 1912) ─────────────────────────────────
//
// A result pasted without a bib is filed as `race:{name}:{date}:` and the same
// result imported from a provider as `race:{name}:{date}:{bib}`, so neither the
// id nor the listing-and-bib skip can see that they are one finish. What both
// paths do know is the listing (one race on one day), the finish clock and,
// often, the overall place, and those are what decide it.

/**
 * How far apart two readings of one finish clock can be. A runner copies
 * `21:43.34` as `21:43` or `21:44`, and a feed that publishes hundredths is
 * stored rounded up (`parseClockToSeconds`), so one finish reads up to a
 * second apart; two different finishes by one runner on one morning — a 5K and
 * a 10K — are minutes apart.
 */
export const SAME_FINISH_TOLERANCE_S = 1;

/** What a result's metadata says about the finish it records. */
export interface FinishFacts {
  bib: string;
  chipS: number | null;
  gunS: number | null;
  place: number | null;
}

export function finishFacts(metadata: unknown): FinishFacts {
  const m = metadata !== null && typeof metadata === 'object' && !Array.isArray(metadata)
    ? metadata as Record<string, unknown>
    : {};
  const clock = (raw: unknown) => {
    const s = parseClock(typeof raw === 'number' ? String(raw) : raw);
    return s > 0 ? s : null;
  };
  return {
    bib: resultText(m.bib),
    chipS: clock(m.chip_time),
    gunS: clock(m.gun_time),
    place: toPositiveInt(m.overall_place),
  };
}

/**
 * Whether two results under ONE listing for ONE runner are the same finish.
 *
 * Two bibs decide it alone. Otherwise the overall places, when both carry one,
 * must agree, and the clocks must agree to within `SAME_FINISH_TOLERANCE_S` —
 * chip against chip and gun against gun wherever both sides have that reading,
 * and only when no reading is shared, the one each side has (RunSignUp's
 * `chip_time` is often empty, and a runner pastes their time into whichever
 * box). Two results with nothing to compare are not the same finish: a missed
 * merge files a race twice, which the runner can delete, while a false merge
 * writes one race's result over another's.
 */
export function isSameFinish(a: FinishFacts, b: FinishFacts): boolean {
  if (a.bib && b.bib) return a.bib === b.bib;
  if (a.place !== null && b.place !== null && a.place !== b.place) return false;
  const pairs: Array<[number, number]> = [];
  if (a.chipS !== null && b.chipS !== null) pairs.push([a.chipS, b.chipS]);
  if (a.gunS !== null && b.gunS !== null) pairs.push([a.gunS, b.gunS]);
  if (pairs.length === 0) {
    const x = a.chipS ?? a.gunS;
    const y = b.chipS ?? b.gunS;
    if (x === null || y === null) return false;
    pairs.push([x, y]);
  }
  return pairs.every(([x, y]) => Math.abs(x - y) < SAME_FINISH_TOLERANCE_S);
}

/** A run the caller already holds under the listing being imported onto. */
export interface FiledRaceRun {
  id: string;
  source: string;
  metadata: unknown;
}

/** A filed result that an incoming one names, to be written onto it. */
export interface FinishMerge {
  run: FiledRaceRun;
  result: MappedRaceRun;
}

/**
 * Reconcile incoming results against the runs already filed under the same
 * listing. A result is dropped when a filed run is the same finish
 * (`isSameFinish`) and carries everything the result knows; when the result
 * carries a bib the filed run lacks — a bib-less paste, then the provider
 * import of the same race — it is written onto that run instead, so the run
 * gains its bib and later imports skip it by the cheaper rules. Each filed run
 * absorbs at most one result. Pure; the handler does the writes.
 */
export function reconcileFiledFinishes(
  incoming: readonly MappedRaceRun[],
  filed: readonly FiledRaceRun[],
): { fresh: MappedRaceRun[]; skipped: number; merges: FinishMerge[] } {
  const facts = filed.map((f) => finishFacts(f.metadata));
  const claimed = new Set<number>();
  const fresh: MappedRaceRun[] = [];
  const merges: FinishMerge[] = [];
  let skipped = 0;
  for (const result of incoming) {
    const mine = finishFacts(result.metadata);
    const at = facts.findIndex((f, i) => !claimed.has(i) && isSameFinish(mine, f));
    if (at === -1) {
      fresh.push(result);
      continue;
    }
    claimed.add(at);
    if (mine.bib && !facts[at].bib) merges.push({ run: filed[at], result });
    else skipped += 1;
  }
  return { fresh, skipped, merges };
}

/** A single user-pasted result (the no-API path). */
export type PasteResultInput = RaceResultFields;

/**
 * Map a single pasted result onto a runs row, in the same shape as every
 * provider leg. A pasted bib gives it the provider's dedup id; without one it
 * is matched to a provider import of the same race by `reconcileFiledFinishes`.
 * Returns null when the paste has no usable time.
 */
export function parseRaceResultRow(
  input: PasteResultInput,
  opts: {
    userId: string;
    listingId: string;
    raceName: string;
    raceDate: string;
    distanceM: number | null;
    isPublic: boolean;
    followersOnly?: boolean;
  },
): MappedRaceRun | null {
  return mapRaceResult(input, opts);
}

function toPositiveInt(raw: unknown): number | null {
  const n = typeof raw === 'number' ? raw : Number(capField(raw));
  if (!Number.isFinite(n) || n <= 0) return null;
  return Math.floor(n);
}

/**
 * Whether the ChronoTrack Live leg has all three credentials provisioned.
 * Pure over a `(name) => value | undefined` getter so the fail-closed gate is
 * unit-testable without a Deno.env or the EF's heavy supabase-js import.
 */
export function chronoTrackConfigured(
  getEnv: (name: string) => string | undefined,
): boolean {
  return Boolean(
    getEnv('CHRONOTRACK_CLIENT_ID') &&
      getEnv('CHRONOTRACK_USER_ID') &&
      getEnv('CHRONOTRACK_PASSWORD'),
  );
}

/** A finisher row as the ChronoTrack Live API returns it (fields we consume). */
export interface ChronoTrackResult {
  results_bib?: unknown;
  results_time?: unknown; // chip / net time
  results_gun_time?: unknown; // gun time
  results_rank?: unknown; // overall place
  results_division_rank?: unknown; // age-group place
  results_division?: unknown; // age group label
}

/**
 * Map one ChronoTrack finisher onto a runs row for `userId`. Delegates to the
 * shared `mapRaceResult` shaping so the run row shape, the time fallback
 * (chip → gun), the external_id, and the metadata keys are identical across
 * providers — only the provider-specific field names differ here.
 */
export function mapChronoTrackResult(
  r: ChronoTrackResult,
  opts: {
    userId: string;
    listingId: string;
    raceName: string;
    raceDate: string;
    distanceM: number | null;
    isPublic: boolean;
    followersOnly?: boolean;
  },
): MappedRaceRun | null {
  return mapRaceResult(
    {
      bib: r.results_bib,
      chip_time: r.results_time,
      gun_time: r.results_gun_time,
      overall_place: r.results_rank,
      age_group_place: r.results_division_rank,
      age_group: r.results_division,
    },
    opts,
  );
}

/**
 * Build the ChronoTrack Live get-results URL. Centralised so the credential
 * handling (client_id + the user_id/user_pass basic-auth pair in the query
 * string, format=json) lives in one place and the URL is testable. `eventId`
 * is the ChronoTrack event id stored on the listing's `provider_race_id`.
 */
export function chronoTrackResultsUrl(opts: {
  eventId: string;
  clientId: string;
  userId: string;
  password: string;
  bib?: string;
}): string {
  const u = new URL(
    `https://api.chronotrack.com/api/event/${encodeURIComponent(opts.eventId)}/results`,
  );
  u.searchParams.set('format', 'json');
  u.searchParams.set('client_id', opts.clientId);
  u.searchParams.set('user_id', opts.userId);
  u.searchParams.set('user_pass', opts.password);
  if (opts.bib) u.searchParams.set('bib', opts.bib);
  return u.toString();
}

/**
 * Pull the flat finisher array out of the ChronoTrack Live results envelope,
 * capped. CTLive nests rows under `event_results[]`; tolerate a top-level
 * `results` too (the same defensive shape as the RunSignUp extractor).
 */
export function extractChronoTrackResults(payload: unknown): ChronoTrackResult[] {
  const out: ChronoTrackResult[] = [];
  if (!payload || typeof payload !== 'object') return out;
  const obj = payload as Record<string, unknown>;
  const rows = obj.event_results;
  if (Array.isArray(rows)) {
    for (const r of rows) {
      out.push(r as ChronoTrackResult);
      if (out.length >= MAX_RESULTS_ROWS) return out;
    }
  }
  if (out.length === 0 && Array.isArray(obj.results)) {
    for (const r of obj.results) {
      out.push(r as ChronoTrackResult);
      if (out.length >= MAX_RESULTS_ROWS) return out;
    }
  }
  return out;
}

// ── RunSignUp ────────────────────────────────────────────────────────────────
//
// Both endpoints are public (measured 2026-10-14: HTTP 200 with no key), so the
// leg runs keyless and sends `api_key` / `api_secret` only when BOTH are set —
// the rule `race-listings-sync` applies to the same provider (decisions § 1899).
// What the live feed actually takes and returns, which the earlier reader had
// guessed at:
//
// - get-results REQUIRES `event_id`. Without it the answer is an error
//   envelope — `{"error":{"error_code":3,...,"param_missing":[{"param_name":
//   "event_id"}]}}` — with HTTP 200, so a status check alone reads it as a race
//   with nobody in it. The event comes from `GET /Rest/race/{race_id}`, whose
//   `events` carry every edition the race has held.
// - `bib_num` narrows upstream (a bib that ran answers one row, one that did
//   not answers none). `user_id` is IGNORED keyless: it answers the whole field,
//   so it can never be the thing that scopes an import (issue #360).
// - A row carries `bib` (a number), `place`, `chip_time` (often `""`),
//   `clock_time`, both with hundredths, and one `division-<id>-placement`
//   column per division the set defines, named in the set's `results_headers`.

/** Append the RunSignUp key pair, but only when both halves are set. */
function withRunSignUpKey(u: URL, apiKey?: string | null, apiSecret?: string | null): URL {
  if (apiKey && apiSecret) {
    u.searchParams.set('api_key', apiKey);
    u.searchParams.set('api_secret', apiSecret);
  }
  return u;
}

/** `GET /Rest/race/{race_id}`: the race and every event it has held. */
export function runSignUpRaceUrl(opts: {
  raceId: string;
  apiKey?: string | null;
  apiSecret?: string | null;
}): string {
  const u = new URL(`https://runsignup.com/Rest/race/${encodeURIComponent(opts.raceId)}`);
  u.searchParams.set('format', 'json');
  return withRunSignUpKey(u, opts.apiKey, opts.apiSecret).toString();
}

/**
 * Build the RunSignUp get-results URL for one event, narrowed upstream to one
 * bib. `results_per_page` is the row cap, so a feed that stopped honouring
 * `bib_num` would show up as `resultsPossiblyTruncated` rather than as a silent
 * first page.
 */
export function runSignUpResultsUrl(opts: {
  raceId: string;
  eventId: string;
  bib: string;
  apiKey?: string | null;
  apiSecret?: string | null;
}): string {
  const u = new URL(
    `https://runsignup.com/Rest/race/${encodeURIComponent(opts.raceId)}/results/get-results`,
  );
  u.searchParams.set('format', 'json');
  u.searchParams.set('event_id', opts.eventId);
  u.searchParams.set('bib_num', opts.bib);
  u.searchParams.set('results_per_page', String(MAX_RESULTS_ROWS));
  return withRunSignUpKey(u, opts.apiKey, opts.apiSecret).toString();
}

/** A RunSignUp event a listing's results may sit under. */
export interface RunSignUpEvent {
  eventId: string;
  distanceM: number | null;
}

/** How many of one race-day's events an import will query, at most. */
export const MAX_RUNSIGNUP_EVENTS = 8;

/**
 * The in-person running events of the race that started on `raceDate`.
 *
 * One listing is one race (decisions § 1899), and a race morning commonly runs
 * a 5K, a 10K and a half under it, so the runner's result can be under any of
 * them. The race's `events` also carry every past edition, which is what lets a
 * past listing find its own year. `start_time` is `M/D/YYYY HH:MM` in the
 * race's own zone, so its date half is compared as the race's local day — the
 * same reading `race_date` was stored with. The event matching the listing's
 * distance sorts first, because it is the one the listing was filed under;
 * volunteer slots, walks and virtual options are never queried.
 */
export function runSignUpEventsOn(
  payload: unknown,
  raceDate: string,
  listingDistanceM: number | null,
): RunSignUpEvent[] {
  if (!payload || typeof payload !== 'object') return [];
  const race = (payload as Record<string, unknown>).race;
  if (!race || typeof race !== 'object') return [];
  const events = (race as Record<string, unknown>).events;
  if (!Array.isArray(events)) return [];
  const out: RunSignUpEvent[] = [];
  for (const raw of events) {
    if (!raw || typeof raw !== 'object') continue;
    const ev = raw as RunSignUpEventRow;
    if (!isInPersonRunningEvent(ev)) continue;
    const startDay = typeof ev.start_time === 'string' ? ev.start_time.trim().split(/\s+/)[0] : '';
    if (parseProviderRaceDate(startDay) !== raceDate) continue;
    const eventId = resultText(ev.event_id, 32);
    if (!/^\d+$/.test(eventId)) continue;
    out.push({ eventId, distanceM: parseRunSignUpDistance(ev.distance) });
  }
  out.sort((a, b) =>
    Number(b.distanceM !== null && b.distanceM === listingDistanceM) -
    Number(a.distanceM !== null && a.distanceM === listingDistanceM)
  );
  return out.slice(0, MAX_RUNSIGNUP_EVENTS);
}

/** One RunSignUp result row with the headers of the set it came from. */
export interface RunSignUpResultRow {
  result: Record<string, unknown>;
  headers: Record<string, unknown>;
}

/**
 * Pull the flat finisher array out of the RunSignUp get-results envelope,
 * capped. Rows sit under `individual_results_sets[].results[]`, and each set
 * names its own division columns, so every row keeps its set's headers.
 */
export function extractRunSignUpResults(payload: unknown): RunSignUpResultRow[] {
  const out: RunSignUpResultRow[] = [];
  if (!payload || typeof payload !== 'object') return out;
  const sets = (payload as Record<string, unknown>).individual_results_sets;
  if (!Array.isArray(sets)) return out;
  for (const set of sets) {
    if (!set || typeof set !== 'object') continue;
    const rows = (set as Record<string, unknown>).results;
    const rawHeaders = (set as Record<string, unknown>).results_headers;
    const headers = rawHeaders && typeof rawHeaders === 'object' && !Array.isArray(rawHeaders)
      ? rawHeaders as Record<string, unknown>
      : {};
    if (!Array.isArray(rows)) continue;
    for (const r of rows) {
      if (!r || typeof r !== 'object' || Array.isArray(r)) continue;
      out.push({ result: r as Record<string, unknown>, headers });
      if (out.length >= MAX_RESULTS_ROWS) return out;
    }
  }
  return out;
}

const DIVISION_COLUMN = /^division-\d+-placement$/;

/**
 * The runner's age group and their place in it, or null when the row does not
 * say which one that is.
 *
 * RunSignUp has no age-group field: a row holds a placement for each division
 * it scored in, and the set's headers name them (`M2029`, `F 30-39`,
 * `M Overall`, `All Female`). An age group is the division whose name carries
 * an age, so the one placed division with a digit in its name is taken. Zero is
 * common — an overall award winner is usually lifted out of their age group —
 * and two happens where a race defines two age schemes side by side; both leave
 * the age group unset rather than pick one.
 */
export function runSignUpAgeGroup(
  row: RunSignUpResultRow,
): { label: string; place: number } | null {
  let found: { label: string; place: number } | null = null;
  for (const [key, value] of Object.entries(row.result)) {
    if (!DIVISION_COLUMN.test(key)) continue;
    const place = toPositiveInt(value);
    if (place === null) continue;
    const label = capField(row.headers[key], 40);
    if (!/\d/.test(label)) continue;
    if (found) return null;
    found = { label, place };
  }
  return found;
}

/** Map one RunSignUp result row onto a runs row (see `mapRaceResult`). */
export function mapRunSignUpResult(
  row: RunSignUpResultRow,
  opts: {
    userId: string;
    listingId: string;
    raceName: string;
    raceDate: string;
    distanceM: number | null;
    isPublic: boolean;
    followersOnly?: boolean;
  },
): MappedRaceRun | null {
  const r = row.result;
  const ag = runSignUpAgeGroup(row);
  return mapRaceResult(
    {
      bib: r.bib,
      chip_time: r.chip_time,
      gun_time: r.clock_time,
      overall_place: r.place,
      age_group: ag?.label,
      age_group_place: ag?.place,
    },
    opts,
  );
}

// ── Athlete-scoping guard (issue #360) ───────────────────────────────────────
//
// RunSignUp's get-results returns EVERY finisher (up to MAX_RESULTS_ROWS) when
// unfiltered. Without narrowing, a standalone import inserts the whole field as
// the caller's own runs, and a matchRunId enrich stamps mapped[0] (usually the
// winner) onto the caller's run. The gate below fails closed: a request must
// name the runner's RunSignUp user id or a bib before any fetch, and an enrich
// must resolve to exactly one result.

export interface RaceImportGate {
  ok: boolean;
  status?: number;
  error?: string;
  /// Why, when the `error` code alone would send a reader looking for the
  /// wrong thing. Only the UltraSignup probe carries one today.
  reason?: string;
}

const GATE_OK: RaceImportGate = { ok: true };

/**
 * Pre-fetch gate for the RunSignUp leg: a request is scoped only by a bib.
 *
 * The bib narrows twice — upstream (`bib_num`) and again over the mapped rows
 * (`filterResultsByBib`), because the gate proves the REQUEST was scoped, not
 * that the feed honoured it. The runner's RunSignUp user id used to count as
 * scope too, and it cannot: the feed ignores `user_id` keyless and answers the
 * whole field, and no result row carries a user id to narrow by afterwards. An
 * unscoped request is rejected 400 `runsignup_bib_required` — never fetched.
 */
export function runSignUpScopeGate(scope: { bib?: string }): RaceImportGate {
  return capField(scope.bib) ? GATE_OK : {
    ok: false,
    status: 400,
    error: 'runsignup_bib_required',
  };
}

/**
 * Pre-fetch gate for the ChronoTrack leg — the same fail-closed rule as
 * `runSignUpScopeGate`, which the ChronoTrack branch never had.
 *
 * `chronoTrackResultsUrl` only narrows the upstream fetch when a bib is
 * supplied; omit it and the request returns the WHOLE finisher field for the
 * event. `extractChronoTrackResults` then takes up to MAX_RESULTS_ROWS (2000)
 * and `mapChronoTrackResult` stamps the CALLER's user_id on every one, so a
 * plain "import from ChronoTrack" with no bib inserts 2000 strangers' races as
 * the caller's own runs — which re-derive personal_records (the winner's 2:09
 * becomes their marathon PR), fire award_achievements_for_user, poison
 * run_streaks_for_user, and feed every challenge leaderboard.
 *
 * `matchResultGate` does not cover this: it guards only the matchRunId enrich
 * path, not the plain-insert path.
 */
export function chronoTrackScopeGate(scope: { bib?: string }): RaceImportGate {
  return capField(scope.bib) ? GATE_OK : {
    ok: false,
    status: 400,
    error: 'chronotrack_bib_required',
  };
}

/**
 * Post-fetch gate for the matchRunId (enrich) path. Enrich merges ONE result
 * onto the caller's own run, so it must resolve to exactly one mapped result;
 * more than one is ambiguous (which finisher is the caller?) and is rejected
 * 400 `ambiguous_match` rather than silently taking mapped[0].
 */
export function matchResultGate(mappedCount: number): RaceImportGate {
  return mappedCount === 1 ? GATE_OK : {
    ok: false,
    status: 400,
    error: 'ambiguous_match',
  };
}

/**
 * Keep only the mapped results whose bib matches `bib`. Every bib-scoped leg
 * narrows here as well as upstream: a feed that ignores a filter answers the
 * whole field, and every row of it carries the caller's user id by then
 * (issue #360). A blank bib is a no-op.
 */
export function filterResultsByBib(
  mapped: MappedRaceRun[],
  bib: string,
): MappedRaceRun[] {
  const want = capField(bib);
  if (!want) return mapped;
  return mapped.filter((r) => r.metadata.bib === want);
}


// ── UltraSignup ──────────────────────────────────────────────────────────────
//
// UltraSignup has no per-athlete results endpoint: `/service/events.svc/results/
// athlete?uid=` answers HTTP 404. The feed its own participant page reads is
// `/service/events.svc/historybyname/{first}/{last}/` — keyless, keyed by NAME,
// and answering with EVERY same-named person it knows (`Id`, `FirstName`,
// `LastName`, `Age`, `Results[]`). So an import is two choices the runner makes
// once (which name, and which of the people under it is them) plus one the
// listing makes (which race):
//
//   - the person: the feed's `Id`, picked in Settings from `ultraSignUpCandidates`
//     and stored on the runner's `integrations` row;
//   - the race: each result names its race in `event_distance_id`, the `did`
//     UltraSignup's own result links are built from
//     (`/results_event.aspx?did=` + event_distance_id). A row is kept only when
//     that id equals the listing's `provider_race_id` AND its `eventdate` is the
//     listing's `race_date`.
//
// The date is the second key rather than a redundancy. `race-listings-sync`
// reads the listing id from a field it calls `eventid` on an endpoint that has
// never answered (decisions § 1841), and UltraSignup numbers events and
// distances in two separate integer spaces — so a listing carrying an event id
// could equal an unrelated race's distance id by coincidence. Two keys from two
// sources have to agree before a stranger's race becomes this runner's history,
// and when they do not the row is dropped, never stamped (decisions § 975).

/// UltraSignup spells a finished result `status: 1`; 2 is DNF, 3 DNS, 5 DQ, and
/// the rest are other non-finishes — the participant page's own templates.
export const ULTRASIGNUP_STATUS_FINISHED = 1;
/// The longest name part the import will send. Matches the
/// `integrations.external_*_name` CHECK (20270726000003), so the column can
/// hold nothing this refuses.
export const ULTRASIGNUP_NAME_MAX_LEN = 60;
/// A common name answers with many people; the picker needs the plausible few.
export const MAX_ULTRASIGNUP_CANDIDATES = 25;
/// How many of a candidate's races the picker shows to tell them apart.
export const ULTRASIGNUP_RECENT_EVENTS = 2;

/**
 * Whether this deployment has opted into the UltraSignup leg.
 *
 * The feed is keyless, so there is no credential whose absence could gate it —
 * but it is an undocumented feed on someone else's site, reached from OUR
 * egress IP with the runner's name in the URL, and that is an operator's call
 * to make, not a default. Fail-closed: anything but the literal `true` is off.
 */
export function ultraSignUpEnabled(getEnv: (name: string) => string | undefined): boolean {
  return getEnv('ULTRASIGNUP_RESULTS_ENABLED') === 'true';
}

/**
 * A name part as it may be sent: trimmed, inner whitespace collapsed, at most
 * `ULTRASIGNUP_NAME_MAX_LEN` code points, letters (any script) with the
 * apostrophes, hyphens, periods and spaces real names carry, and starting with
 * a letter — which also keeps a `.` / `..` path segment out of the URL. Null
 * when it is not one.
 */
export function ultraSignUpNamePart(raw: unknown): string | null {
  if (typeof raw !== 'string') return null;
  const s = raw.normalize('NFC').trim().replace(/\s+/g, ' ');
  if (!s || Array.from(s).length > ULTRASIGNUP_NAME_MAX_LEN) return null;
  return /^\p{L}[\p{L}\p{M}'’ .-]*$/u.test(s) ? s : null;
}

/**
 * One of UltraSignup's integer ids (a person `Id`, an `event_distance_id`, or
 * the listing's `provider_race_id`) as a canonical decimal string, or null.
 * Canonical so `0138805` and `138805` cannot disagree, and positive because the
 * feed's zero is "none".
 */
export function ultraSignUpNumericId(raw: unknown): string | null {
  const s = typeof raw === 'number'
    ? (Number.isSafeInteger(raw) ? String(raw) : '')
    : typeof raw === 'string'
    ? raw.trim()
    : '';
  if (!/^[0-9]{1,12}$/.test(s)) return null;
  const n = Number(s);
  return n > 0 ? String(n) : null;
}

/** The historybyname URL for one name. Each part is a single encoded segment. */
export function ultraSignUpHistoryUrl(firstName: string, lastName: string): string {
  return 'https://ultrasignup.com/service/events.svc/historybyname/' +
    `${encodeURIComponent(firstName)}/${encodeURIComponent(lastName)}/`;
}

/** UltraSignup's `eventdate` ("9/25/2025 12:00:00 AM") as YYYY-MM-DD, or null. */
export function parseUltraSignUpDate(raw: unknown): string | null {
  const m = capField(raw, 40).match(/^(\d{1,2})\/(\d{1,2})\/(\d{4})(?:\s|$)/);
  if (!m) return null;
  const iso = `${m[3]}-${m[1].padStart(2, '0')}-${m[2].padStart(2, '0')}`;
  return isIsoCalendarDate(iso) ? iso : null;
}

/** A person as historybyname returns them (the fields we consume). */
export interface UltraSignUpPerson {
  Id?: unknown;
  FirstName?: unknown;
  LastName?: unknown;
  Age?: unknown;
  Results?: unknown;
}

/** One of a person's results (the fields we consume). No bib is published. */
export interface UltraSignUpResult {
  event_distance_id?: unknown; // the race: UltraSignup's `did`
  eventname?: unknown;
  eventdate?: unknown; // "9/25/2025 12:00:00 AM"
  place?: unknown; // overall place
  formattime?: unknown; // "8:35:11"
  time?: unknown; // the same clock, unformatted on some rows
  status?: unknown; // 1 = finished
}

/** The people array out of a historybyname answer, capped. Anything else is none. */
export function extractUltraSignUpPeople(payload: unknown): UltraSignUpPerson[] {
  if (!Array.isArray(payload)) return [];
  const out: UltraSignUpPerson[] = [];
  for (const p of payload) {
    if (p && typeof p === 'object' && !Array.isArray(p)) out.push(p as UltraSignUpPerson);
    if (out.length >= MAX_RESULTS_ROWS) break;
  }
  return out;
}

function resultsOf(person: UltraSignUpPerson): UltraSignUpResult[] {
  if (!Array.isArray(person.Results)) return [];
  return person.Results.filter((r): r is UltraSignUpResult =>
    Boolean(r) && typeof r === 'object' && !Array.isArray(r)
  );
}

/** One row of the Settings picker: enough to tell same-named people apart. */
export interface UltraSignUpCandidate {
  id: string;
  firstName: string;
  lastName: string;
  /// The feed's current age, or null where it publishes 0 (unknown).
  age: number | null;
  resultCount: number;
  recentEvents: { name: string; date: string | null }[];
}

/**
 * The picker's candidates. A person with no usable `Id` is left out — it could
 * never be stored, so offering it would only fail one step later. Order is the
 * feed's own.
 */
export function ultraSignUpCandidates(people: UltraSignUpPerson[]): UltraSignUpCandidate[] {
  const out: UltraSignUpCandidate[] = [];
  for (const p of people) {
    const id = ultraSignUpNumericId(p.Id);
    if (!id) continue;
    const results = resultsOf(p);
    const recent = results
      .map((r) => ({ name: capField(r.eventname), date: parseUltraSignUpDate(r.eventdate) }))
      .filter((e) => e.name)
      .sort((a, b) => (b.date ?? '').localeCompare(a.date ?? ''))
      .slice(0, ULTRASIGNUP_RECENT_EVENTS);
    const age = toPositiveInt(p.Age);
    out.push({
      id,
      firstName: capField(p.FirstName, ULTRASIGNUP_NAME_MAX_LEN),
      lastName: capField(p.LastName, ULTRASIGNUP_NAME_MAX_LEN),
      age: age != null && age < 130 ? age : null,
      resultCount: results.length,
      recentEvents: recent,
    });
    if (out.length >= MAX_ULTRASIGNUP_CANDIDATES) break;
  }
  return out;
}

/**
 * Whether one result is the listing's race: its `event_distance_id` equals the
 * listing's `provider_race_id`, and its `eventdate` is the listing's
 * `race_date`. Both, or it is not this race.
 */
export function ultraSignUpResultIsForListing(
  r: UltraSignUpResult,
  listing: { providerRaceId: string; raceDate: string },
): boolean {
  const did = ultraSignUpNumericId(r.event_distance_id);
  const want = ultraSignUpNumericId(listing.providerRaceId);
  if (!did || !want || did !== want) return false;
  const date = parseUltraSignUpDate(r.eventdate);
  return date != null && date === listing.raceDate;
}

/**
 * Map one UltraSignup result onto a runs row. Only a finished result is a run —
 * a DNF / DNS / DQ row carries a `time` of "0". Delegates to the shared shaping
 * so the row, the external_id and the metadata keys match every other provider;
 * UltraSignup publishes no bib, so the id's bib slot is empty, which is also
 * what a bib-less paste of the same race produces — the two dedup.
 *
 * This does NOT decide which race the row is: call it only on rows
 * `ultraSignUpResultIsForListing` kept, which `ultraSignUpImportRows` does.
 */
export function mapUltraSignUpResult(
  r: UltraSignUpResult,
  opts: {
    userId: string;
    listingId: string;
    raceName: string;
    raceDate: string;
    distanceM: number | null;
    isPublic: boolean;
    followersOnly?: boolean;
  },
): MappedRaceRun | null {
  if (Number(r.status) !== ULTRASIGNUP_STATUS_FINISHED) return null;
  return mapRaceResult(
    { chip_time: capField(r.formattime) || capField(r.time), overall_place: r.place },
    opts,
  );
}

/**
 * The whole UltraSignup import, minus the network: pick the runner out of a
 * historybyname answer, keep only their results for the listing's race, map
 * those. `personFound: false` means the stored `Id` is not among the people
 * that name answers with any more (a renamed profile, a typo'd link) — a
 * different answer from "found you, you have no result for this race".
 */
export function ultraSignUpImportRows(
  payload: unknown,
  opts: {
    personId: string;
    providerRaceId: string;
    userId: string;
    listingId: string;
    raceName: string;
    raceDate: string;
    distanceM: number | null;
    isPublic: boolean;
    followersOnly?: boolean;
  },
): { personFound: boolean; considered: number; mapped: MappedRaceRun[] } {
  const person = extractUltraSignUpPeople(payload).find((p) =>
    ultraSignUpNumericId(p.Id) === opts.personId
  );
  if (!person) return { personFound: false, considered: 0, mapped: [] };
  const results = resultsOf(person).slice(0, MAX_RESULTS_ROWS);
  const mapped = results
    .filter((r) => ultraSignUpResultIsForListing(r, opts))
    .map((r) => mapUltraSignUpResult(r, opts))
    .filter((r): r is MappedRaceRun => r !== null);
  return { personFound: true, considered: results.length, mapped };
}

/** A request's UltraSignup person, validated, or the 400 that refuses it. */
export type UltraSignUpScope =
  | { ok: true; personId: string; firstName: string; lastName: string }
  | { ok: false; status: number; error: string };

/**
 * Pre-fetch gate for the UltraSignup import: the request must name the person
 * `Id` AND the name it was found under, because the feed is keyed by the name
 * and the `Id` is what picks the runner out of it. Missing either is 400
 * `ultrasignup_person_required` — never a fetch, and never a fallback onto the
 * listing's `provider_race_id`, which is a RACE id.
 */
export function ultraSignUpScopeGate(raw: {
  personId?: unknown;
  firstName?: unknown;
  lastName?: unknown;
}): UltraSignUpScope {
  const personId = ultraSignUpNumericId(raw.personId);
  const firstName = ultraSignUpNamePart(raw.firstName);
  const lastName = ultraSignUpNamePart(raw.lastName);
  if (!personId || !firstName || !lastName) {
    return { ok: false, status: 400, error: 'ultrasignup_person_required' };
  }
  return { ok: true, personId, firstName, lastName };
}

/**
 * The UltraSignup leg's availability, as a probe answers it.
 *
 * `flow` is what the CLIENT says it can do. A client built before the person
 * flow sends an athlete id the leg no longer reads, so it is told the leg is
 * unavailable (reason `client_unsupported`) rather than shown a tile whose
 * every import 400s — which keeps an older mobile build's tile dark until it
 * learns the flow. A current client on a deployment that has not opted in gets
 * the plain `provider_not_configured`.
 */
export function ultraSignUpProbe(
  getEnv: (name: string) => string | undefined,
  flow: unknown,
): RaceImportGate {
  if (flow !== 'person') {
    return {
      ok: false,
      status: 503,
      error: 'provider_not_configured',
      reason: 'client_unsupported',
    };
  }
  if (!ultraSignUpEnabled(getEnv)) {
    return { ok: false, status: 503, error: 'provider_not_configured' };
  }
  return GATE_OK;
}
