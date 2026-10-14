/// The provider race-calendar sync's readings, caps and reconciliation.
///
/// The RunSignUp reader is pinned against a trimmed copy of the live, keyless
/// `GET /Rest/races` payload (`fixtures/runsignup_races.json`, 2026-10-14). The
/// UltraSignup one is still unverified, so for it what is pinned is that a row
/// which does not yield the two things `race_listings` requires becomes nothing
/// and is COUNTED, rather than becoming a race on a public calendar with a
/// guessed name or a transposed date (decisions § 977).
///
/// Run with `cd apps/backend && deno test --no-check --allow-read --allow-env
/// supabase/functions/race-listings-sync/lib.test.ts`.

import { assert, assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import {
  DEFAULT_NEAR_RADIUS_M,
  EXCLUDED,
  MAX_LISTING_LOCATION_LEN,
  MAX_LISTING_NAME_LEN,
  MAX_LISTING_ROWS,
  MAX_NEAR_RADIUS_M,
  type RaceListingUpsert,
  type StoredListing,
  distanceMetresFrom,
  extractProviderRaces,
  listingDiffers,
  listingUpsertFrom,
  listingUrl,
  type NormalisedRace,
  nearHintError,
  parseNearHint,
  parseRunSignUpDistance,
  parseProviderRaceDate,
  providerRacesUrl,
  readProviderRace,
  readRunSignUpRace,
  readUltraSignUpRace,
  reconcileListingBatch,
} from './lib.ts';

const MIGRATIONS = new URL('../../migrations/', import.meta.url).pathname;

const LIVE = JSON.parse(
  await Deno.readTextFile(new URL('./fixtures/runsignup_races.json', import.meta.url)),
);

function asRace(r: unknown): NormalisedRace {
  assert(r !== null && r !== EXCLUDED && typeof r === 'object', `expected a race, got ${r}`);
  return r as NormalisedRace;
}

Deno.test('the field caps are the columns own CHECK constraints, not numbers picked here', () => {
  // A composer capping LOWER than the column is merely conservative; one capping
  // higher hands the batch a 23514 that loses every other race in it. So the
  // caps are read back out of the migration that declares them.
  const sql = Deno.readTextFileSync(`${MIGRATIONS}20270503_001_free_text_length_caps.sql`);
  const name = /race_listings_name_len_chk\s*\n?\s*check \(name is null or char_length\(name\) <= (\d+)\)/
    .exec(sql);
  const loc =
    /race_listings_location_label_len_chk\s*\n?\s*check \(location_label is null or char_length\(location_label\) <= (\d+)\)/
      .exec(sql);
  assert(name && loc, 'the length CHECKs are no longer in 20270503_001 — re-anchor this guard');
  assert(
    MAX_LISTING_NAME_LEN <= Number(name![1]),
    `name cap ${MAX_LISTING_NAME_LEN} exceeds the column's ${name![1]}`,
  );
  assert(
    MAX_LISTING_LOCATION_LEN <= Number(loc![1]),
    `location cap ${MAX_LISTING_LOCATION_LEN} exceeds the column's ${loc![1]}`,
  );
});

Deno.test('an ISO date is taken whole and a time suffix is dropped', () => {
  assertEquals(parseProviderRaceDate('2027-06-20'), '2027-06-20');
  assertEquals(parseProviderRaceDate('2027-06-20T08:30:00Z'), '2027-06-20');
  assertEquals(parseProviderRaceDate('2027-06-20 08:30'), '2027-06-20');
  assertEquals(parseProviderRaceDate('2027-02-29'), null, 'not a leap year');
  assertEquals(parseProviderRaceDate('2028-02-29'), '2028-02-29');
  assertEquals(parseProviderRaceDate('2027-13-01'), null);
});

Deno.test('a slash date is read US month-first, and refused when it cannot be', () => {
  assertEquals(parseProviderRaceDate('6/20/2027'), '2027-06-20');
  assertEquals(parseProviderRaceDate('06/05/2027'), '2027-06-05');
  // The tripwire. A day-first feed announces itself on the first race past the
  // 12th of a month rather than seeding the calendar with transposed dates.
  assertEquals(parseProviderRaceDate('20/06/2027'), null);
  assertEquals(parseProviderRaceDate('13/01/2027'), null);
  assertEquals(parseProviderRaceDate('2/31/2027'), null, 'the calendar still applies');
  assertEquals(parseProviderRaceDate(''), null);
  assertEquals(parseProviderRaceDate(null), null);
  assertEquals(parseProviderRaceDate(20270620), null);
});

Deno.test('a distance is converted, and an unknown unit is null rather than assumed', () => {
  assertEquals(distanceMetresFrom(26.2, 'miles'), 42165);
  assertEquals(distanceMetresFrom(26.2, 'mi'), 42165);
  assertEquals(distanceMetresFrom(5, 'K'), 5000);
  assertEquals(distanceMetresFrom(42195, undefined), 42195, 'a bare number is already metres');
  assertEquals(distanceMetresFrom(42195, 'metres'), 42195);
  // The one that matters. US race listings write MILES as `M` and SI writes
  // METRES as `m`; a case-insensitive table collapses them and files a 100-mile
  // race as a 100-metre one, and a case-sensitive one silently picks a reading
  // of a letter whose meaning in this feed has not been observed. Both readings
  // are refused, so the race keeps a null distance instead of somebody else's
  // band.
  assertEquals(distanceMetresFrom(100, 'M'), null);
  assertEquals(distanceMetresFrom(42195, 'm'), null);
  // `search_race_listings` buckets distance into race bands, so a guessed unit
  // files a 5K under "ultra".
  assertEquals(distanceMetresFrom(5, 'furlongs'), null);
  assertEquals(distanceMetresFrom(0, 'km'), null);
  assertEquals(distanceMetresFrom(-5, 'km'), null);
  assertEquals(distanceMetresFrom('not a number', 'km'), null);
  assertEquals(distanceMetresFrom(Infinity, 'km'), null);
});

Deno.test('a url the column would refuse is dropped, not written', () => {
  // `race_listings_entry_url_scheme_check` is `~* '^https?://'`; a value that
  // fails it raises 23514 and takes the whole batch insert with it.
  assertEquals(listingUrl('https://runsignup.com/Race/X'), 'https://runsignup.com/Race/X');
  assertEquals(listingUrl('http://x.test/r'), 'http://x.test/r');
  assertEquals(listingUrl('runsignup.com/Race/X'), null);
  assertEquals(listingUrl('javascript:alert(1)'), null);
  assertEquals(listingUrl(''), null);
  assertEquals(listingUrl(undefined), null);
});

Deno.test('a RunSignUp row without a name or a date becomes nothing', () => {
  assertEquals(readRunSignUpRace({ race_id: 1, next_date: '06/20/2027' }), null);
  assertEquals(readRunSignUpRace({ race_id: 1, name: 'Bighorn' }), null);
  assertEquals(readRunSignUpRace({}), null);
});

Deno.test('the live RunSignUp payload maps, race by race', () => {
  const rows = extractProviderRaces(LIVE);
  assertEquals(rows.length, 3, 'every `races[].race` is unwrapped');
  const [bacon, best, virtualOnly] = rows.map((r) => readProviderRace('runsignup', r));

  // A 5K run beside a 1-mile walk: the walk never decides the distance, and
  // `3.1 Miles` lands in the 5k band (4500-5500) `search_race_listings` uses.
  const b = asRace(bacon);
  assertEquals(b.providerRaceId, '68640');
  assertEquals(b.date, '2027-06-12', '`next_date` 06/12/2027, a date with no zone shift');
  assertEquals(b.distanceM, 4989);
  assertEquals(b.locationLabel, 'Port Huron, MI, US');
  assertEquals(b.entryUrl, 'https://runsignup.com/Race/MI/PortHuron/BaconandBubbles5k1Mile');
  assertEquals(b.resultsUrl, null, '`external_results_url` is null in the feed');
  assert(b.name.startsWith('"Bacon & Bubbles" 5K'));

  // 5K / 10K / 13.1 Miles on one morning files under the longest.
  assertEquals(asRace(best).distanceM, 21082);

  // Both events are `virtual_race`: there is no start line to put on a map.
  assertEquals(virtualOnly, EXCLUDED);
});

Deno.test('drafts, private races and races with no in-person running event are excluded', () => {
  const base = { race_id: 1, name: 'R', next_date: '06/20/2027' };
  assertEquals(readRunSignUpRace({ ...base, is_draft_race: 'T' }), EXCLUDED);
  assertEquals(readRunSignUpRace({ ...base, is_private_race: 'T' }), EXCLUDED);
  assertEquals(
    readRunSignUpRace({ ...base, events: [{ event_type: 'walking_only', distance: '5K' }] }),
    EXCLUDED,
  );
  assertEquals(
    readRunSignUpRace({
      ...base,
      events: [{ event_type: 'running_race', distance: '50K', volunteer: 'T' }],
    }),
    EXCLUDED,
    'a volunteer slot is not a race',
  );
  // No events expansion at all is not evidence of anything: file it with no
  // distance rather than refuse it.
  assertEquals(asRace(readRunSignUpRace({ ...base, is_draft_race: 'F' })).distanceM, null);
  // A running event whose distance is unreadable still makes it a race.
  assertEquals(
    asRace(readRunSignUpRace({ ...base, events: [{ event_type: 'trail_race', distance: null }] }))
      .distanceM,
    null,
  );
  // A past race with no next running still files, for a results import.
  assertEquals(
    asRace(readRunSignUpRace({ race_id: 7, name: 'Old', last_date: '05/04/2019' })).date,
    '2019-05-04',
  );
});

Deno.test('a RunSignUp distance reads every spelling the live feed uses', () => {
  assertEquals(parseRunSignUpDistance('5K'), 5000);
  assertEquals(parseRunSignUpDistance('50K'), 50000);
  assertEquals(parseRunSignUpDistance('3.1K'), 3100);
  assertEquals(parseRunSignUpDistance('3.1 Miles'), 4989);
  assertEquals(parseRunSignUpDistance('1 Miles'), 1609);
  assertEquals(parseRunSignUpDistance('26.2 Miles'), 42165);
  assertEquals(parseRunSignUpDistance('100 Miles'), 160934);
  assertEquals(parseRunSignUpDistance('100 Yards'), 91);
  assertEquals(parseRunSignUpDistance('10 Kilometers'), 10000);
  assertEquals(parseRunSignUpDistance('Half Marathon'), 21098);
  assertEquals(parseRunSignUpDistance('marathon'), 42195);
  // A glued lower-case `m` is metres in this feed (`100m`, `5000m`, `1600m`);
  // a capital `M` is still refused, since a US listing could mean miles by it.
  assertEquals(parseRunSignUpDistance('5000m'), 5000);
  assertEquals(parseRunSignUpDistance('1600m'), 1600);
  assertEquals(parseRunSignUpDistance('100M'), null);
  assertEquals(parseRunSignUpDistance('5 furlongs'), null);
  assertEquals(parseRunSignUpDistance('Fun Run'), null);
  assertEquals(parseRunSignUpDistance(null), null);
  assertEquals(parseRunSignUpDistance(''), null);
});

Deno.test('an over-long name is capped rather than refused by the column', () => {
  const reading = readRunSignUpRace({
    race_id: 1,
    name: 'x'.repeat(400),
    next_date: '2027-06-20',
    address: { city: 'y'.repeat(200), state: 'z'.repeat(200) },
  });
  const race = reading === EXCLUDED ? null : reading;
  // `typeof` rather than a null test: a reader that answers `undefined` gives
  // `race?.name.length` the same `undefined` the cap constant would have, and
  // two absent values compare equal. The vacuity operator scored this case as
  // surviving until the check named a string.
  assert(typeof race?.name === 'string', 'the reader produced no name to cap');
  assert(typeof race!.locationLabel === 'string', 'the reader produced no location to cap');
  assertEquals(race!.name.length, MAX_LISTING_NAME_LEN);
  assertEquals(race!.locationLabel!.length, MAX_LISTING_LOCATION_LEN);
});

Deno.test('an UltraSignup row reads its own spellings and nobody elses', () => {
  const race = readUltraSignUpRace({
    eventid: 91234,
    eventname: 'Hardrock 100',
    eventdate: '7/9/2027',
    city: 'Silverton',
    state: 'CO',
    distance: 100.5,
    distance_units: 'miles',
    url: 'https://ultrasignup.com/register.aspx?did=91234',
  });
  assertEquals(race?.providerRaceId, '91234');
  assertEquals(race?.date, '2027-07-09');
  assertEquals(race?.locationLabel, 'Silverton, CO');
  assertEquals(race?.resultsUrl, null);
  // The whole point of the unverified-field-names posture, and the dispatcher
  // hands each provider its own reader rather than a merged one: a payload
  // spelled the other provider's way yields nothing, not a race with a guessed
  // name.
  assertEquals(readProviderRace('ultrasignup', { name: 'X', next_date: '2027-07-09' }), null);
  assertEquals(readProviderRace('runsignup', { eventname: 'X', eventdate: '2027-07-09' }), null);
});

Deno.test('the envelope walk tolerates the nestings and caps the batch', () => {
  assertEquals(extractProviderRaces([{ race_id: 1 }, { race_id: 2 }]).length, 2);
  assertEquals(extractProviderRaces({ races: [{ race: { race_id: 3 } }] })[0].race_id, 3);
  assertEquals(extractProviderRaces({ races: [{ race_id: 4 }] })[0].race_id, 4);
  assertEquals(extractProviderRaces({ events: [{ eventid: 5 }] })[0].eventid, 5);
  assertEquals(extractProviderRaces(null).length, 0);
  assertEquals(extractProviderRaces({}).length, 0);
  assertEquals(extractProviderRaces('nope').length, 0);
  const huge = { races: Array.from({ length: MAX_LISTING_ROWS + 40 }, () => ({ race_id: 1 })) };
  assertEquals(extractProviderRaces(huge).length, MAX_LISTING_ROWS);
});

function upsert(id: string | null, over: Partial<RaceListingUpsert> = {}): RaceListingUpsert {
  return {
    ...listingUpsertFrom('runsignup', {
      providerRaceId: id,
      name: 'Race',
      date: '2027-06-20',
      distanceM: 42195,
      locationLabel: 'Somewhere',
      entryUrl: null,
      resultsUrl: null,
    }),
    ...over,
  };
}

Deno.test('the batch is reconciled against storage AND against itself', () => {
  const batch = reconcileListingBatch(
    [upsert('a'), upsert('b'), upsert('a'), upsert(null)],
    ['b'],
  );
  assertEquals(batch.fresh.map((r) => r.provider_race_id), ['a']);
  assertEquals(batch.existing.map((r) => r.provider_race_id), ['b']);
  // The repeat and the id-less row: the insert is ONE statement against the
  // partial unique index, so a repeat would 23505 and lose every other race in
  // the batch — and an id-less row would be re-inserted on every sync, since the
  // index does not cover nulls.
  assertEquals(batch.skipped, 2);
});

Deno.test('a provider row is marked verified, which only the service role may do', () => {
  const row = upsert('a');
  assertEquals(row.is_verified, true);
  assertEquals(row.provider, 'runsignup');
});

function storedOf(over: Partial<StoredListing> = {}): StoredListing {
  return {
    id: 'L-1',
    provider_race_id: 'a',
    name: 'Race',
    race_date: '2027-06-20',
    distance_m: 42195,
    location_label: 'Somewhere',
    entry_url: null,
    results_url: null,
    is_verified: true,
    ...over,
  };
}

Deno.test('an unchanged race writes nothing, and each field that moves writes', () => {
  assertEquals(listingDiffers(storedOf(), upsert('a')), false);
  assertEquals(listingDiffers(storedOf({ race_date: '2027-06-27' }), upsert('a')), true);
  assertEquals(listingDiffers(storedOf({ name: 'Renamed' }), upsert('a')), true);
  assertEquals(listingDiffers(storedOf({ distance_m: 21097 }), upsert('a')), true);
  assertEquals(listingDiffers(storedOf({ location_label: 'Elsewhere' }), upsert('a')), true);
  assertEquals(listingDiffers(storedOf({ entry_url: 'https://x.test' }), upsert('a')), true);
  assertEquals(listingDiffers(storedOf({ results_url: 'https://x.test' }), upsert('a')), true);
  // A race a user submitted first lands unverified; the provider catching up
  // with it is exactly when that should change.
  assertEquals(listingDiffers(storedOf({ is_verified: false }), upsert('a')), true);
});

Deno.test('a region hint is validated, and a bad one is an error not a silent no-hint', () => {
  assertEquals(parseNearHint(undefined), { ok: true, near: null });
  assertEquals(parseNearHint(null), { ok: true, near: null });
  assertEquals(parseNearHint({ lng: -106.9, lat: 37.8 }), {
    ok: true,
    near: { point: { lng: -106.9, lat: 37.8 }, postalCode: null, radiusM: DEFAULT_NEAR_RADIUS_M },
  });
  assertEquals(parseNearHint({ postal_code: ' 10001 ', radius_m: 25000 }), {
    ok: true,
    near: { point: null, postalCode: '10001', radiusM: 25000 },
  });
  // Falling back to "no hint" on a typo pulls the provider's whole national feed
  // and writes it into the calendar as if it were local.
  assertEquals(parseNearHint({ lat: 37.8 }), { ok: false, error: 'invalid_near_lng' });
  assertEquals(parseNearHint({ lng: 200, lat: 37.8 }), { ok: false, error: 'invalid_near_lng' });
  assertEquals(parseNearHint({ lng: -106.9, lat: 91 }), { ok: false, error: 'invalid_near_lat' });
  assertEquals(parseNearHint({ postal_code: 10001 }), {
    ok: false,
    error: 'invalid_near_postal_code',
  });
  assertEquals(parseNearHint({ postal_code: '<script>' }).ok, false);
  assertEquals(parseNearHint({ radius_m: 5000 }), { ok: false, error: 'invalid_near' });
  assertEquals(parseNearHint({ lng: 0, lat: 0, radius_m: 0 }), {
    ok: false,
    error: 'invalid_near_radius',
  });
  assertEquals(parseNearHint({ lng: 0, lat: 0, radius_m: MAX_NEAR_RADIUS_M + 1 }).ok, false);
  assertEquals(parseNearHint({ lng: 0, lat: 0, radius_m: NaN }).ok, false);
  assertEquals(parseNearHint([1, 2]), { ok: false, error: 'invalid_near' });
  assertEquals(parseNearHint('nope'), { ok: false, error: 'invalid_near' });
});

Deno.test('RunSignUp searches by US ZIP, never by a point it would ignore', () => {
  // Measured: RunSignUp drops lat/lng without an error, so a point hint would
  // pull the national feed and file it as local.
  const point = { point: { lng: -74, lat: 40.75 }, postalCode: null, radiusM: 16093 };
  const zip = { point: null, postalCode: '10001', radiusM: 16093 };
  assertEquals(nearHintError('runsignup', null), null);
  assertEquals(nearHintError('runsignup', point), 'near_postal_code_required');
  assertEquals(nearHintError('runsignup', zip), null);
  assertEquals(
    nearHintError('runsignup', { ...zip, postalCode: 'SW1A 1AA' }),
    'near_postal_code_not_us',
  );
  assertEquals(nearHintError('ultrasignup', zip), 'near_point_required');
  assertEquals(nearHintError('ultrasignup', point), null);
});

Deno.test('the RunSignUp URL is keyless unless both halves of a key are set', () => {
  const zip = { point: null, postalCode: '10001', radiusM: 80467 };
  const rs = new URL(providerRacesUrl({ provider: 'runsignup', apiKey: null, apiSecret: null, near: zip }));
  assertEquals(rs.origin + rs.pathname, 'https://runsignup.com/Rest/races');
  const q = rs.searchParams;
  assertEquals(q.get('format'), 'json');
  assertEquals(q.get('events'), 'T', 'distances live on the events expansion');
  assertEquals(q.get('sort'), 'date ASC', 'the cap trims the far future, not the alphabet');
  assertEquals(q.get('results_per_page'), String(MAX_LISTING_ROWS));
  assertEquals(q.get('zipcode'), '10001');
  assertEquals(q.get('radius'), '50', '80467 m is 50 miles');
  assertEquals(q.has('api_key'), false);
  assertEquals(q.has('lat') || q.has('lng'), false, 'RunSignUp ignores a point; never send one');

  const half = new URL(providerRacesUrl({ provider: 'runsignup', apiKey: 'KEY', apiSecret: null, near: null }));
  assertEquals(half.searchParams.has('api_key'), false, 'half a credential is no credential');
  assertEquals(half.searchParams.has('zipcode'), false, 'no hint means no region params');

  const keyed = new URL(providerRacesUrl({ provider: 'runsignup', apiKey: 'KEY', apiSecret: 'SECRET', near: null }));
  assertEquals(keyed.searchParams.get('api_key'), 'KEY');
  assertEquals(keyed.searchParams.get('api_secret'), 'SECRET');

  const us = providerRacesUrl({
    provider: 'ultrasignup',
    apiKey: 'K',
    apiSecret: 'S',
    near: { point: { lng: -106.9, lat: 37.8 }, postalCode: null, radiusM: 80467 },
  });
  assert(us.startsWith('https://ultrasignup.com/service/events.svc/'));
  assert(us.includes('api_key=K') && us.includes('radius=50') && us.includes('lat=37.8'));
});

// The listings land in one batch upsert. A name capped through the middle of an
// emoji leaves half a character, Postgres refuses the request body's JSON, and
// every race in the batch goes with it.
Deno.test('a capped race name never ends in half an emoji', () => {
  const race = asRace(readRunSignUpRace({
    race_id: 9,
    name: 'a'.repeat(MAX_LISTING_NAME_LEN - 1) + '\u{1F383} Pumpkin Run',
    next_date: '2027-10-30',
  }));
  assertEquals(race.name, 'a'.repeat(MAX_LISTING_NAME_LEN - 1));
  assertEquals(/[\uD800-\uDFFF]/.test(race.name), false);
});
