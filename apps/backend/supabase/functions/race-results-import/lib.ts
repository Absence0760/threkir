// Pure helpers for the race-results importer.
//
// Import modes:
//   - 'runsignup'   — maps the RunSignUp REST get-results JSON onto runs rows.
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
 * It matters most on the RunSignUp bib-scoped path, which is the one that is
 * reachable rather than theoretical: `runSignUpResultsUrl` narrows upstream by
 * USER ID only, so a request scoped by bib alone fetches the WHOLE finisher
 * field and `filterResultsByBib` narrows afterwards. A major with 30,000
 * finishers therefore truncates at 2,000 BEFORE the bib filter runs, and a
 * runner whose bib sits past that slice is told nothing was found
 * (decisions § 976).
 */
export function resultsPossiblyTruncated(rowCount: number): boolean {
  return rowCount >= MAX_RESULTS_ROWS;
}

/** Trim + truncate an untrusted text field. Non-strings become ''. */
export function capField(raw: unknown, max: number = MAX_FIELD_LEN): string {
  if (typeof raw !== 'string') return '';
  return clipText(raw, max);
}

/** Parse "H:MM:SS" / "MM:SS" / "SS" into whole seconds. 0 on garbage. */
export function parseClockToSeconds(time: unknown): number {
  const s = capField(time);
  if (!s) return 0;
  const parts = s.split(':').map((p) => Number(p));
  if (parts.some((n) => !Number.isFinite(n) || n < 0)) return 0;
  if (parts.length === 3) return parts[0] * 3600 + parts[1] * 60 + parts[2];
  if (parts.length === 2) return parts[0] * 60 + parts[1];
  if (parts.length === 1) return parts[0];
  return 0;
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

/** A finisher row as RunSignUp returns it (the fields we consume). */
export interface RunSignUpResult {
  bib_num?: unknown;
  chip_time?: unknown;
  clock_time?: unknown; // gun time
  place?: unknown; // overall place
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
  external_id: string;
  race_listing_id: string;
  metadata: Record<string, Json>;
}

/**
 * Map one RunSignUp finisher onto a runs row for `userId`. `raceName` +
 * `raceDate` + `distanceM` come from the race_listings row being imported;
 * `chip_time` is authoritative for duration_s, falling back to clock (gun)
 * time when chip is absent. Returns null when the result can't become a valid
 * runs row: no usable time (a DNS/DNF row with no result is not a run), or a
 * null `distanceM` — `runs.distance_m` is NOT NULL, so a listing with no
 * stored distance would otherwise produce a row that fails the batch insert
 * (23502) and silently imports nothing for the whole race.
 */
export function mapRunSignUpResult(
  r: RunSignUpResult,
  opts: {
    userId: string;
    listingId: string;
    raceName: string;
    raceDate: string;
    distanceM: number | null;
    isPublic: boolean;
  },
): MappedRaceRun | null {
  const chip = capField(r.chip_time);
  const gun = capField(r.clock_time);
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

  const bib = capField(r.bib_num);
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
  const place = toPositiveInt(r.place);
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
    external_id: raceExternalId(opts.raceName, opts.raceDate, bib),
    race_listing_id: opts.listingId,
    metadata,
  };
}

/** A single user-pasted result (the no-API path). */
export interface PasteResultInput {
  bib?: unknown;
  chip_time?: unknown;
  gun_time?: unknown;
  overall_place?: unknown;
  age_group_place?: unknown;
  age_group?: unknown;
}

/**
 * Map a single pasted result onto a runs row. Same shape + dedup id as the
 * RunSignUp path so a later provider sync of the same race can't create a
 * duplicate. Returns null when the paste has no usable time.
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
  },
): MappedRaceRun | null {
  return mapRunSignUpResult(
    {
      bib_num: input.bib,
      chip_time: input.chip_time,
      clock_time: input.gun_time,
      place: input.overall_place,
      age_group_place: input.age_group_place,
      age_group: input.age_group,
    },
    opts,
  );
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
 * shared `mapRunSignUpResult` shaping so the run row shape, the time fallback
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
  },
): MappedRaceRun | null {
  return mapRunSignUpResult(
    {
      bib_num: r.results_bib,
      chip_time: r.results_time,
      clock_time: r.results_gun_time,
      place: r.results_rank,
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

/**
 * Build the RunSignUp get-results URL. Centralised so the scraper-hygiene
 * (api_key/api_secret in the query string, format=json) lives in one place and
 * the URL is testable. `userId` here is the runner's RunSignUp account id —
 * NOT our auth user id.
 */
