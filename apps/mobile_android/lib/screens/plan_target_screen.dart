import 'package:flutter/widgets.dart';

import '../local_run_store.dart';
import '../push_target.dart';
import '../training_service.dart';
import 'plan_detail_screen.dart';
import 'workout_detail_screen.dart';

/// The screen a [PushTargetKind.plan] or [PushTargetKind.planWorkout] target
/// opens: the plan's detail, or one of its workouts. Shared by a tapped push
/// and a plan link (the home-screen widget), which reach the shell through
/// the same handoff.
Widget planTargetScreen(
  PushTarget target, {
  required TrainingService training,
  LocalRunStore? runStore,
}) {
  assert(
    target.kind == PushTargetKind.plan ||
        target.kind == PushTargetKind.planWorkout,
  );
  final workoutId = target.workoutId;
  if (target.kind == PushTargetKind.planWorkout && workoutId != null) {
    return WorkoutDetailScreen(
      training: training,
      planId: target.id!,
      workoutId: workoutId,
    );
  }
  return PlanDetailScreen(
    training: training,
    planId: target.id!,
    runStore: runStore,
  );
}
