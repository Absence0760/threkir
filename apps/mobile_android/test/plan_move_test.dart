// Unit tests for the days a planned workout can be moved to.
// Web twin: apps/web/src/lib/training/plan_move.test.ts (same cases).

import 'package:core_models/core_models.dart' show PlanWorkoutRow;
import 'package:flutter_test/flutter_test.dart';

import '../lib/plan_move.dart';

// Week 1 (from Monday 2031-03-10) of a plan starting Monday 2031-03-03,
// stored the way the generator writes it: a row on every day.
PlanWorkoutRow _row(
  String id,
  String date,
  String kind, {
  String weekId = 'wk1',
  bool manuallyCompleted = false,
  String? completedRunId,
}) {
  final p = date.split('-').map(int.parse).toList();
  return PlanWorkoutRow(
    id: id,
    weekId: weekId,
    scheduledDate: DateTime(p[0], p[1], p[2]),
    kind: kind,
    manuallyCompleted: manuallyCompleted,
    completedRunId: completedRunId,
  );
}

final _week = [
  _row('mon', '2031-03-10', 'rest'),
  _row('tue', '2031-03-11', 'tempo'),
  _row('wed', '2031-03-12', 'easy', manuallyCompleted: true),
  _row('thu', '2031-03-13', 'race'),
];

List<List<String?>> _pairs(List<WorkoutMoveDay> days) =>
    [for (final d in days) [d.date, d.occupant?.id]];

void main() {
  test('every other day of the week is offered, with its occupant', () {
    final days = workoutMoveDays(
      planStartIso: '2031-03-03',
      planEndIso: '2031-03-20',
      weekIndex: 1,
      workout: _week[1],
      workouts: _week,
      todayIso: '2031-03-01',
    );
    expect(_pairs(days), [
      ['2031-03-10', 'mon'],
      ['2031-03-14', null],
      ['2031-03-15', null],
      ['2031-03-16', null],
    ]);
  });

  test('a completed workout or a race is never displaced', () {
    final days = workoutMoveDays(
      planStartIso: '2031-03-03',
      planEndIso: '2031-03-20',
      weekIndex: 1,
      workout: _week[1],
      workouts: _week,
      todayIso: '2031-03-01',
    );
    expect(
      days.any((d) => d.date == '2031-03-12' || d.date == '2031-03-13'),
      isFalse,
    );
    expect(canDisplaceForMove(_week[0]), isTrue);
    expect(canDisplaceForMove(_week[2]), isFalse);
    expect(canDisplaceForMove(_week[3]), isFalse);
    expect(
      canDisplaceForMove(
          _row('linked', '2031-03-10', 'easy', completedRunId: 'run-1')),
      isFalse,
    );
  });

  test('days past the plan end or before today are not offered', () {
    final days = workoutMoveDays(
      planStartIso: '2031-03-03',
      planEndIso: '2031-03-14',
      weekIndex: 1,
      workout: _week[1],
      workouts: _week,
      todayIso: '2031-03-11',
    );
    expect([for (final d in days) d.date], ['2031-03-14']);
  });

  test('a row in another week never counts as an occupant', () {
    final rows = [
      _row('w0-mon', '2031-03-03', 'easy', weekId: 'wk0'),
      _row('stray', '2031-03-05', 'long'),
    ];
    final days = workoutMoveDays(
      planStartIso: '2031-03-03',
      planEndIso: '2031-03-20',
      weekIndex: 0,
      workout: rows[0],
      workouts: rows,
      todayIso: '2031-03-01',
    );
    expect(_pairs(days), [
      ['2031-03-04', null],
      ['2031-03-05', null],
      ['2031-03-06', null],
      ['2031-03-07', null],
      ['2031-03-08', null],
      ['2031-03-09', null],
    ]);
  });

  test('a completed workout keeps its day', () {
    expect(
      workoutMoveDays(
        planStartIso: '2031-03-03',
        planEndIso: '2031-03-20',
        weekIndex: 1,
        workout: _week[2],
        workouts: _week,
        todayIso: '2031-03-01',
      ),
      isEmpty,
    );
  });
}