export function runSignUpResultsUrl(opts: {
  raceId: string;
  apiKey: string;
  apiSecret: string;
  runSignUpUserId?: string;
}): string {
  const u = new URL(
    `https://runsignup.com/Rest/race/${encodeURIComponent(opts.raceId)}/results/get-results`,
  );
  u.searchParams.set('format', 'json');
  u.searchParams.set('api_key', opts.apiKey);
  u.searchParams.set('api_secret', opts.apiSecret);
  if (opts.runSignUpUserId) u.searchParams.set('user_id', opts.runSignUpUserId);
  return u.toString();
}

/**
 * Pull the flat finisher array out of the RunSignUp get-results envelope,
 * capped. The API nests results under
 * `individual_results_sets[].results[]`; tolerate a top-level `results` too.
 */
export function extractRunSignUpResults(payload: unknown): RunSignUpResult[] {
  const out: RunSignUpResult[] = [];
  if (!payload || typeof payload !== 'object') return out;
  const obj = payload as Record<string, unknown>;
  const sets = obj.individual_results_sets;
  if (Array.isArray(sets)) {
    for (const set of sets) {
      const rows = (set as Record<string, unknown>)?.results;
      if (Array.isArray(rows)) {
        for (const r of rows) {
          out.push(r as RunSignUpResult);
          if (out.length >= MAX_RESULTS_ROWS) return out;
        }
      }
    }
  }
  if (out.length === 0 && Array.isArray(obj.results)) {
    for (const r of obj.results) {
      out.push(r as RunSignUpResult);
      if (out.length >= MAX_RESULTS_ROWS) return out;
    }
  }
  return out;
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
 * Pre-fetch gate for the RunSignUp leg. A request is scoped when it carries the
 * runner's RunSignUp user id (narrows the upstream fetch) or a bib (narrows the
 * mapped results client-side via `filterResultsByBib`). An unscoped request is
 * rejected 400 `runsignup_athlete_id_required` — never fetched.
 */
export function runSignUpScopeGate(scope: {
  runSignUpUserId?: string;
  bib?: string;
}): RaceImportGate {
  const scoped = Boolean(capField(scope.runSignUpUserId) || capField(scope.bib));
  return scoped ? GATE_OK : {
    ok: false,
    status: 400,
    error: 'runsignup_athlete_id_required',
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
 * Keep only the mapped results whose bib matches `bib`. RunSignUp's API filters
 * only by user id, so a request scoped by bib alone must be narrowed here — a
 * blank bib is a no-op (the user-id narrowing already applied upstream).
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
  },
): MappedRaceRun | null {
  if (Number(r.status) !== ULTRASIGNUP_STATUS_FINISHED) return null;
  return mapRunSignUpResult(
    { chip_time: capField(r.formattime) || capField(r.time), place: r.place },
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
export type UltraSignUpPersonScope =
  | { ok: true; personId: string; firstName: string; lastName: string }
  | { ok: false; status: number; error: string };

/**
 * Pre-fetch gate for the UltraSignup import: the request must name the person
 * `Id` AND the name it was found under, because the feed is keyed by the name
 * and the `Id` is what picks the runner out of it. Missing either is 400
 * `ultrasignup_person_required` — never a fetch, and never a fallback onto the
 * listing's `provider_race_id`, which is a RACE id.
 */
export function ultraSignUpPersonScope(raw: {
  personId?: unknown;
  firstName?: unknown;
  lastName?: unknown;
}): UltraSignUpPersonScope {
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
