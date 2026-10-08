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

/// The estimator a recompute applies: spec v1.2's smoother. A run already
/// carrying it has nothing to gain; a `kalman_v1` run (spec v1.1's forward
/// filter) is offered again.
const String currentDistanceEstimator = 'kalman_v2';

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

/// The viewer owns the run, it has a stored track, one of our recorders
/// wrote it, its distance is not a pedometer estimate, and it was not already
/// recorded or recomputed with the current estimator. The RPC re-checks the
/// first two server-side; the rest only decide whether the action is useful.
bool canRecomputeDistance(RecomputeCandidate? run, String? viewerId) {
  if (run == null || viewerId == null || viewerId.isEmpty) return false;
  if (run.userId != viewerId) return false;
  final trackUrl = run.trackUrl;
  if (trackUrl == null || trackUrl.isEmpty) return false;
  if (!recomputableSources.contains(run.source)) return false;
  final metadata = run.metadata ?? const <String, dynamic>{};
  if (metadata[MetadataKeys.distanceSource] == 'pedometer') return false;
  if (metadata[MetadataKeys.distanceEstimator] == currentDistanceEstimator) {
    return false;
  }
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
