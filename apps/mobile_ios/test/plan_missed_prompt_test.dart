// Mirrors apps/web/src/lib/training/plan_missed_prompt.test.ts case-for-case.
import 'package:flutter_test/flutter_test.dart';

import '../lib/plan_adherence.dart';
import '../lib/plan_missed_prompt.dart';

const _today = '2026-03-11';

MissedPromptWorkout _wo(
  String id,
  String date,
  String kind,
  double? dist, {
  bool completed = false,
  bool skipped = false,
  bool answered = false,
}) =>
    MissedPromptWorkout(
      id: id,
      scheduledDate: date,
      kind: kind,
      targetDistanceM: dist,
      completed: completed,
      skipped: skipped,
      answered: answered,
    );

MissedPromptWeek _week(
        int idx, String phase, double planned, List<MissedPromptWorkout> wos) =>
    MissedPromptWeek(
        weekIndex: idx, phase: phase, plannedMetres: planned, workouts: wos);

/// A build block: last week's long run on Sunday the 8th, this week's on
/// Sunday the 15th, next week's on the 22nd.
List<MissedPromptWeek> _block({
  double lastLongM = 20000,
  bool tempoDone = false,
  bool tempoAnswered = false,
  String nextPhase = 'build',
  double nextPlanned = 44000,
}) =>
    [
      _week(0, 'build', 40000, [
        _wo('mon', '2026-03-02', 'easy', 8000),
        _wo('long-8', '2026-03-08', 'long', lastLongM),
      ]),
      _week(1, 'build', 42000, [
        _wo('tue', '2026-03-10', 'tempo', 9000,
            completed: tempoDone, answered: tempoAnswered),
        _wo('long-15', '2026-03-15', 'long', 18000),
      ]),
      _week(2, nextPhase, nextPlanned, [
        _wo('long-22', '2026-03-22', 'long', 19000),
      ]),
    ];

void _expectAdvice(
    MissedPrompt? p, MakeUpRecommendation rec, MissedWorkoutReason reason) {
  expect(p?.advice.recommendation, rec);
  expect(p?.advice.reason, reason);
}

