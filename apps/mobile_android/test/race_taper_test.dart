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
        {int? durationS,
        Object? structure,
        String? notes,
        String? phase = 'build',
        bool completed = false,
        bool skipped = false,
        bool taperApplied = false}) =>
    RaceTaperWorkout(
      id: id,
      scheduledDate: date,
      kind: kind,
      targetDistanceM: distanceM,
      targetDurationSeconds: durationS,
      structure: structure,
      notes: notes,
      phase: phase,
      completed: completed,
      skipped: skipped,
      taperApplied: taperApplied,
    );

const _today = '2027-03-01';
// A road B race: every case below that is not about ultras pins the road
// windows, which the ultra rules must leave exactly as they were.
final _springHalf = _race('2027-04-04', 'B', 21097.5);
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
      races: [_springHalf],
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
      races: [_springHalf],
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
    expect(after(_springHalf, ['2027-04-11', '2027-04-12']), ['2027-04-11']);
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
      races: [_springHalf],
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
      races: [_springHalf],
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
            workouts: workouts, races: [_springHalf], today: '2027-04-04'),
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
        _springHalf,
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
      races: [_springHalf],
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

  test(
      'raceTaperProposals: a workout an applied taper already eased is not cut again',
      () {
    final workouts = [
      _wo('w-int', '2027-03-30', 'interval', 10000),
      _wo('w-easy', '2027-03-31', 'easy', 8000),
    ];
    final first = raceTaperProposals(
        workouts: workouts, races: [_springHalf], today: _today);
    List<RaceTaperWorkout> applied({required bool stamped}) => [
          for (final w in workouts)
            () {
              final c = first.firstWhere((x) => x.workoutId == w.id);
              return _wo(w.id, w.scheduledDate, c.toKind, c.toMetres,
                  taperApplied: stamped);
            }(),
        ];
    expect(
        _summary(raceTaperProposals(
            workouts: applied(stamped: true),
            races: [_springHalf],
            today: _today)),
        isEmpty);
    expect(
        _summary(raceTaperProposals(
            workouts: applied(stamped: false),
            races: [_springHalf],
            today: _today)),
        [
          ['w-int', RaceTaperReason.preRace, 'easy', 4225, false],
          ['w-easy', RaceTaperReason.preRace, 'easy', 3380, false],
        ]);
  });

  test('raceTaperProposals: duration shrinks by the factor the distance moved',
      () {
    final changes = raceTaperProposals(
      workouts: [
        _wo('w-easy', '2027-03-30', 'easy', 8000, durationS: 2400),
        _wo('w-timed', '2027-03-31', 'easy', null, durationS: 3600),
        _wo('w-tempo', '2027-04-02', 'tempo', 12000, durationS: 3600),
      ],
      races: [_springHalf],
      today: _today,
    );
    expect([
      for (final c in changes)
        [c.workoutId, c.toMetres, c.fromDurationS, c.toDurationS]
    ], [
      ['w-easy', 5200, 2400, 1560],
      ['w-timed', null, 3600, 2340],
      // The shakeout's 5 km cap is the factor: 5000 / 12000 of 3600 s.
      ['w-tempo', 5000, 3600, 1500],
    ]);
    expect(raceTaperPatch(changes[1]), {'target_duration_seconds': 2340});
  });

  test(
      'raceTaperProposals: a walk/run day loses repeats with the session, and '
      'the notes that described them', () {
    const intervals = {
      'warmup': {'duration_s': 300, 'pace': 'easy'},
      'repeats': {
        'count': 8,
        'duration_s': 90,
        'recovery_duration_s': 120,
        'recovery_pace': 'walk',
      },
      'cooldown': {'duration_s': 300, 'pace': 'easy'},
    };
    const continuous = {
      'warmup': {'duration_s': 300, 'pace': 'easy'},
      'repeats': {'count': 1, 'duration_s': 1800, 'recovery_pace': 'walk'},
      'cooldown': {'duration_s': 300, 'pace': 'easy'},
    };
    final changes = raceTaperProposals(
      workouts: [
        _wo('w-wr', '2027-03-30', 'walk_run', 4000,
            durationS: 2160,
            structure: intervals,
            notes: 'Walk 5 min, then run 90s / walk 120s × 8, walk 5 min.'),
        _wo('w-grad', '2027-03-31', 'walk_run', 5000,
            durationS: 2400, structure: continuous),
      ],
      races: [_springHalf],
      today: _today,
    );
    // 8 repeats × 0.65 = 5.2 → 5; 300 + 5 × 90 + 4 × 120 + 300 = 1530 s.
    expect(raceTaperPatch(changes[0]), {
      'target_distance_m': 2600,
      'target_duration_seconds': 1530,
      'structure': {
        ...intervals,
        'repeats': {...intervals['repeats']!, 'count': 5},
      },
      'notes': null,
    });
    // One continuous run: 1800 s × 0.65 = 1170 s; 300 + 1170 + 300 = 1770 s.
    expect(raceTaperPatch(changes[1]), {
      'target_distance_m': 3250,
      'target_duration_seconds': 1770,
      'structure': {
        ...continuous,
        'repeats': {...continuous['repeats']!, 'duration_s': 1170},
      },
    });
  });

  test(
      'raceTaperProposals: a session whose kind changes loses the notes and '
      'structure that described it', () {
    final changes = raceTaperProposals(
      workouts: [
        _wo('w-int', '2027-03-29', 'interval', 10000,
            notes: '6x800 at 5K pace',
            structure: const {
              'repeats': {'count': 6}
            }),
        _wo('w-long', '2027-03-30', 'long', 20000,
            notes: 'Last 5 km at marathon pace',
            structure: const {
              'steady': {'distance_m': 5000}
            }),
        _wo('w-easy', '2027-03-31', 'easy', 8000, notes: 'Flat route'),
      ],
      races: [_springHalf],
      today: _today,
    );
    expect(raceTaperPatch(changes[0]), {
      'kind': 'easy',
      'target_distance_m': 6500,
      'target_pace_sec_per_km': null,
      'target_pace_tolerance_sec': null,
      'structure': null,
      'notes': null,
    });
    expect(raceTaperPatch(changes[1]), {
      'kind': 'easy',
      'target_distance_m': 13000,
      'structure': null,
      'notes': null,
    });
    // Same kind, only shorter: the runner's own note still fits.
    expect(raceTaperPatch(changes[2]), {'target_distance_m': 5200});
  });

  test(
      'raceTaperProposals: recovery after an ultra B race adds a day per 2 km past the marathon, up to 21',
      () {
    List<String> after(PlanRace r, List<String> days) => [
          for (final c in raceTaperProposals(
            workouts: [for (final d in days) _wo('w-$d', d, 'tempo', 8000)],
            races: [r],
            today: _today,
          ))
            c.scheduledDate,
        ];
    // Two Oceans: 7 + (56 - 42.195) / 2 = 13.9 -> 14 days.
    expect(after(_twoOceans, ['2027-04-18', '2027-04-19']), ['2027-04-18']);
    // A 90 km race reaches the 21-day ceiling; 100 miles stays there.
    expect(after(_race('2027-04-04', 'B', 90000), ['2027-04-25', '2027-04-26']),
        ['2027-04-25']);
    expect(
        after(_race('2027-04-04', 'B', 160934.4), ['2027-04-25', '2027-04-26']),
        ['2027-04-25']);
    // Continuous at the marathon: the marathon and a 43 km race both take 7.
    expect(after(_race('2027-04-04', 'B', 42195), ['2027-04-11', '2027-04-12']),
        ['2027-04-11']);
    expect(after(_race('2027-04-04', 'B', 43000), ['2027-04-11', '2027-04-12']),
        ['2027-04-11']);
    // A C race stays at 2 days at any distance.
    expect(after(_race('2027-04-04', 'C', 56000), ['2027-04-06', '2027-04-07']),
        ['2027-04-06']);
  });

  test('raceTaperProposals: an ultra B race eases the 8 days before it, a road B race 6',
      () {
    List<List<Object?>> before(PlanRace r) => [
          for (final c in raceTaperProposals(
            workouts: [
              _wo('w-9', '2027-03-26', 'easy', 8000),
              _wo('w-8', '2027-03-27', 'long', 30000, durationS: 3 * 3600),
              _wo('w-7', '2027-03-28', 'long', 30000),
            ],
            races: [r],
            today: _today,
          ))
            [c.workoutId, c.reason, c.toKind, c.toMetres, c.toDurationS],
        ];
    expect(before(_twoOceans), [
      ['w-8', RaceTaperReason.preRace, 'easy', 19500, 7020],
      ['w-7', RaceTaperReason.preRace, 'easy', 19500, null],
    ]);
    expect(before(_springHalf), isEmpty);
  });
}
