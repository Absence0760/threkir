// First-time plan discovery on Home (training.md § First-time plan
// discovery; web `Recent5kPlanCard.svelte` + the dashboard plan promo). A
// runner with no plan always has a way to start one: "Train for something"
// in the welcome block and the plan slot, or, with a measured 5K from the
// last eight weeks, a suggestion to build a plan from it. "Not now" is stored
// in the universal settings bag. The pick itself is pinned by
// recent_5k_suggestion_test.dart; this pins the surface.

import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/l10n/date_format.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/local_food_store.dart';
import '../lib/local_gym_store.dart';
import '../lib/local_route_store.dart';
import '../lib/local_run_store.dart';
import '../lib/preferences.dart';
import '../lib/screens/dashboard_screen.dart';
import '../lib/screens/plan_new_screen.dart';
import '../lib/settings_sync.dart';
import '../lib/plan_calibration.dart';
import '../lib/training_service.dart';
import '../lib/widgets/top_banner.dart' show kTopBannerMaxDuration;
import 'pump_until.dart';

class _Api extends ApiClient {
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
  Future<List<Run>> getRuns({int limit = 50, DateTime? before}) async =>
      const [];

  @override
  Future<List<FoodLogRow>> fetchFoodLog({
    required DateTime from,
    required DateTime to,
  }) async =>
      const [];

  @override
  Future<List<PersonalRecordRow>> fetchPersonalRecords() async => const [];

  @override
  Future<UserProfileRow?> fetchMyProfile() async => null;
}

class _Training extends TrainingService {
  _Training({this.overview, this.fails = false});
  final ActivePlanOverview? overview;
  final bool fails;

  @override
  Future<ActivePlanOverview?> fetchActiveOverview() async {
    if (fails) throw Exception('test: plan read failed');
    return overview;
  }

  @override
  Future<TrainingPlanRow?> fetchPausedPlan() async => null;

  @override
  Future<PlanCalibration> fetchPlanCalibration() async =>
      PlanCalibration.unknown;
  @override
  Future<PlanRunHistory?> fetchPlanRunHistory() async => null;
  @override
  Future<List<TrainingPlanRow>> fetchClubTemplates(String clubId) async =>
      const [];
}

class _Service extends SettingsService {
  _Service(this.values) : super(deviceId: 'test-device', platform: 'android');
  final Map<String, dynamic> values;

  @override
  T? effective<T>(String key, {T? fallback}) =>
      values.containsKey(key) ? values[key] as T? : fallback;
}

class _Sync extends SettingsSyncService {
  _Sync(Preferences prefs, this._service, {this.writeFails = false})
      : super(preferences: prefs);
  final SettingsService? _service;
  final bool writeFails;
  final List<Map<String, dynamic>> writes = [];

  @override
  bool get synced => true;

  @override
  SettingsService? get service => _service;

  @override
  Future<void> updateUniversal(Map<String, dynamic> changes) async {
    writes.add(changes);
    if (writeFails) throw Exception('test: settings write refused');
  }
}

/// A plan that starts in ten days: its "Starts in" card owns the slot.
ActivePlanOverview _notStartedPlan() {
  final now = DateTime.now();
  final start = DateTime(now.year, now.month, now.day + 10);
  final workout = PlanWorkoutRow(
    id: 'wo-1',
    weekId: 'wk-1',
    scheduledDate: start,
    kind: 'easy',
    targetDistanceM: 5000,
    manuallyCompleted: false,
  );
  return ActivePlanOverview(
    plan: TrainingPlanRow(
      id: 'plan-1',
      userId: 'u1',
      name: 'Autumn 10k',
      goalEvent: '10k',
      goalDistanceM: 10000,
      startDate: start,
      endDate: start.add(const Duration(days: 56)),
      daysPerWeek: 4,
      status: 'active',
      source: 'app',
      isTemplate: false,
      isPublicTemplate: false,
    ),
    weeks: [
      PlanWeekRow(id: 'wk-1', planId: 'plan-1', weekIndex: 0, phase: 'base'),
    ],
    workouts: [workout],
    todayWorkout: null,
    completionPct: 0,
    currentWeekIndex: 0,
  );
}

final DateTime _tenDaysAgo =
    DateTime.now().toUtc().subtract(const Duration(days: 10));

Run _run(String id, DateTime startedAt, {int? fastest5kS}) => Run(
      id: id,
      startedAt: startedAt,
      duration: const Duration(minutes: 45),
      distanceMetres: 8000,
      source: RunSource.app,
      metadata: {
        if (fastest5kS != null) MetadataKeys.fastest5kS: fastest5kS,
      },
    );

