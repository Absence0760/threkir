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
/// moved more than 100 m and hold a plausible duration — a run still carrying
/// the ten-day repair placeholder has no time to rank — fastest first, with
/// tied durations kept in input order. JS's `Array.prototype.sort` is stable;
/// Dart's `List.sort` is not past 32 elements, so the tie-break is explicit.
List<RouteHistoryRun> qualifyingAttempts(
  RouteHistoryRun currentRun,
  Iterable<RouteHistoryRun> allRuns,
) {
  if (currentRun.routeId == null) return const [];
  final thisActivity = currentRun.activityType ?? 'run';
  final kept = allRuns
      .where((r) =>
          r.routeId == currentRun.routeId &&
          r.distanceM > 100 &&
          isPlausibleRunDuration(r.durationS) &&
          (r.activityType ?? 'run') == thisActivity)
      .toList();
  final order = List<int>.generate(kept.length, (i) => i)
    ..sort((a, b) {
      final byDuration = kept[a].durationS.compareTo(kept[b].durationS);
      return byDuration != 0 ? byDuration : a.compareTo(b);
    });
  return [for (final i in order) kept[i]];
}

/// The current run's standing among [attempts], or null when there is
/// nothing to show — fewer than two attempts, or the run is not among them.
RouteHistorySummary? summariseHistory(
  String currentRunId,
  List<RouteHistoryRun> attempts,
) {
  if (attempts.length < 2) return null;
  final pb = attempts.first;
  final idx = attempts.indexWhere((r) => r.id == currentRunId);
  if (idx < 0) return null;
  final current = attempts[idx];
  return RouteHistorySummary(
    rank: idx + 1,
    total: attempts.length,
    pb: pb,
    isPb: pb.id == currentRunId,
    deltaSeconds: current.durationS - pb.durationS,
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
