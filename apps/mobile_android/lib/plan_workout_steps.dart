import 'package:core_models/core_models.dart'
    show PlanWorkoutRow, TrainingPlanRow;
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:run_recorder/run_recorder.dart'
    show WorkoutStep, expandWorkoutSteps;

import 'training.dart' show resolveTrainingPaces;

/// The symbolic pace bag that resolves `'easy'`, `'jog'`, `'tempo'`, etc. for
/// [expandWorkoutSteps]. Plans on this codebase don't store an explicit
/// `paces` jsonb — the bag is re-derived from the goal with the same
/// `resolveTrainingPaces` the generator uses, so the running-time bands match
/// what the editor showed.
///
/// One derivation for every surface that executes a workout: the run screen's
/// runner and the step list the phone pushes to a watch. Two copies would let
/// the wrist run a rep at a different pace from the phone.
///
/// Empty on a null plan, and on a plan whose goal cannot be resolved (a NaN
/// goal pace, a zero-distance goal): the expander then falls back to each
/// step's own target, which is a hint degrading rather than a run failing.
Map<String, int> planPaceBag(TrainingPlanRow? plan) {
  if (plan == null) return const {};
  try {
    final tp = resolveTrainingPaces(
      goalDistanceM: plan.goalDistanceM,
      goalTimeSec: plan.goalTimeSeconds,
      recent5kSec: plan.current5kSeconds,
    );
    return <String, int>{
      'easy': tp.easy,
      'jog': tp.easy + 60,
      'marathon': tp.marathon,
      'tempo': tp.tempo,
      'interval': tp.interval,
      'repetition': tp.repetition,
    };
  } catch (e, st) {
    debugPrint('planPaceBag failed for plan ${plan.id}: $e\n$st');
    return const {};
  }
}

/// Expand a planned workout into the steps a runner executes, with its own
/// tolerance and its own fallback target for an unstructured session.
List<WorkoutStep> expandPlanWorkoutSteps(
  PlanWorkoutRow workout, {
  Map<String, int> paces = const {},
}) {
  final structure = workout.structure is Map<String, dynamic>
      ? workout.structure as Map<String, dynamic>
      : null;
  return expandWorkoutSteps(
    structure: structure,
    paces: paces,
    toleranceSecPerKm: workout.targetPaceToleranceSec ?? 10,
    fallbackDistanceMetres: workout.targetDistanceM,
    fallbackPaceSecPerKm: workout.targetPaceSecPerKm,
  );
}
