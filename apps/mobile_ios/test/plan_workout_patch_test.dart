import 'package:flutter_test/flutter_test.dart';

import '../lib/training_service.dart';

void main() {
  test('planWorkoutPatch: a kind away from race clears the race fields', () {
    final patch = planWorkoutPatch(
      kind: 'long',
      race: (name: 'Two Oceans', priority: 'B', goalTimeSec: 23400),
    );
    expect(patch, {
      'kind': 'long',
      'race_name': null,
      'race_priority': null,
    });
  });

  test(
      'planWorkoutPatch: a former race moving to another kind also clears '
      'its goal time', () {
    expect(planWorkoutPatch(kind: 'long', fromKind: 'race'), {
      'kind': 'long',
      'race_name': null,
      'race_priority': null,
      'target_duration_seconds': null,
    });
  });

  test(
      'planWorkoutPatch: a non-race kind change keeps a duration target the '
      'row did not get from a race', () {
    expect(planWorkoutPatch(kind: 'easy', fromKind: 'long'), {
      'kind': 'easy',
      'race_name': null,
      'race_priority': null,
    });
  });

  test('planWorkoutPatch: race fields are written as given, nulls included',
      () {
    expect(
      planWorkoutPatch(
        kind: 'race',
        race: (name: '  Two Oceans Ultra ', priority: 'B', goalTimeSec: 23400),
      ),
      {
        'kind': 'race',
        'race_name': 'Two Oceans Ultra',
        'race_priority': 'B',
        'target_duration_seconds': 23400,
      },
    );
    expect(
      planWorkoutPatch(race: (name: ' ', priority: null, goalTimeSec: null)),
      {
        'race_name': null,
        'race_priority': null,
        'target_duration_seconds': null,
      },
    );
  });

  test('planWorkoutPatch: absent arguments leave their columns alone', () {
    expect(planWorkoutPatch(), isEmpty);
    expect(
        planWorkoutPatch(
            targets: (distanceM: 8000, paceSecPerKm: null), notes: '  '),
        {
          'target_distance_m': 8000.0,
          'target_pace_sec_per_km': null,
          'notes': null,
        });
  });

  test('planWorkoutPatch: a rest kind clears every target', () {
    expect(
      planWorkoutPatch(
        kind: 'rest',
        fromKind: 'tempo',
        targets: (distanceM: 8000, paceSecPerKm: 300),
      ),
      {
        'kind': 'rest',
        'race_name': null,
        'race_priority': null,
        'target_distance_m': null,
        'target_pace_sec_per_km': null,
        'target_pace_end_sec_per_km': null,
        'target_pace_tolerance_sec': null,
        'pace_zone': null,
        'structure': null,
        'target_rpe_min': null,
        'target_rpe_max': null,
        'target_hr_min_bpm': null,
        'target_hr_max_bpm': null,
      },
    );
  });

  test(
      'planWorkoutPatch: effort and heart-rate ranges are written as given, '
      'and left alone when not passed', () {
    expect(
      planWorkoutPatch(
        rpe: (min: 3, max: 4),
        hr: (min: null, max: 125),
      ),
      {
        'target_rpe_min': 3,
        'target_rpe_max': 4,
        'target_hr_min_bpm': null,
        'target_hr_max_bpm': 125,
      },
    );
    expect(planWorkoutPatch(rpe: (min: null, max: null)), {
      'target_rpe_min': null,
      'target_rpe_max': null,
    });
  });

  test('planWorkoutPatch: a rest day clears the ranges it was handed', () {
    final patch = planWorkoutPatch(
      kind: 'rest',
      rpe: (min: 3, max: 4),
      hr: (min: null, max: 125),
    );
    expect(patch['target_rpe_min'], isNull);
    expect(patch['target_hr_max_bpm'], isNull);
    expect(patch.containsKey('target_hr_max_bpm'), isTrue);
  });
}
