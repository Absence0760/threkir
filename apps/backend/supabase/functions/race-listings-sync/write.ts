/// The write half of a provider race sync: read a provider payload, place each
/// race on the map (from the feed's own point, else its ZIP), and reconcile the
/// result into `race_listings`.
///
/// Shared by the caller-driven sync (index.ts) and the scheduled sweep
/// (`race-listings-sweep`), so the two cannot disagree about what a listing is.
/// The client handed in must be the SERVICE ROLE: a provider race is
/// `is_verified`, and the `race_listings_force_unverified` trigger forces false
/// for every other role.

import type { DbClient } from '../_shared/database.ts';
import {
  EXCLUDED,
  type ListingSyncProvider,
  listingDiffers,
  listingUpsertFrom,
  MAX_LISTING_ROWS,
  type NormalisedRace,
  pointEwkt,
  type RaceListingUpsert,
  type RaceRowProvider,
  readProviderRace,
  reconcileListingBatch,
  extractProviderRaces,
  isRunSignUpRaceFeed,
  runSignUpErrorOf,
  type StoredListing,
} from './lib.ts';
import { type ParkrunScope, readParkrunFeed, readParkrunSlice, scopeParkrunFeatures } from './parkrun.ts';

export interface SyncSummary {
  synced: number;
  updated: number;
  skipped: number;
  unusable: number;
  excluded: number;
  /// Listings written without a point: no ZIP, a ZIP with no ZCTA, or a lookup
  /// that failed. Counted apart, because a race nobody can find by "near me"
  /// is a different gap from a race that was not written at all.
  unplaced: number;
  total: number;
  complete: boolean;
}

export type SyncOutcome =
  | { ok: true; summary: SyncSummary }
  | { ok: false; status: number; error: string };

/// The point for each ZIP the table knows, or null when the lookup failed. A
/// failure is logged and the listings still get written, without a point, and
/// are counted `unplaced` — placing a race is never a reason not to list it —
/// but null keeps it apart from "the table has no such ZIP", which is an
/// answer and may clear a stale point where a failure must not.
export async function zipPoints(
  service: DbClient,
  zips: readonly string[],
): Promise<Map<string, string> | null> {
  const out = new Map<string, string>();
  if (zips.length === 0) return out;
  const { data, error } = await service
    .from('us_zcta_points')
    .select('zcta, lat, lng')
    .in('zcta', [...zips]);
  if (error) {
    console.error('race-listings-sync: zip point lookup failed', error.message);
    return null;
  }
  for (const row of data ?? []) out.set(row.zcta, pointEwkt(row.lat, row.lng));
  return out;
}

export async function syncProviderPayload(
  service: DbClient,
  provider: RaceRowProvider,
  payload: unknown,
): Promise<SyncOutcome> {
  if (provider === 'runsignup' && runSignUpErrorOf(payload) !== null) {
    console.error('race-listings-sync: runsignup refused the request', runSignUpErrorOf(payload));
    return { ok: false, status: 502, error: 'runsignup upstream error' };
  }
  if (provider === 'runsignup' && !isRunSignUpRaceFeed(payload)) {
    console.error('race-listings-sync: runsignup answered without a races array');
    return { ok: false, status: 502, error: 'runsignup upstream shape' };
  }
  const rows = extractProviderRaces(payload);
  const races: NormalisedRace[] = [];
  let unusable = 0;
  let excluded = 0;
  for (const row of rows) {
    const race = readProviderRace(provider, row);
    if (race === EXCLUDED) {
      excluded++;
      continue;
    }
    if (!race) {
      unusable++;
      continue;
    }
    races.push(race);
  }

  return await writeListings(service, provider, races, {
    synced: 0,
    updated: 0,
    skipped: 0,
    unusable,
    excluded,
    unplaced: 0,
    total: rows.length,
    complete: rows.length < MAX_LISTING_ROWS,
  });
}

