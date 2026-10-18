// Workout detail's failure paths and its open-workout actions (#1186
// Robustness: "error and timeout states", "workout detail skip / unskip /
// Start").

import 'dart:async';

import 'package:core_models/core_models.dart' hide Route;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart' show FullBodyLoader;
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/screens/workout_detail_screen.dart';
import '../lib/training_service.dart';
import 'pump_until.dart';

PlanWorkoutRow _workout({DateTime? skippedAt}) => PlanWorkoutRow(
      id: 'wo-1',
      weekId: 'week-1',
      scheduledDate: DateTime(2026, 4, 5),
      kind: 'easy',
      targetDistanceM: 5000,
      manuallyCompleted: false,
      skippedAt: skippedAt,
    );

class _FakeTraining extends TrainingService {
  /// What each `fetchWorkout` call does, in order; the last one repeats. An
  /// [Object] is thrown; null serves [workout].
  final List<Object?> loads;
  PlanWorkoutRow workout;
  Object? skipError;
  int fetchCalls = 0;
  final skipCalls = <bool>[];

  _FakeTraining(this.workout, {this.loads = const [null]});

  @override
  Future<PlanWorkoutRow?> fetchWorkout(String id) async {
    final outcome = loads[fetchCalls.clamp(0, loads.length - 1)];
    fetchCalls++;
    if (outcome != null) throw outcome;
    return workout;
  }

  @override
  Future<void> setSkipped(String workoutId, bool skipped) async {
    skipCalls.add(skipped);
    if (skipError != null) throw skipError!;
    workout = _workout(skippedAt: skipped ? DateTime(2026, 4, 5, 9) : null);
  }
}

/// Opens the screen from a host route so a pop has somewhere to land, and
/// returns the future of what it popped with.
Future<Future<Object?>> _open(
    WidgetTester tester, _FakeTraining training) async {
  late Future<Object?> popped;
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => popped = Navigator.of(context).push<Object?>(
            MaterialPageRoute(
              builder: (_) => WorkoutDetailScreen(
                training: training,
                planId: 'plan-1',
                workoutId: 'wo-1',
              ),
            ),
          ),
          child: const Text('open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await pumpUntil(
    tester,
    () => !tester.any(find.byType(FullBodyLoader)),
    describe: 'the workout fetch to settle',
  );
  await tester.pump();
  return popped;
}

void main() {
  final en = lookupAppLocalizations(const Locale('en'));

  group('load failures', () {
    testWidgets('a failed load says so, and retry recovers', (tester) async {
      final training =
          _FakeTraining(_workout(), loads: [Exception('boom'), null]);
      await _open(tester, training);

      expect(find.text(en.workoutLoadError), findsOneWidget);
      expect(find.text(en.workoutStart), findsNothing);

      await tester.tap(find.text(en.errorStateRetry));
      await pumpUntil(
        tester,
        () => tester.any(find.text(en.workoutStart)),
        describe: 'the retried load to render the workout',
      );
      expect(training.fetchCalls, 2);
      expect(find.text(en.workoutLoadError), findsNothing);
    });

    testWidgets('a timed-out load names the connection', (tester) async {
      await _open(
        tester,
        _FakeTraining(_workout(), loads: [TimeoutException('slow link')]),
      );
      expect(find.text(en.workoutTimeoutError), findsOneWidget);
      expect(find.text(en.workoutLoadError), findsNothing);
    });
  });

  group('open-workout actions', () {
    testWidgets('Start pops with the workout so the caller can run it',
        (tester) async {
      final popped = await _open(tester, _FakeTraining(_workout()));

      await tester.tap(find.text(en.workoutStart));
      await tester.pumpAndSettle();

      final result = await popped;
      expect(result, isA<PlanWorkoutRow>());
      expect((result! as PlanWorkoutRow).id, 'wo-1');
    });

    testWidgets('Skip marks it skipped, and Unskip reopens it', (tester) async {
      final training = _FakeTraining(_workout());
      await _open(tester, training);

      await tester.tap(find.text(en.workoutSkip));
      await pumpUntil(
        tester,
        () => tester.any(find.byKey(const Key('workoutDetailSkipped'))),
        describe: 'the skipped panel after the reload',
      );
      expect(training.skipCalls, [true]);
      expect(find.text(en.workoutStart), findsNothing);

      await tester.tap(find.text(en.workoutUnskip));
      await pumpUntil(
        tester,
        () => tester.any(find.text(en.workoutStart)),
        describe: 'the open workout after unskipping',
      );
      expect(training.skipCalls, [true, false]);
      expect(find.byKey(const Key('workoutDetailSkipped')), findsNothing);
    });

    testWidgets('a failed skip says so and leaves the workout open',
        (tester) async {
      final training = _FakeTraining(_workout())..skipError = Exception('no');
      await _open(tester, training);

      await tester.tap(find.text(en.workoutSkip));
      await tester.pump();
      await tester.pump();

      expect(find.text(en.workoutSkipError), findsOneWidget);
      expect(find.text(en.workoutStart), findsOneWidget);
      expect(find.byKey(const Key('workoutDetailSkipped')), findsNothing);
      await tester.pump(const Duration(seconds: 4));
    });
  });
}
