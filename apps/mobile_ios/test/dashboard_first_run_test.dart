import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ui_kit/ui_kit.dart' show ActivityLoader;

import '../lib/goals.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/local_food_store.dart';
import '../lib/local_gym_store.dart';
import '../lib/local_route_store.dart';
import '../lib/local_run_store.dart';
import '../lib/preferences.dart';
import '../lib/screens/dashboard_screen.dart';
import '../lib/training_service.dart';
import '../lib/widgets/pending_sync_banner.dart';
import 'pump_until.dart';
import 'store_write_watch.dart';

/// A signed-in client that answers the two history probes, and counts the PB
/// fetch so a pull-to-refresh can be observed.
class _HistoryApi extends ApiClient {
  _HistoryApi({this.runs = 0});

  final int runs;
  int pbFetches = 0;

  @override
  String? get userId => 'u1';

  @override
  Future<List<
      ({
        Map<String, dynamic> workout,
        List<Map<String, dynamic>> sets
      })>> fetchGymWorkoutsWithSets({int limit = 50}) async =>
      const [];

  @override
  Future<List<Run>> getRuns({
    int limit = 50,
    DateTime? before,
    DateTime? updatedSince,
  }) async =>
      [
        for (var i = 0; i < runs; i++)
          Run(
            id: 'r$i',
            startedAt: DateTime.utc(2026, 4, 15),
            duration: const Duration(minutes: 25),
            distanceMetres: 5000,
            source: RunSource.app,
          ),
      ];

  @override
  Future<List<FoodLogRow>> fetchFoodLog({
    required DateTime from,
    required DateTime to,
  }) async =>
      const [];

  @override
  Future<List<PersonalRecordRow>> fetchPersonalRecords() async {
    pbFetches++;
    return const [];
  }

  @override
  Future<UserProfileRow?> fetchMyProfile() async => null;
}

class _PlanTraining extends TrainingService {
  @override
  Future<ActivePlanOverview?> fetchActiveOverview() async {
    final today = DateTime.now();
    final workout = PlanWorkoutRow(
      id: 'wo-1',
      weekId: 'wk-1',
      scheduledDate: today,
      kind: 'easy',
      targetDistanceM: 5000,
      manuallyCompleted: false,
    );
    return ActivePlanOverview(
      plan: TrainingPlanRow(
        id: 'plan-1',
        userId: 'u1',
        name: 'First 5k',
        goalEvent: '5k',
        goalDistanceM: 5000,
        startDate: today,
        endDate: today.add(const Duration(days: 56)),
        daysPerWeek: 3,
        status: 'active',
        source: 'app',
        isTemplate: false,
        isPublicTemplate: false,
      ),
      weeks: [
        PlanWeekRow(
          id: 'wk-1',
          planId: 'plan-1',
          weekIndex: 0,
          phase: 'base',
          targetVolumeM: 10000,
        ),
      ],
      workouts: [workout],
      todayWorkout: workout,
      completionPct: 0,
      currentWeekIndex: 0,
    );
  }
}

final _dirs = <Directory>[];

Future<Directory> _tmp(String tag) async {
  final d = Directory.systemTemp.createTempSync('dash_first_run_$tag');
  _dirs.add(d);
  return d;
}

Future<
    ({
      LocalRunStore runStore,
      LocalRouteStore routeStore,
      LocalGymStore gymStore,
      LocalFoodStore foodStore,
      Preferences prefs,
    })> _stores() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = Preferences();
  await prefs.init();
  final runStore = LocalRunStore();
  await runStore.init(overrideDirectory: await _tmp('runs'));
  final gymStore = LocalGymStore();
  await gymStore.init(overrideDirectory: await _tmp('gym'));
  final foodStore = LocalFoodStore();
  await foodStore.init(overrideDirectory: await _tmp('food'));
  return (
    runStore: runStore,
    routeStore: LocalRouteStore(),
    gymStore: gymStore,
    foodStore: foodStore,
    prefs: prefs,
  );
}

Future<void> _pump(
  WidgetTester tester,
  dynamic s, {
  ApiClient? api,
  TrainingService? training,
  VoidCallback? onLogLift,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: DashboardScreen(
        apiClient: api,
        training: training,
        runStore: s.runStore,
        routeStore: s.routeStore,
        gymStore: s.gymStore,
        foodStore: s.foodStore,
        preferences: s.prefs,
        onLogLift: onLogLift,
      ),
    ),
  );
  await tester.pump();
}

