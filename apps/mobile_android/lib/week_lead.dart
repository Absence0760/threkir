/// The dashboard's opening card for an account that has runs: how this
/// calendar week is going, what it is measured against, and the next session
/// the active plan has scheduled (#905 workstream 3).
///
/// The week is the runner's calendar week on their `week_start` pref, the same
/// window the "This Week" stat card and `ThisWeekStrip` use, so the three never
/// disagree about what "this week" holds. Plan workouts marked done without a
/// linked run count toward it the way the stat card counts them.
///
/// The yardstick is, in order: the plan's distance for the same calendar week,
/// the runner's own weekly goal (distance, then run count), and otherwise their
/// average over the weeks before this one (decisions § 1792). A week with no
/// activity inside the average window is a real zero, but weeks before the
/// runner's first activity are not weeks they missed, so the window is
/// shortened to their history rather than diluted by it.
///
/// Dart twin of `apps/web/src/lib/training/week_lead.ts` — keep the
/// algorithm, edge cases, outputs, and test counts in lockstep. The web's
/// generic `W extends LeadPlanWorkout` is a plain [LeadPlanWorkout] carrying
/// the row's [LeadPlanWorkout.id] here, since a generated row class cannot
/// implement an interface after the fact.
library;

import 'current_week.dart' show WeekStart;
import 'goals.dart' show GoalPeriod, RunGoal, weekStartLocal;

class LeadActivity {
  final String startedAt;
  final double distanceM;
  const LeadActivity({required this.startedAt, required this.distanceM});
}

class LeadPlanWorkout {
  final String? id;
  final String scheduledDate;
  final String kind;
  final double? targetDistanceM;
  final bool manuallyCompleted;
  final String? completedRunId;
  final String? skippedAt;

  const LeadPlanWorkout({
    this.id,
    required this.scheduledDate,
    required this.kind,
    required this.targetDistanceM,
    this.manuallyCompleted = false,
    this.completedRunId,
    this.skippedAt,
  });
}

const int recentAverageWeeks = 4;

enum WeekComparisonKind { plan, goal, goalRuns, average }

/// One of four yardsticks. [targetM] is set for `plan` / `goal`,
/// [targetCount] for `goalRuns`, [averageM] + [weeks] for `average`.
class WeekComparison {
  final WeekComparisonKind kind;
  final double? targetM;
  final double? targetCount;
  final double? averageM;
  final int? weeks;

  const WeekComparison.plan(double this.targetM)
      : kind = WeekComparisonKind.plan,
        targetCount = null,
        averageM = null,
        weeks = null;
  const WeekComparison.goal(double this.targetM)
      : kind = WeekComparisonKind.goal,
        targetCount = null,
        averageM = null,
        weeks = null;
  const WeekComparison.goalRuns(double this.targetCount)
      : kind = WeekComparisonKind.goalRuns,
        targetM = null,
        averageM = null,
        weeks = null;
  const WeekComparison.average(double this.averageM, int this.weeks)
      : kind = WeekComparisonKind.average,
        targetM = null,
        targetCount = null;

  @override
  bool operator ==(Object other) =>
      other is WeekComparison &&
      other.kind == kind &&
      other.targetM == targetM &&
      other.targetCount == targetCount &&
      other.averageM == averageM &&
      other.weeks == weeks;

  @override
  int get hashCode => Object.hash(kind, targetM, targetCount, averageM, weeks);

  @override
  String toString() =>
      'WeekComparison($kind, targetM: $targetM, targetCount: $targetCount, '
      'averageM: $averageM, weeks: $weeks)';
}

class WeekLead {
  final double distanceM;
  final int count;
  final WeekComparison? comparison;
  final LeadPlanWorkout? next;

  /// Whole calendar days from today to [next] — 0 is today, 1 tomorrow.
  final int? nextInDays;

  const WeekLead({
    required this.distanceM,
    required this.count,
    required this.comparison,
    required this.next,
    required this.nextInDays,
  });
}

String _localIso(DateTime d) {
  final mo = d.month.toString().padLeft(2, '0');
  final da = d.day.toString().padLeft(2, '0');
  return '${d.year}-$mo-$da';
}

int _isoToEpochDay(String iso) {
  final parts = iso.split('-').map(int.parse).toList();
  return DateTime.utc(parts[0], parts[1], parts[2]).millisecondsSinceEpoch ~/
      86400000;
}

DateTime _addDays(DateTime d, int days) =>
    DateTime(d.year, d.month, d.day + days, d.hour, d.minute, d.second,
        d.millisecond, d.microsecond);

bool _isDone(LeadPlanWorkout w) =>
    w.manuallyCompleted || w.completedRunId != null;

int? _epochMs(String iso) =>
    DateTime.tryParse(iso)?.millisecondsSinceEpoch;

