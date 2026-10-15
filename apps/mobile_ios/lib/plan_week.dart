/// Which week of a training plan a given day falls in.
///
/// The offset between the plan's start date and today is counted in whole UTC
/// epoch-days rather than by differencing two local `DateTime`s: a
/// local-midnight span that crosses a DST transition is not an exact multiple
/// of 24 hours (it is ±1h), so `difference().inDays` truncates a day short
/// and, on a 7-day boundary, reports the previous week. Mirrors the
/// `_isoToEpochDay` approach in `cycle_plan.dart`.
///
/// Dart twin of `apps/web/src/lib/training/plan_week.ts` — keep the algorithm,
/// edge cases, outputs, and test counts in lockstep.
library;

import 'dart:math' as math;

int _isoToEpochDay(String iso) {
  final parts = iso.split('-');
  final utc = DateTime.utc(
    int.parse(parts[0]),
    int.parse(parts[1]),
    int.parse(parts[2]),
  );
  return (utc.millisecondsSinceEpoch / 86400000).floor();
}

int currentPlanWeekIndex(
  String startDateIso,
  String todayIso,
  int weekCount,
) {
  final dayIndex = _isoToEpochDay(todayIso) - _isoToEpochDay(startDateIso);
  if (dayIndex < 0) return 0;
  return math.min(weekCount - 1, dayIndex ~/ 7);
}

/// Where today sits against a plan's race day (its end date). Twin of
/// `planRaceCountdown` in `plan_week.ts`.
enum PlanRaceCountdownKind { startsIn, raceIn, raceDay, racePast }

/// [days] is whole days to the start ([PlanRaceCountdownKind.startsIn]) or to
/// the race ([PlanRaceCountdownKind.raceIn]), counted in epoch-days for the
/// same DST reason as above, and 0 otherwise. Callers own the wording.
class PlanRaceCountdown {
  final PlanRaceCountdownKind kind;
  final int days;
  const PlanRaceCountdown(this.kind, this.days);

  @override
  bool operator ==(Object other) =>
      other is PlanRaceCountdown && other.kind == kind && other.days == days;

  @override
  int get hashCode => Object.hash(kind, days);

  @override
  String toString() => 'PlanRaceCountdown($kind, $days)';
}

PlanRaceCountdown planRaceCountdown(
  String startDateIso,
  String endDateIso,
  String todayIso,
) {
  final today = _isoToEpochDay(todayIso);
  final start = _isoToEpochDay(startDateIso);
  final end = _isoToEpochDay(endDateIso);
  if (today < start) {
    return PlanRaceCountdown(PlanRaceCountdownKind.startsIn, start - today);
  }
  if (today > end) {
    return const PlanRaceCountdown(PlanRaceCountdownKind.racePast, 0);
  }
  if (today == end) {
    return const PlanRaceCountdown(PlanRaceCountdownKind.raceDay, 0);
  }
  return PlanRaceCountdown(PlanRaceCountdownKind.raceIn, end - today);
}
