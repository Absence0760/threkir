// Unit tests for the step-haptic decision (lib/step_haptics.dart) and the
// vibration channel client (lib/run_haptics_bridge.dart), plus the seam the
// run screen relies on: a REAL WorkoutRunner's events, decided and played,
// reach `run_app/haptics` with the right pattern names (issue #1186).

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:run_recorder/run_recorder.dart';

import '../lib/run_haptics_bridge.dart';
import '../lib/step_haptics.dart';

WorkoutStep _step(WorkoutStepKind kind, {double distance = 400}) =>
    WorkoutStep(
      kind: kind,
      targetDistanceMetres: distance,
      targetPaceSecPerKm: 300,
      label: kind.name,
    );

StepTransitionEvent _into(WorkoutStepKind kind) => StepTransitionEvent(
      previousIndex: 0,
      currentIndex: 1,
      step: _step(kind),
    );

RunSnapshot _snap(double distance, int sec) =>
    RunSnapshot(elapsed: Duration(seconds: sec), distanceMetres: distance);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('stepHapticFor', () {
    test('a step that asks for effort buzzes step_work', () {
      expect(stepHapticFor(_into(WorkoutStepKind.rep)),
          RunHapticPattern.stepWork);
      expect(stepHapticFor(_into(WorkoutStepKind.steady)),
          RunHapticPattern.stepWork);
    });

    test('a step that eases off buzzes step_ease', () {
      for (final kind in [
        WorkoutStepKind.warmup,
        WorkoutStepKind.recovery,
        WorkoutStepKind.walk,
        WorkoutStepKind.cooldown,
      ]) {
        expect(stepHapticFor(_into(kind)), RunHapticPattern.stepEase,
            reason: kind.name);
      }
    });

    test('every step kind is decided', () {
      for (final kind in WorkoutStepKind.values) {
        expect(stepHapticFor(_into(kind)), isNotNull, reason: kind.name);
      }
    });

    test('the first step of a workout buzzes too', () {
      final first = StepTransitionEvent(
          previousIndex: -1,
          currentIndex: 0,
          step: _step(WorkoutStepKind.warmup));
      expect(stepHapticFor(first), RunHapticPattern.stepEase);
    });

    test('completion buzzes workout_complete', () {
      expect(stepHapticFor(const WorkoutCompleteEvent()),
          RunHapticPattern.workoutComplete);
    });

    test('progress, drift and abandon stay voice-only', () {
      final step = _step(WorkoutStepKind.rep);
      expect(
          stepHapticFor(StepProgressEvent(
              step: step, index: 0, kind: StepProgressKind.halfway)),
          isNull);
      expect(
          stepHapticFor(PaceDriftEvent(
              step: step, index: 0, ahead: true, deltaSecPerKm: 30)),
          isNull);
      expect(stepHapticFor(const WorkoutAbandonedEvent()), isNull);
    });
  });

  test('paceAlertHaptic maps direction to pattern', () {
    expect(paceAlertHaptic(tooSlow: true), RunHapticPattern.paceSpeedUp);
    expect(paceAlertHaptic(tooSlow: false), RunHapticPattern.paceSlowDown);
  });

  test('wire names are the ones the native tables key on', () {
    // RunHapticPatterns.kt and RunHapticsBridge.pulses (AppDelegate.swift)
    // name exactly these; RunHapticPatternsTest pins the Kotlin side.
    expect(RunHapticPattern.values.map((p) => p.wireName).toSet(), {
      'step_work',
      'step_ease',
      'workout_complete',
      'pace_speed_up',
      'pace_slow_down',
    });
  });

  group('RunHapticsBridge', () {
    const channel = MethodChannel(RunHapticsBridge.channelName);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    test('sends play with the wire name', () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return true;
      });
      await const RunHapticsBridge().play(RunHapticPattern.stepWork);
      expect(calls.single.method, 'play');
      expect(calls.single.arguments, 'step_work');
    });

    test('a platform error or a missing handler is swallowed', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'no_vibrator');
      });
      await expectLater(
          const RunHapticsBridge().play(RunHapticPattern.paceSlowDown),
          completes);
      messenger.setMockMethodCallHandler(channel, null);
      await expectLater(
          const RunHapticsBridge().play(RunHapticPattern.paceSlowDown),
          completes);
    });

    test('a real runner\'s step changes and completion reach the channel',
        () async {
      final played = <Object?>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        played.add(call.arguments);
        return true;
      });
      final runner = WorkoutRunner(steps: [
        _step(WorkoutStepKind.warmup, distance: 200),
        _step(WorkoutStepKind.rep, distance: 200),
        _step(WorkoutStepKind.recovery, distance: 200),
      ]);
      final sub = runner.events.listen((e) {
        final p = stepHapticFor(e);
        if (p != null) const RunHapticsBridge().play(p);
      });

      runner.onSnapshot(_snap(0, 0));
      runner.onSnapshot(_snap(100, 30));
      runner.onSnapshot(_snap(210, 60));
      runner.onSnapshot(_snap(420, 120));
      runner.onSnapshot(_snap(630, 180));
      await pumpEventQueue();

      expect(played, [
        'step_ease',
        'step_work',
        'step_ease',
        'workout_complete',
      ]);
      await sub.cancel();
      runner.dispose();
    });
  });
}