/// Seeds [runs] to disk and mounts Home inside `runAsync`, then waits for the
/// plan reads to settle: store I/O runs on the real event loop, so the wait is
/// a [pumpUntil], never a delay.
Future<void> _mount(
  WidgetTester tester, {
  required List<Run> runs,
  required TrainingService training,
  SettingsSyncService? Function(Preferences prefs)? sync,
  required bool Function() ready,
  required String describe,
}) async {
  tester.view.physicalSize = const Size(400, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  late Directory dir;
  await tester.runAsync(() async {
    await initializeDateFormatting();
    SharedPreferences.setMockInitialValues({});
    final prefs = Preferences();
    await prefs.init();
    dir = Directory.systemTemp.createTempSync('dashboard_plan_discovery_');
    final seed = LocalRunStore();
    await seed.init(overrideDirectory: dir);
    for (final r in runs) {
      await seed.save(r);
    }
    final runStore = LocalRunStore();
    await runStore.init(overrideDirectory: dir);
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: DashboardScreen(
        apiClient: _Api(),
        runStore: runStore,
        routeStore: LocalRouteStore(),
        gymStore: LocalGymStore(),
        foodStore: LocalFoodStore(),
        preferences: prefs,
        training: training,
        settingsSync: sync?.call(prefs),
      ),
    ));
  });
  addTearDown(() => dir.deleteSync(recursive: true));
  await pumpUntil(tester, ready, describe: describe);
}

final _suggestion = find.byKey(const Key('dashboardRecent5k'));
final _trainFor = find.byKey(const Key('dashboardTrainForSomething'));
final _welcomeTrainFor =
    find.byKey(const Key('dashboardWelcomeTrainForSomething'));
final _nextRace = find.byKey(const Key('dashboardNextRace'));

