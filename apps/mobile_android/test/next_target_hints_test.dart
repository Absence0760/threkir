import 'package:flutter_test/flutter_test.dart';

import '../lib/gym_progression.dart';
import '../lib/next_target_hints.dart';

HintRoutineExercise _exercise(
  String exerciseName,
  int targetReps, [
  ProgressionScheme progression = ProgressionScheme.linear,
]) =>
    HintRoutineExercise(
      exerciseName: exerciseName,
      progression: progression,
      progressionParams: const {},
      sets: [(targetRepsMin: targetReps, targetRepsMax: targetReps)],
    );

HintLoggedSet _logged(String exerciseName, num weightKg, num reps) =>
    HintLoggedSet(
      exerciseName: exerciseName,
      weightKg: weightKg,
      reps: reps,
      setType: 'working',
    );

void main() {
  test('a lift programmed into two blocks yields one hint, from the first block',
      () {
    // Heavy top set then back-offs: the same lift in two routine blocks, both
    // on a scheme. One hint per block put two chips on the review for the same
    // lift, and web keyed its list by exerciseKey and crashed on the duplicate.
    final hints = buildNextTargetHints(
      exercises: [
        _exercise('Squat', 5),
        _exercise('Bench Press', 5),
        _exercise('squat', 8),
      ],
      sets: [
        _logged('Squat', 100, 5),
        _logged('Bench Press', 60, 5),
        _logged('squat', 80, 8),
      ],
      history: const [],
    );
    final keys = hints.map((h) => h.exerciseKey).toList();
    expect(keys.toSet().length, keys.length);
    expect(keys, ['squat', 'bench press']);
    expect(hints[0].exerciseName, 'Squat');
    expect(hints[0].suggestedRepsMin, 5);
    expect(hints[0].currentTopKg, 100);
  });

  test('a lift on no scheme or with no logged sets gets no hint', () {
    final hints = buildNextTargetHints(
      exercises: [
        _exercise('Squat', 5, ProgressionScheme.none),
        _exercise('Deadlift', 5),
      ],
      sets: [_logged('Squat', 100, 5)],
      history: const [],
    );
    expect(hints, isEmpty);
  });

  test('a second block still speaks for the lift when the first is on no scheme',
      () {
    final hints = buildNextTargetHints(
      exercises: [
        _exercise('Squat', 5, ProgressionScheme.none),
        _exercise('Squat', 8),
      ],
      sets: [_logged('Squat', 80, 8)],
      history: const [],
    );
    expect(hints.length, 1);
    expect(hints[0].suggestedRepsMin, 8);
  });
}
