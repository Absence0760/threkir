import 'package:flutter_test/flutter_test.dart';

import '../lib/plan_races.dart';
import '../lib/plan_recap.dart';
import '../lib/training.dart' show vdotFromRace;

// Mirror: apps/web/src/lib/training/plan_recap.test.ts.

const plan = RecapPlan(
  startDate: '2026-03-01',
  endDate: '2026-04-26',
  goalDistanceM: 21097.5,
  goalTimeSeconds: 5700,
  trimmedAt: null,
);

RecapWorkout wo(
  String id,
  String date,
  String kind, {
  double? targetDistanceM = -1,
  int? targetDurationSeconds,
  String? completedRunId,
  bool manuallyCompleted = false,
  String? skippedAt,
  String? missedAckAt,
  String? raceName,
}) =>
    RecapWorkout(
      id: id,
      scheduledDate: date,
      kind: kind,
      targetDistanceM: targetDistanceM == -1
          ? (kind == 'rest' ? null : 10000)
          : targetDistanceM,
      targetDurationSeconds: targetDurationSeconds,
      completedRunId: completedRunId,
      manuallyCompleted: manuallyCompleted,
      skippedAt: skippedAt,
      missedAckAt: missedAckAt,
      raceName: raceName,
    );

PlanRecapRun run(String id, String date, double distanceM, int durationS,
        {String? activityType = 'run', bool? isDnf = false}) =>
    PlanRecapRun(
      id: id,
      date: date,
      distanceM: distanceM,
      durationS: durationS,
      activityType: activityType,
      isDnf: isDnf,
    );

PlanRace race(String date, String priority, String? workoutId,
        [double distanceM = 21097.5]) =>
    PlanRace(
      date: date,
      name: null,
      priority: priority,
      distanceM: distanceM,
      goalTimeSec: null,
      workoutId: workoutId,
    );

PlanRecap recap({
  RecapPlan p = plan,
  List<RecapWorkout> workouts = const [],
  List<PlanRecapRun> runs = const [],
  List<PlanRecapRecord> records = const [],
  String todayIso = '2026-04-27',
}) =>
    assemblePlanRecap(
      plan: p,
      workouts: workouts,
      runs: runs,
      records: records,
      todayIso: todayIso,
    );

RecapPlan planWith({double? goalDistanceM, DateTime? trimmedAt}) => RecapPlan(
      startDate: plan.startDate,
      endDate: plan.endDate,
      goalDistanceM: goalDistanceM ?? plan.goalDistanceM,
      goalTimeSeconds: goalDistanceM == null ? plan.goalTimeSeconds : null,
      trimmedAt: trimmedAt,
    );