void main() {
  test('the window is seven days', () {
    expect(missedPromptWindowDays, 7);
  });

  test('nothing missed asks nothing', () {
    final weeks = [
      _week(0, 'build', 20000,
          [_wo('a', '2026-03-10', 'easy', 5000, completed: true)]),
    ];
    expect(missedWorkoutPrompt(weeks: weeks, today: _today), isNull);
  });

  test("today's workout is never missed", () {
    final weeks = [
      _week(0, 'build', 20000, [_wo('a', _today, 'long', 15000)]),
    ];
    expect(missedWorkoutPrompt(weeks: weeks, today: _today), isNull);
  });

  test('rest, done and skipped workouts are never asked about', () {
    final weeks = [
      _week(0, 'build', 20000, [
        _wo('rest', '2026-03-09', 'rest', null),
        _wo('done', '2026-03-08', 'easy', 5000, completed: true),
        _wo('skip', '2026-03-10', 'tempo', 7000, skipped: true),
      ]),
    ];
    expect(missedWorkoutPrompt(weeks: weeks, today: _today), isNull);
  });

  test('the most recent miss is asked about', () {
    final p = missedWorkoutPrompt(weeks: _block(), today: _today);
    expect(p?.workoutId, 'tue');
    expect(p?.scheduledDate, '2026-03-10');
  });

  test('an answered miss is not asked again, and the next most recent is', () {
    final p =
        missedWorkoutPrompt(weeks: _block(tempoAnswered: true), today: _today);
    expect(p?.workoutId, 'long-8');
  });

  test(
      'a miss exactly seven days back is asked about, one eight days back is not',
      () {
    final seven = [
      _week(0, 'build', 20000, [_wo('a', '2026-03-04', 'easy', 5000)]),
    ];
    expect(missedWorkoutPrompt(weeks: seven, today: _today)?.workoutId, 'a');
    final eight = [
      _week(0, 'build', 20000, [_wo('a', '2026-03-03', 'easy', 5000)]),
    ];
    expect(missedWorkoutPrompt(weeks: eight, today: _today), isNull);
  });

  test('two misses on one day keep the earlier in plan order', () {
    final weeks = [
      _week(0, 'build', 20000, [
        _wo('first', '2026-03-10', 'easy', 5000),
        _wo('second', '2026-03-10', 'tempo', 6000),
      ]),
    ];
    expect(
        missedWorkoutPrompt(weeks: weeks, today: _today)?.workoutId, 'first');
  });

  test('a missed easy run is let go, with no make-up', () {
    final weeks = [
      _week(0, 'build', 20000, [
        _wo('a', '2026-03-10', 'easy', 5000),
        _wo('l', '2026-03-15', 'long', 15000),
      ]),
    ];
    final p = missedWorkoutPrompt(weeks: weeks, today: _today);
    _expectAdvice(
        p, MakeUpRecommendation.skip, MissedWorkoutReason.notLongRun);
    expect(p?.makeUp, isNull);
    expect(p?.makeUpAnswers, isEmpty);
  });

  test('a missed tempo is dropped, not moved', () {
    final p = missedWorkoutPrompt(weeks: _block(), today: _today);
    expect(p?.kind, 'tempo');
    _expectAdvice(
        p, MakeUpRecommendation.skip, MissedWorkoutReason.notLongRun);
    expect(p?.makeUp, isNull);
  });

  test(
      'a missed long run in the build is made up by stretching the next long run at most 15%',
      () {
    final p = missedWorkoutPrompt(weeks: _block(tempoDone: true), today: _today);
    expect(p?.workoutId, 'long-8');
    _expectAdvice(
        p, MakeUpRecommendation.makeUp, MissedWorkoutReason.keySession);
    expect(p?.makeUp?.workoutId, 'long-15');
    expect(p?.makeUp?.fromMetres, 18000);
    expect(p?.makeUp?.toMetres, 20000);
    expect(p?.makeUpAnswers, ['long-8']);
  });

  test('the stretch is capped at 15% of the next long run', () {
    final p = missedWorkoutPrompt(
        weeks: _block(lastLongM: 30000, tempoDone: true), today: _today);
    expect(p?.makeUp?.toMetres, 20700);
  });

  test('a missed long run in the taper is let go', () {
    final weeks = [
      _week(0, 'taper', 20000, [_wo('long', '2026-03-08', 'long', 16000)]),
      _week(1, 'race', 15000, [_wo('race', '2026-03-15', 'race', 21097)]),
    ];
    final p = missedWorkoutPrompt(weeks: weeks, today: _today);
    _expectAdvice(p, MakeUpRecommendation.skip, MissedWorkoutReason.taper);
    expect(p?.makeUp, isNull);
  });

  test('a missed long run before a recovery week is let go', () {
    final weeks = [
      _week(0, 'build', 40000, const []),
      _week(1, 'build', 42000, [_wo('long-10', '2026-03-10', 'long', 20000)]),
      _week(2, 'build', 30000, [_wo('long-22', '2026-03-22', 'long', 19000)]),
    ];
    final p = missedWorkoutPrompt(weeks: weeks, today: _today);
    _expectAdvice(
        p, MakeUpRecommendation.skip, MissedWorkoutReason.recoverySoon);
    expect(p?.makeUp, isNull);
  });

  test('a long run the next long run already covers asks with no make-up', () {
    final p = missedWorkoutPrompt(
        weeks: _block(lastLongM: 16000, tempoDone: true), today: _today);
    _expectAdvice(
        p, MakeUpRecommendation.makeUp, MissedWorkoutReason.keySession);
    expect(p?.makeUp, isNull);
    expect(p?.makeUpAnswers, isEmpty);
  });

  test('an answered long run does not feed the make-up', () {
    final weeks = [
      _week(0, 'build', 40000,
          [_wo('old', '2026-03-01', 'long', 30000, answered: true)]),
      _week(1, 'build', 42000, [_wo('new', '2026-03-08', 'long', 19000)]),
      _week(2, 'build', 44000, [_wo('next', '2026-03-15', 'long', 18000)]),
    ];
    final p = missedWorkoutPrompt(weeks: weeks, today: _today);
    expect(p?.workoutId, 'new');
    expect(p?.makeUp?.toMetres, 19000);
    expect(p?.makeUpAnswers, ['new']);
  });

  test('an older unanswered missed long run is answered with the make-up it feeds',
      () {
    final weeks = [
      _week(0, 'build', 40000, [_wo('old', '2026-02-22', 'long', 22000)]),
      _week(1, 'build', 42000, [_wo('new', '2026-03-08', 'long', 19000)]),
      _week(2, 'build', 44000, [_wo('next', '2026-03-15', 'long', 18000)]),
    ];
    final p = missedWorkoutPrompt(weeks: weeks, today: _today);
    expect(p?.workoutId, 'new');
    expect(p?.makeUp?.toMetres, 20700);
    expect(p?.makeUpAnswers, ['old', 'new']);
  });

  test('a missed walk-run session is answered with repeating the week, never a make-up',
      () {
    final weeks = [
      _week(0, 'build', 0, [
        _wo('wr-9', '2026-03-09', 'walk_run', 2050),
        _wo('wr-11', '2026-03-11', 'walk_run', 2050),
      ]),
      _week(1, 'graduation', 0, [_wo('wr-16', '2026-03-16', 'walk_run', 2050)]),
    ];
    final p = missedWorkoutPrompt(weeks: weeks, today: _today);
    expect(p?.workoutId, 'wr-9');
    expect(p?.advice.recommendation, MakeUpRecommendation.skip);
    expect(p?.advice.reason, MissedWorkoutReason.repeatWeek);
    expect(p?.makeUp, isNull);
    expect(p?.makeUpAnswers, isEmpty);
  });
}