/// The parkrun leg: one global events file, of which `scope` names the slice
/// this sync writes (./parkrun.ts), dated for the run at `nowMs`.
export async function syncParkrunPayload(
  service: DbClient,
  payload: unknown,
  scope: ParkrunScope,
  nowMs: number,
): Promise<SyncOutcome> {
  const feed = readParkrunFeed(payload);
  if (feed === null) {
    console.error('race-listings-sync: parkrun answered without an events feature array');
    return { ok: false, status: 502, error: 'parkrun upstream shape' };
  }
  const slice = scopeParkrunFeatures(feed.features, scope);
  const { races, unusable } = readParkrunSlice(slice.features, feed.hosts, nowMs);
  return await writeListings(service, 'parkrun', races, {
    synced: 0,
    updated: 0,
    skipped: 0,
    unusable,
    excluded: 0,
    unplaced: 0,
    total: slice.features.length,
    complete: slice.complete,
  });
}

async function writeListings(
  service: DbClient,
  provider: ListingSyncProvider,
  races: NormalisedRace[],
  summary: SyncSummary,
): Promise<SyncOutcome> {
  if (races.length === 0) return { ok: true, summary };

  const zips = [
    ...new Set(
      races.filter((r) => !r.point).map((r) => r.postalCode).filter((z): z is string => z !== null),
    ),
  ];
  const points = await zipPoints(service, zips);
  // Per race: whether its point (or its lack of one) is a known answer. A race
  // that carries its own point, or has no US ZIP, has one whatever the lookup did.
  const pointKnown = new Map<string, boolean>();
  const listings: RaceListingUpsert[] = races.map((race) => {
    const own = race.point ? pointEwkt(race.point.lat, race.point.lng) : null;
    const point = own ??
      (race.postalCode === null || points === null ? null : points.get(race.postalCode) ?? null);
    if (point === null) summary.unplaced++;
    if (race.providerRaceId !== null) {
      pointKnown.set(race.providerRaceId, own !== null || race.postalCode === null || points !== null);
    }
    return listingUpsertFrom(provider, race, point);
  });

  const ids = listings
    .map((l) => l.provider_race_id)
    .filter((id): id is string => id !== null);
  // One string literal: a concatenated column list infers as `string` and
  // silently degrades the typed client to `any`.
  const { data: storedRows, error: readErr } = await service
    .from('race_listings')
    .select('id, provider_race_id, name, race_date, distance_m, location_label, location_point, entry_url, results_url, is_verified')
    .eq('provider', provider)
    .in('provider_race_id', ids);
  if (readErr) {
    // A read that failed is not an empty calendar. Proceeding would insert every
    // race again and duplicate the whole feed.
    console.error('race-listings-sync: existing-listing read failed', readErr.message);
    return { ok: false, status: 500, error: 'listing_read_failed' };
  }

  const stored = new Map<string, StoredListing>();
  for (const row of (storedRows ?? []) as StoredListing[]) {
    if (row.provider_race_id !== null) stored.set(row.provider_race_id, row);
  }

  const batch = reconcileListingBatch(listings, [...stored.keys()]);
  summary.skipped = batch.skipped;

  if (batch.fresh.length > 0) {
    const { error } = await service.from('race_listings').insert(batch.fresh);
    if (error) {
      console.error('race-listings-sync: insert failed', error.message);
      return { ok: false, status: 500, error: 'listing_insert_failed' };
    }
    summary.synced = batch.fresh.length;
  }

  // Only the rows whose stored answer actually differs. The partial unique index
  // cannot arbitrate an ON CONFLICT through PostgREST, so each rewrite is its own
  // round trip and a sync that rewrote everything would issue one per race on
  // every run.
  for (const row of batch.existing) {
    const current = stored.get(row.provider_race_id!)!;
    const known = pointKnown.get(row.provider_race_id!) === true;
    if (!listingDiffers(current, row, known)) continue;
    const { error } = await service
      .from('race_listings')
      .update({
        name: row.name,
        race_date: row.race_date,
        distance_m: row.distance_m,
        location_label: row.location_label,
        // The point is written whenever the ZIP table answered for this race,
        // including "no point" for a race that moved somewhere it cannot place;
        // a failed lookup leaves the stored point as it was.
        ...(row.location_point !== null || known ? { location_point: row.location_point } : {}),
        entry_url: row.entry_url,
        results_url: row.results_url,
        is_verified: true,
      })
      .eq('id', current.id);
    if (error) {
      console.error('race-listings-sync: update failed', error.message);
      return { ok: false, status: 500, error: 'listing_update_failed' };
    }
    summary.updated++;
  }

  return { ok: true, summary };
}
