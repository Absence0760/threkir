// Workout detail's failure paths and its open-workout actions (#1186
// Robustness: "error and timeout states", "workout detail skip / unskip /
// Start").

import 'dart:async';
import 'dart:io';

import 'package:core_models/core_models.dart' hide Route;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart' show ListCard;
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/main.dart' show pendingStartWorkout;
import '../lib/plan_current.dart' show PlanWorkoutStatus;
import '../lib/run_stop_dock.dart';
import '../lib/screens/workout_detail_screen.dart';
import '../lib/training_service.dart';
import '../lib/widgets/plan_workout_status_style.dart';
import '../lib/widgets/loading_skeletons.dart';
import 'pump_until.dart';

PlanWorkoutRow _workout({DateTime? skippedAt, bool manual = false}) =>
    PlanWorkoutRow(
      id: 'wo-1',
      weekId: 'week-1',
      scheduledDate: DateTime(2026, 4, 5),
      kind: 'easy',
      targetDistanceM: 5000,
      manuallyCompleted: manual,
      completedAt: manual ? DateTime(2026, 4, 5, 9) : null,
      skippedAt: skippedAt,
    );

class _FakeTraining extends TrainingService {
  /// What each `fetchWorkout` call does, in order; the last one repeats. An
  /// [Object] is thrown; null serves [workout].
  final List<Object?> loads;
  PlanWorkoutRow workout;
  Object? skipError;
  Object? markError;
  int fetchCalls = 0;
  final skipCalls = <bool>[];
  final markCalls = <bool>[];

  /// Hold the write open until completed, when set: a write the backend
  /// never answers, or one still in flight.
  Completer<void>? skipGate;
  Completer<void>? markGate;

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
    await skipGate?.future;
    if (skipError != null) throw skipError!;
    workout = _workout(skippedAt: skipped ? DateTime(2026, 4, 5, 9) : null);
  }

  @override
  Future<void> markCompleted(
    String workoutId,
    String? runId, {
    bool manual = false,
  }) async {
    markCalls.add(manual);
    await markGate?.future;
    if (markError != null) throw markError!;
    workout = _workout(manual: manual);
  }
}

/// What a Start left for the shell and the recorder: the workout it armed and
/// the start it asked for. Spent on read, so one test's Start cannot answer
/// for the next.
({String? armed, RunStartRequest? start}) _takeStart() {
  final armed = pendingStartWorkout.value?.id;
  pendingStartWorkout.value = null;
  return (armed: armed, start: runStartRequests.take());
}

/// Opens the screen from a host route so a pop has somewhere to land, and
/// returns the future of what it popped with.
Future<Future<Object?>> _open(
  WidgetTester tester,
  _FakeTraining training, {
  PlanWorkoutRow? initial,
}) async {
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
                initial: initial,
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
    () => !tester.any(find.byType(SectionedDetailSkeleton)),
    describe: 'the workout fetch to settle',
  );
  await tester.pump();
  return popped;
}

