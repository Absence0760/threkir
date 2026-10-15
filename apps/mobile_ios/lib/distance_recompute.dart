/// Whether the run-detail screen may offer "Recalculate distance", the
/// original distance a recompute kept aside, and how a refusal reads
/// (docs/features/gps_distance.md § Server recompute). TS↔Dart parity pair
/// with `apps/web/src/lib/runs/distance_recompute.ts` — keep in lockstep.
library;

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';

/// Sources whose distance one of our own recorders computed from the GPS
/// track it stored, so the server can recompute it from that same track. An
/// import carries a distance some other system decided, and a recompute
/// would overwrite it with ours. Keep in step with the source set the
/// job_worker's distance_recompute handler accepts.
const List<RunSource> recomputableSources = [RunSource.app, RunSource.watch];

/// The estimator a recompute applies: spec v1.4's smoother. A run already
/// carrying it has nothing to gain; a run a recompute stamped `kalman_v3`
/// (spec v1.3's smoother), `kalman_v2` (spec v1.2's) or `kalman_v1` (spec
/// v1.1's forward filter) is offered again.
const String currentDistanceEstimator = 'kalman_v4';

/// Live stamps of recorders that feed their estimator fixes their track gate
/// refuses (spec v1.4 on): such a run's stored track holds every fix the
/// estimator took only when it says `track_complete`, so a replay of any
/// other would credit each canopy stretch its chord and read short. A spec
/// bump adds its value. Mirrors `trackGatedEstimators` in the job_worker.
const List<String> trackGatedEstimators = ['kalman_v4'];

/// The four fields the predicate reads, so a server row and a local [Run]
/// can both be asked. A local [Run] carries no owner id and keeps its
/// `track_url` in metadata; [RecomputeCandidate.fromRun] bridges that.
class RecomputeCandidate {
  final String? userId;
  final RunSource source;
  final String? trackUrl;
  final Map<String, dynamic>? metadata;

  const RecomputeCandidate({
    required this.userId,
    required this.source,
    required this.trackUrl,
    required this.metadata,
  });

  factory RecomputeCandidate.fromRun(Run run, {required String? ownerId}) =>
      RecomputeCandidate(
        userId: ownerId,
        source: run.source,
        trackUrl: run.metadata?[MetadataKeys.trackUrl] as String?,
        metadata: run.metadata,
      );
}

/// The viewer owns the run and it is a run the server recompute would
/// actually rewrite. The rule past ownership mirrors
/// `distanceRecomputeSkipReason` in
/// apps/job_worker/internal/handler_distance_recompute.go exactly — the
/// worker re-checks it and completes a refused job silently, so an action
/// offered here that the worker would skip is a no-op the runner cannot see.
/// Change the two together. On top of the worker's rule, a run already on the
/// current estimator is not offered: the worker would accept it, but a replay
/// through the same smoother has nothing to gain.
bool canRecomputeDistance(RecomputeCandidate? run, String? viewerId) {
  if (run == null || viewerId == null || viewerId.isEmpty) return false;
  if (run.userId != viewerId) return false;
  final trackUrl = run.trackUrl;
  if (trackUrl == null || trackUrl.isEmpty) return false;
  if (!recomputableSources.contains(run.source)) return false;
  final metadata = run.metadata ?? const <String, dynamic>{};
  if (metadata[MetadataKeys.inProgress] == true) return false;
  if (metadata[MetadataKeys.manualEntry] == true) return false;
  if (metadata[MetadataKeys.indoor] == true) return false;
  if (metadata[MetadataKeys.indoorEstimated] == true) return false;
  // Any provenance tag names a non-GPS distance (pedometer, treadmill), and
  // an unknown one is not the estimator's to overwrite.
  final distanceSource = metadata[MetadataKeys.distanceSource];
  if (distanceSource is String && distanceSource.isNotEmpty) return false;
  // Stamped by the phone recorder, which saved the smoother's figure over
  // every fix, and never recomputed: its stored track is movement-gated, so
  // a replay would see fewer fixes than the save did. A watch stamp
  // (`kalman_v1`, the wrist's forward filter) is no bar: the watch stored
  // every fix that filter took, so the replay gains the smoother.
  if (run.source != RunSource.watch &&
      metadata.containsKey(MetadataKeys.distanceEstimator) &&
      !metadata.containsKey(MetadataKeys.distanceRecomputedAt)) {
    return false;
  }
  // Stamped live by a v1.4 recorder whose track omits the canopy fixes its
  // estimator took. The Wear OS and watchOS builds before track_complete
  // stamp `kalman_v1`, whose track the replay reproduces.
  final estimator = metadata[MetadataKeys.distanceEstimator];
  final recomputed = metadata.containsKey(MetadataKeys.distanceRecomputedAt);
  if (!recomputed &&
      estimator is String &&
      trackGatedEstimators.contains(estimator) &&
      metadata[MetadataKeys.trackComplete] != true) {
    return false;
  }
  // A recompute already applied the current smoother. A live stamp names
  // the recorder's forward filter, which the replay improves on.
  if (recomputed && estimator == currentDistanceEstimator) return false;
  return true;
}

/// The recorder's original distance a recompute kept aside, or null when the
/// run was never recomputed (or the value is unusable).
double? recordedDistanceM(Map<String, dynamic>? metadata) {
  final raw = metadata?[MetadataKeys.distanceRecordedM];
  return raw is num && raw.isFinite && raw > 0 ? raw.toDouble() : null;
}

enum RecomputeFailure { notAuthorized, noTrack, other }

/// Maps the RPC's typed refusals (42501 not the owner, 22000 no stored track,
/// surfaced by [ApiClient.requestDistanceRecompute] as a
/// [DistanceRecomputeRefused]) to the message the screen shows; anything else
/// is a generic failure.
RecomputeFailure classifyRecomputeError(Object? error) {
  if (error is DistanceRecomputeRefused) {
    return switch (error.reason) {
      DistanceRecomputeRefusal.notAuthorized => RecomputeFailure.notAuthorized,
      DistanceRecomputeRefusal.noTrack => RecomputeFailure.noTrack,
    };
  }
  return RecomputeFailure.other;
}
