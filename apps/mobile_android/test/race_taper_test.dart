// Mirrors apps/web/src/lib/training/race_taper.test.ts case-for-case.
import 'package:flutter_test/flutter_test.dart';

import '../lib/plan_races.dart';
import '../lib/race_taper.dart';

PlanRace _race(String date, String priority, double? distanceM) => PlanRace(
      date: date,
      name: 'race-$date',
      priority: priority,
      distanceM: distanceM,
      goalTimeSec: null,
      workoutId: 'r-$date',
    );

RaceTaperWorkout _wo(String id, String date, String kind, double? distanceM,
        {String? phase = 'build', bool completed = false, bool skipped = false}) =>
    RaceTaperWorkout(
      id: id,
      scheduledDate: date,
      kind: kind,
      targetDistanceM: distanceM,
      phase: phase,
      completed: completed,
      skipped: skipped,
    );

const _today = '2027-03-01';
final _twoOceans = _race('2027-04-04', 'B', 56000);

List<List<Object?>> _summary(List<RaceTaperChange> changes) => [
      for (final c in changes)
        [c.workoutId, c.reason, c.toKind, c.toMetres, c.clearsPace],
    ];

void main() {
  test(
      'raceTaperProposals: a B race eases the 6 days before it and runs quality easy',
      () {
    final changes = raceTaperProposals(
      workouts: [
        _wo('w-long', '2027-03-28', 'long', 30000),
        _wo('w-int', '2027-03-29', 'interval', 10000),
        _wo('w-easy', '2027-03-31', 'easy', 8000),
      ],
      races: [_twoOceans],
      today: _today,
    );
    expect(_summary(changes), [
      ['w-int', RaceTaperReason.preRace, 'easy', 6500, true],
      ['w-easy', RaceTaperReason.preRace, 'easy', 5200, false],
    ]);
    expect(changes[0].raceDate, '2027-04-04');
    expect(changes[0].racePriority, 'B');
    expect(changes[0].raceName, 'race-2027-04-04');
  });

  test(
      'raceTaperProposals: the 2 days before a B race carry only a shakeout capped at 5 km',
      () {
    final changes = raceTaperProposals(
      workouts: [
        _wo('w-tempo', '2027-04-02', 'tempo', 12000),
        _wo('w-easy', '2027-04-03', 'easy', 8000),
        _wo('w-walk', '2027-04-03', 'walk_run', null),
      ],
      races: [_twoOceans],
      today: _today,
    );
    expect(_summary(changes), [
      ['w-tempo', RaceTaperReason.shakeout, 'easy', 5000, true],
      ['w-easy', RaceTaperReason.shakeout, 'easy', 4000, false],
    ]);
  });

  test(
      'raceTaperProposals: recovery after a B race lasts one day per 3 km raced, 4 to 7 days',
      () {
    List<String> after(PlanRace r, List<String> days) => [
          for (final c in raceTaperProposals(
            workouts: [for (final d in days) _wo('w-$d', d, 'tempo', 8000)],
            races: [r],
            today: _today,
          ))
            c.scheduledDate,
        ];
    expect(after(_twoOceans, ['2027-04-11', '2027-04-12']), ['2027-04-11']);
    expect(after(_race('2027-04-04', 'B', 10000), ['2027-04-08', '2027-04-09']),
        ['2027-04-08']);
    expect(after(_race('2027-04-04', 'B', null), ['2027-04-09', '2027-04-10']),
        ['2027-04-09']);
  });

  test(
      'raceTaperProposals: recovery caps the long run at 75% and runs quality easy',
      () {
    final changes = raceTaperProposals(
      workouts: [
        _wo('w-int', '2027-04-06', 'interval', 10000),
        _wo('w-long', '2027-04-07', 'long', 24000),
        _wo('w-easy', '2027-04-08', 'easy', 8000),
      ],
      races: [_twoOceans],
      today: _today,
    );
    expect(_summary(changes), [
      ['w-int', RaceTaperReason.postRace, 'easy', 10000, true],
      ['w-long', RaceTaperReason.postRace, 'long', 18000, false],
    ]);
  });

  test('raceTaperProposals: a C race eases 3 days before and 2 days after', () {
    final parkrun = _race('2027-03-20', 'C', 5000);
    final changes = raceTaperProposals(
      workouts: [
        _wo('w-a', '2027-03-16', 'interval', 10000),
        _wo('w-b', '2027-03-17', 'interval', 10000),
        _wo('w-c', '2027-03-22', 'tempo', 9000),
        _wo('w-d', '2027-03-23', 'tempo', 9000),
      ],
      races: [parkrun],
      today: _today,
    );
    expect(_summary(changes), [
      ['w-b', RaceTaperReason.preRace, 'easy', 8000, true],
      ['w-c', RaceTaperReason.postRace, 'easy', 9000, true],
    ]);
    expect(changes[0].racePriority, 'C');
  });

  test(
      'raceTaperProposals: done, skipped, past, rest, race and A-taper workouts are never touched',
      () {
    final changes = raceTaperProposals(
      workouts: [
        _wo('w-done', '2027-03-30', 'tempo', 10000, completed: true),
        _wo('w-skip', '2027-03-30', 'tempo', 10000, skipped: true),
        _wo('w-rest', '2027-03-31', 'rest', null),
        _wo('w-race', '2027-04-04', 'race', 56000),
        _wo('w-other-race', '2027-04-02', 'race', 5000),
        _wo('w-taper', '2027-04-01', 'tempo', 10000, phase: 'taper'),
        _wo('w-past', '2027-03-30', 'tempo', 10000),
      ],
      races: [_twoOceans],
      today: '2027-03-31',
    );
    expect(changes, isEmpty);
  });

  test('raceTaperProposals: a race already run, or an A race, gets no window',
      () {
    final workouts = [
      _wo('w-int', '2027-04-02', 'interval', 10000),
      _wo('w-tmp', '2027-04-06', 'tempo', 8000),
    ];
    expect(
        raceTaperProposals(
            workouts: workouts, races: [_twoOceans], today: '2027-04-04'),
        isEmpty);
    expect(
        raceTaperProposals(
            workouts: workouts,
            races: [_race('2027-04-04', 'A', 42195)],
            today: _today),
        isEmpty);
  });

  test('raceTaperProposals: overlapping windows take the stronger rule', () {
    final changes = raceTaperProposals(
      workouts: [
        _wo('w-x', '2027-04-02', 'tempo', 12000),
        _wo('w-y', '2027-03-31', 'easy', 10000),
      ],
      races: [
        _race('2027-03-30', 'C', 5000),
        _race('2027-03-31', 'C', 5000),
        _twoOceans,
      ],
      today: _today,
    );
    expect(_summary(changes), [
      ['w-y', RaceTaperReason.preRace, 'easy', 6500, false],
      ['w-x', RaceTaperReason.shakeout, 'easy', 5000, true],
    ]);
    expect([for (final c in changes) [c.workoutId, c.raceDate]], [
      ['w-y', '2027-04-04'],
      ['w-x', '2027-04-04'],
    ]);
  });

  test('raceTaperPatch: writes only the columns that change', () {
    final changes = raceTaperProposals(
      workouts: [
        _wo('w-int', '2027-03-30', 'interval', 10000),
        _wo('w-easy', '2027-03-31', 'easy', 8000),
      ],
      races: [_twoOceans],
      today: _today,
    );
    expect(raceTaperPatch(changes[0]), {
      'kind': 'easy',
      'target_distance_m': 6500,
      'target_pace_sec_per_km': null,
      'target_pace_tolerance_sec': null,
      'structure': null,
    });
    expect(raceTaperPatch(changes[1]), {'target_distance_m': 5200});
  });
}