void main() {
  final en = lookupAppLocalizations(const Locale('en'));

  // Mark done and Skip write the same row; with each guarding only itself,
  // both could be tapped together and their reloads raced.
  testWidgets('while Mark done is in flight, Skip is held too', (tester) async {
    final gate = Completer<void>();
    final training = _FakeTraining(_workout())..markGate = gate;
    await _open(tester, training, initial: _workout());
    await tester.tap(find.byKey(const Key('workoutDetailMarkDone')));
    await tester.pump();

    final skip = tester.widget<ButtonStyleButton>(
        find.byKey(const Key('workoutDetailSkip')));
    expect(skip.onPressed, isNull);
    await tester.tap(find.byKey(const Key('workoutDetailSkip')));
    await tester.pump();
    expect(training.skipCalls, isEmpty);

    gate.complete();
    await pumpUntil(
      tester,
      () => tester.any(find.byKey(const Key('workoutDetailMarkNotDone'))),
      describe: 'the mark to land and the done panel to render',
    );
    expect(training.markCalls, [true]);
  });

  group('writes the backend never answers', () {
    testWidgets('Mark done gives up, says so and gives the button back',
        (tester) async {
      final training = _FakeTraining(_workout())..markGate = Completer<void>();
      await _open(tester, training, initial: _workout());
      await tester.tap(find.byKey(const Key('workoutDetailMarkDone')));
      await tester.pump();
      expect(markButton(tester).onPressed, isNull);

      await tester.pump(const Duration(seconds: 16));
      expect(find.text(en.workoutUpdateError), findsOneWidget);
      expect(markButton(tester).onPressed, isNotNull);
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('Skip gives up, says so and gives the button back',
        (tester) async {
      final training = _FakeTraining(_workout())..skipGate = Completer<void>();
      await _open(tester, training, initial: _workout());
      await tester.tap(find.text(en.workoutSkip));
      await tester.pump();

      await tester.pump(const Duration(seconds: 16));
      expect(find.text(en.workoutSkipError), findsOneWidget);
      expect(skipButton(tester, en).onPressed, isNotNull);
      await tester.pump(const Duration(seconds: 4));
    });
  });

  group('load failures', () {
    testWidgets('a failed load says so, and retry recovers', (tester) async {
      final training = _FakeTraining(
        _workout(),
        loads: [Exception('boom'), null],
      );
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

  group('a row handed in by the caller', () {
    testWidgets('renders at once, and Start works with no signal', (
      tester,
    ) async {
      final training = _FakeTraining(
        _workout(),
        loads: [const SocketException('no route')],
      );
      final popped = await _open(tester, training, initial: _workout());

      expect(training.fetchCalls, 1, reason: 'it still tries to refresh');
      expect(find.text(en.workoutStart), findsOneWidget);
      expect(find.text(en.commonStaleOffline), findsOneWidget);
      expect(find.text(en.authErrorOffline), findsNothing);

      await tester.tap(find.text(en.workoutStart));
      await tester.pumpAndSettle();
      await popped;
      expect(_takeStart(), (armed: 'wo-1', start: RunStartRequest.start));
    });

    testWidgets('a fresher row from the refresh replaces it', (tester) async {
      final training = _FakeTraining(
        _workout(skippedAt: DateTime(2026, 4, 5, 9)),
      );
      await _open(tester, training, initial: _workout());

      expect(find.byKey(const Key('workoutDetailSkipped')), findsOneWidget);
      expect(find.text(en.workoutStart), findsNothing);
    });
  });

  testWidgets('a first load offline says offline', (tester) async {
    await _open(
      tester,
      _FakeTraining(_workout(), loads: [const SocketException('no route')]),
    );
    expect(find.text(en.authErrorOffline), findsOneWidget);
    expect(find.text(en.workoutLoadError), findsNothing);
  });

  group('open-workout actions', () {
    testWidgets(
        'Start returns to the shell and starts the run with the workout '
        'armed, whoever opened the page (#1374)', (tester) async {
      // Progress and a notification open this page too, and neither read a
      // popped row: their Start was a dead button. Start now asks for the
      // start itself, through the recorder's own checks and countdown.
      final popped = await _open(tester, _FakeTraining(_workout()));

      await tester.tap(find.text(en.workoutStart));
      await tester.pumpAndSettle();

      expect(await popped, isNull);
      expect(find.byType(WorkoutDetailScreen), findsNothing);
      expect(_takeStart(), (armed: 'wo-1', start: RunStartRequest.start));
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

    testWidgets('a failed skip says so and leaves the workout open', (
      tester,
    ) async {
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

  // #1186 parity: web lets a runner tick a session they did without
  // recording it; mobile had the service call and no button.
  group('mark as done by hand', () {
    testWidgets('marks it done in the shared done look, and Mark not done '
        'reopens it with no dialog', (tester) async {
      final training = _FakeTraining(_workout());
      await _open(tester, training);

      await tester.tap(find.byKey(const Key('workoutDetailMarkDone')));
      await pumpUntil(
        tester,
        () => tester.any(find.byKey(const Key('workoutDetailCompleted'))),
        describe: 'the completed panel after the reload',
      );
      expect(training.markCalls, [true]);
      expect(find.text(en.workoutStart), findsNothing);

      final context = tester.element(
        find.byKey(const Key('workoutDetailCompleted')),
      );
      final done = planWorkoutStatusLook(
        Theme.of(context),
        PlanWorkoutStatus.done,
      );
      final card = tester.widget<ListCard>(
        find.byKey(const Key('workoutDetailCompleted')),
      );
      expect(card.color, done.fill);
      expect(card.outline, done.outline);

      await tester.tap(find.byKey(const Key('workoutDetailMarkNotDone')));
      await pumpUntil(
        tester,
        () => tester.any(find.text(en.workoutStart)),
        describe: 'the open workout after clearing the mark',
      );
      expect(find.byType(AlertDialog), findsNothing);
      expect(training.markCalls, [true, false]);
    });

    testWidgets('a failed mark says so and leaves the workout open', (
      tester,
    ) async {
      final training = _FakeTraining(_workout())..markError = Exception('no');
      await _open(tester, training);

      await tester.tap(find.byKey(const Key('workoutDetailMarkDone')));
      await tester.pump();
      await tester.pump();

      expect(find.text(en.workoutUpdateError), findsOneWidget);
      expect(find.text(en.workoutStart), findsOneWidget);
      expect(find.byKey(const Key('workoutDetailCompleted')), findsNothing);
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('a rest day offers no mark', (tester) async {
      final training = _FakeTraining(
        PlanWorkoutRow(
          id: 'wo-1',
          weekId: 'week-1',
          scheduledDate: DateTime(2026, 4, 5),
          kind: 'rest',
          manuallyCompleted: false,
        ),
      );
      await _open(tester, training);
      expect(find.byKey(const Key('workoutDetailMarkDone')), findsNothing);
    });
  });
}

ButtonStyleButton markButton(WidgetTester tester) => tester.widget<ButtonStyleButton>(
    find.ancestor(
        of: find.byKey(const Key('workoutDetailMarkDone')),
        matching: find.bySubtype<ButtonStyleButton>(),
        matchRoot: true).first);

ButtonStyleButton skipButton(WidgetTester tester, AppLocalizations en) =>
    tester.widget<ButtonStyleButton>(find
        .ancestor(
            of: find.text(en.workoutSkip),
            matching: find.bySubtype<ButtonStyleButton>())
        .first);
