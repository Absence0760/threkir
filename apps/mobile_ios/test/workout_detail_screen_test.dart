import 'dart:async';

import 'package:core_models/core_models.dart' hide Route;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/rendering.dart';
import 'package:ui_kit/ui_kit.dart' show FullBodyLoader, ListSkeleton, TextLane;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/preferences.dart';
import '../lib/relink_candidates.dart';
import '../lib/screens/workout_detail_screen.dart';
import '../lib/training.dart';
import '../lib/training_service.dart';

PlanWorkoutRow _completedWorkout({String? completedRunId = 'run-current'}) {
  return PlanWorkoutRow(
    id: 'fake-workout-id',
    weekId: 'week-1',
    scheduledDate: DateTime(2026, 4, 5),
    kind: 'easy',
    targetDistanceM: 5000,
    completedRunId: completedRunId,
    completedAt: DateTime(2026, 4, 5, 8),
    manuallyCompleted: false,
  );
}

class _FakeTraining extends TrainingService {
  final PlanWorkoutRow workout;
  final List<RelinkCandidateRun> candidates;

  /// Held open so a test can observe the picker's loading frame.
  final Completer<void>? gateCandidates;
  String? lastMarkRunId;
  bool markCalled = false;

  _FakeTraining(this.workout, this.candidates, {this.gateCandidates});

  @override
  Future<PlanWorkoutRow?> fetchWorkout(String id) async => workout;

  @override
  Future<List<RelinkCandidateRun>> fetchRelinkCandidates(
    PlanWorkoutRow workout,
  ) async {
    await gateCandidates?.future;
    return candidates;
  }

  @override
  Future<void> markCompleted(String workoutId, String? runId,
      {bool manual = false}) async {
    markCalled = true;
    lastMarkRunId = runId;
  }
}

RelinkCandidateRun _cand(String id, String started) => RelinkCandidateRun(
      id: id,
      startedAt: DateTime.parse(started),
      distanceM: 5000,
      durationS: 1800,
    );

Future<void> _pumpWith(WidgetTester tester, _FakeTraining training) {
  return tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: WorkoutDetailScreen(
        training: training,
        planId: 'fake-plan-id',
        workoutId: 'fake-workout-id',
      ),
    ),
  );
}

bool _supabaseReady = false;

Future<void> _ensureSupabase() async {
  if (_supabaseReady) return;
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  await Supabase.initialize(
    url: 'http://127.0.0.1:24321',
    anonKey: 'eyJ.local.test',
  );
  _supabaseReady = true;
}

Future<void> _pump(WidgetTester tester) {
  return tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: WorkoutDetailScreen(
        training: TrainingService(),
        planId: 'fake-plan-id',
        workoutId: 'fake-workout-id',
      ),
    ),
  );
}

