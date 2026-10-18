import 'package:flutter_test/flutter_test.dart';
import '../lib/plan_replan.dart';
import '../lib/plan_volume_anchor.dart';

ReplanWorkout _wo(
  String id,
  String scheduledDate,
  String kind,
  double? targetDistanceM, {
  bool completed = false,
  bool skipped = false,
  bool isPast = false,
}) =>
    ReplanWorkout(
      id: id,
      scheduledDate: scheduledDate,
      kind: kind,
      targetDistanceM: targetDistanceM,
      completed: completed,
      skipped: skipped,
      isPast: isPast,
    );

ReplanWeek _week(
  int weekIndex,
  double plannedMetres,
  double actualMetres,
  bool isComplete,
  List<ReplanWorkout> workouts, {
  String phase = 'build',
}) =>
    ReplanWeek(
      weekIndex: weekIndex,
      phase: phase,
      plannedMetres: plannedMetres,
      actualMetres: actualMetres,
      isComplete: isComplete,
      workouts: workouts,
    );

/// A 40 km week of four future sessions: long 16, easy 10, tempo 8, easy 6.
ReplanWeek _fullWeek(int weekIndex, String date, {String phase = 'build'}) =>
    _week(
      weekIndex,
      40000,
      0,
      false,
      [
        _wo('l$weekIndex', date, 'long', 16000),
        _wo('e$weekIndex', date, 'easy', 10000),
        _wo('t$weekIndex', date, 'tempo', 8000),
        _wo('r$weekIndex', date, 'easy', 6000),
        _wo('x$weekIndex', date, 'rest', null),
      ],
      phase: phase,
    );

Map<String, double> _byId(List<ReplanChange> changes) =>
    {for (final c in changes) c.workoutId: c.toMetres};

