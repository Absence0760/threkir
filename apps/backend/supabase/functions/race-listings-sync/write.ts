/// The write half of a provider race sync: read a provider payload, place each
/// race on the map from its ZIP, and reconcile the result into `race_listings`.
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
  readProviderRace,
  reconcileListingBatch,
  extractProviderRaces,
  isRunSignUpRaceFeed,
  runSignUpErrorOf,
  type StoredListing,
} from './lib.ts';

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

/// The point for each ZIP the table knows. A failed lookup is logged and
/// answers no points: the listings still get written, without one, and are
/// counted `unplaced` — placing a race is never a reason not to list it.
export async function zipPoints(
  service: DbClient,
  zips: readonly string[],
): Promise<Map<string, string>> {
  const out = new Map<string, string>();
  if (zips.length === 0) return out;
  const { data, error } = await service
    .from('us_zcta_points')
    .select('zcta, lat, lng')
    .in('zcta', [...zips]);
  if (error) {
    console.error('race-listings-sync: zip point lookup failed', error.message);
    return out;
  }
  for (const row of data ?? []) out.set(row.zcta, pointEwkt(row.lat, row.lng));
  return out;
}

export async function syncProviderPayload(
  service: DbClient,
  provider: ListingSyncProvider,
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

  const complete = rows.length < MAX_LISTING_ROWS;
  const summary: SyncSummary = {
    synced: 0,
    updated: 0,
    skipped: 0,
    unusable,
    excluded,
    unplaced: 0,
    total: rows.length,
    complete,
  };
  if (races.length === 0) return { ok: true, summary };

  const zips = [...new Set(races.map((r) => r.postalCode).filter((z): z is string => z !== null))];
  const points = await zipPoints(service, zips);
  const listings: RaceListingUpsert[] = races.map((race) => {
    const point = race.postalCode === null ? null : points.get(race.postalCode) ?? null;
    if (point === null) summary.unplaced++;
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
    if (!listingDiffers(current, row)) continue;
    const { error } = await service
      .from('race_listings')
      .update({
        name: row.name,
        race_date: row.race_date,
        distance_m: row.distance_m,
        location_label: row.location_label,
        // A point is written when one is known and never cleared by a lookup
        // that found none: a failed read must not unplace a placed race.
        ...(row.location_point !== null ? { location_point: row.location_point } : {}),
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
