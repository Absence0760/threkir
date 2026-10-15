/// The edges of a RunSignUp result row that decide whether a runner gets the
/// right run, a wrong one, or none: hundredths at the edge of a minute or an
/// hour, a chip time that is present but blank, a DNF or DNS row with no time,
/// and the age-group recogniser when the row does not say which division is the
/// runner's age group. lib.test.ts pins the common shapes from the recorded
/// fixture; these are the boundaries around them.
///
/// Run with `cd apps/backend && deno test --no-check --allow-read --allow-env
/// supabase/functions/race-results-import/runsignup_rows.test.ts`.

import { assert, assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import {
  extractRunSignUpResults,
  mapRunSignUpResult,
  parseClockToSeconds,
  runSignUpAgeGroup,
} from './lib.ts';

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

// Division names as RunSignUp races write them, from the headers of 826 public
// events across 297 races fetched 2026-10-14 (decisions § 1913), plus the
// hypotheticals the follow-up named (`Wave 2`, `Team 5`, `2025 Series`,
// `Clydesdale 200+`). `true` is an age group. Every `false` but `Open` carries
// a digit, so the rule this replaced (any placed division with a digit in its
// name) filed each of them as the runner's age group.
const DIVISION_NAMES: Array<[string, boolean]> = [
  ['M2029', true],
  ['F0119', true],
  ['X3039', true],
  ['F80120', true],
  ['F 30-39', true],
  ['M 0- 9', true],
  ['F_01-10', true],
  ['Male 40-49', true],
  ['Men 25-29', true],
  ['Female 20 to 29', true],
  ['F - 12 to 19', true],
  ['Ages 18-24', true],
  ['30-39 Female', true],
  ['15 to 19', true],
  ['Female 70 and Over', true],
  ["Men's 40 and Over", true],
  ['FEMALE - 62 and Older', true],
  ['Female 70 Plus', true],
  ['M75+', true],
  ['80 +', true],
  ['Female 14 & Under', true],
  ['19 & Under', true],
  ['60 and over', true],
  ['Under 18', true],
  ['F14&UND', true],
  ['M14U', true],
  ['MU14', true],
  ['M 10-', true],
  ['Boys age 10', true],
  ['Age 6', true],
  ['5K_F30-39', true],
  ['10K_M15&UND', true],
  ['1M_F40+', true],
  // Weight classes, banded by age themselves, place a runner instead of their
  // age group.
  ['Clydesdale 40 and Over', false],
  ['Clydesdale 39 and Under', false],
  ['M Clydesdale Under 40', false],
  ['F Athena 40 & Over', false],
  ['Athena 39 and Under', false],
  ['Clydesdale 200+', false],
  ['Athena 150+', false],
  // Overall and masters awards lift a runner out of the age groups.
  ['M Top 3 Overall', false],
  ['F Top 3', false],
  ['Top 10 Female', false],
  ['Top 10', false],
  ['M Masters (40+)', false],
  ['Masters 40+', false],
  // A catch-all covering the whole field, and placeholders.
  ['M 1-99', false],
  ['F 0-99', false],
  ['X01100', false],
  ['F 00-00', false],
  ['Male 99 and Under', false],
  // Other awards and things that are not ages at all.
  ['2 Person Team', false],
  ['Team 5', false],
  ['Wave 2', false],
  ['2025 Series', false],
  ['M PH 30-39', false],
  ['M ATD2', false],
  ['10K DEL BICENTENARIO LIBRE DAMAS', false],
  ['F - 45668', false],
  ['14-Jan', false],
  ['200+', false],
  ['M125129', false],
  ['M30-24', false],
  // Shapes too ambiguous to read: unset rather than guessed.
  ['2029', false],
  ['M14', false],
  ['M114', false],
  ['Female 80', false],
  ['Open', false],
];

Deno.test('a placed division is the age group only when its name is an age band', () => {
  for (const [name, isAgeGroup] of DIVISION_NAMES) {
    const headers = { 'division-7-placement': name };
    assertEquals(
      runSignUpAgeGroup({ result: { 'division-7-placement': 3 }, headers }),
      isAgeGroup ? { label: name, place: 3 } : null,
      name,
    );
  }
});

Deno.test('a weight-class or overall winner keeps no age group, and an age band beside the award still counts', () => {
  // Placed in an award AND an age band is one age band, not two.
  const headers = {
    'division-1-placement': 'Clydesdale 40 and Over',
    'division-2-placement': 'M Top 3 Overall',
    'division-3-placement': 'M 40-44',
  };
  assertEquals(
    runSignUpAgeGroup({
      result: { 'division-1-placement': 1, 'division-2-placement': 2, 'division-3-placement': 5 },
      headers,
    }),
    { label: 'M 40-44', place: 5 },
  );
});

/// The runner's own age, read against a band label in the two recorded sets.
function ageInBand(label: string, age: number): boolean {
  const range = /(\d+)-(\d+)$/.exec(label);
  if (range) return age >= Number(range[1]) && age <= Number(range[2]);
  const over = /(\d+)\+$/.exec(label);
  if (over) return age >= Number(over[1]);
  const under = /(\d+)-$/.exec(label);
  if (under) return age <= Number(under[1]);
  throw new Error(`no band in ${label}`);
}

function recorded(file: string) {
  const payload = JSON.parse(Deno.readTextFileSync(new URL(`./fixtures/${file}`, import.meta.url)));
  return extractRunSignUpResults(payload).map((row) => ({
    bib: row.result.bib as number,
    age: row.result.age as number,
    ageGroup: runSignUpAgeGroup(row),
  }));
}

Deno.test('recorded sets: weight classes and overall awards stay unset, every age group holds the runner', () => {
  // A triathlon with age-banded Clydesdale divisions and a second, unplaced
  // `M 40-44` scheme beside the placed `Men 40-44` one; and a duathlon with
  // Top 3 Overall, Clydes, Athena and the `M 10-` / `M 75+` open ends. One row
  // per distinct placement, names and cities replaced.
  const tri = recorded('runsignup_results_clydesdale_bands.json');
  const du = recorded('runsignup_results_top3_weight_classes.json');
  const byBib = new Map([...tri, ...du].map((r) => [r.bib, r.ageGroup?.label ?? null]));
  // Clydesdale 40 and Over, Clydesdale 39 and Under.
  assertEquals([byBib.get(3496), byBib.get(3461)], [null, null]);
  // M / F Top 3 Overall, M Clydes, F Athena.
  assertEquals([byBib.get(207), byBib.get(147), byBib.get(242), byBib.get(251)], [null, null, null, null]);
  assertEquals([byBib.get(6841), byBib.get(222), byBib.get(296)], ['Men 40-44', 'M 75+', 'M 10-']);
  // Rows placed in an age band: every one is read, and holds the runner's age.
  const placed = [...tri, ...du].filter((r) => r.ageGroup !== null);
  assertEquals([tri.filter((r) => r.ageGroup).length, du.filter((r) => r.ageGroup).length], [21, 26]);
  for (const r of placed) assert(ageInBand(r.ageGroup!.label, r.age), `${r.bib} ${r.age} ${r.ageGroup!.label}`);
});
