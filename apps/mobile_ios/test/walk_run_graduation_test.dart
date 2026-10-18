// Mirrors apps/web/src/lib/training/walk_run_graduation.test.ts case-for-case.
import 'package:flutter_test/flutter_test.dart';

import '../lib/training.dart';
import '../lib/walk_run_graduation.dart';

GraduationWorkout _wo(String id, String kind, String date, bool done,
        [num? runDistanceM]) =>
    GraduationWorkout(
      id: id,
      kind: kind,
      scheduledDate: date,
      done: done,
      runDistanceM: runDistanceM,
    );

void main() {
  test('walkRunGraduation: the 5K done is a graduation', () {
    final g = walkRunGraduation([
      _wo('a', 'walk_run', '2026-03-02', true),
      _wo('r', 'rest', '2026-03-03', false),
      _wo('b', 'walk_run', '2026-03-06', true, 5000),
      _wo('r2', 'rest', '2026-03-07', false),
    ]);
    expect(
        g,
        const WalkRunGraduation(
            workoutId: 'b', date: '2026-03-06', ranFiveK: true));
  });

  test(
      'walkRunGraduation: nothing until the last session is done, earlier sessions do not count',
      () {
    expect(
      walkRunGraduation([
        _wo('a', 'walk_run', '2026-03-02', true),
        _wo('b', 'walk_run', '2026-03-06', false, 5000),
      ]),
      isNull,
    );
  });

  test('walkRunGraduation: an older plan ending on a timed run graduates without a 5K',
      () {
    final g = walkRunGraduation([
      _wo('a', 'walk_run', '2026-03-02', false),
      _wo('b', 'walk_run', '2026-03-06', true),
    ]);
    expect(
        g,
        const WalkRunGraduation(
            workoutId: 'b', date: '2026-03-06', ranFiveK: false));
  });

  test('walkRunGraduation: never for a plan that is not walk-run', () {
    expect(
      walkRunGraduation([
        _wo('a', 'walk_run', '2026-03-02', true, 5000),
        _wo('e', 'easy', '2026-03-01', true),
      ]),
      isNull,
    );
    expect(walkRunGraduation([_wo('r', 'rest', '2026-03-01', false)]), isNull);
    expect(walkRunGraduation(const []), isNull);
  });

  test('walkRunGraduation: the last session is the latest date, not the last row',
      () {
    final g = walkRunGraduation([
      _wo('late', 'walk_run', '2026-03-06', true, 5000),
      _wo('early', 'walk_run', '2026-03-02', false),
      _wo('race', 'race', '2026-03-01', false),
    ]);
    expect(g?.workoutId, 'late');
  });

  test(
      'structureRunDistanceM: the run distance, or null for a timed or unreadable structure',
      () {
    expect(
        structureRunDistanceM({
          'repeats': {'count': 1, 'distance_m': 5000, 'recovery_pace': 'walk'}
        }),
        5000);
    expect(
        structureRunDistanceM({
          'repeats': {'count': 1, 'duration_s': 1800, 'recovery_pace': 'walk'}
        }),
        isNull);
    expect(
        structureRunDistanceM({
          'repeats': {'distance_m': '5000'}
        }),
        isNull);
    expect(structureRunDistanceM({'repeats': <Object>[]}), isNull);
    expect(structureRunDistanceM(null), isNull);
    expect(structureRunDistanceM('x'), isNull);
  });

  test("walkRunGraduation: the generator's plan graduates on its final session",
      () {
    final plan = generatePlan(GeneratePlanInput(
      goalEvent: GoalEvent.distance5k,
      startDate: DateTime(2026, 6, 1),
      daysPerWeek: 3,
      beginnerWalkRun: true,
    ));
    final all = plan.weeks.expand((w) => w.workouts).toList();
    final rows = [
      for (var i = 0; i < all.length; i++)
        _wo(
          'w$i',
          workoutKindDbValue(all[i].kind),
          toIsoDate(all[i].scheduledDate),
          all[i].kind == WorkoutKind.walkRun,
          structureRunDistanceM(all[i].structure?.toJson()),
        ),
    ];
    final g = walkRunGraduation(rows);
    expect(g?.ranFiveK, isTrue);
    expect(g?.date, '2026-07-31');
    expect(
      walkRunGraduation([
        for (final r in rows)
          r.id == g?.workoutId
              ? _wo(r.id, r.kind, r.scheduledDate, false, r.runDistanceM)
              : r,
      ]),
      isNull,
    );
  });
}
