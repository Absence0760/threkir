import {
  assert,
  assertEquals,
} from 'https://deno.land/std@0.224.0/assert/mod.ts';
import {
  capField,
  chronoTrackConfigured,
  chronoTrackResultsUrl,
  extractChronoTrackResults,
  extractRunSignUpResults,
  extractUltraSignUpPeople,
  filterResultsByBib,
  mapChronoTrackResult,
  mapRunSignUpResult,
  mapUltraSignUpResult,
  type MappedRaceRun,
  matchResultGate,
  MAX_FIELD_LEN,
  MAX_RESULTS_ROWS,
  parseClockToSeconds,
  parseRaceResultRow,
  raceExternalId,
  runSignUpResultsUrl,
  chronoTrackScopeGate,
  runSignUpScopeGate,
  MAX_ULTRASIGNUP_CANDIDATES,
  parseUltraSignUpDate,
  ULTRASIGNUP_NAME_MAX_LEN,
  ultraSignUpCandidates,
  ultraSignUpEnabled,
  ultraSignUpHistoryUrl,
  ultraSignUpNamePart,
  ultraSignUpNumericId,
  ultraSignUpScopeGate,
  ultraSignUpProbe,
  ultraSignUpResultIsForListing,
} from './lib.ts';
import { isIsoCalendarDate } from '../_shared/calendar_date.ts';
import { SYNTHETIC_START_TIME_UTC } from '../_shared/synthetic_start_time.ts';

const OPTS = {
  userId: 'u-1',
  listingId: 'L-1',
  raceName: 'Richmond Half Marathon',
  raceDate: '2025-09-21',
  distanceM: 21097,
  isPublic: false,
};

Deno.test('capField trims and truncates', () => {
  assertEquals(capField('  hi  '), 'hi');
  assertEquals(capField('x'.repeat(MAX_FIELD_LEN + 50)).length, MAX_FIELD_LEN);
  assertEquals(capField(42), '');
  assertEquals(capField(null), '');
});

Deno.test('parseClockToSeconds handles H:MM:SS / MM:SS / SS', () => {
  assertEquals(parseClockToSeconds('1:47:23'), 1 * 3600 + 47 * 60 + 23);
  assertEquals(parseClockToSeconds('24:31'), 24 * 60 + 31);
  assertEquals(parseClockToSeconds('45'), 45);
});

Deno.test('parseClockToSeconds rejects garbage as 0', () => {
  assertEquals(parseClockToSeconds('abc'), 0);
  assertEquals(parseClockToSeconds(''), 0);
  assertEquals(parseClockToSeconds('-1:00'), 0);
});

Deno.test('raceExternalId is race:name:date:bib and colon-safe', () => {
  assertEquals(
    raceExternalId('Richmond Half', '2025-09-21', '1234'),
    'race:Richmond Half:2025-09-21:1234',
  );
  // Embedded colons in a scraped value are replaced so they can't break the
  // delimiter (only the four leading literal colons remain).
  const id = raceExternalId('A:B', '2025-01-01', '7:7');
  assertEquals(id, 'race:A B:2025-01-01:7 7');
});

Deno.test('mapRunSignUpResult maps a finisher onto a race run', () => {
  const run = mapRunSignUpResult(
    {
      bib_num: '1234',
      chip_time: '1:47:23',
      clock_time: '1:48:01',
      place: 142,
      age_group_place: 12,
      age_group: 'M35-39',
    },
    OPTS,
  );
  assert(run !== null);
  assertEquals(run!.source, 'race');
  assertEquals(run!.activity_type, 'run');
  assertEquals(run!.distance_m, 21097);
  assertEquals(run!.duration_s, 1 * 3600 + 47 * 60 + 23);
  assertEquals(run!.external_id, 'race:Richmond Half Marathon:2025-09-21:1234');
  assertEquals(run!.race_listing_id, 'L-1');
  assertEquals(run!.started_at, '2025-09-21T10:00:00Z');
  assertEquals(run!.metadata.race_name, 'Richmond Half Marathon');
  assertEquals(run!.metadata.bib, '1234');
  assertEquals(run!.metadata.chip_time, '1:47:23');
  assertEquals(run!.metadata.gun_time, '1:48:01');
  assertEquals(run!.metadata.overall_place, 142);
  assertEquals(run!.metadata.age_group_place, 12);
  assertEquals(run!.metadata.age_group, 'M35-39');
});

