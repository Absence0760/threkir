import 'package:core_models/core_models.dart' show DistanceUnit;
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:run_recorder/run_recorder.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/lock_screen_step.dart';

final _en = lookupAppLocalizations(const Locale('en'));
final _de = lookupAppLocalizations(const Locale('de'));

WorkoutStep _rep(int i, int of, {double metres = 400, int pace = 240}) =>
    WorkoutStep(
      kind: WorkoutStepKind.rep,
      repIndex: i,
      repTotal: of,
      targetDistanceMetres: metres,
      targetPaceSecPerKm: pace,
      label: 'Rep $i/$of',
    );

WorkoutStep _walk({int seconds = 90}) => WorkoutStep(
      kind: WorkoutStepKind.walk,
      targetDistanceMetres: 0,
      targetDurationSec: seconds,
      targetPaceSecPerKm: 600,
      label: 'Walk',
      paced: false,
    );

RunSnapshot _at(int sec, double metres) =>
    RunSnapshot(elapsed: Duration(seconds: sec), distanceMetres: metres);

void main() {
  group('lockScreenStep', () {
    test('null with no workout armed — a free run is unchanged', () {
      expect(lockScreenStep(null, l10n: _en, unit: DistanceUnit.km), isNull);
    });

    test('a distance rep: localized name, metres left, target pace', () {
      final runner = WorkoutRunner(steps: [_rep(3, 6)])
        ..onSnapshot(_at(0, 0))
        ..onSnapshot(_at(30, 120));
      final step = lockScreenStep(runner, l10n: _en, unit: DistanceUnit.km)!;
      expect(step.line, 'Rep 3 of 6 · 280 m to go · @ 4:00 /km');
      expect(step.index, 0);
      expect(step.isTimed, isFalse);
      expect(step.complete, isFalse);
      runner.dispose();
    });

    test('miles: yards left and a per-mile target', () {
      final runner = WorkoutRunner(steps: [_rep(1, 4)])..onSnapshot(_at(0, 0));
      final step = lockScreenStep(runner, l10n: _en, unit: DistanceUnit.mi)!;
      // 400 m = 437 yd; 4:00 /km = 6:26 /mi.
      expect(step.line, 'Rep 1 of 4 · 437 yd to go · @ 6:26 /mi');
      runner.dispose();
    });

    test('a timed walk: time left as a clock, no pace target', () {
      final runner = WorkoutRunner(steps: [_walk()])
        ..onSnapshot(_at(0, 0))
        ..onSnapshot(_at(0, 0));
      final step = lockScreenStep(runner, l10n: _en, unit: DistanceUnit.km)!;
      expect(step.line, 'Walk · 1:30 to go');
      expect(step.remaining, const Duration(seconds: 90));
      expect(step.targetText, isNull,
          reason: 'a walk-run step is effort-led — there is no pace to hold');
      runner.dispose();
    });

    test('reads in the runner\'s language, not the expander\'s English label',
        () {
      final runner = WorkoutRunner(steps: [_rep(2, 5)])..onSnapshot(_at(0, 0));
      final step = lockScreenStep(runner, l10n: _de, unit: DistanceUnit.km)!;
      expect(step.name, _de.ttsStepRepOf(2, 5));
      expect(step.remainingText, _de.runWorkoutRemainingMetres(400));
      expect(step.name, isNot(contains('Rep 2/5')));
      runner.dispose();
    });

    test('the step after a skip is a new index', () {
      final runner = WorkoutRunner(steps: [_rep(1, 2), _walk(), _rep(2, 2)])
        ..onSnapshot(_at(0, 0));
      final first = lockScreenStep(runner, l10n: _en, unit: DistanceUnit.km)!;
      runner.skipStep();
      final second = lockScreenStep(runner, l10n: _en, unit: DistanceUnit.km)!;
      expect(second.index, isNot(first.index));
      expect(second.name, 'Walk');
      runner.dispose();
    });

    test('a finished workout says so, at an index past every step', () {
      final runner = WorkoutRunner(steps: [_rep(1, 1, metres: 100)])
        ..onSnapshot(_at(0, 0))
        ..onSnapshot(_at(30, 120));
      expect(runner.isComplete, isTrue);
      final step = lockScreenStep(runner, l10n: _en, unit: DistanceUnit.km)!;
      expect(step.complete, isTrue);
      expect(step.index, 1);
      expect(step.line, _en.runWorkoutCompleteBand);
      runner.dispose();
    });

    test('an abandoned workout leaves the lock screen to the stats', () {
      final runner = WorkoutRunner(steps: [_rep(1, 3)])..onSnapshot(_at(0, 0));
      runner.abandon();
      expect(lockScreenStep(runner, l10n: _en, unit: DistanceUnit.km), isNull);
      runner.dispose();
    });

    test('over an hour left reads h:mm:ss', () {
      final runner = WorkoutRunner(steps: [_walk(seconds: 3725)])
        ..onSnapshot(_at(0, 0));
      final step = lockScreenStep(runner, l10n: _en, unit: DistanceUnit.km)!;
      expect(step.remainingText, '1:02:05 to go');
      runner.dispose();
    });
  });

  group('LockScreenStep equality', () {
    LockScreenStep step({
      int index = 2,
      String remainingText = '1:30 to go',
      Duration? remaining = const Duration(seconds: 90),
    }) =>
        LockScreenStep(
          index: index,
          name: 'Walk',
          remainingText: remainingText,
          remaining: remaining,
        );

    test('a timed step\'s countdown is not a change — the widget ticks it',
        () {
      expect(
        step(remainingText: '1:30 to go', remaining: const Duration(seconds: 90)),
        step(remainingText: '1:10 to go', remaining: const Duration(seconds: 70)),
      );
    });

    test('a distance step\'s remaining text is a change', () {
      expect(
        step(remainingText: '300 m to go', remaining: null),
        isNot(step(remainingText: '280 m to go', remaining: null)),
      );
    });

    test('a new index is a change', () {
      expect(step(index: 2), isNot(step(index: 3)));
    });
  });
}
