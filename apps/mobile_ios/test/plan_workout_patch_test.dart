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
    expect(planWorkoutPatch(targetDistanceM: 8000, notes: '  '), {
      'target_distance_m': 8000.0,
      'notes': null,
    });
  });
}