Deno.test('mapped metadata never carries the promoted-away activity_type key', () => {
  // activity_type is a real runs column (20261207_001); a bag copy would ride
  // the matchRunId merge path back onto stripped rows. The column write stays.
  const run = mapRunSignUpResult({ bib_num: '1234', chip_time: '1:47:23' }, OPTS);
  assert(run !== null);
  assertEquals(run!.activity_type, 'run');
  assertEquals('activity_type' in run!.metadata, false);
  assertEquals('is_dnf' in run!.metadata, false);
});

Deno.test('mapRunSignUpResult falls back to gun time when chip is absent', () => {
  const run = mapRunSignUpResult({ bib_num: '5', clock_time: '0:30:00' }, OPTS);
  assert(run !== null);
  assertEquals(run!.duration_s, 30 * 60);
  assertEquals(run!.metadata.chip_time, undefined);
  assertEquals(run!.metadata.gun_time, '0:30:00');
});

Deno.test('mapRunSignUpResult returns null when there is no usable time', () => {
  assertEquals(mapRunSignUpResult({ bib_num: '9' }, OPTS), null);
  assertEquals(mapRunSignUpResult({ chip_time: 'DNS' }, OPTS), null);
});

Deno.test('mapRunSignUpResult honours isPublic from privacy_default', () => {
  const priv = mapRunSignUpResult({ chip_time: '20:00' }, OPTS);
  assertEquals(priv!.is_public, false);
  const pub = mapRunSignUpResult({ chip_time: '20:00' }, { ...OPTS, isPublic: true });
  assertEquals(pub!.is_public, true);
});

Deno.test('mapRunSignUpResult drops non-positive places', () => {
  const run = mapRunSignUpResult(
    { chip_time: '20:00', place: 0, age_group_place: -1 },
    OPTS,
  );
  assertEquals(run!.metadata.overall_place, undefined);
  assertEquals(run!.metadata.age_group_place, undefined);
});

Deno.test('mapRunSignUpResult returns null when the listing has no distance', () => {
  // runs.distance_m is NOT NULL — a null/zero distance from a listing with no
  // stored distance can't become a valid run. Dropping it here keeps the
  // batch insert from 23502'ing on the null and silently importing nothing.
  assertEquals(mapRunSignUpResult({ chip_time: '20:00' }, { ...OPTS, distanceM: null }), null);
  assertEquals(mapRunSignUpResult({ chip_time: '20:00' }, { ...OPTS, distanceM: 0 }), null);
  // Other providers + the paste path delegate here, so they inherit the guard.
  assertEquals(parseRaceResultRow({ chip_time: '20:00' }, { ...OPTS, distanceM: null }), null);
  assertEquals(
    mapUltraSignUpResult({ status: 1, formattime: '20:00' }, { ...OPTS, distanceM: null }),
    null,
  );
});

Deno.test('parseRaceResultRow maps a pasted result with the same shape/id', () => {
  const run = parseRaceResultRow(
    { bib: '77', chip_time: '0:55:10', gun_time: '0:55:40', overall_place: 9, age_group: 'F40-44' },
    OPTS,
  );
  assert(run !== null);
  assertEquals(run!.external_id, 'race:Richmond Half Marathon:2025-09-21:77');
  assertEquals(run!.duration_s, 55 * 60 + 10);
  assertEquals(run!.metadata.age_group, 'F40-44');
});

Deno.test('runSignUpResultsUrl includes key/secret/format and encodes raceId', () => {
  const url = runSignUpResultsUrl({
    raceId: '9001',
    apiKey: 'KEY',
    apiSecret: 'SECRET',
    runSignUpUserId: 'rs-42',
  });
  assert(url.startsWith('https://runsignup.com/Rest/race/9001/results/get-results'));
  assert(url.includes('format=json'));
  assert(url.includes('api_key=KEY'));
  assert(url.includes('api_secret=SECRET'));
  assert(url.includes('user_id=rs-42'));
});

Deno.test('extractRunSignUpResults reads the nested results sets envelope', () => {
  const payload = {
    individual_results_sets: [
      { results: [{ bib_num: '1', chip_time: '20:00' }, { bib_num: '2', chip_time: '21:00' }] },
      { results: [{ bib_num: '3', chip_time: '22:00' }] },
    ],
  };
  const rows = extractRunSignUpResults(payload);
  assertEquals(rows.length, 3);
  assertEquals(rows[2].bib_num, '3');
});