void main() {
  test('recapGoalRace: the end-date race, else the last A race, else the last race',
      () {
    expect(
        recapGoalRace([race('2026-04-05', 'B', 'b'), race('2026-04-26', 'A', 'a')],
                '2026-04-26')
            ?.workoutId,
        'a');
    expect(
        recapGoalRace([
          race('2026-03-20', 'A', 'a1'),
          race('2026-04-05', 'A', 'a2'),
          race('2026-04-12', 'C', 'c'),
        ], '2026-04-26')
            ?.workoutId,
        'a2');
    expect(
        recapGoalRace([race('2026-04-05', 'B', 'b'), race('2026-04-12', 'C', 'c')],
                '2026-04-26')
            ?.workoutId,
        'c');
    expect(recapGoalRace([], '2026-04-26'), isNull);
  });

  test('sessions: the ring counts, plus the skipped sessions it leaves out', () {
    final r = recap(
      workouts: [
        wo('w1', '2026-03-01', 'long', manuallyCompleted: true),
        wo('w2', '2026-03-02', 'rest', manuallyCompleted: true),
        wo('w3', '2026-03-03', 'easy', skippedAt: '2026-03-03T08:00:00Z'),
        wo('w4', '2026-03-04', 'tempo'),
        wo('w5', '2026-04-26', 'race', completedRunId: 'r-race'),
      ],
      runs: [run('r-race', '2026-04-26', 21200, 5400)],
    );
    expect(
        r.sessions,
        const RecapSessions(
            completed: 2, total: 3, pct: 67, skipped: 1, missed: 1));
  });

  test('sessions: an answered or moved miss is still missed, an upcoming day is not',
      () {
    final r = recap(workouts: [
      wo('w1', '2026-03-03', 'long', missedAckAt: '2026-03-05T08:00:00Z'),
      wo('w2', '2026-03-10', 'easy'),
      wo('w3', '2026-03-12', 'easy', skippedAt: '2026-03-12T08:00:00Z'),
      wo('w4', '2026-03-14', 'rest'),
      wo('w5', '2026-04-27', 'easy'),
    ]);
    expect(
        r.sessions,
        const RecapSessions(
            completed: 0, total: 3, pct: 0, skipped: 1, missed: 2));
  });

  test('an empty plan recaps to zeros and still offers the next plan', () {
    final r = recap(p: planWith(trimmedAt: DateTime.utc(2026, 3, 2, 10)));
    expect(
        r.sessions,
        const RecapSessions(
            completed: 0, total: 0, pct: 0, skipped: 0, missed: 0));
    expect(
        r.volume,
        const RecapVolume(
            basis: RecapVolumeBasis.distance, done: 0, planned: 0));
    expect(r.longRuns,
        const RecapLongRuns(done: 0, planned: 0, first: null, longest: null));
    expect(r.race, isNull);
    expect(r.next.startIso, '2026-05-10');
  });

  test('long runs: done of planned, from the first to the longest', () {
    final r = recap(
      workouts: [
        wo('l3', '2026-03-15', 'long',
            completedRunId: 'r3', targetDistanceM: 18000),
        wo('l1', '2026-03-01', 'long',
            manuallyCompleted: true, targetDistanceM: 12000),
        wo('l2', '2026-03-08', 'long',
            completedRunId: 'r2', targetDistanceM: 15000),
        wo('l4', '2026-03-22', 'long', targetDistanceM: 20000),
        wo('l5', '2026-03-29', 'long',
            skippedAt: '2026-03-29T08:00:00Z', targetDistanceM: 22000),
        wo('e1', '2026-03-02', 'easy',
            completedRunId: 'r9', targetDistanceM: 30000),
      ],
      runs: [
        run('r2', '2026-03-08', 16200, 5800),
        run('r3', '2026-03-15', 0, 0),
        run('r9', '2026-03-02', 30000, 9000),
      ],
    );
    expect(r.longRuns,
        const RecapLongRuns(done: 3, planned: 4, first: 12000, longest: 18000));
  });

  test('distance: a linked run counts its real distance, a ticked workout its target',
      () {
    final r = recap(
      workouts: [
        wo('w1', '2026-03-01', 'long',
            completedRunId: 'r1', targetDistanceM: 16000),
        wo('w2', '2026-03-03', 'easy',
            manuallyCompleted: true, targetDistanceM: 8000),
        wo('w3', '2026-03-05', 'easy', targetDistanceM: 6000),
        wo('w4', '2026-03-07', 'easy',
            skippedAt: '2026-03-07T08:00:00Z', targetDistanceM: 5000),
      ],
      runs: [run('r1', '2026-03-01', 17500, 6000)],
    );
    expect(
        r.volume,
        const RecapVolume(
            basis: RecapVolumeBasis.distance, done: 25500, planned: 30000));
  });

  test('a walk-run plan reports time, not distance', () {
    RecapWorkout timed(String id, String date,
            {String? completedRunId, bool manuallyCompleted = false}) =>
        wo(id, date, 'walk_run',
            targetDistanceM: 3000,
            targetDurationSeconds: 1800,
            completedRunId: completedRunId,
            manuallyCompleted: manuallyCompleted);
    final r = recap(
      workouts: [
        timed('w1', '2026-03-01', completedRunId: 'r1'),
        timed('w2', '2026-03-03', manuallyCompleted: true),
        timed('w3', '2026-03-05'),
        wo('w4', '2026-03-06', 'rest'),
      ],
      runs: [run('r1', '2026-03-01', 3100, 2000)],
    );
    expect(
        r.volume,
        const RecapVolume(
            basis: RecapVolumeBasis.time, done: 3800, planned: 5400));
  });

  test('records: only those set inside the plan window, by date then distance',
      () {
    final r = recap(records: const [
      PlanRecapRecord(distance: '5k', timeS: 1190, date: '2026-02-28', runId: 'a'),
      PlanRecapRecord(distance: '10k', timeS: 2500, date: '2026-04-26', runId: 'b'),
      PlanRecapRecord(distance: '5k', timeS: 1180, date: '2026-04-26', runId: 'b'),
      PlanRecapRecord(distance: '1_mile', timeS: 360, date: '2026-03-01', runId: 'c'),
      PlanRecapRecord(
          distance: 'marathon', timeS: 12600, date: '2026-04-27', runId: 'd'),
    ]);
    expect(r.records.map((x) => '${x.date} ${x.distance}').toList(),
        ['2026-03-01 1_mile', '2026-04-26 10k', '2026-04-26 5k']);
  });

  test('the race workout linked to a run gives the race run and its VDOT', () {
    final r = recap(
      workouts: [
        wo('w-race', '2026-04-26', 'race',
            completedRunId: 'r-race', raceName: 'Spring Half', targetDistanceM: null),
      ],
      runs: [run('r-race', '2026-04-26', 21097.5, 5400)],
    );
    expect(r.race?.name, 'Spring Half');
    expect(r.race?.distanceM, 21097.5);
    expect(
        r.race?.run,
        const PlanRecapRaceRun(
            id: 'r-race', distanceM: 21097.5, durationS: 5400, isDnf: false));
    expect(r.race?.raced, isTrue);
    expect(r.race?.vdot, 51);
  });

  test('an unlinked race workout has no run; a ticked one was still raced', () {
    final sameDay = [run('r-other', '2026-04-26', 21000, 5600)];
    final unlinked = recap(
        workouts: [wo('w-race', '2026-04-26', 'race')], runs: sameDay);
    expect(unlinked.race?.run, isNull);
    expect(unlinked.race?.raced, isFalse);
    expect(unlinked.next.recovery, isNull);
    final ticked = recap(
      workouts: [wo('w-race', '2026-04-26', 'race', manuallyCompleted: true)],
      runs: sameDay,
    );
    expect(ticked.race?.run, isNull);
    expect(ticked.race?.raced, isTrue);
    expect(ticked.race?.vdot, isNull);
  });

  test('a race with no workout row takes the longest run-family run that day covering 75% of it',
      () {
    final goal = race('2026-04-26', 'A', null, 10000);
    final runs = [
      run('jog', '2026-04-26', 3000, 1100),
      run('ride', '2026-04-26', 40000, 4000, activityType: 'cycle'),
      run('race', '2026-04-26', 10050, 2500),
      run('eve', '2026-04-25', 12000, 3600),
    ];
    expect(recapRaceRun(goal, const [], runs)?.id, 'race');
    expect(
        recapRaceRun(goal, const [], [run('jog', '2026-04-26', 7000, 2400)]),
        isNull);
    expect(
        recapRaceRun(goal, const [], [run('ok', '2026-04-26', 7500, 2400)])?.id,
        'ok');
  });

  test('recapRaceVdot: null for a DNF, a walk, an ultra, or no time', () {
    const r = PlanRecapRaceRun(
        id: 'r', distanceM: 21097.5, durationS: 5400, isDnf: false);
    expect(recapRaceVdot(r, null), 51);
    expect(
        recapRaceVdot(
            const PlanRecapRaceRun(
                id: 'r', distanceM: 21097.5, durationS: 5400, isDnf: true),
            'run'),
        isNull);
    expect(recapRaceVdot(r, 'walk'), isNull);
    expect(
        recapRaceVdot(
            const PlanRecapRaceRun(
                id: 'r', distanceM: 50000, durationS: 18000, isDnf: false),
            'run'),
        isNull);
    expect(
        recapRaceVdot(
            const PlanRecapRaceRun(
                id: 'r', distanceM: 21097.5, durationS: 0, isDnf: false),
            'run'),
        isNull);
    expect(recapRaceVdot(null, 'run'), isNull);
  });

  test('fiveKSecondsAtVdot inverts vdotFromRace at 5 km', () {
    expect(fiveKSecondsAtVdot(vdotFromRace(5000, 1200)), 1200);
    expect(fiveKSecondsAtVdot(51), 1176);
    expect(fiveKSecondsAtVdot(0), isNull);
    expect(fiveKSecondsAtVdot(double.nan), isNull);
  });

  test('next: recovery after a marathon pushes the next plan past the wizard default',
      () {
    final r = recap(
      p: planWith(goalDistanceM: 42195),
      workouts: [
        wo('w-race', '2026-04-26', 'race',
            completedRunId: 'r', targetDistanceM: 42195),
      ],
      runs: [run('r', '2026-04-26', 42195, 12600)],
    );
    expect(r.race?.vdot, 44.6);
    expect(r.next.recovery,
        const RecapRecovery(days: 14, untilIso: '2026-05-10'));
    expect(r.next.startIso, '2026-05-17');
    expect(r.next.seed5kSec, fiveKSecondsAtVdot(44.6));
  });

  test('next: a recovery already over and a race past the recent window seed nothing',
      () {
    final r = recap(
      workouts: [
        wo('w-race', '2026-04-26', 'race',
            completedRunId: 'r', targetDistanceM: 21097.5),
      ],
      runs: [run('r', '2026-04-26', 21097.5, 5400)],
      todayIso: '2026-07-01',
    );
    expect(r.next.recovery, isNull);
    expect(r.next.startIso, '2026-07-12');
    expect(r.next.seed5kSec, isNull);
    expect(r.race?.vdot, 51);
  });

  test('a plan ended early with no race rows has no race and starts on the default',
      () {
    final r = recap(
      p: planWith(trimmedAt: DateTime.utc(2026, 4, 1, 10)),
      workouts: [wo('w1', '2026-03-01', 'long', manuallyCompleted: true)],
    );
    expect(r.race, isNull);
    expect(r.next.recovery, isNull);
    expect(r.next.startIso, '2026-05-10');
    expect(r.next.seed5kSec, isNull);
  });
}