void main() {
  setUpAll(_ensureSupabase);

  group('WorkoutDetailScreen — initial render', () {
    testWidgets('first frame shows the full-body loader', (tester) async {
      // Reason: while _loading is true the screen returns a bare
      // Scaffold carrying nothing but the loader.
      await _pump(tester);
      expect(find.byType(FullBodyLoader), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 400));
    });

    testWidgets('the loading Scaffold keeps an AppBar, so back works',
        (tester) async {
      await _pump(tester);
      expect(find.byType(AppBar), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 400));
    });
  });

  group('WorkoutDetailScreen — re-link picker', () {
    testWidgets('Re-link opens the picker, picking a run calls markCompleted',
        (tester) async {
      final training = _FakeTraining(
        _completedWorkout(),
        [
          _cand('run-current', '2026-04-05T07:00:00Z'),
          _cand('run-other', '2026-04-06T07:00:00Z'),
        ],
      );
      await _pumpWith(tester, training);
      await tester.pumpAndSettle();

      // Completed card shows the Re-link button.
      expect(find.text('Re-link'), findsOneWidget);
      await tester.tap(find.text('Re-link'));
      await tester.pumpAndSettle();

      // Dialog lists both candidate runs.
      expect(find.text('Link a different run'), findsOneWidget);
      expect(find.byType(ListTile), findsNWidgets(2));
      // The current pick is tagged.
      expect(find.text('Current'), findsOneWidget);

      // Pick the non-current run.
      await tester.tap(find.byType(ListTile).at(1));
      await tester.pumpAndSettle();

      expect(training.markCalled, isTrue);
      expect(training.lastMarkRunId, 'run-other');
    });

    testWidgets('picker holds the row layout with a section skeleton while '
        'candidates load', (tester) async {
      final gate = Completer<void>();
      final training = _FakeTraining(
        _completedWorkout(),
        [_cand('run-current', '2026-04-05T07:00:00Z')],
        gateCandidates: gate,
      );
      await _pumpWith(tester, training);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Re-link'));
      // Indeterminate-free: the skeleton pulses forever, so pumpAndSettle
      // would never return.
      await tester.pump(const Duration(milliseconds: 400));

      final skeleton = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(ListSkeleton),
      );
      expect(skeleton, findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      // A skeleton that overflows its dialog is worse than the spinner it
      // replaced.
      expect(tester.takeException(), isNull);

      gate.complete();
      await tester.pump(const Duration(milliseconds: 400));
      expect(skeleton, findsNothing);
      expect(find.byType(ListTile), findsOneWidget);
    });

    testWidgets('picker shows the empty state when no candidates', (tester) async {
      final training = _FakeTraining(_completedWorkout(), const []);
      await _pumpWith(tester, training);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Re-link'));
      await tester.pumpAndSettle();

      expect(find.text('No eligible runs near this date.'), findsOneWidget);
      expect(find.byType(ListTile), findsNothing);
    });

    testWidgets('no Re-link button when the workout is only manually completed',
        (tester) async {
      final training = _FakeTraining(
        _completedWorkout(completedRunId: null),
        const [],
      );
      await _pumpWith(tester, training);
      await tester.pumpAndSettle();

      // Re-link is run-link-only: a manually-completed workout has no run.
      expect(find.text('Re-link'), findsNothing);
    });

    testWidgets('a manually-completed workout reads Completed and can be '
        'marked not done', (tester) async {
      final training = _FakeTraining(
        PlanWorkoutRow(
          id: 'fake-workout-id',
          weekId: 'week-1',
          scheduledDate: DateTime(2026, 4, 5),
          kind: 'easy',
          targetDistanceM: 5000,
          completedAt: DateTime(2026, 4, 5, 8),
          manuallyCompleted: true,
        ),
        const [],
      );
      await _pumpWith(tester, training);
      await tester.pumpAndSettle();

      // It used to read as a plain to-do with a Start button, while the
      // plan rows and calendar called it done.
      expect(find.text('Completed'), findsOneWidget);
      expect(find.text('Start workout'), findsNothing);

      await tester.tap(find.text('Mark not done'));
      await tester.pumpAndSettle();
      expect(find.text('Mark not done?'), findsOneWidget);
      await tester.tap(find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(TextButton, 'Mark not done'),
      ));
      await tester.pumpAndSettle();
      expect(training.markCalled, isTrue);
      expect(training.lastMarkRunId, isNull);
    });
  });

  group('WorkoutDetailScreen — race workout', () {
    PlanWorkoutRow raceWorkout({String? name, String? priority}) =>
        PlanWorkoutRow(
          id: 'fake-workout-id',
          weekId: 'week-1',
          scheduledDate: DateTime(2027, 4, 4),
          kind: 'race',
          targetDistanceM: 56000,
          targetDurationSeconds: 23400,
          raceName: name,
          racePriority: priority,
          manuallyCompleted: false,
        );

    testWidgets('headlines the race name and shows its priority and goal time',
        (tester) async {
      await _pumpWith(
          tester,
          _FakeTraining(
              raceWorkout(name: 'Two Oceans Ultra', priority: 'B'), const []));
      await tester.pumpAndSettle();
      expect(
          tester.widget<Text>(find.byKey(const Key('workoutDetailHeading'))).data,
          'Two Oceans Ultra');
      expect(find.text('RACE PRIORITY'), findsOneWidget);
      expect(find.text('B — important race'), findsOneWidget);
      expect(find.text('GOAL TIME'), findsOneWidget);
      expect(find.text('6:30:00'), findsOneWidget);
    });

    testWidgets('an unnamed race with no priority falls back to the kind',
        (tester) async {
      await _pumpWith(tester, _FakeTraining(raceWorkout(), const []));
      await tester.pumpAndSettle();
      expect(
          tester.widget<Text>(find.byKey(const Key('workoutDetailHeading'))).data,
          'Race');
      expect(find.text('RACE PRIORITY'), findsNothing);
    });
  });

  group('WorkoutDetailScreen — walk-run structure', () {
    // The C25K generator writes only duration_s / recovery_duration_s; the
    // structure list cast `distance_m as num` and threw on null.
    PlanWorkoutRow walkRunRow(int weekIndex) {
      final plan = generatePlan(GeneratePlanInput(
        goalEvent: GoalEvent.distance5k,
        startDate: DateTime(2026, 6, 1),
        daysPerWeek: 3,
        beginnerWalkRun: true,
      ));
      final g = plan.weeks[weekIndex].workouts
          .firstWhere((w) => w.kind == WorkoutKind.walkRun);
      return PlanWorkoutRow(
        id: 'fake-workout-id',
        weekId: 'week-1',
        scheduledDate: g.scheduledDate,
        kind: workoutKindDbValue(g.kind),
        targetDistanceM: g.targetDistanceM,
        targetDurationSeconds: g.targetDurationSeconds,
        targetPaceSecPerKm: g.targetPaceSecPerKm,
        structure: g.structure!.toJson(),
        manuallyCompleted: false,
      );
    }

    testWidgets('renders steps as durations instead of throwing',
        (tester) async {
      await _pumpWith(tester, _FakeTraining(walkRunRow(0), const []));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // Week 1: walk 5 min, run 1:00 / walk 1:30 x 8, walk 5 min.
      expect(find.text('5:00'), findsNWidgets(2));
      expect(find.text('@ easy'), findsNWidgets(2));
      expect(find.text('8× 1:00'), findsOneWidget);
      expect(
          tester
              .widget<Text>(find.byKey(const Key('workoutStepRecovery')))
              .textSpan!
              .toPlainText(),
          'Recovery  1:30 walk');
      expect(find.textContaining(' with '), findsNothing);
    });

    testWidgets('the hero reads the session as a pattern and a length',
        (tester) async {
      await _pumpWith(tester, _FakeTraining(walkRunRow(0), const []));
      await tester.pumpAndSettle();
      expect(
          tester.widget<Text>(find.byKey(const Key('walkRunPattern'))).data,
          '5 min warm-up, 8 × (1 min run / 90 s walk), 5 min cool-down');
      // 300 + 8 × 60 + 7 × 90 + 300 = 1710 s: a recovery sits between reps.
      expect(tester.widget<Text>(find.byKey(const Key('walkRunTotal'))).data,
          'about 29 min');
      expect(
          tester.widget<Text>(find.byKey(const Key('workoutDetailTotal'))).data,
          'Total: 28:30');
      expect(find.byKey(const Key('workoutDetailTimeline')), findsOneWidget);
    });

    testWidgets('the graduation run has no recovery clause', (tester) async {
      await _pumpWith(tester, _FakeTraining(walkRunRow(8), const []));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('1× 25:00'), findsOneWidget);
      expect(find.byKey(const Key('workoutStepRecovery')), findsNothing);
      expect(
          tester.widget<Text>(find.byKey(const Key('walkRunPattern'))).data,
          contains('25 min run'));
    });
  });

  group('WorkoutDetailScreen — header', () {
    PlanWorkoutRow row({String kind = 'tempo', String? zone}) => PlanWorkoutRow(
          id: 'fake-workout-id',
          weekId: 'week-1',
          scheduledDate: DateTime(2026, 4, 5),
          kind: kind,
          targetPaceSecPerKm: 300,
          paceZone: zone,
          manuallyCompleted: false,
        );

    testWidgets('the date is localized, not ISO, and the kind is not repeated '
        'in the AppBar', (tester) async {
      await _pumpWith(tester, _FakeTraining(row(), const []));
      await tester.pumpAndSettle();
      expect(
          tester.widget<Text>(find.byKey(const Key('workoutDetailDate'))).data,
          'Apr 5, 2026');
      expect(find.text('2026-04-05'), findsNothing);
      expect(find.text('Tempo'), findsOneWidget);
    });

    testWidgets('a Daniels zone code is explained, free text is kept',
        (tester) async {
      await _pumpWith(tester, _FakeTraining(row(zone: 'T'), const []));
      await tester.pumpAndSettle();
      expect(find.text('Zone T · Tempo'), findsOneWidget);
    });

    testWidgets('a session with no segments shows the free-form placeholder',
        (tester) async {
      await _pumpWith(tester, _FakeTraining(row(kind: 'easy'), const []));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('workoutDetailFreeForm')), findsOneWidget);
      expect(find.text('Free-form run'), findsOneWidget);
    });

    testWidgets('a rest day has no free-form placeholder', (tester) async {
      await _pumpWith(tester, _FakeTraining(row(kind: 'rest'), const []));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('workoutDetailFreeForm')), findsNothing);
    });
  });

  group('WorkoutDetailScreen — status panels reflow', () {
    Future<void> pumpGerman(WidgetTester tester, PlanWorkoutRow w) async {
      tester.view.physicalSize = const Size(360, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('de'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2.0)),
            child: child!,
          ),
          home: WorkoutDetailScreen(
            training: _FakeTraining(w, const []),
            planId: 'fake-plan-id',
            workoutId: 'fake-workout-id',
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('the completed panel fits in German at 2.0x', (tester) async {
      await pumpGerman(tester, _completedWorkout());
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('workoutDetailCompleted')), findsOneWidget);
    });

    testWidgets('the skipped panel fits in German at 2.0x', (tester) async {
      await pumpGerman(
          tester,
          PlanWorkoutRow(
            id: 'fake-workout-id',
            weekId: 'week-1',
            scheduledDate: DateTime(2026, 4, 5),
            kind: 'easy',
            skippedAt: DateTime(2026, 4, 5, 9),
            manuallyCompleted: false,
          ));
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('workoutDetailSkipped')), findsOneWidget);
    });
  });

  group('WorkoutDetailScreen — pace tolerance unit', () {
    PlanWorkoutRow tempo() => PlanWorkoutRow(
          id: 'fake-workout-id',
          weekId: 'week-1',
          scheduledDate: DateTime(2026, 4, 5),
          kind: 'tempo',
          targetPaceSecPerKm: 300,
          targetPaceToleranceSec: 10,
          manuallyCompleted: false,
        );

    Future<void> withUnit(bool miles) async {
      SharedPreferences.setMockInitialValues({'use_miles': miles});
      final prefs = Preferences();
      await prefs.init();
      registerActivePreferences(prefs);
    }

    tearDown(() async => withUnit(false));

    testWidgets('km mode labels the tolerance per km', (tester) async {
      await tester.runAsync(() => withUnit(false));
      await _pumpWith(tester, _FakeTraining(tempo(), const []));
      await tester.pumpAndSettle();
      expect(find.text('5:00/km'), findsOneWidget);
      expect(find.text('±10s/km'), findsOneWidget);
    });

    testWidgets('miles mode converts the tolerance to per mile',
        (tester) async {
      // 10 s/km beside an 8:03/mi pace is 16 s/mi, not "±10s".
      await tester.runAsync(() => withUnit(true));
      await _pumpWith(tester, _FakeTraining(tempo(), const []));
      await tester.pumpAndSettle();
      expect(find.text('8:03/mi'), findsOneWidget);
      expect(find.text('±16s/mi'), findsOneWidget);
    });
  });

  group('WorkoutDetailScreen — unlink confirm', () {
    testWidgets('Cancel does not unlink; confirm calls markCompleted(null)',
        (tester) async {
      final training = _FakeTraining(_completedWorkout(), const []);
      await _pumpWith(tester, training);
      await tester.pumpAndSettle();

      // Tap Unlink → confirm dialog appears.
      await tester.tap(find.text('Unlink'));
      await tester.pumpAndSettle();
      expect(find.text('Unlink run'), findsOneWidget);

      // Cancel → no mutation.
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(training.markCalled, isFalse);

      // Tap Unlink again → confirm via the dialog's Unlink button.
      await tester.tap(find.text('Unlink'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(TextButton, 'Unlink'),
        ),
      );
      await tester.pumpAndSettle();

      expect(training.markCalled, isTrue);
      expect(training.lastMarkRunId, isNull);
    });
  });

  group('WorkoutDetailScreen — the structure lane holds a localized term', () {
    // Each structure row is `term | value` with the term in a 90px box.
    // Portuguese "Desaquecimento" needs 105.7px in real Roboto at labelMedium
    // w700 and carries no break opportunity, so it painted straight over the
    // value beside it — at 1.0x, before the OS text scale entered it. German
    // "Wiederholungen" and Spanish "Repeticiones" are the same shape. The pair
    // now reflows (a Wrap) rather than sharing one line at any cost, because
    // at 2x a term and its value genuinely do not fit side by side.
    //
    // Pinned as a derivation, never as an absolute fit: flutter_test renders a
    // fixed-advance font 2-6x wider than Roboto, so a lane that clears its
    // term's intrinsic width here clears it on a device too.
    PlanWorkoutRow _structured() => PlanWorkoutRow(
          id: 'fake-workout-id',
          weekId: 'week-1',
          scheduledDate: DateTime(2026, 4, 5),
          kind: 'interval',
          targetDistanceM: 8000,
          manuallyCompleted: false,
          structure: const {
            'warmup': {'distance_m': 1500},
            'cooldown': {'distance_m': 1500},
          },
        );

    Future<void> pumpPortuguese(WidgetTester tester, {double scale = 1.0}) async {
      tester.view.physicalSize = const Size(320, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('pt'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: WorkoutDetailScreen(
            training: _FakeTraining(_structured(), const []),
            planId: 'fake-plan-id',
            workoutId: 'fake-workout-id',
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Finder termLane() => find.ancestor(
          of: find.text('Desaquecimento'),
          matching: find.byType(TextLane),
        );

    testWidgets('the term lane widens to the term instead of overpainting',
        (tester) async {
      await pumpPortuguese(tester);
      expect(termLane(), findsOneWidget);
      final term =
          tester.renderObject<RenderParagraph>(find.text('Desaquecimento'));
      expect(
        tester.getSize(termLane()).width,
        greaterThanOrEqualTo(term.getMaxIntrinsicWidth(double.infinity)),
      );
      expect(term.size.height, lessThan(term.preferredLineHeight * 2),
          reason: 'the term must stay one line tall');
    });

    testWidgets('the term lane floor grows with the OS text scale',
        (tester) async {
      await pumpPortuguese(tester, scale: 2.0);
      expect(tester.takeException(), isNull,
          reason: 'the pair reflows rather than overrunning the card');
      expect(tester.getSize(termLane()).width, greaterThanOrEqualTo(180));
    });
  });
}
