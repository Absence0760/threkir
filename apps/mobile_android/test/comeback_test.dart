import 'package:flutter_test/flutter_test.dart';

import '../lib/comeback.dart';
import '../lib/plan_ramp.dart';
import '../lib/self_load.dart';
import '../lib/training.dart';
import '../lib/training_load.dart' show kLayoffResetDays;

const int _dayMs = 86400000;
final int _now = DateTime.parse('2026-08-14T12:00:00.000Z').millisecondsSinceEpoch;

String _iso(int ms) =>
    DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toIso8601String();

RunForVolume _run(num daysAgo, double distanceM, [String activityType = 'run']) {
  return RunForVolume(
    startedAt: _iso(_now - (daysAgo * _dayMs).round()),
    distanceM: distanceM,
    activityType: activityType,
  );
}

/// A runner who trained 40 km a week for four weeks, took [layoffDays] off,
/// and has just logged [thisWeekM] in the last seven days.
List<RunForVolume> _comebackRunner(
  num layoffDays,
  double thisWeekM, [
  double baseWeeklyM = 40000,
]) {
  final lastBefore = 1 + layoffDays;
  return [
    _run(1, thisWeekM),
    _run(lastBefore, baseWeeklyM),
    _run(lastBefore + 7, baseWeeklyM),
    _run(lastBefore + 14, baseWeeklyM),
    _run(lastBefore + 21, baseWeeklyM),
  ];
}

void _expectSame(ComebackLoad a, ComebackLoad b) {
  expect(a.verdict, b.verdict);
  expect(a.layoffDays, b.layoffDays);
  expect(a.layoffWeeks, b.layoffWeeks);
  expect(a.thisWeekM, b.thisWeekM);
  expect(a.preLayoffWeeklyM, b.preLayoffWeeklyM);
  expect(a.share, b.share);
}