({double averageM, int weeks})? recentWeeklyAverage(
  List<LeadActivity> activities,
  DateTime thisWeekStart, [
  int weeks = recentAverageWeeks,
]) {
  final windowStart = _addDays(thisWeekStart, -7 * weeks).millisecondsSinceEpoch;
  final startMs = thisWeekStart.millisecondsSinceEpoch;
  int? earliest;
  var totalM = 0.0;
  for (final a in activities) {
    final t = _epochMs(a.startedAt);
    if (t == null) continue;
    if (earliest == null || t < earliest) earliest = t;
    if (t >= windowStart && t < startMs && a.distanceM > 0) {
      totalM += a.distanceM;
    }
  }
  if (earliest == null || earliest >= startMs) return null;
  var span = weeks;
  while (span > 1 &&
      earliest >=
          _addDays(thisWeekStart, -7 * (span - 1)).millisecondsSinceEpoch) {
    span -= 1;
  }
  return (averageM: totalM / span, weeks: span);
}

class WeeklyGoalTarget {
  final double? distanceM;
  final double? runCount;
  const WeeklyGoalTarget({this.distanceM, this.runCount});

  @override
  bool operator ==(Object other) =>
      other is WeeklyGoalTarget &&
      other.distanceM == distanceM &&
      other.runCount == runCount;

  @override
  int get hashCode => Object.hash(distanceM, runCount);

  @override
  String toString() =>
      'WeeklyGoalTarget(distanceM: $distanceM, runCount: $runCount)';
}

/// The week-period targets among the dashboard's goals: the first distance
/// target and the first run-count target, which need not be the same goal.
/// `Preferences.goals` already carries the settings-backed weekly mileage
/// goal only when the runner has no weekly distance goal of their own
/// (`settings_sync.dart`), so the first match is the one the Goals section
/// shows.
WeeklyGoalTarget? weeklyGoalTarget(List<RunGoal> goals) {
  double? distanceM;
  double? runCount;
  for (final g in goals) {
    if (g.period != GoalPeriod.week) continue;
    final d = g.distanceMetres;
    if (distanceM == null && d != null && d > 0) distanceM = d;
    final c = g.runCount;
    if (runCount == null && c != null && c > 0) runCount = c;
  }
  return distanceM == null && runCount == null
      ? null
      : WeeklyGoalTarget(distanceM: distanceM, runCount: runCount);
}

double plannedDistanceForWeek(
  List<LeadPlanWorkout> workouts,
  DateTime thisWeekStart,
) {
  final first = _localIso(thisWeekStart);
  final last = _localIso(_addDays(thisWeekStart, 6));
  var total = 0.0;
  for (final w in workouts) {
    if (w.kind == 'rest') continue;
    if (w.scheduledDate.compareTo(first) < 0 ||
        w.scheduledDate.compareTo(last) > 0) {
      continue;
    }
    total += w.targetDistanceM ?? 0;
  }
  return total;
}

LeadPlanWorkout? nextPlanSession(
    List<LeadPlanWorkout> workouts, String todayIso) {
  LeadPlanWorkout? best;
  for (final w in workouts) {
    if (w.kind == 'rest' || _isDone(w) || w.skippedAt != null) continue;
    if (w.scheduledDate.compareTo(todayIso) < 0) continue;
    if (best == null || w.scheduledDate.compareTo(best.scheduledDate) < 0) {
      best = w;
    }
  }
  return best;
}

WeekLead weekLead({
  required List<LeadActivity> activities,
  required List<LeadPlanWorkout>? planWorkouts,
  WeeklyGoalTarget? weeklyGoal,
  required WeekStart weekStart,
  required DateTime now,
}) {
  final start = weekStartLocal(now, weekStartDay: weekStart.name);
  final startMs = start.millisecondsSinceEpoch;
  final todayIso = _localIso(now);
  final startIso = _localIso(start);

  var distanceM = 0.0;
  var count = 0;
  for (final a in activities) {
    final t = _epochMs(a.startedAt);
    if (t == null || t < startMs) continue;
    distanceM += a.distanceM > 0 ? a.distanceM : 0;
    count += 1;
  }

  final workouts = planWorkouts ?? const <LeadPlanWorkout>[];
  for (final w in workouts) {
    if (!(w.manuallyCompleted && w.completedRunId == null)) continue;
    if (w.scheduledDate.compareTo(startIso) < 0 ||
        w.scheduledDate.compareTo(todayIso) > 0) {
      continue;
    }
    distanceM += w.targetDistanceM ?? 0;
    count += 1;
  }

  WeekComparison? comparison;
  final planned =
      planWorkouts != null ? plannedDistanceForWeek(workouts, start) : 0.0;
  final goalDistance = weeklyGoal?.distanceM;
  final goalRuns = weeklyGoal?.runCount;
  if (planned > 0) {
    comparison = WeekComparison.plan(planned);
  } else if (goalDistance != null && goalDistance > 0) {
    comparison = WeekComparison.goal(goalDistance);
  } else if (goalRuns != null && goalRuns > 0) {
    comparison = WeekComparison.goalRuns(goalRuns);
  } else {
    final avg = recentWeeklyAverage(activities, start);
    if (avg != null && avg.averageM > 0) {
      comparison = WeekComparison.average(avg.averageM, avg.weeks);
    }
  }

  final next =
      planWorkouts != null ? nextPlanSession(workouts, todayIso) : null;
  final nextInDays = next == null
      ? null
      : _isoToEpochDay(next.scheduledDate) - _isoToEpochDay(todayIso);

  return WeekLead(
    distanceM: distanceM,
    count: count,
    comparison: comparison,
    next: next,
    nextInDays: nextInDays,
  );
}
