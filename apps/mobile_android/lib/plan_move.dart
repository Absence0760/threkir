/// The days a planned workout can be moved to (decisions § 2073).
///
/// A workout moves inside its own plan week and the plan's dates, never onto a
/// day already past, and never displaces a completed workout or a race. A day
/// that already holds a row is offered with that row as its occupant: the move
/// trades the two days (`move_plan_workout`). The server enforces the week,
/// the plan's dates and completion; the past and races are the pickers' rule.
///
/// Dart twin of `apps/web/src/lib/training/plan_move.ts`. Keep the algorithm,
/// edge cases, outputs and test counts in lockstep.
library;

import 'package:core_models/core_models.dart' show PlanWorkoutRow;

import 'training.dart' show isWorkoutCompleted, toIsoDate;

class WorkoutMoveDay {
  final String date;

  /// The row already on that day, which takes the moved workout's old day.
  final PlanWorkoutRow? occupant;

  const WorkoutMoveDay(this.date, this.occupant);
}

/// Whether a move may push this workout to another day by taking its day.
bool canDisplaceForMove(PlanWorkoutRow w) =>
    !isWorkoutCompleted(w) && w.kind != 'race';

String _shiftIso(String iso, int days) {
  final p = iso.split('-');
  return toIsoDate(
    DateTime.utc(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]) + days),
  );
}

/// The days [workout] (in plan week [weekIndex]) may move to, in date order.
/// Empty for a completed workout, which keeps its day.
List<WorkoutMoveDay> workoutMoveDays({
  required String planStartIso,
  required String planEndIso,
  required int weekIndex,
  required PlanWorkoutRow workout,
  required List<PlanWorkoutRow> workouts,
  required String todayIso,
}) {
  if (isWorkoutCompleted(workout)) return const [];
  final weekStart = _shiftIso(planStartIso, weekIndex * 7);
  final own = toIsoDate(workout.scheduledDate);
  final days = <WorkoutMoveDay>[];
  for (var i = 0; i < 7; i++) {
    final date = _shiftIso(weekStart, i);
    if (date.compareTo(planEndIso) > 0) break;
    if (date == own || date.compareTo(todayIso) < 0) continue;
    PlanWorkoutRow? occupant;
    for (final o in workouts) {
      if (o.id != workout.id &&
          o.weekId == workout.weekId &&
          toIsoDate(o.scheduledDate) == date) {
        occupant = o;
        break;
      }
    }
    if (occupant != null && !canDisplaceForMove(occupant)) continue;
    days.add(WorkoutMoveDay(date, occupant));
  }
  return days;
}
