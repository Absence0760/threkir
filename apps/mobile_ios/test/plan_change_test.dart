// ignore_for_file: avoid_relative_lib_imports
// Mirrors apps/web/src/lib/training/plan_change.test.ts case-for-case.
import 'package:flutter_test/flutter_test.dart';

import '../lib/plan_change.dart';

const _rows = [
  PlanChangeWorkoutRow(
    id: 'w2',
    scheduledDate: '2027-11-17',
    kind: 'tempo',
    targetDistanceM: 8000,
    targetDurationSeconds: null,
    skipped: false,
  ),
  PlanChangeWorkoutRow(
    id: 'w1',
    scheduledDate: '2027-11-16',
    kind: 'easy',
    targetDistanceM: 10000,
    targetDurationSeconds: 3600,
    skipped: false,
  ),
  PlanChangeWorkoutRow(
    id: 'w3',
    scheduledDate: '2027-11-18',
    kind: 'rest',
    targetDistanceM: null,
    targetDurationSeconds: null,
    skipped: false,
  ),
];
const _weeks = [
  PlanChangeWeekRow(id: 'k1', weekIndex: 1, targetVolumeM: 30000),
  PlanChangeWeekRow(id: 'k0', weekIndex: 0, targetVolumeM: 28000),
];

void main() {
  test('the status vocabulary is the CHECK set, and anything else reads as unknown', () {
    expect(planChangeStatuses,
        ['pending', 'approved', 'declined', 'withdrawn', 'overridden']);
    for (final s in planChangeStatuses) {
      expect(parsePlanChangeStatus(s), s);
    }
    expect(parsePlanChangeStatus('applied'), isNull);
    expect(parsePlanChangeStatus(null), isNull);
  });

  test('only objects with a string id are changes', () {
    expect(parseChangeList(null), isEmpty);
    expect(parseChangeList({'id': 'x'}), isEmpty);
    expect(
      parseChangeList([
        {'id': 'a'},
        {'id': 3},
        null,
        ['id'],
        'id',
        {'id': 'b', 'skip': true},
      ]),
      [
        {'id': 'a'},
        {'id': 'b', 'skip': true},
      ],
    );
  });

  test('ids are listed in stored order', () {
    final ids = planChangeIds([
      {'id': 'w2'},
      {'id': 'w1'},
    ], [
      {'id': 'k0', 'target_volume_m': 1},
    ]);
    expect(ids.workoutIds, ['w2', 'w1']);
    expect(ids.weekIds, ['k0']);
  });

  test('a scaled workout keeps what the change does not name', () {
    final r = planChangeLines([
      {'id': 'w1', 'target_distance_m': 9000},
    ], const [], _rows, _weeks);
    expect(r.workouts, hasLength(1));
    expect(
      r.workouts[0].before,
      const PlanChangeWorkoutState(
        scheduledDate: '2027-11-16',
        kind: 'easy',
        distanceM: 10000,
        durationS: 3600,
        skipped: false,
      ),
    );
    expect(
      r.workouts[0].after,
      const PlanChangeWorkoutState(
        scheduledDate: '2027-11-16',
        kind: 'easy',
        distanceM: 9000,
        durationS: 3600,
        skipped: false,
      ),
    );
  });

  test('an ease to recovery, a move and a skip each land on their own line, sorted by the current day', () {
    final r = planChangeLines([
      {'id': 'w3', 'scheduled_date': '2027-11-19'},
      {
        'id': 'w2',
        'kind': 'recovery',
        'target_distance_m': 5000,
        'target_pace_sec_per_km': null,
      },
      {'id': 'w1', 'skip': true},
    ], const [], _rows, _weeks);
    expect([for (final l in r.workouts) l.workoutId], ['w1', 'w2', 'w3']);
    expect(r.workouts[0].after.skipped, isTrue);
    expect(r.workouts[1].after.kind, 'recovery');
    expect(r.workouts[1].after.distanceM, 5000);
    expect(r.workouts[2].after.scheduledDate, '2027-11-19');
    expect(r.unreadable, 0);
  });

  test('a malformed field keeps the current value rather than inventing one', () {
    final r = planChangeLines([
      {'id': 'w1', 'target_distance_m': 'lots', 'kind': 7, 'skip': 'yes'},
    ], const [], _rows, _weeks);
    expect(r.workouts[0].after, r.workouts[0].before);
  });

  test('an explicit null clears the target', () {
    final r = planChangeLines([
      {'id': 'w1', 'target_duration_seconds': null},
    ], const [], _rows, _weeks);
    expect(r.workouts[0].after.durationS, isNull);
  });

  test('week targets are listed by week, and unreadable rows are counted, not shown', () {
    final r = planChangeLines([
      {'id': 'gone', 'target_distance_m': 1},
    ], [
      {'id': 'k1', 'target_volume_m': 27000},
      {'id': 'k0', 'target_volume_m': 25200},
      {'id': 'k9', 'target_volume_m': 1},
    ], _rows, _weeks);
    expect(r.workouts, isEmpty);
    expect([for (final w in r.weeks) (w.weekId, w.weekIndex, w.beforeM, w.afterM)], [
      ('k0', 0, 28000, 25200),
      ('k1', 1, 30000, 27000),
    ]);
    expect(r.unreadable, 2);
  });
}