Deno.test('extractRunSignUpResults tolerates a top-level results array + caps', () => {
  assertEquals(extractRunSignUpResults({ results: [{ bib_num: 'a' }] }).length, 1);
  assertEquals(extractRunSignUpResults(null).length, 0);
  assertEquals(extractRunSignUpResults({}).length, 0);
  const big = { results: Array.from({ length: MAX_RESULTS_ROWS + 100 }, () => ({ bib_num: 'x' })) };
  assertEquals(extractRunSignUpResults(big).length, MAX_RESULTS_ROWS);
});

// ── UltraSignup ──────────────────────────────────────────────────────────────
//
// Attribution against a whole historybyname payload lives in
// `ultrasignup_attribution.test.ts`; these pin the pieces.

const ULTRA_OPTS = {
  userId: 'u-1',
  listingId: 'L-9',
  raceName: 'Example Peaks 100 Mile',
  raceDate: '2025-06-20',
  distanceM: 160934,
  isPublic: false,
};

Deno.test('mapUltraSignUpResult maps a finished result onto a race run', () => {
  const run = mapUltraSignUpResult(
    { status: 1, formattime: '28:40:15', time: '28:40:15', place: 87 },
    ULTRA_OPTS,
  );
  assert(run !== null);
  assertEquals(run!.source, 'race');
  assertEquals(run!.distance_m, 160934);
  assertEquals(run!.duration_s, 28 * 3600 + 40 * 60 + 15);
  assertEquals(run!.started_at, '2025-06-20T10:00:00Z');
  assertEquals(run!.metadata.chip_time, '28:40:15');
  assertEquals(run!.metadata.overall_place, 87);
  // UltraSignup publishes no bib, and the mapper does not invent one.
  assertEquals(run!.metadata.bib, undefined);
  assertEquals(run!.external_id, 'race:Example Peaks 100 Mile:2025-06-20:');
});

Deno.test('mapUltraSignUpResult falls back to the unformatted time', () => {
  const run = mapUltraSignUpResult({ status: 1, time: '5:01:44' }, ULTRA_OPTS);
  assertEquals(run?.duration_s, 5 * 3600 + 1 * 60 + 44);
});

Deno.test('mapUltraSignUpResult drops every non-finish status', () => {
  // 2 DNF, 3 DNS, 5 DQ, and the rest — a time is no proof of a finish.
  for (const status of [-1, 0, 2, 3, 4, 5, 6, undefined, 'x']) {
    assertEquals(mapUltraSignUpResult({ status, formattime: '4:00:00' }, ULTRA_OPTS), null);
  }
  assertEquals(mapUltraSignUpResult({ status: 2, formattime: '0', time: '0' }, ULTRA_OPTS), null);
  // The feed's number may arrive as a string; it is the same finish.
  assert(mapUltraSignUpResult({ status: '1', formattime: '4:00:00' }, ULTRA_OPTS) !== null);
});

Deno.test('mapUltraSignUpResult dedups with a bib-less paste of the same race', () => {
  const ultra = mapUltraSignUpResult({ status: 1, formattime: '4:32:10' }, ULTRA_OPTS);
  const paste = parseRaceResultRow({ chip_time: '4:32:10' }, ULTRA_OPTS);
  assertEquals(ultra!.external_id, paste!.external_id);
});

Deno.test('parseUltraSignUpDate reads the feed\'s US date with its midnight clock', () => {
  assertEquals(parseUltraSignUpDate('9/25/2025 12:00:00 AM'), '2025-09-25');
  assertEquals(parseUltraSignUpDate('12/1/2024'), '2024-12-01');
  assertEquals(parseUltraSignUpDate('2/30/2025 12:00:00 AM'), null);
  assertEquals(parseUltraSignUpDate('2025-09-25'), null);
  assertEquals(parseUltraSignUpDate(null), null);
});

