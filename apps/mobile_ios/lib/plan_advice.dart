/// The advice line a plan week or a workout shows, read from what the row
/// already holds rather than from an English sentence the generator saved
/// into `notes` (decisions § 2348). Pure; each surface localizes the kind.
///
/// Mirrors `apps/web/src/lib/training/plan_advice.ts` — keep in lockstep
/// (TS↔Dart parity pair, equal test counts).
library;

import 'training.dart' show isUltraDistance;

enum WeekAdviceKind { race, taper, graduation, walkBreaks, backToBack }

WeekAdviceKind? weekAdviceKind(String phase, Iterable<String> workoutKinds) {
  if (phase == 'race') return WeekAdviceKind.race;
  if (phase == 'taper') return WeekAdviceKind.taper;
  if (phase == 'graduation') return WeekAdviceKind.graduation;
  if (workoutKinds.contains('walk_run')) return WeekAdviceKind.walkBreaks;
  // The ultra generator opens the week on Sunday's long run and closes it on
  // Saturday's, the first half of the next weekend's pair.
  return workoutKinds.where((k) => k == 'long').length >= 2
      ? WeekAdviceKind.backToBack
      : null;
}

enum WorkoutAdviceKind {
  easy,
  long,
  timeOnFeet,
  tempo,
  interval,
  marathonPace,
  walkRun,
  race,
  ultraRace,
  rest,
}

/// A long run set by time with no pace is a time-on-feet run (the ultra
/// generator's shape); a race past the marathon is an ultra race.
WorkoutAdviceKind workoutAdviceKind({
  required String kind,
  double? targetDistanceM,
  int? targetDurationSeconds,
  int? targetPaceSecPerKm,
}) =>
    switch (kind) {
      'easy' || 'recovery' => WorkoutAdviceKind.easy,
      'long' => targetDurationSeconds != null &&
              targetDurationSeconds > 0 &&
              targetPaceSecPerKm == null
          ? WorkoutAdviceKind.timeOnFeet
          : WorkoutAdviceKind.long,
      'tempo' => WorkoutAdviceKind.tempo,
      'interval' => WorkoutAdviceKind.interval,
      'marathon_pace' => WorkoutAdviceKind.marathonPace,
      'walk_run' => WorkoutAdviceKind.walkRun,
      'race' => targetDistanceM != null && isUltraDistance(targetDistanceM)
          ? WorkoutAdviceKind.ultraRace
          : WorkoutAdviceKind.race,
      _ => WorkoutAdviceKind.rest,
    };
