/// "Restart this plan": the dates a restart offers and refuses. `restart_training_plan` copies the plan, moving every
/// workout by the offset between the old and new start dates.
///
/// The start follows the creation wizard (`plan_start.dart`), generalised
/// from "a Sunday" to the source plan's own start weekday: day roles are
/// offsets from the start date, and a library or coach plan may be anchored
/// on any day. A walk-run plan has no weekday-bound role, so it may start any
/// day and defaults to tomorrow, as in the wizard.
library;

import 'cycle_plan.dart' show daysBetweenIso;
import 'plan_bulk_ops.dart' show shiftIsoDate;

class RestartWorkout {
  final String kind;
  final String scheduledDate;

  const RestartWorkout({required this.kind, required this.scheduledDate});
}

/// The same test `create_training_plan` applies: every workout a walk-run,
/// rest or race day, and at least one walk-run.
bool isWalkRunPlan(List<RestartWorkout> workouts) =>
    workouts.any((w) => w.kind == 'walk_run') &&
    workouts.every(
        (w) => w.kind == 'walk_run' || w.kind == 'rest' || w.kind == 'race');

/// The earliest race on or after [todayIso], which blocks a restart: moving
/// the plan would move race day off the real date. Null when every race is
/// behind the runner, or the plan has none.
String? upcomingRaceIso(List<RestartWorkout> workouts, String todayIso) {
  String? best;
  for (final w in workouts) {
    if (w.kind != 'race') continue;
    final d = daysBetweenIso(todayIso, w.scheduledDate);
    if (d == null || d < 0) continue;
    if (best == null || w.scheduledDate.compareTo(best) < 0) {
      best = w.scheduledDate;
    }
  }
  return best;
}

/// A picked date, snapped forward to the source plan's start weekday
/// (unchanged for a walk-run plan or an unreadable date).
String alignRestartStartIso(String iso, String sourceStartIso, bool walkRun) {
  if (walkRun) return iso;
  final d = daysBetweenIso(sourceStartIso, iso);
  if (d == null) return iso;
  return shiftIsoDate(iso, (-d) % 7);
}

/// The start a restart offers first: tomorrow for a walk-run plan, otherwise
/// the source's start weekday at least a week out.
String defaultRestartStartIso(
    String sourceStartIso, String todayIso, bool walkRun) {
  if (walkRun) return shiftIsoDate(todayIso, 1);
  return alignRestartStartIso(shiftIsoDate(todayIso, 7), sourceStartIso, false);
}

/// Whether a restart may start on [iso]: not before today, and on the
/// source's start weekday unless it is a walk-run plan.
bool restartStartAllowed(
    String iso, String sourceStartIso, String todayIso, bool walkRun) {
  final fromToday = daysBetweenIso(todayIso, iso);
  final fromSource = daysBetweenIso(sourceStartIso, iso);
  if (fromToday == null || fromSource == null || fromToday < 0) return false;
  return walkRun || fromSource % 7 == 0;
}

/// Where a date of the source plan lands in the copy.
String restartedDateIso(
    String dateIso, String sourceStartIso, String newStartIso) {
  final offset = daysBetweenIso(sourceStartIso, newStartIso);
  return offset == null ? dateIso : shiftIsoDate(dateIso, offset);
}