Deno.test('ultraSignUpNumericId canonicalises an id and refuses anything else', () => {
  assertEquals(ultraSignUpNumericId(138805), '138805');
  assertEquals(ultraSignUpNumericId(' 0138805 '), '138805');
  assertEquals(ultraSignUpNumericId(0), null);
  assertEquals(ultraSignUpNumericId('0'), null);
  assertEquals(ultraSignUpNumericId(-4), null);
  assertEquals(ultraSignUpNumericId(1.5), null);
  assertEquals(ultraSignUpNumericId('12a'), null);
  assertEquals(ultraSignUpNumericId('1234567890123'), null);
  assertEquals(ultraSignUpNumericId(null), null);
});

Deno.test('ultraSignUpNamePart takes real names and nothing a URL could misread', () => {
  assertEquals(ultraSignUpNamePart('  Mary   Ann '), 'Mary Ann');
  assertEquals(ultraSignUpNamePart("O'Brien"), "O'Brien");
  assertEquals(ultraSignUpNamePart('Jean-Luc'), 'Jean-Luc');
  assertEquals(ultraSignUpNamePart('Zoë'), 'Zoë');
  assertEquals(ultraSignUpNamePart('St. John'), 'St. John');
  assertEquals(ultraSignUpNamePart('山田'), '山田');
  for (const bad of ['', '   ', '..', '.', 'a/b', 'a?b', 'a#b', 'a%2F', '-x', 'x1', 7, null]) {
    assertEquals(ultraSignUpNamePart(bad), null, `accepted ${String(bad)}`);
  }
  assertEquals(ultraSignUpNamePart('a'.repeat(ULTRASIGNUP_NAME_MAX_LEN))?.length, ULTRASIGNUP_NAME_MAX_LEN);
  assertEquals(ultraSignUpNamePart('a'.repeat(ULTRASIGNUP_NAME_MAX_LEN + 1)), null);
});

Deno.test('ultraSignUpHistoryUrl puts each name in one encoded path segment', () => {
  assertEquals(
    ultraSignUpHistoryUrl('Mary Ann', 'Zoë'),
    'https://ultrasignup.com/service/events.svc/historybyname/Mary%20Ann/Zo%C3%AB/',
  );
});

Deno.test('ultraSignUpResultIsForListing needs the race id AND the date', () => {
  const r = { event_distance_id: 500101, eventdate: '6/20/2025 12:00:00 AM' };
  const listing = { providerRaceId: '500101', raceDate: '2025-06-20' };
  assertEquals(ultraSignUpResultIsForListing(r, listing), true);
  assertEquals(ultraSignUpResultIsForListing(r, { ...listing, providerRaceId: '500102' }), false);
  assertEquals(ultraSignUpResultIsForListing(r, { ...listing, raceDate: '2025-06-21' }), false);
  assertEquals(ultraSignUpResultIsForListing(r, { ...listing, providerRaceId: '' }), false);
  assertEquals(ultraSignUpResultIsForListing({ ...r, event_distance_id: null }, listing), false);
  assertEquals(ultraSignUpResultIsForListing({ ...r, eventdate: 'soon' }, listing), false);
});

Deno.test('extractUltraSignUpPeople reads a bare array of people and nothing else', () => {
  assertEquals(extractUltraSignUpPeople([{ Id: 1 }, null, 'x', [], { Id: 2 }]).length, 2);
  assertEquals(extractUltraSignUpPeople({ results: [{ Id: 1 }] }).length, 0);
  assertEquals(extractUltraSignUpPeople(null).length, 0);
  const big = Array.from({ length: MAX_RESULTS_ROWS + 5 }, (_, i) => ({ Id: i + 1 }));
  assertEquals(extractUltraSignUpPeople(big).length, MAX_RESULTS_ROWS);
});

Deno.test('ultraSignUpCandidates gives the picker enough to tell namesakes apart', () => {
  const out = ultraSignUpCandidates([
    {
      Id: 900001,
      FirstName: 'Alex',
      LastName: 'Sample',
      Age: 41,
      Results: [
        { eventname: 'Old Race', eventdate: '3/2/2024 12:00:00 AM' },
        { eventname: 'Newest Race', eventdate: '6/20/2025 12:00:00 AM' },
        { eventname: 'Middle Race', eventdate: '4/12/2025 12:00:00 AM' },
      ],
    },
    { Id: 0, FirstName: 'Alex', LastName: 'Sample', Results: [] }, // no usable id
    { Id: 900002, FirstName: 'Alex', LastName: 'Sample', Age: 0, Results: 'nope' },
  ]);
  assertEquals(out.length, 2);
  assertEquals(out[0], {
    id: '900001',
    firstName: 'Alex',
    lastName: 'Sample',
    age: 41,
    resultCount: 3,
    recentEvents: [
      { name: 'Newest Race', date: '2025-06-20' },
      { name: 'Middle Race', date: '2025-04-12' },
    ],
  });
  // Age 0 is the feed's "unknown", not a newborn.
  assertEquals(out[1].age, null);
  assertEquals(out[1].resultCount, 0);
  const many = Array.from({ length: MAX_ULTRASIGNUP_CANDIDATES + 3 }, (_, i) => ({ Id: i + 1 }));
  assertEquals(ultraSignUpCandidates(many).length, MAX_ULTRASIGNUP_CANDIDATES);
});

