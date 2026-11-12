import 'package:run_recorder/run_recorder.dart';

/// The vibration patterns a run can ask the phone for. Each one is meant to
/// be told apart by feel alone, through a pocket, with the screen off — the
/// whole point of a haptic cue is the runner who is not looking and may not
/// be listening (audio off, minimal voice mode, a podcast over the cue).
///
/// [wireName] is the method-channel argument; the native pattern tables key
/// on it (`RunHapticPatterns.kt` on Android, `RunHapticsBridge` in iOS
/// `AppDelegate.swift`), and both their tests name the same five.
enum RunHapticPattern {
  /// A step that asks for effort begins: a rep (or the "Run" of a run/walk)
  /// or a steady block. Three long pulses.
  stepWork('step_work'),

  /// A step that lets the runner ease off begins: warm-up, recovery, walk,
  /// cool-down. Two long pulses.
  stepEase('step_ease'),

  /// The last step finished. One long pulse then two short.
  workoutComplete('workout_complete'),

  /// Pace alert, running too slow. Two sharp pulses.
  paceSpeedUp('pace_speed_up'),

  /// Pace alert, running too fast. One sharp pulse.
  paceSlowDown('pace_slow_down');

  const RunHapticPattern(this.wireName);

  final String wireName;
}

/// Which pattern, if any, a workout-runner event should buzz. Null for the
/// events that stay voice-only: the in-step progress and pace-drift nudges
/// are frequent enough that buzzing them would teach the runner to ignore
/// the buzz, and an abandon is the runner's own tap with the screen on.
RunHapticPattern? stepHapticFor(WorkoutExecEvent event) {
  if (event is StepTransitionEvent) {
    return switch (event.step.kind) {
      WorkoutStepKind.rep || WorkoutStepKind.steady => RunHapticPattern.stepWork,
      WorkoutStepKind.warmup ||
      WorkoutStepKind.recovery ||
      WorkoutStepKind.walk ||
      WorkoutStepKind.cooldown =>
        RunHapticPattern.stepEase,
    };
  }
  if (event is WorkoutCompleteEvent) return RunHapticPattern.workoutComplete;
  return null;
}

/// The pace-alert pattern for a drift in the given direction.
RunHapticPattern paceAlertHaptic({required bool tooSlow}) =>
    tooSlow ? RunHapticPattern.paceSpeedUp : RunHapticPattern.paceSlowDown;
