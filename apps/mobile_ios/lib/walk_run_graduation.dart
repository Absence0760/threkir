/// The couch-to-5K completion moment: whether a walk-run plan's runner has
/// graduated, which is when the plan's last walk-run session (the 5K the
/// generator ends on, [kWalkRunGraduationM]) is done. Pure; the plan page
/// shows the celebration and the next step off it.
///
/// Mirrors `apps/web/src/lib/training/walk_run_graduation.ts` — keep in
/// lockstep (TS↔Dart parity pair, equal test counts).
library;

import 'plan_restart.dart' show RestartWorkout, isWalkRunPlan;
import 'training.dart' show kWalkRunGraduationM;

class GraduationWorkout {
  final String id;
  final String kind;

  /// ISO scheduled date (YYYY-MM-DD).
  final String scheduledDate;

  /// Done: linked to a run or marked complete.
  final bool done;

  /// The distance the session's one run ends on, when it ends on one
  /// (`structure.repeats.distance_m`).
  final num? runDistanceM;

  const GraduationWorkout({
    required this.id,
    required this.kind,
    required this.scheduledDate,
    required this.done,
    this.runDistanceM,
  });
}

class WalkRunGraduation {
  final String workoutId;

  /// ISO date of the graduation session.
  final String date;

  /// The last session was the 5K. A plan generated before the graduation run
  /// ended on a 5K finished on a timed run instead, and is told so.
  final bool ranFiveK;

  const WalkRunGraduation({
    required this.workoutId,
    required this.date,
    required this.ranFiveK,
  });

  @override
  bool operator ==(Object other) =>
      other is WalkRunGraduation &&
      other.workoutId == workoutId &&
      other.date == date &&
      other.ranFiveK == ranFiveK;

  @override
  int get hashCode => Object.hash(workoutId, date, ranFiveK);
}

/// The distance a stored `plan_workouts.structure` ends its run on
/// (`repeats.distance_m`), or null when it ends on time or is unreadable.
num? structureRunDistanceM(Object? structure) {
  if (structure is! Map) return null;
  final r = structure['repeats'];
  if (r is! Map) return null;
  final d = r['distance_m'];
  return d is num && d.isFinite && d > 0 ? d : null;
}

/// The graduation, or null when the plan is not a walk-run plan or its last
/// walk-run session is not done yet. A skipped last session is not a
/// graduation. Of two sessions on the last date, the later in plan order is
/// the last.
WalkRunGraduation? walkRunGraduation(List<GraduationWorkout> workouts) {
  if (!isWalkRunPlan([
    for (final w in workouts)
      RestartWorkout(kind: w.kind, scheduledDate: w.scheduledDate),
  ])) {
    return null;
  }
  GraduationWorkout? last;
  for (final w in workouts) {
    if (w.kind != 'walk_run') continue;
    if (last == null || w.scheduledDate.compareTo(last.scheduledDate) >= 0) {
      last = w;
    }
  }
  if (last == null || !last.done) return null;
  final run = last.runDistanceM;
  return WalkRunGraduation(
    workoutId: last.id,
    date: last.scheduledDate,
    ranFiveK: run != null && run >= kWalkRunGraduationM,
  );
}