Deno.test('ultraSignUpScopeGate needs the id and both halves of the name', () => {
  const refused = { ok: false, status: 400, error: 'ultrasignup_person_required' } as const;
  assertEquals(ultraSignUpScopeGate({}), refused);
  assertEquals(ultraSignUpScopeGate({ personId: '900001', firstName: 'Alex' }), refused);
  assertEquals(ultraSignUpScopeGate({ firstName: 'Alex', lastName: 'Sample' }), refused);
  // The old athlete-id shape is not a person.
  assertEquals(ultraSignUpScopeGate({ personId: 'uid-42', firstName: 'A', lastName: 'B' }), refused);
  assertEquals(
    ultraSignUpScopeGate({ personId: 900001, firstName: ' Alex ', lastName: 'Sample' }),
    { ok: true, personId: '900001', firstName: 'Alex', lastName: 'Sample' },
  );
});

Deno.test('ultraSignUpEnabled is off unless the deployment says exactly true', () => {
  assertEquals(ultraSignUpEnabled(() => undefined), false);
  assertEquals(ultraSignUpEnabled(() => '1'), false);
  assertEquals(ultraSignUpEnabled(() => 'TRUE'), false);
  assertEquals(ultraSignUpEnabled((n) => (n === 'ULTRASIGNUP_RESULTS_ENABLED' ? 'true' : undefined)), true);
});

Deno.test('ultraSignUpProbe keeps a client without the person flow dark', () => {
  const on = (n: string) => (n === 'ULTRASIGNUP_RESULTS_ENABLED' ? 'true' : undefined);
  assertEquals(ultraSignUpProbe(on, undefined), {
    ok: false,
    status: 503,
    error: 'provider_not_configured',
    reason: 'client_unsupported',
  });
  assertEquals(ultraSignUpProbe(() => undefined, 'person'), {
    ok: false,
    status: 503,
    error: 'provider_not_configured',
  });
  assertEquals(ultraSignUpProbe(on, 'person').ok, true);
});

Deno.test('chronoTrackConfigured fails closed unless all three creds are set', () => {
  const full: Record<string, string> = {
    CHRONOTRACK_CLIENT_ID: 'cid',
    CHRONOTRACK_USER_ID: 'uid',
    CHRONOTRACK_PASSWORD: 'pw',
  };
  assert(chronoTrackConfigured((n) => full[n]));
  // Any one missing → unconfigured (the dev/CI default is all-unset).
  assertEquals(chronoTrackConfigured(() => undefined), false);
  for (const drop of Object.keys(full)) {
    const partial = { ...full, [drop]: '' };
    assertEquals(chronoTrackConfigured((n) => partial[n]), false);
  }
});

Deno.test('mapChronoTrackResult maps a ChronoTrack finisher onto a race run', () => {
  const run = mapChronoTrackResult(
    {
      results_bib: '1234',
      results_time: '1:47:23',
      results_gun_time: '1:48:01',
      results_rank: 142,
      results_division_rank: 12,
      results_division: 'M35-39',
    },
    OPTS,
  );
  assert(run !== null);
  assertEquals(run!.source, 'race');
  assertEquals(run!.distance_m, 21097);
  assertEquals(run!.duration_s, 1 * 3600 + 47 * 60 + 23);
  // Identical external_id + metadata shaping to the RunSignUp path (shared mapper).
  assertEquals(run!.external_id, 'race:Richmond Half Marathon:2025-09-21:1234');
  assertEquals(run!.metadata.race_name, 'Richmond Half Marathon');
  assertEquals(run!.metadata.bib, '1234');
  assertEquals(run!.metadata.chip_time, '1:47:23');
  assertEquals(run!.metadata.gun_time, '1:48:01');
  assertEquals(run!.metadata.overall_place, 142);
  assertEquals(run!.metadata.age_group_place, 12);
  assertEquals(run!.metadata.age_group, 'M35-39');
});

