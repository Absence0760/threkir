// Mirrors apps/web/src/lib/training/workout_summary.test.ts case-for-case.
import 'package:flutter_test/flutter_test.dart';

import '../lib/training.dart';
import '../lib/workout_summary.dart';

const _intervals = WorkoutStructure(
  warmup: {'distance_m': 1500, 'pace': 'easy'},
  repeats: {
    'count': 5,
    'distance_m': 1000,
    'pace_sec_per_km': 240,
    'recovery_distance_m': 400,
    'recovery_pace': 'jog',
  },
  cooldown: {'distance_m': 1500, 'pace': 'easy'},
);

const _walkRunWeek1 = WorkoutStructure(
  warmup: {'duration_s': 300, 'pace': 'easy'},
  repeats: {
    'count': 8,
    'duration_s': 60,
    'pace_sec_per_km': 420,
    'recovery_duration_s': 90,
    'recovery_pace': 'walk',
  },
  cooldown: {'duration_s': 300, 'pace': 'easy'},
);

void main() {
  test('structureSegments: a recovery sits between reps, never after the last',
      () {
    final roles = structureSegments(_intervals).map((s) => s.role).toList();
    expect(roles, [
      SegmentRole.warmup,
      SegmentRole.work, SegmentRole.recovery, SegmentRole.work,
      SegmentRole.recovery, SegmentRole.work, SegmentRole.recovery,
      SegmentRole.work, SegmentRole.recovery, SegmentRole.work,
      SegmentRole.cooldown,
    ]);
    final sum =
        structureSegments(_intervals).fold<double>(0, (s, x) => s + x.fraction);
    expect((sum - 1).abs(), lessThan(1e-9));
  });

  test('structureTotal: sums the executed steps in one measure', () {
    // 1500 + 5 × 1000 + 4 × 400 + 1500
    expect(structureTotal(_intervals), const StructureTotalDistance(9600));
    // 300 + 8 × 60 + 7 × 90 + 300
    expect(structureTotal(_walkRunWeek1), const StructureTotalDuration(1710));
  });

  test('structureTotal: a session mixing metres and seconds has no total', () {
    const mixed = WorkoutStructure(
      warmup: {'duration_s': 600, 'pace': 'easy'},
      steady: {'distance_m': 5000, 'pace_sec_per_km': 300},
    );
    expect(structureTotal(mixed), isNull);
    expect(structureSegments(mixed).length, 2);
    expect(structureTotal(null), isNull);
    expect(structureSegments(null), isEmpty);
  });

  test('walkRunPattern: week 1 reads as its timed intervals', () {
    expect(
      walkRunPattern(_walkRunWeek1),
      const WalkRunPattern(
        warmupS: 300,
        count: 8,
        runS: 60,
        walkS: 90,
        cooldownS: 300,
        totalS: 1710,
        runM: null,
      ),
    );
  });

  test('walkRunPattern: the graduation run has no walk', () {
    const grad = WorkoutStructure(
      warmup: {'duration_s': 300, 'pace': 'easy'},
      repeats: {
        'count': 1,
        'duration_s': 1500,
        'pace_sec_per_km': 420,
        'recovery_pace': 'walk',
      },
      cooldown: {'duration_s': 300, 'pace': 'easy'},
    );
    final p = walkRunPattern(grad);
    expect(p?.walkS, isNull);
    expect(p?.totalS, 2100);
  });

  test('walkRunPattern: the graduation 5K ends on its distance, its walks still timed',
      () {
    const fiveK = WorkoutStructure(
      warmup: {'duration_s': 300, 'pace': 'easy'},
      repeats: {
        'count': 1,
        'distance_m': 5000,
        'pace_sec_per_km': 420,
        'recovery_pace': 'walk',
      },
      cooldown: {'duration_s': 300, 'pace': 'easy'},
    );
    expect(
      walkRunPattern(fiveK),
      const WalkRunPattern(
        warmupS: 300,
        count: 1,
        runS: 0,
        walkS: null,
        cooldownS: 300,
        totalS: 600,
        runM: 5000,
      ),
    );
    // A distance only ends a single run; repeated distance reps are not a
    // walk-run pattern.
    expect(
      walkRunPattern(WorkoutStructure(
        warmup: fiveK.warmup,
        repeats: {...fiveK.repeats!, 'count': 2},
        cooldown: fiveK.cooldown,
      )),
      isNull,
    );
  });

  test('walkRunPattern: matches the generator for every C25K week', () {
    final plan = generatePlan(GeneratePlanInput(
      goalEvent: GoalEvent.distance5k,
      startDate: DateTime(2026, 6, 1),
      daysPerWeek: 3,
      beginnerWalkRun: true,
    ));
    for (final week in plan.weeks) {
      for (final w in week.workouts.where((x) => x.kind == WorkoutKind.walkRun)) {
        final p = walkRunPattern(w.structure);
        expect(p, isNotNull);
        if (p!.runM != null) {
          expect(p.runM, w.structure!.repeats!['distance_m']);
        } else {
          expect(p.totalS, w.targetDurationSeconds);
        }
      }
    }
  });

  test(
      'plannedWorkoutSize: a walk-run reads as minutes, its graduation 5K as 5 km, a road run as its target',
      () {
    StructureTotal? size(String kind, double? targetDistanceM,
            int? targetDurationS, Object? structure) =>
        plannedWorkoutSize(
            kind: kind,
            targetDistanceM: targetDistanceM,
            targetDurationS: targetDurationS,
            structure: structure);
    expect(size('walk_run', 2050, 1710, _walkRunWeek1.toJson()),
        const StructureTotalDuration(1710));
    expect(
      size('walk_run', 5857, 4260, {
        'warmup': {'duration_s': 300, 'pace': 'easy'},
        'repeats': {'count': 1, 'distance_m': 5000, 'recovery_pace': 'walk'},
        'cooldown': {'duration_s': 300, 'pace': 'easy'},
      }),
      const StructureTotalDistance(5000),
    );
    // No readable pattern: the stored duration, never the estimated distance.
    expect(size('walk_run', 2050, 1710, null),
        const StructureTotalDuration(1710));
    expect(size('walk_run', 2050, 1710, 'x'),
        const StructureTotalDuration(1710));
    expect(size('walk_run', 2050, null, [1]), isNull);
    expect(size('easy', 8000, 2400, null), const StructureTotalDistance(8000));
    expect(size('easy', null, 2400, null), isNull);
    expect(size('easy', 0, null, null), isNull);
    expect(size('rest', 3000, null, null), isNull);
  });

  test('walkRunPattern: null for a paced session and a distance-measured one',
      () {
    expect(walkRunPattern(_intervals), isNull);
    expect(
      walkRunPattern(WorkoutStructure(
        warmup: const {'distance_m': 800, 'pace': 'easy'},
        repeats: _walkRunWeek1.repeats,
        cooldown: _walkRunWeek1.cooldown,
      )),
      isNull,
    );
    expect(walkRunPattern(null), isNull);
  });

  test('spokenDuration: minutes, seconds, or both', () {
    expect(spokenDuration(60), const SpokenMinutes(1));
    expect(spokenDuration(300), const SpokenMinutes(5));
    expect(spokenDuration(90), const SpokenSeconds(90));
    expect(spokenDuration(45), const SpokenSeconds(45));
    expect(spokenDuration(150), const SpokenMinSec(2, 30));
    expect(spokenDuration(double.nan), const SpokenSeconds(0));
    expect(spokenDuration(-5), const SpokenSeconds(0));
  });

  test('aboutMinutes: rounds to whole minutes, never below one', () {
    expect(aboutMinutes(1710), 29);
    expect(aboutMinutes(1680), 28);
    expect(aboutMinutes(10), 1);
    expect(aboutMinutes(double.infinity), 1);
  });

  test('paceZoneName: Daniels codes and words, case-insensitive', () {
    expect(paceZoneName('T'), PaceZoneName.tempo);
    expect(paceZoneName(' mp '), PaceZoneName.marathon);
    expect(paceZoneName('I'), PaceZoneName.interval);
    expect(paceZoneName('r'), PaceZoneName.repetition);
    expect(paceZoneName('E'), PaceZoneName.easy);
    expect(paceZoneName('Z2'), isNull);
    expect(paceZoneName('\u0085t'), isNull);
    expect(paceZoneName(null), isNull);
  });
}
