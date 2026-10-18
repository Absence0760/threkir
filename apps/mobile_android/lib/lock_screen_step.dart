import 'package:core_models/core_models.dart' show DistanceUnit;
import 'package:flutter/foundation.dart';
import 'package:run_recorder/run_recorder.dart' show WorkoutRunner;

import 'l10n/gen/app_localizations.dart';
import 'preferences.dart' show UnitFormat;
import 'workout_step_name.dart';

/// The structured-workout step as both lock screens show it: Android's
/// ongoing notification and iOS's Live Activity. Every string is localized
/// and unit-formatted here, so neither native side formats anything.
@immutable
class LockScreenStep {
  const LockScreenStep({
    required this.index,
    required this.name,
    this.remainingText,
    this.remaining,
    this.targetText,
    this.complete = false,
  });

  /// Position in the workout; the step count once it is [complete]. A change
  /// here is a step change, which `LiveActivityCadence` admits at once.
  final int index;

  /// "Rep 3 of 6", "Walk", or the workout-complete line.
  final String name;

  /// "400 m to go" / "1:30 to go". For a timed step this is the frozen value
  /// a paused run shows; a running one counts down from [remaining] on-device.
  final String? remainingText;

  /// Time left on a timed step; null on a distance step.
  final Duration? remaining;

  /// "@ 4:00 /km"; null on an effort-led (walk-run) step.
  final String? targetText;

  final bool complete;

  bool get isTimed => remaining != null;

  /// "Rep 3 of 6 · 400 m to go · @ 4:00 /km", "Walk · 1:30 to go".
  String get line =>
      [name, remainingText, targetText].whereType<String>().join(' · ');

  /// A timed step's remaining time is absent, for the same reason the run
  /// clock is absent from `LiveActivityFrame`'s equality: the widget counts it
  /// down itself, so a tick is not a reason to spend an ActivityKit update.
  @override
  bool operator ==(Object other) =>
      other is LockScreenStep &&
      other.index == index &&
      other.name == name &&
      other.targetText == targetText &&
      other.complete == complete &&
      other.isTimed == isTimed &&
      (isTimed || other.remainingText == remainingText);

  @override
  int get hashCode => Object.hash(
        index,
        name,
        targetText,
        complete,
        isTimed,
        isTimed ? null : remainingText,
      );
}

/// The step [runner] is on, or null when there is no workout to show: none
/// armed, or abandoned (the run carries on as a free run, and the lock screen
/// goes back to stats alone).
LockScreenStep? lockScreenStep(
  WorkoutRunner? runner, {
  required AppLocalizations l10n,
  required DistanceUnit unit,
}) {
  if (runner == null) return null;
  final step = runner.currentStep;
  if (step == null) {
    return LockScreenStep(
      index: runner.steps.length,
      name: l10n.runWorkoutCompleteBand,
      complete: true,
    );
  }
  // An abandoned runner keeps its current step; only a finished one clears it.
  if (runner.isComplete) return null;

  final timed = step.isDurationBased;
  final remaining = timed ? runner.stepRemainingDuration : null;
  final String remainingText;
  if (remaining != null) {
    remainingText = l10n.runWorkoutRemainingDuration(_clock(remaining));
  } else if (unit == DistanceUnit.mi) {
    remainingText = l10n
        .runWorkoutRemainingYards((runner.stepRemainingMetres * 1.09361).round());
  } else {
    remainingText =
        l10n.runWorkoutRemainingMetres(runner.stepRemainingMetres.round());
  }
  final pace = step.targetPaceSecPerKm.toDouble();
  return LockScreenStep(
    index: runner.currentStepIndex,
    name: workoutStepName(step, l10n),
    remainingText: remainingText,
    remaining: remaining,
    targetText: step.paced
        ? l10n.workoutStructAtPace(
            '${UnitFormat.pace(pace, unit)} ${UnitFormat.paceLabel(unit)}')
        : null,
  );
}

/// "1:30", or "1:02:05" past the hour — the shape the iOS countdown renders,
/// so the frozen value and the ticking one read the same.
String _clock(Duration d) {
  final total = d.inSeconds;
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = (total % 60).toString().padLeft(2, '0');
  if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:$s';
  return '$m:$s';
}