Deno.test('mapChronoTrackResult falls back to gun time + returns null with no time', () => {
  const gun = mapChronoTrackResult({ results_bib: '5', results_gun_time: '0:30:00' }, OPTS);
  assert(gun !== null);
  assertEquals(gun!.duration_s, 30 * 60);
  assertEquals(gun!.metadata.chip_time, undefined);
  assertEquals(gun!.metadata.gun_time, '0:30:00');
  assertEquals(mapChronoTrackResult({ results_bib: '9' }, OPTS), null);
});

Deno.test('chronoTrackResultsUrl includes creds/format and encodes the event id', () => {
  const url = chronoTrackResultsUrl({
    eventId: 'EVT 42',
    clientId: 'CID',
    userId: 'UID',
    password: 'PASS',
    bib: '77',
  });
  assert(url.startsWith('https://api.chronotrack.com/api/event/EVT%2042/results'));
  assert(url.includes('format=json'));
  assert(url.includes('client_id=CID'));
  assert(url.includes('user_id=UID'));
  assert(url.includes('user_pass=PASS'));
  assert(url.includes('bib=77'));
});

Deno.test('extractChronoTrackResults reads event_results + tolerates results + caps', () => {
  const nested = {
    event_results: [
      { results_bib: '1', results_time: '20:00' },
      { results_bib: '2', results_time: '21:00' },
    ],
  };
  assertEquals(extractChronoTrackResults(nested).length, 2);
  assertEquals(extractChronoTrackResults({ results: [{ results_bib: 'a' }] }).length, 1);
  assertEquals(extractChronoTrackResults(null).length, 0);
  assertEquals(extractChronoTrackResults({}).length, 0);
  const big = {
    event_results: Array.from({ length: MAX_RESULTS_ROWS + 100 }, () => ({ results_bib: 'x' })),
  };
  assertEquals(extractChronoTrackResults(big).length, MAX_RESULTS_ROWS);
});

// ──────────────────────────────────────────────────────────────────
// Synthetic started_at — a race feed carries a date with no start
// clock, so the mapper appends the shared 10:00 UTC time-of-day. Same
// choice + rationale as parkrun-import's parseParkrunDate (persona-hunt
// finding Pro #5), extracted into `SYNTHETIC_START_TIME_UTC` so the two
// importers can't silently diverge. Mirrors parkrun-import/lib.test.ts.

function localDateAt(stampIso: string, offsetHours: number): string {
  const stampMs = Date.parse(stampIso);
  const localMs = stampMs + offsetHours * 3_600_000;
  const d = new Date(localMs);
  const pad = (n: number) => String(n).padStart(2, '0');
  return `${d.getUTCFullYear()}-${pad(d.getUTCMonth() + 1)}-${pad(d.getUTCDate())}`;
}

Deno.test('started_at synthesises the shared 10:00 UTC time on a date with no clock', () => {
  assertEquals(SYNTHETIC_START_TIME_UTC, 'T10:00:00Z');
  const run = mapRunSignUpResult({ bib_num: '1234', chip_time: '1:47:23' }, OPTS);
  assert(run !== null);
  assertEquals(run!.started_at, '2025-09-21T10:00:00Z');
});

Deno.test('started_at local calendar date is preserved at UTC-10 (Hawaii, the bug case)', () => {
  // Pre-fix at T08:00:00Z, Hawaii's UTC-10 offset wrapped a Saturday
  // race back to Friday. T10:00:00Z keeps it on Saturday. Pinned so a
  // future "back to T08" refactor breaks this test.
  const run = mapRunSignUpResult({ bib_num: '1', chip_time: '1:00:00' }, OPTS);
  assertEquals(localDateAt(run!.started_at, -10), '2025-09-21');
});

Deno.test('started_at local calendar date is preserved at UTC+13 (NZ NZDT)', () => {
  const run = mapRunSignUpResult({ bib_num: '1', chip_time: '1:00:00' }, OPTS);
  assertEquals(localDateAt(run!.started_at, 13), '2025-09-21');
});

