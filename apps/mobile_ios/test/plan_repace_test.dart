// Twin of apps/web/src/lib/training/plan_repace.test.ts — same cases.

import 'package:core_models/core_models.dart' show PlanWorkoutRow;
import 'package:flutter_test/flutter_test.dart';

import '../lib/plan_repace.dart';
import '../lib/training.dart' show resolveTrainingPaces;

const _half = 21097.5;

PlanWorkoutRow _wo(
  String id,
  String date, {
  String kind = 'easy',
  int? pace = 330,
  int? duration,
  Object? structure,
  String? completedRunId,
  bool manual = false,
  DateTime? skippedAt,
}) =>
    PlanWorkoutRow(
      id: id,
      weekId: 'w',
      scheduledDate: DateTime.parse(date),
      kind: kind,
      targetPaceSecPerKm: pace,
      targetDurationSeconds: duration,
      structure: structure,
      completedRunId: completedRunId,
      manuallyCompleted: manual,
      skippedAt: skippedAt,
    );

List<RepacePatch> _patches(List<PlanWorkoutRow> workouts,
        {int? oldGoal = 2 * 3600,
        int? newGoal = 1 * 3600 + 48 * 60,
        int? recent5k}) =>
    goalTimeRepacePatches(
      goalDistanceM: _half,
      oldGoalTimeSec: oldGoal,
      newGoalTimeSec: newGoal,
      recent5kSec: recent5k,
      todayIso: '2026-06-10',
      workouts: workouts,
    );

void main() {
  test('a faster goal scales every future open pace by the goal-pace ratio', () {
    final p = _patches([_wo('a', '2026-06-12')]).single;
    expect(p['target_pace_sec_per_km'], (330 * (108 / 120)).round());
  });

  test('the scaled paces are the ones a fresh plan at the new goal would carry',
      () {
    final before =
        resolveTrainingPaces(goalDistanceM: _half, goalTimeSec: 2 * 3600);
    final after = resolveTrainingPaces(
        goalDistanceM: _half, goalTimeSec: 1 * 3600 + 48 * 60);
    final p = _patches(
            [_wo('t', '2026-06-12', kind: 'tempo', pace: before.tempo)])
        .single;
    expect(((p['target_pace_sec_per_km'] as int) - after.tempo).abs(),
        lessThanOrEqualTo(1));
  });

  test('the past, completed and skipped sessions are left alone', () {
    final patches = _patches([
      _wo('past', '2026-06-09'),
      _wo('done', '2026-06-12', completedRunId: 'r1'),
      _wo('manual', '2026-06-12', manual: true),
      _wo('skipped', '2026-06-12', skippedAt: DateTime.utc(2026, 6, 12, 8)),
      _wo('today', '2026-06-10'),
    ]);
    expect(patches.map((p) => p['id']), ['today']);
  });

  test('a plan anchored on a recent 5K keeps its paces', () {
    expect(_patches([_wo('a', '2026-06-12')], recent5k: 1500), isEmpty);
  });

  test('an unchanged goal changes nothing', () {
    expect(_patches([_wo('a', '2026-06-12')], newGoal: 2 * 3600), isEmpty);
  });

  test('interval and steady paces inside the structure scale; effort labels do not',
      () {
    final structure = {
      'warmup': {'distance_m': 1500, 'pace': 'easy'},
      'repeats': {
        'count': 5,
        'distance_m': 1000,
        'pace_sec_per_km': 240,
        'recovery_distance_m': 400,
        'recovery_pace': 'jog',
      },
      'cooldown': {'distance_m': 1500, 'pace': 'easy'},
    };
    final p = _patches([
      _wo('i', '2026-06-12', kind: 'interval', pace: 240, structure: structure)
    ]).single;
    final s = p['structure'] as Map<String, Object?>;
    final repeats = s['repeats'] as Map<String, Object?>;
    expect(repeats['pace_sec_per_km'], (240 * 0.9).round());
    expect(repeats['recovery_pace'], 'jog');
    expect((s['warmup'] as Map)['pace'], 'easy');
    expect(repeats['distance_m'], 1000);
    expect((structure['repeats']!)['pace_sec_per_km'], 240,
        reason: 'the input is not mutated');
  });

  test('the goal race takes the new goal time; another race keeps its own', () {
    final patches = _patches([
      _wo('a-race', '2026-07-01', kind: 'race', pace: null, duration: 7200),
      _wo('b-race', '2026-06-20', kind: 'race', pace: null, duration: 2700),
    ]);
    expect(patches, [
      {'id': 'a-race', 'target_duration_seconds': 6480}
    ]);
  });

  test('a walk-run session with no pace target has nothing to change', () {
    expect(_patches([_wo('w', '2026-06-12', kind: 'walk_run', pace: null)]),
        isEmpty);
  });

  test('scaleStructurePaces passes scalars and null through', () {
    expect(scaleStructurePaces(null, 0.9), isNull);
    expect(scaleStructurePaces('easy', 0.9), 'easy');
    expect(
        scaleStructurePaces({
          'steady': {'pace_sec_per_km': 300}
        }, 0.9),
        {
          'steady': {'pace_sec_per_km': 270}
        });
  });
}