void main() {
  test('anchorToActualVolume: an on-track week proposes nothing', () {
    final weeks = [_week(0, 40000, 38000, true, []), _fullWeek(1, '2026-06-08')];
    expect(anchorToActualVolume(weeks: weeks), isNull);
  });

  test('anchorToActualVolume: a niggle week caps next week at 10% over what was run',
      () {
    final weeks = [_week(0, 40000, 20000, true, []), _fullWeek(1, '2026-06-08')];
    final a = anchorToActualVolume(weeks: weeks)!;
    expect(a.anchorWeekIndex, 0);
    expect(a.anchorMetres, 20000);
    expect(a.returning, isFalse);
    // cap 22 km over 40 km: factor 0.55, each session floored to the 100 m.
    final to = _byId(a.changes);
    expect(to['l1'], 8800);
    expect(to['e1'], 5500);
    expect(to['t1'], 4400);
    expect(to['r1'], 3300);
    expect(a.changes.every((c) => c.reason == ReplanReason.anchorActualVolume),
        isTrue);
    final total = to.values.fold<double>(0, (s, v) => s + v);
    expect(total <= 22000, isTrue);
  });

  test('anchorToActualVolume: the climb grows 10% a week from what each week prescribes',
      () {
    final weeks = [
      _week(0, 40000, 20000, true, []),
      _fullWeek(1, '2026-06-08'),
      _fullWeek(2, '2026-06-15'),
    ];
    final a = anchorToActualVolume(weeks: weeks)!;
    final to = _byId(a.changes);
    final week1 =
        ['l1', 'e1', 't1', 'r1'].fold<double>(0, (s, id) => s + (to[id] ?? 0));
    final week2 =
        ['l2', 'e2', 't2', 'r2'].fold<double>(0, (s, id) => s + (to[id] ?? 0));
    expect(week1, 22000);
    expect(week2 <= week1 * 1.1, isTrue);
    expect(week2 > week1, isTrue);
  });

  test('anchorToActualVolume: the climb ends once the plan fits, and later weeks are untouched',
      () {
    final weeks = [
      _week(0, 40000, 30000, true, []),
      _fullWeek(1, '2026-06-08'),
      _fullWeek(2, '2026-06-15'),
      _fullWeek(3, '2026-06-22'),
    ];
    final a = anchorToActualVolume(weeks: weeks)!;
    // 33 km, then 36.3 km, then 39.9 km caps: all three still cap; a 40 km
    // week never moves in a fourth. Every change is in weeks 1..3.
    expect(a.changes.every((c) => RegExp(r'[1-3]$').hasMatch(c.workoutId)),
        isTrue);
    final weeks2 = [
      _week(0, 40000, 30000, true, []),
      _fullWeek(1, '2026-06-08'),
      _week(2, 20000, 0, false, [_wo('s', '2026-06-15', 'easy', 20000)]),
    ];
    final b = anchorToActualVolume(weeks: weeks2)!;
    expect(b.changes.any((c) => c.workoutId == 's'), isFalse);
  });

  test('anchorToActualVolume: taper and race weeks are never touched, and the climb stops there',
      () {
    final weeks = [
      _week(0, 40000, 10000, true, []),
      _fullWeek(1, '2026-06-08', phase: 'taper'),
      _fullWeek(2, '2026-06-15'),
    ];
    expect(anchorToActualVolume(weeks: weeks), isNull);
  });

  test('anchorToActualVolume: no session goes under the 3 km floor, and one already under it stays',
      () {
    final weeks = [
      _week(0, 30000, 2000, true, []),
      _week(1, 30000, 0, false, [
        _wo('a', '2026-06-08', 'long', 20000),
        _wo('b', '2026-06-09', 'recovery', 2500),
        _wo('c', '2026-06-10', 'easy', 7500),
      ]),
    ];
    final a = anchorToActualVolume(weeks: weeks)!;
    final to = _byId(a.changes);
    expect(to['a'], 3000);
    expect(to['c'], 3000);
    expect(to.containsKey('b'), isFalse);
  });

  test('anchorToActualVolume: done sessions count as prescribed, missed ones count nothing, past ones never change',
      () {
    final weeks = [
      _week(0, 40000, 20000, true, []),
      _week(1, 40000, 0, false, [
        _wo('done', '2026-06-08', 'long', 12000, completed: true, isPast: true),
        _wo('missed', '2026-06-09', 'easy', 10000, isPast: true),
        _wo('ahead', '2026-06-12', 'easy', 18000),
      ]),
    ];
    final a = anchorToActualVolume(weeks: weeks)!;
    // 22 km cap less the 12 km done leaves 10 km for the one session ahead.
    expect([for (final c in a.changes) [c.workoutId, c.toMetres]], [
      ['ahead', 10000],
    ]);
  });

  test('anchorToActualVolume: rest, race and skipped sessions are neither counted nor changed',
      () {
    final weeks = [
      _week(0, 40000, 20000, true, []),
      _week(1, 40000, 0, false, [
        _wo('race', '2026-06-08', 'race', 10000),
        _wo('skip', '2026-06-09', 'easy', 10000, skipped: true),
        _wo('a', '2026-06-10', 'easy', 30000),
      ]),
    ];
    final a = anchorToActualVolume(weeks: weeks)!;
    expect([for (final c in a.changes) [c.workoutId, c.toMetres]], [
      ['a', 22000],
    ]);
  });

  test('anchorToActualVolume: a week with no running is a break, and the anchor is the last week that had some',
      () {
    final weeks = [
      _week(0, 40000, 30000, true, []),
      _week(1, 40000, 0, true, []),
      _fullWeek(2, '2026-06-15'),
    ];
    final a = anchorToActualVolume(weeks: weeks)!;
    expect(a.anchorWeekIndex, 0);
    expect(a.idleWeeks, 1);
    expect(a.returning, isFalse);
    final total = a.changes.fold<double>(0, (s, c) => s + c.toMetres);
    expect(total <= 33000, isTrue);
  });

  test('anchorToActualVolume: four weeks away restarts at half of what was last run',
      () {
    // A resume pushed the plan back four weeks: indices 1..4 have no rows.
    final weeks = [_week(0, 40000, 36000, true, []), _fullWeek(5, '2026-07-06')];
    final a = anchorToActualVolume(weeks: weeks)!;
    expect(a.idleWeeks, 4);
    expect(a.returning, isTrue);
    // An 18 km cap: 7.2 + 4.5 + 3.6 km, and the 6 km run held at the 3 km
    // floor rather than scaled to 2.7 km, so the floor is what overshoots.
    final to = _byId(a.changes);
    expect([for (final id in ['l5', 'e5', 't5', 'r5']) to[id]],
        [7200, 4500, 3600, 3000]);
  });

  test('anchorToActualVolume: no completed week with running, or nothing ahead, proposes nothing',
      () {
    expect(
      anchorToActualVolume(
          weeks: [_week(0, 40000, 0, true, []), _fullWeek(1, '2026-06-08')]),
      isNull,
    );
    expect(anchorToActualVolume(weeks: [_week(0, 40000, 10000, true, [])]),
        isNull);
    expect(anchorToActualVolume(weeks: [_fullWeek(0, '2026-06-01')]), isNull);
  });

  test('anchorToActualVolume: a week already anchored proposes nothing more', () {
    final ahead = _fullWeek(1, '2026-06-08');
    final weeks = [_week(0, 40000, 20000, true, []), ahead];
    final a = anchorToActualVolume(weeks: weeks)!;
    final to = _byId(a.changes);
    final applied = _week(
      ahead.weekIndex,
      ahead.plannedMetres,
      ahead.actualMetres,
      ahead.isComplete,
      [
        for (final x in ahead.workouts)
          _wo(x.id, x.scheduledDate, x.kind, to[x.id] ?? x.targetDistanceM),
      ],
      phase: ahead.phase,
    );
    expect(anchorToActualVolume(weeks: [weeks[0], applied]), isNull);
  });

  test('anchorToActualVolume: a week run as its anchored sessions prescribed is not short',
      () {
    // The week's target stays 40 km after an anchor; its sessions ask for 22.
    final sessions = [
      _wo('l0', '2026-06-07', 'long', 12000, completed: true, isPast: true),
      _wo('e0', '2026-06-03', 'easy', 10000, completed: true, isPast: true),
      _wo('x0', '2026-06-02', 'rest', null, isPast: true),
    ];
    final anchored = _week(0, 40000, 21000, true, sessions);
    expect(
        anchorToActualVolume(weeks: [anchored, _fullWeek(1, '2026-06-08')]),
        isNull);
    final short = _week(0, 40000, 15000, true, sessions);
    final a =
        anchorToActualVolume(weeks: [short, _fullWeek(1, '2026-06-08')])!;
    expect(a.anchorMetres, 15000);
  });

  test('preferVolumeAnchor: the anchor replaces every other proposal, and nothing changes without one',
      () {
    const other = [
      ReplanChange(
        workoutId: 'l1',
        scheduledDate: '2026-06-08',
        reason: ReplanReason.makeUpLong,
        fromMetres: 16000,
        toMetres: 18400,
      ),
    ];
    expect(identical(preferVolumeAnchor(null, other), other), isTrue);
    final a = anchorToActualVolume(
        weeks: [_week(0, 40000, 20000, true, []), _fullWeek(1, '2026-06-08')])!;
    expect(identical(preferVolumeAnchor(a, other), a.changes), isTrue);
  });
}