Deno.test('started_at known limit at UTC+14 (Samoa DST)', () => {
  // No single UTC hour can satisfy every offset in the 26-hour
  // worldwide range. Samoa during DST (UTC+14) is the documented known
  // exception — same acceptable trade as parkrun-import. Pinning the
  // actual behaviour so a future "improve this" attempt has a baseline.
  const run = mapRunSignUpResult({ bib_num: '1', chip_time: '1:00:00' }, OPTS);
  assertEquals(localDateAt(run!.started_at, 14), '2025-09-22');
});

// ── Athlete-scoping guard (issue #360) ───────────────────────────────────────

Deno.test('runSignUpScopeGate rejects an unscoped request 400 runsignup_athlete_id_required', () => {
  // No user id and no bib — the fetch would return the whole finisher field.
  assertEquals(runSignUpScopeGate({}), {
    ok: false,
    status: 400,
    error: 'runsignup_athlete_id_required',
  });
  // Blank / whitespace-only values are not a scope.
  assertEquals(runSignUpScopeGate({ runSignUpUserId: '', bib: '  ' }).ok, false);
});

Deno.test('runSignUpScopeGate accepts a request scoped by user id or bib', () => {
  assertEquals(runSignUpScopeGate({ runSignUpUserId: 'rs-42' }).ok, true);
  assertEquals(runSignUpScopeGate({ bib: '1234' }).ok, true);
  assertEquals(runSignUpScopeGate({ runSignUpUserId: 'rs-42', bib: '1234' }).ok, true);
});

Deno.test('matchResultGate rejects an ambiguous enrich 400 ambiguous_match', () => {
  // 0 or >1 mapped results can't be merged onto the caller's one run.
  assertEquals(matchResultGate(0), { ok: false, status: 400, error: 'ambiguous_match' });
  assertEquals(matchResultGate(2), { ok: false, status: 400, error: 'ambiguous_match' });
  assertEquals(matchResultGate(150), { ok: false, status: 400, error: 'ambiguous_match' });
});

Deno.test('matchResultGate accepts exactly one mapped result', () => {
  assertEquals(matchResultGate(1), { ok: true });
});

Deno.test('filterResultsByBib narrows a mapped field to the requested bib', () => {
  const field: MappedRaceRun[] = [
    mapRunSignUpResult({ bib_num: '1', chip_time: '20:00' }, OPTS)!,
    mapRunSignUpResult({ bib_num: '1234', chip_time: '1:47:23' }, OPTS)!,
    mapRunSignUpResult({ bib_num: '9', chip_time: '25:00' }, OPTS)!,
  ];
  const one = filterResultsByBib(field, '1234');
  assertEquals(one.length, 1);
  assertEquals(one[0].metadata.bib, '1234');
  // A trimmed bib still matches the capField-normalised stored value.
  assertEquals(filterResultsByBib(field, ' 1234 ').length, 1);
  // No match → empty (the standalone insert then imports nothing, the match
  // path then rejects ambiguous_match on length 0).
  assertEquals(filterResultsByBib(field, 'nope').length, 0);
  // A blank bib is a no-op (user-id narrowing already applied upstream).
  assertEquals(filterResultsByBib(field, '').length, 3);
});

// End-to-end shape the EF enforces for the RunSignUp leg (issue #360): a
// full field of finishers, unscoped, is rejected before any insert; scoped to a
// bib it narrows to exactly one; that one result clears the enrich gate.
Deno.test('EF gate flow: unscoped rejected, bib-scoped enriches exactly one', () => {
  const field: MappedRaceRun[] = [
    mapRunSignUpResult({ bib_num: '1', chip_time: '18:00' }, OPTS)!, // the winner
    mapRunSignUpResult({ bib_num: '77', chip_time: '55:10' }, OPTS)!, // the caller
    mapRunSignUpResult({ bib_num: '9', chip_time: '25:00' }, OPTS)!,
  ];
  // 1. Standalone import with no scope → rejected, nothing mapped/inserted.
  assertEquals(runSignUpScopeGate({}).error, 'runsignup_athlete_id_required');
  // 2. Match import with no scope → same pre-fetch rejection.
  assertEquals(runSignUpScopeGate({ bib: '' }).ok, false);
  // 3. Scoped by the caller's bib → mapped narrows to one, enrich gate passes.
  assertEquals(runSignUpScopeGate({ bib: '77' }).ok, true);
  const narrowed = filterResultsByBib(field, '77');
  assertEquals(narrowed.length, 1);
  assertEquals(narrowed[0].metadata.bib, '77');
  assertEquals(matchResultGate(narrowed.length).ok, true);
  // 4. Scoped, but the whole field slips through unfiltered → enrich rejected
  //    rather than stamping mapped[0] (the winner) onto the caller's run.
  assertEquals(matchResultGate(field.length).error, 'ambiguous_match');
});

