import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:run_recorder/run_recorder.dart' show WorkoutStep, WorkoutStepKind;

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/workout_step_name.dart';

// The name the runner hears announced and reads on the lock screen for each
// step. A beginner on a walk-run session must hear "walk" on an unpaced
// warm-up, and "Run", never "Rep", for a timed interval.
void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));

  WorkoutStep step(
    WorkoutStepKind kind, {
    int? index,
    int? total,
    int? durationS,
    bool paced = true,
  }) =>
      WorkoutStep(
        kind: kind,
        repIndex: index,
        repTotal: total,
        targetDistanceMetres: durationS == null ? 400 : 0,
        targetDurationSec: durationS,
        targetPaceSecPerKm: paced ? 300 : 0,
        label: 'expander literal',
        paced: paced,
      );

  String name(WorkoutStep s) => workoutStepName(s, l10n);

  test('a paced warm-up and cool-down are named plainly', () {
    expect(name(step(WorkoutStepKind.warmup)), 'Warmup');
    expect(name(step(WorkoutStepKind.cooldown)), 'Cooldown');
  });

  test('an unpaced warm-up and cool-down say walk', () {
    expect(name(step(WorkoutStepKind.warmup, paced: false)), 'Warm-up walk');
    expect(name(step(WorkoutStepKind.cooldown, paced: false)), 'Cool-down walk');
  });

  test('a distance rep is a Rep, counted when it has an index', () {
    expect(name(step(WorkoutStepKind.rep, index: 3, total: 6)), 'Rep 3 of 6');
    expect(name(step(WorkoutStepKind.rep)), 'Rep');
  });

  test('a timed rep is a Run, counted when it has an index', () {
    expect(name(step(WorkoutStepKind.rep, index: 2, total: 8, durationS: 60)),
        'Run 2 of 8');
    expect(name(step(WorkoutStepKind.rep, durationS: 60)), 'Run');
  });

  test('an unpaced rep is a Run, and a lone one has no count', () {
    expect(name(step(WorkoutStepKind.rep, index: 2, total: 5, paced: false)),
        'Run 2 of 5');
    // The graduation 5K: one unpaced rep, so "Run 1 of 1" would read oddly.
    expect(name(step(WorkoutStepKind.rep, index: 1, total: 1, paced: false)),
        'Run');
  });

  test('a walk is counted only when there is more than one', () {
    expect(name(step(WorkoutStepKind.walk, index: 2, total: 5, paced: false)),
        'Walk 2 of 5');
    expect(name(step(WorkoutStepKind.walk, index: 1, total: 1, paced: false)),
        'Walk');
    expect(name(step(WorkoutStepKind.walk, paced: false)), 'Walk');
  });

  test('recovery and steady steps', () {
    expect(name(step(WorkoutStepKind.recovery, index: 1, total: 4)), 'Recovery');
    expect(name(step(WorkoutStepKind.steady)), 'Steady');
  });

  test('never reads the expander literal', () {
    for (final kind in WorkoutStepKind.values) {
      expect(name(step(kind)), isNot(contains('expander literal')),
          reason: '$kind');
    }
  });
}