void main() {
  group('the recent-5K suggestion', () {
    testWidgets('names the measured 5K and its day in place of the plain entry',
        (tester) async {
      await _mount(
        tester,
        runs: [_run('r1', _tenDaysAgo, fastest5kS: 1450)],
        training: _Training(),
        sync: (p) => _Sync(p, _Service({})),
        ready: () => _suggestion.evaluate().isNotEmpty,
        describe: 'the recent-5K suggestion',
      );
      final date = formatDateShort(_tenDaysAgo, 'en');
      expect(
        tester
            .widget<Text>(find.byKey(const Key('dashboardRecent5kTitle')))
            .data,
        'Your 5K of 24:10 on $date',
      );
      expect(_trainFor, findsNothing);
    });

    testWidgets('building from it opens the wizard with the time filled in',
        (tester) async {
      await _mount(
        tester,
        runs: [_run('r1', _tenDaysAgo, fastest5kS: 1450)],
        training: _Training(),
        sync: (p) => _Sync(p, _Service({})),
        ready: () => _suggestion.evaluate().isNotEmpty,
        describe: 'the recent-5K suggestion',
      );
      await tester.tap(find.byKey(const Key('dashboardRecent5kBuild')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      final wizard = tester.widget<PlanNewScreen>(find.byType(PlanNewScreen));
      expect(wizard.initialRecent5kSec, 1450);
    });

    testWidgets('"Not now" hides it, stores the stamp and leaves the entry',
        (tester) async {
      late _Sync sync;
      await _mount(
        tester,
        runs: [_run('r1', _tenDaysAgo, fastest5kS: 1450)],
        training: _Training(),
        sync: (p) => sync = _Sync(p, _Service({})),
        ready: () => _suggestion.evaluate().isNotEmpty,
        describe: 'the recent-5K suggestion',
      );
      await tester.tap(find.byKey(const Key('dashboardRecent5kDismiss')));
      await tester.pump();
      expect(_suggestion, findsNothing);
      expect(_trainFor, findsOneWidget);
      expect(sync.writes, hasLength(1));
      final stamp = sync.writes.single[SettingsKeys.planSuggestionDismissedAt];
      expect(stamp, isA<String>());
      expect(
        DateTime.parse(stamp as String).difference(DateTime.now()).abs(),
        lessThan(const Duration(minutes: 1)),
      );
    });

    testWidgets('a refused dismissal says the suggestion may come back',
        (tester) async {
      await _mount(
        tester,
        runs: [_run('r1', _tenDaysAgo, fastest5kS: 1450)],
        training: _Training(),
        sync: (p) => _Sync(p, _Service({}), writeFails: true),
        ready: () => _suggestion.evaluate().isNotEmpty,
        describe: 'the recent-5K suggestion',
      );
      await tester.tap(find.byKey(const Key('dashboardRecent5kDismiss')));
      await tester.pump();
      expect(
        find.text("Couldn't save that, so the suggestion may come back."),
        findsOneWidget,
      );
      expect(_suggestion, findsNothing);
      await tester.pump(kTopBannerMaxDuration);
    });

    testWidgets('a stored dismissal holds until a newer 5K', (tester) async {
      final stamp = DateTime.now()
          .toUtc()
          .subtract(const Duration(days: 5))
          .toIso8601String();
      await _mount(
        tester,
        runs: [_run('r1', _tenDaysAgo, fastest5kS: 1450)],
        training: _Training(),
        sync: (p) => _Sync(
            p, _Service({SettingsKeys.planSuggestionDismissedAt: stamp})),
        ready: () => _trainFor.evaluate().isNotEmpty,
        describe: 'the plain plan entry',
      );
      expect(_suggestion, findsNothing);
    });

    testWidgets('a 5K run since the dismissal is offered', (tester) async {
      final stamp = DateTime.now()
          .toUtc()
          .subtract(const Duration(days: 5))
          .toIso8601String();
      final twoDaysAgo =
          DateTime.now().toUtc().subtract(const Duration(days: 2));
      await _mount(
        tester,
        runs: [
          _run('r1', _tenDaysAgo, fastest5kS: 1450),
          _run('r2', twoDaysAgo, fastest5kS: 1500),
        ],
        training: _Training(),
        sync: (p) => _Sync(
            p, _Service({SettingsKeys.planSuggestionDismissedAt: stamp})),
        ready: () => _suggestion.evaluate().isNotEmpty,
        describe: 'the recent-5K suggestion',
      );
      expect(
        tester
            .widget<Text>(find.byKey(const Key('dashboardRecent5kTitle')))
            .data,
        startsWith('Your 5K of 25:00 on '),
      );
    });

    testWidgets('with the settings bag unread, only the plain entry shows',
        (tester) async {
      await _mount(
        tester,
        runs: [_run('r1', _tenDaysAgo, fastest5kS: 1450)],
        training: _Training(),
        sync: (p) => _Sync(p, null),
        ready: () => _trainFor.evaluate().isNotEmpty,
        describe: 'the plain plan entry',
      );
      expect(_suggestion, findsNothing);
    });
  });

  group('the plain plan entry', () {
    testWidgets('a runner with runs and no 5K is offered "Train for something"',
        (tester) async {
      await _mount(
        tester,
        runs: [_run('r1', _tenDaysAgo)],
        training: _Training(),
        sync: (p) => _Sync(p, _Service({})),
        ready: () => _trainFor.evaluate().isNotEmpty,
        describe: 'the plain plan entry',
      );
      await tester.tap(_trainFor);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      final wizard = tester.widget<PlanNewScreen>(find.byType(PlanNewScreen));
      expect(wizard.initialRecent5kSec, isNull);
    });

    testWidgets('a plan that has not started keeps its card and no entry',
        (tester) async {
      await _mount(
        tester,
        runs: [_run('r1', _tenDaysAgo, fastest5kS: 1450)],
        training: _Training(overview: _notStartedPlan()),
        sync: (p) => _Sync(p, _Service({})),
        ready: () => _nextRace.evaluate().isNotEmpty,
        describe: 'the starts-in card',
      );
      expect(_suggestion, findsNothing);
      expect(_trainFor, findsNothing);
    });

    testWidgets('a failed plan read offers no entry', (tester) async {
      await _mount(
        tester,
        runs: [_run('r1', _tenDaysAgo, fastest5kS: 1450)],
        training: _Training(fails: true),
        sync: (p) => _Sync(p, _Service({})),
        ready: () =>
            find.byKey(const Key('dashboardWeekLead')).evaluate().isNotEmpty,
        describe: 'the week lead',
      );
      await tester.pump();
      expect(_suggestion, findsNothing);
      expect(_trainFor, findsNothing);
    });
  });

  group('the runless welcome', () {
    testWidgets('carries "Train for something" into the plan wizard',
        (tester) async {
      await _mount(
        tester,
        runs: const [],
        training: _Training(),
        ready: () => _welcomeTrainFor.evaluate().isNotEmpty,
        describe: 'the welcome plan entry',
      );
      await tester.tap(_welcomeTrainFor);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(PlanNewScreen), findsOneWidget);
    });

    testWidgets('leaves it out under a plan that has not started',
        (tester) async {
      await _mount(
        tester,
        runs: const [],
        training: _Training(overview: _notStartedPlan()),
        ready: () => _nextRace.evaluate().isNotEmpty,
        describe: 'the starts-in card',
      );
      expect(_welcomeTrainFor, findsNothing);
    });
  });
}
