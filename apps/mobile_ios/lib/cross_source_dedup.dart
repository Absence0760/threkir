/// Cross-source dedup at import time.
///
/// Persona-hunt Round 2 finding Intermediate #3: exact-match on
/// `external_id` works inside one source (round-1 fix for Strava
/// ZIP re-imports) but doesn't catch the same activity arriving via
/// two sources with different namespace prefixes. A Garmin run that
/// syncs to BOTH Strava AND Health Connect lands as two distinct
/// rows: `strava:<id>` and `healthconnect:<uuid>`. Weekly mileage
/// doubles for any affected day; the PB scanner sees the effort
/// twice; the heatmap shows the day twice as deep.
///
/// This helper is a pure fuzzy-match: a candidate import duplicates
/// an existing run when their start times agree within ±5 minutes
/// AND their distances agree within ±5%. The window is wide enough
/// to absorb the small clock + GPS-distance variance you get
/// between platforms (Garmin recorded the start at second 0; Strava
/// ingested it 2 seconds later; Health Connect summarised it
/// 1 second after that), tight enough to never falsely match two
/// genuinely-different runs.

import 'package:core_models/core_models.dart';

import 'run_stats.dart' show haversineMetres;

/// ±180 seconds — the canonical cross-provider start tolerance, in lockstep
/// with `CROSS_PROVIDER_START_TOLERANCE_S` in the web twin
/// (`apps/web/src/lib/integrations/garmin_dedupe.ts`), the Deno twin
/// (`apps/backend/supabase/functions/_shared/strava.ts`), and the Go worker
/// (`apps/job_worker/internal/cross_provider.go`). A few minutes absorbs the
/// offset between a watch's and a service's start stamp; two genuinely
/// distinct runs can't start this close (you can't record two tracks at once).
const Duration kCrossSourceTimeWindow = Duration(seconds: 180);

/// ±5% relative distance — matches `CROSS_PROVIDER_DISTANCE_FRACTION` in the
/// twins. GPS / algorithm differences between providers move total distance a
/// percent or two.
const double kCrossSourceDistanceFraction = 0.05;

/// Returns true when `candidate` looks like a re-import of one of the
/// `existing` runs from a different source — start within the tolerance AND
/// distance within the fraction (both axes, so a warm-up + race of similar
/// distance but well-separated starts is never suppressed).
///
/// The near-duplicate math is the byte-identical twin of the canonical
/// `isCrossProviderDuplicate` (start-gap ≤ 180 s AND |Δdist| ≤ 5% of the
/// LARGER distance). Two mobile-specific guards stay on top of it: the
/// comparison is cross-source only (`r.source == candidate.source` is skipped
/// — same-source re-imports are guarded by the per-user `external_id` unique
/// index at the DB, the mobile equivalent of the web importers running their
/// exact `seen`/`composite` dedupe first), and a zero-distance existing run is
/// ignored so a trackless indoor summary can't false-match.
/// Sources that are AGGREGATORS, not providers: Health Connect and HealthKit
/// hold records written by many other apps, so two rows both tagged with one
/// of these can be the same physical run recorded by Garmin Connect and by
/// Samsung Health. They carry different record uuids, so the `external_id`
/// unique index that guards a same-source RE-import does not see them as the
/// same thing — skipping the comparison let both land and doubled the
/// runner's mileage, PRs and heatmap.
const Set<RunSource> kAggregatorSources = {
  RunSource.healthconnect,
  RunSource.healthkit,
};

/// [alsoDistanceMetres] is a second distance the candidate may match on, as
/// `isImportDuplicate` on web takes: an importer whose distance rule changed
/// passes the figure the old rule stored ([positionsMetres]).
bool isCrossSourceDuplicate(
  Run candidate,
  List<Run> existing, {
  double? alsoDistanceMetres,
}) {
  final distances = [
    candidate.distanceMetres,
    ?alsoDistanceMetres,
  ];
  for (final r in existing) {
    // Same-source pairs are normally left to the external_id index — except
    // for an aggregator, where "same source" says nothing about which app
    // actually recorded the run. Two genuinely distinct runs cannot start
    // within 180 s of each other AND match to 5 % on distance, so widening
    // the comparison here can't suppress a real one.
    if (r.source == candidate.source &&
        !kAggregatorSources.contains(candidate.source)) {
      continue;
    }
    final dt = r.startedAt.difference(candidate.startedAt).abs();
    if (dt > kCrossSourceTimeWindow) continue;
    final existingDist = r.distanceMetres;
    if (existingDist <= 0) continue;
    for (final candidateDist in distances) {
      if (candidateDist <= 0) continue;
      final larger = candidateDist.abs() > existingDist.abs()
          ? candidateDist.abs()
          : existingDist.abs();
      final diff = (candidateDist - existingDist).abs();
      if (diff <= larger * kCrossSourceDistanceFraction) return true;
    }
  }
  return false;
}

/// The hop-sum of [track]'s raw positions, metres: what the Strava ZIP
/// importer stored as a run's distance before #1387, and what a Garmin TCX
/// import on web stored. An importer passes it to [isCrossSourceDuplicate] as
/// `alsoDistanceMetres`, so a run already stored under the old rule is still
/// the same run: on a city start the old and new figures differ by more than
/// the 5 % the guard allows. Mirrors `isImportDuplicate` in
/// `apps/web/src/lib/integrations/garmin_dedupe.ts`.
double positionsMetres(List<Waypoint> track) {
  var sum = 0.0;
  for (var i = 1; i < track.length; i++) {
    sum += haversineMetres(
        track[i - 1].lat, track[i - 1].lng, track[i].lat, track[i].lng);
  }
  return sum;
}
