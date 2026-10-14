/// The UltraSignup leg attributes a result to a listing only when the RESULT
/// says it belongs there.
///
/// Until decisions § 1841 the leg read an athlete feed whose rows named no race,
/// so every row was mapped through the one listing the request named — a 2:58
/// road marathon became a 2:58 hundred-miler — and the leg refused outright
/// (§ 975). The feed UltraSignup really serves, `historybyname`, answers with
/// every same-named PERSON, and each of their results names its race in
/// `event_distance_id`. These tests pin both choices against an anonymised
/// sample of that payload (`fixtures/ultrasignup_historybyname.json`: the field
/// set and value shapes of a real 2026-10-13 response, with every name, id,
/// race and place replaced):
///
///   - the person: only the picked `Id`'s results are considered, though a
///     namesake ran the same race on the same day;
///   - the race: only the result whose `event_distance_id` AND date are the
///     listing's becomes a run, and a DNF never does.
///
/// Run with `cd apps/backend && deno test --no-check --allow-read
/// supabase/functions/race-results-import/ultrasignup_attribution.test.ts`.

import { assert, assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { ultraSignUpImportRows } from './lib.ts';

const PAYLOAD: unknown = JSON.parse(
  Deno.readTextFileSync(new URL('./fixtures/ultrasignup_historybyname.json', import.meta.url)),
);
const SRC = Deno.readTextFileSync(new URL('./handler.ts', import.meta.url));

/// The listing for the race both namesakes ran.
const PEAKS = {
  userId: 'u-1',
  listingId: 'L-peaks',
  raceName: 'Example Peaks 100 Mile',
  raceDate: '2025-06-20',
  distanceM: 160934,
  isPublic: false,
  providerRaceId: '500101',
};

Deno.test('one listing takes one result: the runner\'s own, for that race', () => {
  const rows = ultraSignUpImportRows(PAYLOAD, { ...PEAKS, personId: '900001' });
  assert(rows.personFound);
  // Four results in the history, one of them this race.
  assertEquals(rows.considered, 4);
  assertEquals(rows.mapped.length, 1);
  const run = rows.mapped[0];
  assertEquals(run.race_listing_id, 'L-peaks');
  assertEquals(run.duration_s, 28 * 3600 + 40 * 60 + 15);
  assertEquals(run.metadata.overall_place, 87);
  assertEquals(run.started_at, '2025-06-20T10:00:00Z');
});

Deno.test('the namesake who ran the same race is not the runner', () => {
  // Same name, same race, same day — only the `Id` tells them apart, and it is
  // the one the runner picked that decides whose time becomes theirs.
  const mine = ultraSignUpImportRows(PAYLOAD, { ...PEAKS, personId: '900001' });
  const theirs = ultraSignUpImportRows(PAYLOAD, { ...PEAKS, personId: '900002' });
  assertEquals(mine.mapped.map((r) => r.duration_s), [28 * 3600 + 40 * 60 + 15]);
  assertEquals(theirs.mapped.map((r) => r.duration_s), [31 * 3600 + 5 * 60 + 2]);
});

Deno.test('a history never spreads across a listing: the other races are dropped', () => {
  // The exact § 975 measurement, inverted. The marathon and the 50K are in the
  // same history; neither may land on the 100-miler's listing.
  const rows = ultraSignUpImportRows(PAYLOAD, { ...PEAKS, personId: '900001' });
  assertEquals(new Set(rows.mapped.map((r) => r.race_listing_id)).size, 1);
  assert(!rows.mapped.some((r) => r.duration_s === 2 * 3600 + 58 * 60 + 44));
  assert(!rows.mapped.some((r) => r.duration_s === 4 * 3600 + 32 * 60 + 10));
});

Deno.test('the race id alone is not enough: a listing on another date takes nothing', () => {
  // `provider_race_id` comes from a listing sync whose field is unverified, and
  // UltraSignup numbers events and distances in separate integer spaces. A
  // listing whose id matches by coincidence must also match on the date.
  const rows = ultraSignUpImportRows(PAYLOAD, {
    ...PEAKS,
    raceDate: '2026-06-19',
    personId: '900001',
  });
  assert(rows.personFound);
  assertEquals(rows.mapped, []);
});

Deno.test('a listing for another race takes that race only', () => {
  const rows = ultraSignUpImportRows(PAYLOAD, {
    ...PEAKS,
    listingId: 'L-canyon',
    raceName: 'Sample Canyon 50K',
    raceDate: '2025-04-12',
    distanceM: 50000,
    providerRaceId: '500102',
    personId: '900001',
  });
  assertEquals(rows.mapped.map((r) => r.duration_s), [4 * 3600 + 32 * 60 + 10]);
});

Deno.test('a DNF is not a run, even on its own listing', () => {
  const rows = ultraSignUpImportRows(PAYLOAD, {
    ...PEAKS,
    listingId: 'L-ridge',
    raceName: 'Placeholder Ridge 100K',
    raceDate: '2024-09-27',
    distanceM: 100000,
    providerRaceId: '500103',
    personId: '900001',
  });
  assert(rows.personFound);
  assertEquals(rows.mapped, []);
});

Deno.test('a stored person the name no longer answers with is reported, not imported', () => {
  const rows = ultraSignUpImportRows(PAYLOAD, { ...PEAKS, personId: '123456' });
  assertEquals(rows, { personFound: false, considered: 0, mapped: [] });
});

Deno.test('the attribution gate is gone and the import goes through the attributing helper', () => {
  // The refusal is lifted because the leg can now attribute, not because the
  // three lines were deleted (the followups entry's warning). Pin that the
  // branch maps through `ultraSignUpImportRows` and nothing else, and that it
  // scopes the person before it fetches.
  assert(!SRC.includes('ultraSignUpAttributionGate'), 'the old refusal is still wired');
  const branch = SRC.indexOf("} else if (provider === 'ultrasignup') {");
  const end = SRC.indexOf("} else if (provider === 'chronotrack') {", branch);
  assert(branch !== -1 && end !== -1, 'the ultrasignup branch is gone — re-anchor this guard');
  const body = SRC.slice(branch, end);
  const scope = body.indexOf('ultraSignUpScopeGate(');
  const fetchAt = body.indexOf('await readUpstream(');
  assert(scope !== -1 && fetchAt !== -1 && scope < fetchAt, 'the person must be scoped before the fetch');
  assert(body.includes('ultraSignUpImportRows('), 'the branch no longer maps through the attributing helper');
  assert(!body.includes('mapUltraSignUpResult('), 'the branch maps rows without attributing them');
});
