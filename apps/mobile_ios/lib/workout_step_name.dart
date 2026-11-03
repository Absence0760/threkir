import 'package:run_recorder/run_recorder.dart' show WorkoutStep, WorkoutStepKind;

import 'l10n/gen/app_localizations.dart';

/// The localized name of a workout step: "Warmup", "Rep 3 of 6", "Walk 2 of
/// 5", "Cool-down walk". One derivation for the spoken step announcement and
/// every lock-screen surface that names the step, so the runner hears and
/// reads the same words.
///
/// [WorkoutStep.label] is not used: it is the expander's English literal.
String workoutStepName(WorkoutStep step, AppLocalizations l10n) {
  // A duration-based work rep is a walk-run "Run" interval; a distance-based
  // one is an interval "Rep" (persona #22). An unpaced rep is always a
  // walk-run "Run", the graduation 5K included, and a lone one has no count.
  final run = step.isDurationBased || !step.paced;
  final hasIdx = step.repIndex != null &&
      step.repTotal != null &&
      (step.paced || step.repTotal! > 1);
  // An unpaced warm-up / cool-down is the walking one of a walk-run session:
  // say so, or a beginner reads "Warmup" and starts running.
  return switch (step.kind) {
    WorkoutStepKind.warmup =>
      step.paced ? l10n.ttsStepWarmup : l10n.ttsStepWarmupWalk,
    WorkoutStepKind.rep => hasIdx
        ? (run
            ? l10n.ttsStepRunOf(step.repIndex!, step.repTotal!)
            : l10n.ttsStepRepOf(step.repIndex!, step.repTotal!))
        : (run ? l10n.ttsStepRun : l10n.ttsStepRep),
    WorkoutStepKind.recovery => l10n.ttsStepRecovery,
    WorkoutStepKind.walk => hasIdx
        ? l10n.ttsStepWalkOf(step.repIndex!, step.repTotal!)
        : l10n.ttsStepWalk,
    WorkoutStepKind.steady => l10n.ttsStepSteady,
    WorkoutStepKind.cooldown =>
      step.paced ? l10n.ttsStepCooldown : l10n.ttsStepCooldownWalk,
  };
}
