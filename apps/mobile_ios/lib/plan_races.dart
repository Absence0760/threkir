/// Every race a plan builds toward, not only the one on its end date
/// (decisions § 2009): a `race` workout carries its own name and A/B/C
/// priority, so a Comrades block can hold Two Oceans as a B race with its own
/// countdown and goal. Dates are ISO `yyyy-mm-dd` strings, which order
/// lexically the same as they do chronologically.
///
/// Dart twin of `apps/web/src/lib/training/plan_races.ts` — keep the
/// priority defaults, goal fallbacks, sort order, and test counts in
/// lockstep.
library;

import 'package:core_models/core_models.dart' show PlanWorkoutRow;

const List<String> racePriorities = ['A', 'B', 'C'];

/// The most hours a race goal time may hold, on every surface that reads or
/// edits one: a 240-mile race runs past 100 hours, so two digits would not do.
const int raceGoalMaxHours = 999;

class PlanRace {
  final String date;
  final String? name;
  final String priority;
  final double? distanceM;
  final int? goalTimeSec;
  final String? workoutId;

  const PlanRace({
    required this.date,
    required this.name,
    required this.priority,
    required this.distanceM,
    required this.goalTimeSec,
    required this.workoutId,
  });

  @override
  bool operator ==(Object other) =>
      other is PlanRace &&
      other.date == date &&
      other.name == name &&
      other.priority == priority &&
      other.distanceM == distanceM &&
      other.goalTimeSec == goalTimeSec &&
      other.workoutId == workoutId;

  @override
  int get hashCode =>
      Object.hash(date, name, priority, distanceM, goalTimeSec, workoutId);

  @override
  String toString() =>
      'PlanRace($date, $name, $priority, $distanceM, $goalTimeSec, $workoutId)';
}

/// The fields of a plan workout [planRaces] reads.
class PlanRaceWorkout {
  final String id;
  final String scheduledDate;
  final String kind;
  final String? raceName;
  final String? racePriority;
  final double? targetDistanceM;
  final int? targetDurationSeconds;

  const PlanRaceWorkout({
    required this.id,
    required this.scheduledDate,
    required this.kind,
    this.raceName,
    this.racePriority,
    this.targetDistanceM,
    this.targetDurationSeconds,
  });

  factory PlanRaceWorkout.fromRow(PlanWorkoutRow w) {
    final d = w.scheduledDate;
    String two(int v) => v.toString().padLeft(2, '0');
    return PlanRaceWorkout(
      id: w.id,
      scheduledDate: '${d.year.toString().padLeft(4, '0')}-'
          '${two(d.month)}-${two(d.day)}',
      kind: w.kind,
      raceName: w.raceName,
      racePriority: w.racePriority,
      targetDistanceM: w.targetDistanceM,
      targetDurationSeconds: w.targetDurationSeconds,
    );
  }
}

String? _parseRacePriority(String? value) =>
    racePriorities.contains(value) ? value : null;

/// One entry per `race` workout, sorted by date (ties by workout id). An
/// unset priority is A on the plan's end date and C anywhere else; the
/// end-date race falls back to the plan goal for a missing distance or goal
/// time. A plan with no race workout on its end date gets a synthetic A race
/// there from the plan goal, so a plan without race rows still has its race —
/// unless the plan was ended early ([trimmedAt], migration 20270830000003):
/// its end date is then the day it was cut short, not a race day, and the goal
/// race no longer happens inside it.
List<PlanRace> planRaces({
  required String endDate,
  required double goalDistanceM,
  int? goalTimeSec,
  required DateTime? trimmedAt,
  required List<PlanRaceWorkout> workouts,
}) {
  final races = <PlanRace>[];
  var endDateCovered = false;
  for (final w in workouts) {
    if (w.kind != 'race') continue;
    final onEnd = w.scheduledDate == endDate;
    if (onEnd) endDateCovered = true;
    races.add(PlanRace(
      date: w.scheduledDate,
      name: w.raceName,
      priority: _parseRacePriority(w.racePriority) ?? (onEnd ? 'A' : 'C'),
      distanceM: w.targetDistanceM ?? (onEnd ? goalDistanceM : null),
      goalTimeSec: w.targetDurationSeconds ?? (onEnd ? goalTimeSec : null),
      workoutId: w.id,
    ));
  }
  if (!endDateCovered && trimmedAt == null) {
    races.add(PlanRace(
      date: endDate,
      name: null,
      priority: 'A',
      distanceM: goalDistanceM,
      goalTimeSec: goalTimeSec,
      workoutId: null,
    ));
  }
  races.sort((a, b) {
    final byDate = a.date.compareTo(b.date);
    if (byDate != 0) return byDate;
    return (a.workoutId ?? '').compareTo(b.workoutId ?? '');
  });
  return races;
}

/// The first race on or after [todayIso] (race day itself counts), or null
/// once the last race has passed. Expects [races] sorted, as [planRaces]
/// returns them.
PlanRace? nextRace(List<PlanRace> races, String todayIso) {
  for (final r in races) {
    if (r.date.compareTo(todayIso) >= 0) return r;
  }
  return null;
}
