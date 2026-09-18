import 'package:flutter_test/flutter_test.dart';
import '../lib/plan_adherence.dart';

void main() {
  group('weeklyDrift', () {
    test('on-track when actual matches planned', () {
      final d = weeklyDrift(40000, 41000);
      expect(d.direction, DriftDirection.onTrack);
      expect(d.flagged, false);
    });

    test('flags under-running past the threshold', () {
      final d = weeklyDrift(40000, 28000);
      expect(d.direction, DriftDirection.under);
      expect(d.flagged, true);
      expect(d.driftFraction < -planDriftThreshold, true);
    });

    test('flags over-running past the threshold', () {
      final d = weeklyDrift(40000, 52000);
      expect(d.direction, DriftDirection.over);
      expect(d.flagged, true);
      expect(d.driftFraction > planDriftThreshold, true);
    });

    test('just inside the threshold is not flagged', () {
      final d = weeklyDrift(40000, 47000);
      expect(d.direction, DriftDirection.onTrack);
      expect(d.flagged, false);
    });

    test('no planned volume yields a neutral, unflagged result', () {
      final d = weeklyDrift(0, 30000);
      expect(d.direction, DriftDirection.onTrack);
      expect(d.flagged, false);
      expect(d.driftFraction, 0);
    });

    test('clamps negative actual to zero', () {
      final d = weeklyDrift(40000, -5);
      expect(d.actualMetres, 0);
      expect(d.direction, DriftDirection.under);
    });
  });

  // A plan week running Mon 2026-03-02 → Sun 2026-03-08, 50 km over five
  // running days: Mon 8, Wed 10, Thu 8, Sat 6, Sun 18.
  const week = [
    DriftWorkout(
        scheduledDate: '2026-03-02', kind: 'easy', targetDistanceM: 8000),
    DriftWorkout(
        scheduledDate: '2026-03-03', kind: 'rest', targetDistanceM: null),
    DriftWorkout(
        scheduledDate: '2026-03-04', kind: 'tempo', targetDistanceM: 10000),
    DriftWorkout(
        scheduledDate: '2026-03-05', kind: 'easy', targetDistanceM: 8000),
    DriftWorkout(
        scheduledDate: '2026-03-06', kind: 'rest', targetDistanceM: null),
    DriftWorkout(
        scheduledDate: '2026-03-07', kind: 'easy', targetDistanceM: 6000),
    DriftWorkout(
        scheduledDate: '2026-03-08', kind: 'long', targetDistanceM: 18000),
  ];

  group('weeklyDriftToDate', () {
    test('mid-week and exactly on the plan so far is not flagged', () {
      // Thursday morning, Mon + Wed run as prescribed. The whole-week
      // baseline read this as 18 of 50 km — 64% under plan — every week.
      final d = weeklyDriftToDate(
        workouts: week,
        runs: const [
          DriftRun(date: '2026-03-02', distanceM: 8000),
          DriftRun(date: '2026-03-04', distanceM: 10000),
        ],
        today: '2026-03-05',
      );
      expect(d.plannedMetres, 18000);
      expect(d.actualMetres, 18000);
      expect(d.direction, DriftDirection.onTrack);
      expect(d.flagged, false);
    });

    test('genuinely behind on the elapsed days still flags', () {
      // Same Thursday, but Wednesday's tempo never happened.
      final d = weeklyDriftToDate(
        workouts: week,
        runs: const [DriftRun(date: '2026-03-02', distanceM: 8000)],
        today: '2026-03-05',
      );
      expect(d.plannedMetres, 18000);
      expect(d.direction, DriftDirection.under);
      expect(d.flagged, true);
    });

    test('over-running the elapsed days flags', () {
      final d = weeklyDriftToDate(
        workouts: week,
        runs: const [
          DriftRun(date: '2026-03-02', distanceM: 14000),
          DriftRun(date: '2026-03-04', distanceM: 16000),
        ],
        today: '2026-03-05',
      );
      expect(d.direction, DriftDirection.over);
      expect(d.driftFraction > planDriftThreshold, true);
    });

    test('a session due at the end of today is not yet owed', () {
      // Wednesday, Monday's 8 km done and Wednesday's tempo still ahead of
      // the runner. Counting today's 10 km would read as 44% under plan.
      final d = weeklyDriftToDate(
        workouts: week,
        runs: const [DriftRun(date: '2026-03-02', distanceM: 8000)],
        today: '2026-03-04',
      );
      expect(d.plannedMetres, 8000);
      expect(d.flagged, false);
    });

    test('a run already done today does not read as over-running', () {
      // Thursday, and Thursday's 8 km is already banked. It belongs to a day
      // that has not ended, so it counts on neither side.
      final d = weeklyDriftToDate(
        workouts: week,
        runs: const [
          DriftRun(date: '2026-03-02', distanceM: 8000),
          DriftRun(date: '2026-03-04', distanceM: 10000),
          DriftRun(date: '2026-03-05', distanceM: 8000),
        ],
        today: '2026-03-05',
      );
      expect(d.actualMetres, 18000);
      expect(d.direction, DriftDirection.onTrack);
    });

    test('the first day of the week has nothing to judge', () {
      final d = weeklyDriftToDate(
          workouts: week, runs: const [], today: '2026-03-02');
      expect(d.plannedMetres, 0);
      expect(d.direction, DriftDirection.onTrack);
      expect(d.flagged, false);
    });

    test('once the week has fully elapsed the baseline is the whole week', () {
      final d = weeklyDriftToDate(
        workouts: week,
        runs: const [
          DriftRun(date: '2026-03-02', distanceM: 8000),
          DriftRun(date: '2026-03-04', distanceM: 10000),
          DriftRun(date: '2026-03-05', distanceM: 8000),
          DriftRun(date: '2026-03-08', distanceM: 9000),
        ],
        today: '2026-03-09',
      );
      expect(d.plannedMetres, 50000);
      expect(d.actualMetres, 35000);
      expect(d.direction, DriftDirection.under);
    });

    test("a declared week volume is scaled by the schedule's shape", () {
      // The week is worth 60 km; the workouts place 18 of their 50 km before
      // Thursday, so 36% of the declared volume is owed.
      final d = weeklyDriftToDate(
        workouts: week,
        runs: const [DriftRun(date: '2026-03-02', distanceM: 21600)],
        today: '2026-03-05',
        weekTargetVolumeM: 60000,
      );
      expect(d.plannedMetres, 21600);
      expect(d.direction, DriftDirection.onTrack);
    });

    test('a week volume no workout carries cannot be placed in time', () {
      final d = weeklyDriftToDate(
        workouts: week
            .map((w) => DriftWorkout(
                scheduledDate: w.scheduledDate,
                kind: w.kind,
                targetDistanceM: null))
            .toList(),
        runs: const [],
        today: '2026-03-05',
        weekTargetVolumeM: 40000,
      );
      expect(d.plannedMetres, 0);
      expect(d.flagged, false);
    });

    test('a rest day carrying a distance is excluded from the baseline', () {
      final d = weeklyDriftToDate(
        workouts: const [
          DriftWorkout(
              scheduledDate: '2026-03-02', kind: 'easy', targetDistanceM: 8000),
          DriftWorkout(
              scheduledDate: '2026-03-03', kind: 'rest', targetDistanceM: 5000),
        ],
        runs: const [DriftRun(date: '2026-03-02', distanceM: 8000)],
        today: '2026-03-04',
      );
      expect(d.plannedMetres, 8000);
      expect(d.direction, DriftDirection.onTrack);
    });
  });

  group('missedWorkoutAdvice', () {
    test('base/build long run is worth making up', () {
      final a = missedWorkoutAdvice(const MissedWorkoutInput(
          kind: 'long', isTaper: false, recoveryWeekImminent: false));
      expect(a.recommendation, MakeUpRecommendation.makeUp);
      expect(a.reason, MissedWorkoutReason.keySession);
    });

    test('skip a long run missed in the taper', () {
      final a = missedWorkoutAdvice(const MissedWorkoutInput(
          kind: 'long', isTaper: true, recoveryWeekImminent: false));
      expect(a.recommendation, MakeUpRecommendation.skip);
      expect(a.reason, MissedWorkoutReason.taper);
    });

    test('skip when a recovery week is imminent', () {
      final a = missedWorkoutAdvice(const MissedWorkoutInput(
          kind: 'long', isTaper: false, recoveryWeekImminent: true));
      expect(a.recommendation, MakeUpRecommendation.skip);
      expect(a.reason, MissedWorkoutReason.recoverySoon);
    });

    test('taper takes precedence over recovery-soon', () {
      final a = missedWorkoutAdvice(const MissedWorkoutInput(
          kind: 'long', isTaper: true, recoveryWeekImminent: true));
      expect(a.reason, MissedWorkoutReason.taper);
    });

    test('a missed quality session is just skipped', () {
      for (final kind in ['tempo', 'interval', 'easy', 'marathon_pace']) {
        final a = missedWorkoutAdvice(MissedWorkoutInput(
            kind: kind, isTaper: false, recoveryWeekImminent: false));
        expect(a.recommendation, MakeUpRecommendation.skip);
        expect(a.reason, MissedWorkoutReason.notLongRun);
      }
    });
  });
}
