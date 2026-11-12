/// Re-derive a plan's paces when its goal time changes (issue #1186). Every
/// training pace is a fixed multiple of goal pace (`pacesFromGoalPace`), so the
/// paces a new goal time would generate are the old ones scaled by new goal
/// pace / old goal pace. A plan anchored on a recent 5K resolves the same goal
/// pace either way and gets no changes, which is the generator's own priority.
///
/// Only workouts still ahead and still open are touched: a completed or
/// skipped session is history, and so is anything before today.
///
/// Dart twin of `apps/web/src/lib/training/plan_repace.ts`.
library;

import 'dart:convert';

import 'package:core_models/core_models.dart' show PlanWorkoutRow;

import 'training.dart' show resolveTrainingPacesWithMeta, isWorkoutCompleted;

/// One workout's change, as an `apply_workout_adjustments` entry: `id` plus
/// only the fields that change.
typedef RepacePatch = Map<String, Object?>;

double _goalPace(double goalDistanceM, int? goalTimeSec, int? recent5kSec) =>
    resolveTrainingPacesWithMeta(
      goalDistanceM: goalDistanceM,
      goalTimeSec: goalTimeSec,
      recent5kSec: recent5kSec,
    ).goalPaceSecPerKm;

/// [structure] with every `pace_sec_per_km` scaled by [ratio]. Effort labels
/// (`pace: 'easy'`, `recovery_pace: 'jog'`) are not paces and stay as they are.
Object? scaleStructurePaces(Object? structure, double ratio) {
  if (structure is List) {
    return [for (final s in structure) scaleStructurePaces(s, ratio)];
  }
  if (structure is! Map) return structure;
  return <String, Object?>{
    for (final e in structure.entries)
      e.key as String: e.key == 'pace_sec_per_km' && e.value is num
          ? ((e.value as num) * ratio).round()
          : scaleStructurePaces(e.value, ratio),
  };
}

/// The patches a goal-time change from [oldGoalTimeSec] to [newGoalTimeSec]
/// implies for [workouts], as of [todayIso]. A race workout carrying the old
/// goal time as its target takes the new one.
List<RepacePatch> goalTimeRepacePatches({
  required double goalDistanceM,
  required int? oldGoalTimeSec,
  required int? newGoalTimeSec,
  required int? recent5kSec,
  required String todayIso,
  required List<PlanWorkoutRow> workouts,
}) {
  if (oldGoalTimeSec == newGoalTimeSec) return const [];
  final ratio = _goalPace(goalDistanceM, newGoalTimeSec, recent5kSec) /
      _goalPace(goalDistanceM, oldGoalTimeSec, recent5kSec);
  final goalChanged = oldGoalTimeSec != null &&
      newGoalTimeSec != null &&
      newGoalTimeSec > 0;
  final patches = <RepacePatch>[];
  for (final w in workouts) {
    final date = w.scheduledDate.toIso8601String().substring(0, 10);
    if (date.compareTo(todayIso) < 0) continue;
    if (isWorkoutCompleted(w) || w.skippedAt != null) continue;
    final patch = <String, Object?>{'id': w.id};
    final pace = w.targetPaceSecPerKm;
    if (ratio != 1 && pace != null) {
      final next = (pace * ratio).round();
      if (next != pace) patch['target_pace_sec_per_km'] = next;
    }
    if (ratio != 1 && w.structure != null) {
      final next = scaleStructurePaces(w.structure, ratio);
      if (jsonEncode(next) != jsonEncode(w.structure)) patch['structure'] = next;
    }
    if (goalChanged &&
        w.kind == 'race' &&
        w.targetDurationSeconds == oldGoalTimeSec) {
      patch['target_duration_seconds'] = newGoalTimeSec;
    }
    if (patch.length > 1) patches.add(patch);
  }
  return patches;
}