void main() {
  test('the layoff threshold is the fitness-reset one, not a second number', () {
    expect(kLayoffMinDays, kLayoffResetDays);
  });

  test('a gentle first week back is graded easing_in', () {
    final load = comebackLoad(_comebackRunner(70, 12000), _now);
    expect(load.verdict, ComebackVerdict.easingIn);
    expect(load.thisWeekM, 12000);
    expect(load.preLayoffWeeklyM, 160000 / kChronicWindowWeeks);
    expect((load.share - 0.3).abs() < 1e-9, isTrue);
    expect(load.layoffDays, 70);
    expect(load.layoffWeeks, 10);
  });

  test('a big first week back is graded steep', () {
    final load = comebackLoad(_comebackRunner(70, 36000), _now);
    expect(load.verdict, ComebackVerdict.steep);
    expect((load.share - 0.9).abs() < 1e-9, isTrue);
  });

  test('the steep threshold is exclusive — exactly half the old base still eases in', () {
    final half = kReturnWeekShare * 40000;
    expect(comebackLoad(_comebackRunner(70, half), _now).verdict,
        ComebackVerdict.easingIn);
    expect(comebackLoad(_comebackRunner(70, half + 1), _now).verdict,
        ComebackVerdict.steep);
  });

  test('layoff weeks round to nearest so a break is never understated', () {
    // 32 days is 4.57 weeks — the case that separates rounding from flooring,
    // which would report 4 and undersell the break by most of a week.
    expect(comebackLoad(_comebackRunner(32, 12000), _now).layoffWeeks, 5);
    expect(comebackLoad(_comebackRunner(45, 12000), _now).layoffWeeks, 6);
  });

  test('a rest week shorter than the layoff threshold is not a comeback', () {
    final load = comebackLoad(_comebackRunner(kLayoffMinDays - 2, 30000), _now);
    expect(load.verdict, ComebackVerdict.insufficient);
  });

  test('a break long enough to reset fitness is a comeback', () {
    final load = comebackLoad(_comebackRunner(kLayoffMinDays, 30000), _now);
    expect(load.verdict, isNot(ComebackVerdict.insufficient));
  });

  test('a base too stale to anchor against says nothing rather than reassuring', () {
    final stale = comebackLoad(_comebackRunner(kLayoffMaxDays + 1, 30000), _now);
    expect(stale.verdict, ComebackVerdict.insufficient);
    expect(stale.share, 0);
    expect(stale.layoffDays, 0);
    final fresh = comebackLoad(_comebackRunner(kLayoffMaxDays, 30000), _now);
    expect(fresh.verdict, isNot(ComebackVerdict.insufficient));
  });

  test('a single run before the break is not a base to come back to', () {
    final load = comebackLoad([_run(1, 30000), _run(71, 40000)], _now);
    expect(load.verdict, ComebackVerdict.insufficient);
  });

  test('the pre-break base needs kMinActiveWeeks of its own windows', () {
    final twoWeeks = [_run(1, 30000), _run(71, 40000), _run(78, 40000)];
    expect(comebackLoad(twoWeeks, _now).verdict, ComebackVerdict.insufficient);
    expect(kMinActiveWeeks, 3);
    final threeWeeks = [...twoWeeks, _run(85, 40000)];
    expect(comebackLoad(threeWeeks, _now).verdict,
        isNot(ComebackVerdict.insufficient));
  });

  test('a week with no running is not graded as a gentle return', () {
    final idle = _comebackRunner(70, 12000).sublist(1);
    expect(comebackLoad(idle, _now).verdict, ComebackVerdict.insufficient);
  });

  test('a runner who never stopped is not on a comeback', () {
    final steady = [_run(1, 40000), _run(8, 40000), _run(15, 40000), _run(22, 40000)];
    expect(comebackLoad(steady, _now).verdict, ComebackVerdict.insufficient);
  });

  test('an empty history says nothing', () {
    expect(comebackLoad(const [], _now).verdict, ComebackVerdict.insufficient);
  });

  test('a run stamped in the future does not inflate the break it appears to open', () {
    // A clock 40 days ahead puts today's run in the future; the hole between
    // it and the runner's last real session reads as 70 days unclamped, and
    // 30 — the break they actually took — once the stamp is pulled back to now.
    final runs = [
      _run(-40, 10000),
      _run(30, 40000),
      _run(37, 40000),
      _run(44, 40000),
      _run(51, 40000),
    ];
    final load = comebackLoad(runs, _now);
    expect(load.layoffDays, 30);
    expect(load.thisWeekM, 10000);
  });

  test('a skewed stamp grades identically to an honest one', () {
    final base = [_run(60, 40000), _run(67, 40000), _run(74, 40000), _run(81, 40000)];
    final skewed = comebackLoad([_run(-100, 8000), ...base], _now);
    final honest = comebackLoad([_run(0, 8000), ...base], _now);
    _expectSame(skewed, honest);
    expect(honest.layoffDays, 60);
  });

  test('the two load cards are mutually exclusive by construction', () {
    final cases = <List<RunForVolume>>[
      _comebackRunner(70, 36000),
      _comebackRunner(70, 12000),
      _comebackRunner(kLayoffMinDays - 2, 30000),
      [_run(1, 40000), _run(8, 40000), _run(15, 40000), _run(22, 40000)],
      // Back for three consecutive weeks: the ratio can carry the question
      // again, so the comeback card must stand down.
      [
        _run(1, 30000),
        _run(8, 20000),
        _run(15, 10000),
        _run(80, 40000),
        _run(87, 40000),
        _run(94, 40000),
      ],
      const [],
    ];
    for (final runs in cases) {
      final ratio = shouldSurfaceSelfLoad(selfLoad(runs, _now));
      final comeback = shouldSurfaceComeback(comebackLoad(runs, _now));
      expect(ratio && comeback, isFalse,
          reason: 'both load cards surfaced for the same history');
    }
  });

  test('a returned runner with three active weeks is handed back to the ratio card', () {
    final runs = [
      _run(1, 30000),
      _run(8, 20000),
      _run(15, 10000),
      _run(80, 40000),
      _run(87, 40000),
      _run(94, 40000),
    ];
    expect(comebackLoad(runs, _now).verdict, ComebackVerdict.insufficient);
    expect(shouldSurfaceSelfLoad(selfLoad(runs, _now)), isTrue);
  });

  test('the most recent break is the one graded, not an older one', () {
    final runs = [
      _run(1, 30000),
      _run(41, 40000),
      _run(48, 40000),
      _run(55, 40000),
      _run(62, 40000),
      // An older, longer break sits behind a full pre-break base.
      _run(400, 90000),
    ];
    final load = comebackLoad(runs, _now);
    expect(load.layoffDays, 40);
    expect(load.preLayoffWeeklyM, 160000 / kChronicWindowWeeks);
  });

  test('cycling is not running volume on either side of the break', () {
    final runs = [
      _run(1, 12000),
      _run(2, 60000, 'cycle'),
      _run(71, 40000),
      _run(78, 40000),
      _run(85, 40000),
      _run(86, 100000, 'cycle'),
    ];
    final load = comebackLoad(runs, _now);
    expect(load.thisWeekM, 12000);
    expect(load.preLayoffWeeklyM, 120000 / kChronicWindowWeeks);
  });

  test('unparseable and non-positive rows are dropped rather than read as a break', () {
    final runs = [
      _run(1, 12000),
      const RunForVolume(
        startedAt: 'not-a-date',
        distanceM: 50000,
        activityType: 'run',
      ),
      RunForVolume(
        startedAt: _iso(_now - 35 * _dayMs),
        distanceM: 0,
        activityType: 'run',
      ),
      _run(71, 40000),
      _run(78, 40000),
      _run(85, 40000),
    ];
    final load = comebackLoad(runs, _now);
    expect(load.verdict, ComebackVerdict.easingIn);
    expect(load.layoffDays, 70);
  });

  test('shouldSurfaceComeback narrows to the verdicts the card has copy for', () {
    // Web's predicate makes an unlabelled verdict a compile error; Dart cannot
    // narrow through a bool, so the guarantee is pinned here instead.
    final load = comebackLoad(_comebackRunner(70, 36000), _now);
    expect(shouldSurfaceComeback(load), isTrue);
    final verdict = switch (load.verdict) {
      ComebackVerdict.easingIn => 'easing_in',
      ComebackVerdict.steep => 'steep',
      ComebackVerdict.insufficient => fail('a steep return should surface'),
    };
    expect(verdict, 'steep');
    expect(shouldSurfaceComeback(comebackLoad(const [], _now)), isFalse);
  });

  group('returningFromBreak', () {
    /// Four 40 km weeks ending [lastRunDaysAgo] days ago, and nothing since.
    List<RunForVolume> openBreakRunner(num lastRunDaysAgo,
            [double baseWeeklyM = 40000]) =>
        [for (final w in [0, 7, 14, 21]) _run(lastRunDaysAgo + w, baseWeeklyM)];

    test('reads a break that is still open, before the first run back', () {
      final r = returningFromBreak(openBreakRunner(60), _now);
      expect(r, isNotNull);
      expect(r!.layoffDays, 60);
      expect(r.layoffWeeks, 9);
      expect(r.preLayoffWeeklyM, 40000);
      expect(r.openingCapM, 40000 * kReturnWeekShare);
      // comebackLoad has nothing to grade until the runner runs again.
      expect(comebackLoad(openBreakRunner(60), _now).verdict,
          ComebackVerdict.insufficient);
    });

    test('agrees with comebackLoad on a break the runner has ended', () {
      final runs = _comebackRunner(60, 5000);
      final r = returningFromBreak(runs, _now);
      expect(r, isNotNull);
      expect(r!.layoffDays, comebackLoad(runs, _now).layoffDays);
      expect(r.preLayoffWeeklyM, comebackLoad(runs, _now).preLayoffWeeklyM);
    });

    test('is null for a runner training consistently now', () {
      final runs = [for (final d in [1, 8, 15, 22]) _run(d, 30000)];
      expect(returningFromBreak(runs, _now), isNull);
    });

    test('is null with no running history at all', () {
      expect(returningFromBreak(const [], _now), isNull);
      expect(returningFromBreak([_run(3, 20000, 'cycle')], _now), isNull);
    });

    test('is null for a break too old to anchor against', () {
      expect(returningFromBreak(openBreakRunner(kLayoffMaxDays + 1), _now),
          isNull);
      expect(
          returningFromBreak(openBreakRunner(kLayoffMaxDays), _now), isNotNull);
    });

    test('is null for a break that ended more than four weeks ago', () {
      // Four 40 km weeks ending 380 days ago, then a run a fortnight for the
      // last 100 days: the break ended long enough ago that its base no
      // longer describes the runner, however sporadic the running since.
      final since = [
        for (final d in [2, 16, 30, 44, 58, 72, 86, 100]) _run(d, 5000)
      ];
      expect(returningFromBreak([...since, ...openBreakRunner(380)], _now),
          isNull);
      // The same break ending 20 days ago still counts.
      final recent = [for (final d in [2, 20]) _run(d, 5000)];
      expect(returningFromBreak([...recent, ...openBreakRunner(200)], _now),
          isNotNull);
    });

    test('is null when the pre-break base is a single run', () {
      expect(returningFromBreak([_run(60, 40000)], _now), isNull);
    });
  });

  group('capReturnRamp', () {
    final day = DateTime(2026, 6, 7);
    GeneratedWorkout workout(WorkoutKind kind, double? metres) =>
        GeneratedWorkout(
          scheduledDate: day,
          kind: kind,
          targetDistanceM: metres,
          targetPaceSecPerKm: kind == WorkoutKind.rest ? null : 300,
          targetPaceToleranceSec: kind == WorkoutKind.rest ? null : 8,
          structure: kind == WorkoutKind.interval
              ? const WorkoutStructure(repeats: {'count': 5})
              : null,
          notes: kind == WorkoutKind.interval ? '5 x 1 km' : null,
        );
    GeneratedWeek week(int index, List<GeneratedWorkout> workouts) =>
        GeneratedWeek(
          weekIndex: index,
          phase: PlanPhase.build,
          targetVolumeM:
              workouts.fold(0.0, (s, w) => s + (w.targetDistanceM ?? 0)),
          workouts: workouts,
        );

    test('caps week 1, lets the next grow 10%, and stops at the first week that fits',
        () {
      final weeks = [
        week(0, [
          workout(WorkoutKind.long, 12000),
          workout(WorkoutKind.rest, null),
          workout(WorkoutKind.interval, 8000),
        ]),
        week(1, [
          workout(WorkoutKind.long, 12000),
          workout(WorkoutKind.rest, null),
          workout(WorkoutKind.easy, 8000),
        ]),
        week(2, [
          workout(WorkoutKind.long, 10000),
          workout(WorkoutKind.race, 5000),
        ]),
      ];
      final capped = capReturnRamp(weeks, 10000, 420);
      // Week 1: 20 km against a 10 km cap, so every session halves.
      expect(capped[0].targetVolumeM, 10000);
      expect(capped[0].workouts[0].targetDistanceM, 6000);
      expect(capped[0].workouts[2].targetDistanceM, 4000);
      // The interval session is an easy run at the easy pace now.
      expect(capped[0].workouts[2].kind, WorkoutKind.easy);
      expect(capped[0].workouts[2].targetPaceSecPerKm, 420);
      expect(capped[0].workouts[2].targetPaceToleranceSec, 30);
      expect(capped[0].workouts[2].structure, isNull);
      expect(capped[0].workouts[2].notes, isNull);
      expect(identical(capped[0].workouts[1], weeks[0].workouts[1]), isTrue);
      // Week 2: capped at 10 km x 1.1 = 11 km, to the nearest 100 m.
      expect(10000 * kReturnWeeklyGrowth, 11000);
      expect(capped[1].workouts[0].targetDistanceM, 6600);
      expect(capped[1].workouts[2].targetDistanceM, 4400);
      expect(capped[1].targetVolumeM, 11000);
      // Week 3: 10 km of running fits its 12.1 km cap (the race is not
      // counted), so the climb ends there and the week is as generated.
      expect(identical(capped[2], weeks[2]), isTrue);
      // The input is untouched.
      expect(weeks[0].targetVolumeM, 20000);
      expect(weeks[0].workouts[2].kind, WorkoutKind.interval);
    });

    test('leaves every week after the first that fits alone, speed work and all',
        () {
      // 40 / 44 / 36 / 48 km against caps of 35 / 38.5 / 42.35 / 46.585 km:
      // the step-back third week fits, so the fourth keeps its intervals and
      // its 48 km even though that is over the cap the climb would have hit.
      final weeks = [
        for (final (i, m) in [40000.0, 44000.0, 36000.0, 48000.0].indexed)
          week(i, [
            workout(WorkoutKind.long, m - 8000),
            workout(WorkoutKind.interval, 8000),
          ]),
      ];
      final capped = capReturnRamp(weeks, 35000, 420);
      expect(capped[0].workouts[1].kind, WorkoutKind.easy);
      expect(capped[1].workouts[1].kind, WorkoutKind.easy);
      expect(identical(capped[2], weeks[2]), isTrue);
      expect(identical(capped[3], weeks[3]), isTrue);
      expect(capped[3].workouts[1].kind, WorkoutKind.interval);
    });

    test('drops sessions the cap would take under 3 km to rest, shortest first',
        () {
      // 20 km over four runs against a 6 km cap: scaling alone would ask for
      // a 900 m run. The 3, 4 and 5 km runs drop in turn and the long run
      // takes the whole 6 km.
      final weeks = [
        week(0, [
          workout(WorkoutKind.long, 8000),
          workout(WorkoutKind.easy, 5000),
          workout(WorkoutKind.easy, 4000),
          workout(WorkoutKind.easy, 3000),
        ]),
      ];
      final w = capReturnRamp(weeks, 6000, 420).single;
      expect(w.workouts[0].targetDistanceM, 6000);
      for (final dropped in w.workouts.skip(1)) {
        expect(dropped.kind, WorkoutKind.rest);
        expect(dropped.targetDistanceM, isNull);
        expect(dropped.targetPaceSecPerKm, isNull);
      }
      expect(w.targetVolumeM, 6000);
    });

    test('labels an easy run it shortens under 4 km a recovery run', () {
      // Two 6 km easy runs against a 7 km cap become two 3.5 km runs.
      final w = capReturnRamp([
        week(0, [
          workout(WorkoutKind.easy, 6000),
          workout(WorkoutKind.easy, 6000),
        ]),
      ], 7000, 420)
          .single;
      expect(
        [for (final wo in w.workouts) (wo.kind, wo.targetDistanceM)],
        [(WorkoutKind.recovery, 3500.0), (WorkoutKind.recovery, 3500.0)],
      );
    });

    test(
        'leaves a week under its cap, and every week for a cap that is not positive',
        () {
      final weeks = [
        week(0, [workout(WorkoutKind.easy, 5000)]),
      ];
      expect(identical(capReturnRamp(weeks, 10000, 420)[0], weeks[0]), isTrue);
      expect(identical(capReturnRamp(weeks, 0, 420), weeks), isTrue);
      expect(identical(capReturnRamp(weeks, double.nan, 420), weeks), isTrue);
    });
  });
}