Deno.test('chronoTrackScopeGate — a bib-less request is rejected before any fetch', () => {
  // chronoTrackResultsUrl only narrows upstream when a bib is supplied, so an
  // unscoped request pulls the WHOLE finisher field and mapChronoTrackResult
  // stamps the caller's user_id on all 2000 of them — the winner's 2:09 lands
  // as the caller's marathon PR. Same fail-closed rule the RunSignUp leg has.
  const gate = chronoTrackScopeGate({});
  assertEquals(gate.ok, false);
  assertEquals(gate.status, 400);
  assertEquals(gate.error, 'chronotrack_bib_required');
});

Deno.test('chronoTrackScopeGate — a blank bib does not count as scoped', () => {
  assertEquals(chronoTrackScopeGate({ bib: '   ' }).ok, false);
});

Deno.test('chronoTrackScopeGate — a bib scopes the request', () => {
  assertEquals(chronoTrackScopeGate({ bib: '1423' }).ok, true);
});

Deno.test('a race whose date is unusable maps to nothing, not to an unparseable stamp', () => {
  // `public_race_listings` is a view, so the generated type cannot carry the
  // base table's NOT NULL and the handler resolves the column with `?? ''`.
  // Appended to the synthetic clock that gave the literal `T10:00:00Z`, which
  // `timestamptz` cannot parse — and because the mapped rows go in as ONE
  // batch, a single unattributable date used to 22007 the whole race rather
  // than dropping one result. Same rule the distance already had.
  const row = { chip_time: '1:45:00', bib_num: '55' };
  for (const raceDate of ['', 'T10:00:00Z', '2025-9-21', '21/09/2025', '2025-02-30', '0000-01-01']) {
    assertEquals(
      mapRunSignUpResult(row, { ...OPTS, raceDate }),
      null,
      raceDate,
    );
  }
  // The positive control: the same row against a real date still maps, so the
  // refusals above are about the date and nothing else.
  const ok = mapRunSignUpResult(row, OPTS);
  assert(ok);
  assertEquals(ok.started_at, `2025-09-21${SYNTHETIC_START_TIME_UTC}`);
});

Deno.test('isIsoCalendarDate accepts the date half only, and the real calendar', () => {
  assertEquals(isIsoCalendarDate('2025-09-21'), true);
  assertEquals(isIsoCalendarDate('2024-02-29'), true, 'a leap day is a day');
  assertEquals(isIsoCalendarDate('2025-02-29'), false, 'and only in a leap year');
  assertEquals(isIsoCalendarDate('1900-02-29'), false, 'the century rule is the calendar\'s');
  assertEquals(isIsoCalendarDate('2000-02-29'), true, 'and so is its exception');
  assertEquals(isIsoCalendarDate('2025-04-31'), false);
  assertEquals(isIsoCalendarDate('2025-13-01'), false);
  assertEquals(isIsoCalendarDate('2025-00-01'), false);
  // A value carrying its own clock is refused: appending the synthetic one
  // would put two times in a single literal.
  assertEquals(isIsoCalendarDate('2025-09-21T00:00:00Z'), false);
  assertEquals(isIsoCalendarDate(null), false);
  assertEquals(isIsoCalendarDate(20250921), false);
});

// Imported finisher names land in one batch insert, so half an emoji at the
// cap (or a lone escape in the provider's JSON) failed every result with it.
Deno.test('capField never leaves half a surrogate pair, at the cap or in the input', () => {
  const capped = capField('a'.repeat(MAX_FIELD_LEN - 1) + '\u{1F3C3}xyz');
  assertEquals(capped, 'a'.repeat(MAX_FIELD_LEN - 1));
  assertEquals(capField('Ana\uD83C Silva'), 'Ana Silva');
});
