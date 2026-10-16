// Mirrors apps/web/src/lib/training/plan_races.test.ts case-for-case.
import 'package:flutter_test/flutter_test.dart';

import '../lib/plan_races.dart';

List<PlanRace> _races(List<PlanRaceWorkout> workouts,
        {DateTime? trimmedAt}) =>
    planRaces(
      endDate: '2027-06-13',
      goalDistanceM: 91000,
      goalTimeSec: 39600,
      trimmedAt: trimmedAt,
      workouts: workouts,
    );

const _twoOceans = PlanRaceWorkout(
  id: 'w-two-oceans',
  scheduledDate: '2027-04-04',
  kind: 'race',
  raceName: 'Two Oceans Ultra',
  racePriority: 'B',
  targetDistanceM: 56000,
  targetDurationSeconds: 23400,
);
const _comrades = PlanRaceWorkout(
  id: 'w-comrades',
  scheduledDate: '2027-06-13',
  kind: 'race',
  raceName: 'Comrades',
);
const _parkrun = PlanRaceWorkout(
  id: 'w-parkrun',
  scheduledDate: '2027-02-06',
  kind: 'race',
  raceName: 'parkrun',
  targetDistanceM: 5000,
);
const _longRun = PlanRaceWorkout(
  id: 'w-long',
  scheduledDate: '2027-03-06',
  kind: 'long',
  targetDistanceM: 42195,
);

void main() {
  test(
      'planRaces: a plan with no race workouts yields one A race at its end date from the plan goal',
      () {
    expect(_races([_longRun]), const [
      PlanRace(
        date: '2027-06-13',
        name: null,
        priority: 'A',
        distanceM: 91000,
        goalTimeSec: 39600,
        workoutId: null,
      ),
    ]);
  });

  test(
      'planRaces: a race workout on the end date with no priority is A and inherits the plan goal',
      () {
    expect(_races([_comrades]), const [
      PlanRace(
        date: '2027-06-13',
        name: 'Comrades',
        priority: 'A',
        distanceM: 91000,
        goalTimeSec: 39600,
        workoutId: 'w-comrades',
      ),
    ]);
  });

  test(
      'planRaces: a mid-plan race workout with priority B keeps its own name, distance and goal time',
      () {
    final races = _races([_twoOceans]);
    expect(races.length, 2);
    expect(
      races[0],
      const PlanRace(
        date: '2027-04-04',
        name: 'Two Oceans Ultra',
        priority: 'B',
        distanceM: 56000,
        goalTimeSec: 23400,
        workoutId: 'w-two-oceans',
      ),
    );
    expect(races[1].workoutId, isNull);
    expect(races[1].priority, 'A');
  });

  test('planRaces: a mid-plan race workout with no priority defaults to C',
      () {
    final races = _races([_parkrun]);
    expect(races[0].workoutId, 'w-parkrun');
    expect(races[0].priority, 'C');
    expect(races[0].distanceM, 5000);
    expect(races[0].goalTimeSec, isNull);
  });

  test(
      'planRaces: races are sorted by date and the end-date A race is not duplicated',
      () {
    final races = _races([_comrades, _longRun, _twoOceans, _parkrun]);
    expect(
      [for (final r in races) [r.workoutId, r.priority]],
      [
        ['w-parkrun', 'C'],
        ['w-two-oceans', 'B'],
        ['w-comrades', 'A'],
      ],
    );
  });

  test(
      'nextRace: returns the first race on or after today, counting race day itself',
      () {
    final races = _races([_comrades, _twoOceans, _parkrun]);
    expect(nextRace(races, '2026-11-16')?.workoutId, 'w-parkrun');
    expect(nextRace(races, '2027-02-07')?.workoutId, 'w-two-oceans');
    expect(nextRace(races, '2027-04-04')?.workoutId, 'w-two-oceans');
    expect(nextRace(races, '2027-04-05')?.workoutId, 'w-comrades');
    expect(nextRace(races, '2027-06-13')?.workoutId, 'w-comrades');
  });

  test('planRaces: a trimmed plan has no implicit end-date race', () {
    final trimmedAt = DateTime.utc(2027, 3, 1, 9);
    final races = _races([_twoOceans, _longRun], trimmedAt: trimmedAt);
    expect([for (final r in races) r.workoutId], ['w-two-oceans']);
    expect(_races([_longRun], trimmedAt: trimmedAt), isEmpty);
    final withRace = _races([_comrades], trimmedAt: trimmedAt);
    expect(withRace.single.workoutId, 'w-comrades');
    expect(withRace.single.priority, 'A');
  });

  test('nextRace: returns null after the last race', () {
    final races = _races([_comrades, _twoOceans]);
    expect(nextRace(races, '2027-06-14'), isNull);
    expect(nextRace(const [], '2027-01-01'), isNull);
  });
}