void main() {
  installStoreWriteWatch();

  tearDown(() {
    for (final d in _dirs) {
      if (d.existsSync()) d.deleteSync(recursive: true);
    }
    _dirs.clear();
  });

  group('Home names itself', () {
    testWidgets('carries a title and no second, mute route to the coach',
        (tester) async {
      final s = await _stores();
      await _pump(tester, s);
      expect(find.text('Home'), findsOneWidget,
          reason: 'the surface opened on four unlabelled glyphs and no title');
      // `_coachEntry()` is a labelled card 8 dp below the toolbar, so the
      // toolbar glyph was a duplicate route with a tooltip for a label.
      expect(find.byIcon(Icons.psychology_outlined), findsNothing);
    });
  });

  group('the runless welcome state', () {
    testWidgets('survives the runner accepting its own offer to set a goal',
        (tester) async {
      final s = await _stores();
      await s.prefs.upsertGoal(const RunGoal(
        id: 'g1',
        period: GoalPeriod.week,
        distanceMetres: 20000,
      ));
      await _pump(tester, s);

      // The old gate was `runs.isEmpty && goals.isEmpty`, so taking the
      // welcome copy's own "Set a goal" action replaced it with three zeroed
      // period cards and a blank heatmap (issue #921).
      expect(find.text('Welcome!'), findsOneWidget);
      // And the goal it just set is still on screen.
      expect(find.textContaining('Goals'), findsWidgets);
    });

    testWidgets('offers a lifter the gym, as web does', (tester) async {
      final s = await _stores();
      var lifts = 0;
      await _pump(tester, s, onLogLift: () => lifts++);

      expect(find.text('Welcome!'), findsOneWidget);
      expect(find.text('Lifting instead?'), findsOneWidget);
      await tester.ensureVisible(find.text('Log a gym session'));
      await tester.tap(find.text('Log a gym session'));
      expect(lifts, 1);
    });

    testWidgets('hides the gym way out when the host cannot reach it',
        (tester) async {
      final s = await _stores();
      await _pump(tester, s);

      expect(find.text('Welcome!'), findsOneWidget);
      expect(find.text('Log a gym session'), findsNothing,
          reason: 'a hint with no working action is a dead button');
    });

    testWidgets('points at the plan card when onboarding already made one',
        (tester) async {
      final s = await _stores();
      await _pump(tester, s, training: _PlanTraining());
      await pumpUntil(
          tester,
          () => find
              .textContaining('Your plan is ready above')
              .evaluate()
              .isNotEmpty,
          describe: 'the plan overview to resolve');

      expect(find.text('Welcome!'), findsOneWidget);
      expect(
          find.text('Your dashboard fills in once you record a run, set a '
              'goal, or import your history.'),
          findsNothing);
    });

    testWidgets('is not shown to a lifter with no runs', (tester) async {
      final s = await _stores();
      await tester.runAsync(() => s.gymStore.createLocal(
            title: 'Push day',
            startedAt: DateTime.now(),
            sets: const [
              (
                exerciseName: 'Bench',
                reps: 8,
                weightKg: 60.0,
                rpe: null,
                setType: null,
                durationS: null,
                exerciseId: null,
              ),
            ],
          ));
      await _pump(tester, s);
      await tester.pump();
      expect(find.text('Welcome!'), findsNothing,
          reason: 'web gates on runs AND gym sessions; 50 lifts is a history');
      await pumpUntilStoreWritesSettle(tester);
    });

    testWidgets('waits for the server before telling a fresh install it has '
        'never run', (tester) async {
      // Disk hydrates before the first frame, so a new device of a
      // deep-history account renders an empty store. Claiming the welcome
      // state from that alone told the owner of 500 synced runs they had
      // never run (issue #921).
      final s = await _stores();
      final api = _HistoryApi(runs: 1);
      await _pump(tester, s, api: api);

      expect(find.text('Welcome!'), findsNothing);
      expect(find.byType(ActivityLoader), findsOneWidget);

      await pumpUntil(tester, () => api.pbFetches > 0,
          describe: 'the mount-time loaders to finish');
      expect(find.text('Welcome!'), findsNothing,
          reason: 'the server says this account has runs on the way');
      await pumpUntilStoreWritesSettle(tester);
    });

    testWidgets('is claimed once the server confirms there is nothing',
        (tester) async {
      final s = await _stores();
      final api = _HistoryApi();
      await _pump(tester, s, api: api);
      await pumpUntil(
          tester, () => find.text('Welcome!').evaluate().isNotEmpty,
          describe: 'the history probe to come back empty');
      await pumpUntilStoreWritesSettle(tester);
    });
  });

  group('Home discloses what has not reached the server', () {
    testWidgets('an unsynced lift raises the banner Home never had',
        (tester) async {
      final s = await _stores();
      await tester.runAsync(() => s.gymStore.createLocal(
            title: 'Push day',
            startedAt: DateTime.now(),
            sets: const [
              (
                exerciseName: 'Bench',
                reps: 8,
                weightKg: 60.0,
                rpe: null,
                setType: null,
                durationS: null,
                exerciseId: null,
              ),
            ],
          ));
      await _pump(tester, s);
      await tester.pump();
      // Home was the one offline-first surface with no pending disclosure at
      // all, so a row that never reached the server was invisible here.
      expect(find.byType(PendingSyncBanner), findsOneWidget);
      expect(find.textContaining('saved on this device'), findsOneWidget);
      await pumpUntilStoreWritesSettle(tester);
    });
  });

  group('Home is not frozen for the process lifetime', () {
    testWidgets('a pull re-runs the loaders', (tester) async {
      final s = await _stores();
      final api = _HistoryApi();
      await _pump(tester, s, api: api);
      await pumpUntil(tester, () => api.pbFetches == 1,
          describe: 'the mount-time PB fetch');

      expect(find.byType(RefreshIndicator), findsOneWidget,
          reason: 'Runs / Gym / Nutrition all pull to refresh; Home did not');
      await tester.fling(
          find.byType(RefreshIndicator), const Offset(0, 300), 1000);
      // The indicator only calls `onRefresh` once the drag settles, and
      // `pumpUntil` deliberately never advances the fake clock.
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await pumpUntil(tester, () => api.pbFetches > 1,
          describe: 'the pull to re-run the five loaders');
      await pumpUntilStoreWritesSettle(tester);
    });
  });
}
