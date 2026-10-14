/// The edges of a RunSignUp result row that decide whether a runner gets the
/// right run, a wrong one, or none: hundredths at the edge of a minute or an
/// hour, a chip time that is present but blank, a DNF or DNS row with no time,
/// and the age-group heuristic when the row does not say which division is the
/// runner's age group. lib.test.ts pins the common shapes from the recorded
/// fixture; these are the boundaries around them.
///
/// Run with `cd apps/backend && deno test --no-check --allow-read --allow-env
/// supabase/functions/race-results-import/runsignup_rows.test.ts`.

import { assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { mapRunSignUpResult, parseClockToSeconds, runSignUpAgeGroup } from './lib.ts';

const OPTS = {
  userId: 'u-1',
  listingId: 'L-1',
  raceName: 'Example 5K',
  raceDate: '2026-09-19',
  distanceM: 5000,
  isPublic: false,
};

Deno.test('hundredths round up across a minute and an hour, never down and never to a fraction', () => {
  // `runs.duration_s` is an integer; a fraction fails the whole insert, and a
  // round-down would hand a runner a time they did not run.
  assertEquals(parseClockToSeconds('59.995'), 60);
  assertEquals(parseClockToSeconds('0:59.995'), 60);
  assertEquals(parseClockToSeconds('59:59.995'), 3600);
  assertEquals(parseClockToSeconds('1:59:59.995'), 7200);
  assertEquals(parseClockToSeconds('2:59:59.01'), 3 * 3600);
  assertEquals(parseClockToSeconds('19:59.00'), 20 * 60 - 1, 'an exact second stays put');
  for (const t of ['59.995', '1:59:59.995', '21:43.34', '3:05:12.5']) {
    assertEquals(Number.isInteger(parseClockToSeconds(t)), true, t);
  }
});

Deno.test('a blank or whitespace chip time falls back to clock time; a real chip time wins', () => {
  const run = (chip: unknown, clock: unknown) =>
    mapRunSignUpResult({ result: { bib: 336, place: 10, chip_time: chip, clock_time: clock }, headers: {} }, OPTS);
  assertEquals(run('', '21:41.08')!.duration_s, 21 * 60 + 42);
  assertEquals(run('   ', '21:41.08')!.duration_s, 21 * 60 + 42);
  assertEquals(run(null, '21:41.08')!.duration_s, 21 * 60 + 42);
  assertEquals(run('21:23.75', '21:41.08')!.duration_s, 21 * 60 + 24, 'chip is the runner\'s own time');
});

Deno.test('a row with no time is refused cleanly, not filed as a zero-second run', () => {
  const run = (chip: unknown, clock: unknown) =>
    mapRunSignUpResult({ result: { bib: 401, place: null, chip_time: chip, clock_time: clock }, headers: {} }, OPTS);
  assertEquals(run('', ''), null, 'a DNF row as the feed writes it');
  assertEquals(run(null, null), null);
  assertEquals(run('DNF', ''), null);
  assertEquals(run('', 'DNS'), null);
  assertEquals(run('0:00:00', ''), null);
  assertEquals(run('', '00:00.00'), null);
  // The positive control: the same row with a time is a run.
  assertEquals(run('', '25:00')!.duration_s, 1500);
});

Deno.test('the age group is set only when exactly one placed division carries an age', () => {
  const headers = {
    'division-1-placement': 'M Overall',
    'division-2-placement': 'M2029',
    'division-3-placement': 'M 20-29',
    'division-4-placement': 'Clydesdale',
    'custom-field-5': 'Top 10',
  };
  const ag = (result: Record<string, unknown>) => runSignUpAgeGroup({ result, headers });
  // A place written as text is still a place.
  assertEquals(ag({ 'division-2-placement': '4' }), { label: 'M2029', place: 4 });
  // An unplaced division (0, '', null) does not count toward the two.
  assertEquals(ag({ 'division-2-placement': 4, 'division-3-placement': 0 }), { label: 'M2029', place: 4 });
  assertEquals(ag({ 'division-2-placement': 4, 'division-3-placement': '' }), { label: 'M2029', place: 4 });
  // Placed in no age division, only the overall and a non-age one: unset.
  assertEquals(ag({ 'division-1-placement': 1, 'division-4-placement': 2 }), null);
  // Placed in two age schemes at once: ambiguous, so unset, not the first.
  assertEquals(ag({ 'division-2-placement': 4, 'division-3-placement': 3 }), null);
  // A digit in a column that is not a division placement is not an age group.
  assertEquals(ag({ 'custom-field-5': 1 }), null);
  // A placement whose division the set never named carries no label to report.
  assertEquals(ag({ 'division-9-placement': 2 }), null);
  // What the mapper files follows: an unset age group writes no key at all.
  const run = mapRunSignUpResult(
    { result: { bib: 1, chip_time: '17:00', 'division-2-placement': 4, 'division-3-placement': 3 }, headers },
    OPTS,
  )!;
  assertEquals([run.metadata.age_group, run.metadata.age_group_place], [undefined, undefined]);
});
