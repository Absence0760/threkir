/// Pure helpers for the run-detail "Route History" card.
///
/// TS↔Dart parity pair with `apps/web/src/lib/routes/route_history.ts` — keep
/// the two in lockstep: algorithm, edge cases, outputs, test counts.
library;

import 'package:core_models/core_models.dart'
    show MetadataKeys, Run, isPlausibleRunDuration;

class RouteHistoryRun {
  final String id;
  final String? routeId;
  final double distanceM;
  final int durationS;
  final String? activityType;

  const RouteHistoryRun({
    required this.id,
    required this.routeId,
    required this.distanceM,
    required this.durationS,
    this.activityType,
  });

  factory RouteHistoryRun.fromRun(Run run) {
    final activity = run.metadata?[MetadataKeys.activityType];
    return RouteHistoryRun(
      id: run.id,
      routeId: run.routeId,
      distanceM: run.distanceMetres,
      durationS: run.duration.inSeconds,
      activityType: activity is String ? activity : null,
    );
  }
}

class RouteHistorySummary {
  final int rank;
  final int total;
  final RouteHistoryRun pb;
  final bool isPb;
  final int deltaSeconds;

  const RouteHistorySummary({
    required this.rank,
    required this.total,
    required this.pb,
    required this.isPb,
    required this.deltaSeconds,
  });
}

/// Attempts on the same route and activity type (null reads as `'run'`) that
/// moved more than 100 m and hold a real time, `0 < durationS < 864000` — a
/// run with distance and no time would be a permanent PB, and one still
/// carrying the ten-day repair placeholder has no time to rank — fastest
/// first. An empty route id is no route. Tied times are decided in
/// [summariseHistory], not by where the sort leaves them.
List<RouteHistoryRun> qualifyingAttempts(
  RouteHistoryRun currentRun,
  Iterable<RouteHistoryRun> allRuns,
) {
  final routeId = currentRun.routeId;
  if (routeId == null || routeId.isEmpty) return const [];
  final thisActivity = currentRun.activityType ?? 'run';
  return allRuns
      .where((r) =>
          r.routeId == routeId &&
          r.distanceM > 100 &&
          r.durationS > 0 &&
          isPlausibleRunDuration(r.durationS) &&
          (r.activityType ?? 'run') == thisActivity)
      .toList()
    ..sort((a, b) => a.durationS.compareTo(b.durationS));
}

/// The current run's standing among [attempts], or null when there is
/// nothing to show — fewer than two attempts, or the run is not among them.
///
/// Ties take standard competition ranking: rank is one plus the attempts
/// strictly faster, so 1500 / 1600 / 1600 / 1700 rank 1, 2, 2, 4, and a run
/// tied with the fastest time is a PB rather than "+0:00 behind" it.
RouteHistorySummary? summariseHistory(
  String currentRunId,
  List<RouteHistoryRun> attempts,
) {
  if (attempts.length < 2) return null;
  final pb = attempts.first;
  final idx = attempts.indexWhere((r) => r.id == currentRunId);
  if (idx < 0) return null;
  final current = attempts[idx];
  final deltaSeconds = current.durationS - pb.durationS;
  return RouteHistorySummary(
    rank: 1 + attempts.where((r) => r.durationS < current.durationS).length,
    total: attempts.length,
    pb: pb,
    isPb: deltaSeconds == 0,
    deltaSeconds: deltaSeconds,
  );
}

/// "+1:23" / "−0:45" / "0:00" — the sign (U+2212 for negative) is always
/// rendered, and hours appear only when non-zero.
String formatSignedDelta(int seconds) {
  final sign = seconds > 0
      ? '+'
      : seconds < 0
          ? '\u2212'
          : '';
  final total = seconds.abs();
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  String two(int v) => v.toString().padLeft(2, '0');
  if (h > 0) return '$sign$h:${two(m)}:${two(s)}';
  return '$sign$m:${two(s)}';
}
