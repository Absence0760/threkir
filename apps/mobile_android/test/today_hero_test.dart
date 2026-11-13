// The adaptive Today hero that leads Home (#1187, decisions § 2385): which
// state it shows comes from the `dashboard_layout` parity pair, and whichever
// it is, it is the first card under the toolbar, above Today's progress
// summary, at the default text size and at 2.0x. Plus hiding a trend group by
// long-pressing its heading on the Progress page (decisions § 2386, issue
// #1374). Web twin:
// `apps/web/tests-e2e/dashboard/today-hero.spec.ts`.

import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/dashboard_layout.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/local_food_store.dart';
import '../lib/local_gym_store.dart';
import '../lib/local_route_store.dart';
import '../lib/local_run_store.dart';
import '../lib/preferences.dart';
import '../lib/screens/today_screen.dart';
import '../lib/screens/progress_screen.dart';
import '../lib/settings_sync.dart';
import '../lib/training_service.dart';
import 'pump_until.dart';

class _FakeTraining extends TrainingService {
  final ActivePlanOverview? overview;
  _FakeTraining(this.overview);
  @override
  Future<ActivePlanOverview?> fetchActiveOverview() async => overview;
}

class _Service extends SettingsService {
  _Service(this.values) : super(deviceId: 'test-device', platform: 'android');
  final Map<String, dynamic> values;

  @override
  T? effective<T>(String key, {T? fallback}) =>
      values.containsKey(key) ? values[key] as T? : fallback;
}

class _Sync extends SettingsSyncService {
  _Sync(Preferences prefs, this._service) : super(preferences: prefs);
  final _Service _service;
  final List<Map<String, dynamic>> writes = [];

  @override
  bool get synced => true;

  @override
  SettingsService? get service => _service;

  @override
  Future<void> updateUniversal(Map<String, dynamic> changes) async {
    writes.add(changes);
  }
}

DateTime get _today {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

ActivePlanOverview _overview({PlanWorkoutRow? today, DateTime? endDate}) {
  final workouts = [?today];
  return ActivePlanOverview(
    plan: TrainingPlanRow(
      id: 'plan-1',
      userId: 'u1',
      name: 'Spring 10k',
      goalEvent: '10k',
      goalDistanceM: 10000,
      startDate: _today.subtract(const Duration(days: 28)),
      endDate: endDate ?? _today.add(const Duration(days: 56)),
      daysPerWeek: 4,
      status: 'active',
      source: 'app',
      isTemplate: false,
      isPublicTemplate: false,
    ),
    weeks: [
      PlanWeekRow(id: 'wk-1', planId: 'plan-1', weekIndex: 4, phase: 'build'),
    ],
    workouts: workouts,
    todayWorkout: today,
    completionPct: 40,
    currentWeekIndex: 4,
  );
}

PlanWorkoutRow _workout(String kind) => PlanWorkoutRow(
      id: 'wo-today',
      weekId: 'wk-1',
      scheduledDate: _today,
      kind: kind,
      targetDistanceM: 6000,
      manuallyCompleted: false,
    );

Run _run(String id, DateTime startedAt) => Run(
      id: id,
      startedAt: startedAt,
      duration: const Duration(minutes: 30),
      distanceMetres: 5000,
      source: RunSource.app,
    );

/// A run two and four days ago: history, a training load to score readiness
/// from, and nothing started today.
List<Run> get _pastRuns => [
      _run('r-2', _today.subtract(const Duration(days: 2, hours: -9))),
      _run('r-4', _today.subtract(const Duration(days: 4, hours: -9))),
    ];

final _hero = find.byKey(const Key('dashboardTodayHero'));
final _summary = find.byKey(const Key('todayProgressSummary'));

Future<_Sync> _mount(
  WidgetTester tester, {
  required List<Run> runs,
  TrainingService? training,
  Map<String, dynamic> bag = const {},
  double textScale = 1.0,
  bool progress = false,
  required bool Function() ready,
}) async {
  tester.view.physicalSize = const Size(400, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  late _Sync sync;
  late Directory dir;
  await tester.runAsync(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = Preferences();
    await prefs.init();
    sync = _Sync(prefs, _Service(Map.of(bag)));
    dir = Directory.systemTemp.createTempSync('dashboard_today_hero_');
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
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: progress
          ? ProgressScreen(
              runStore: runStore,
              routeStore: LocalRouteStore(),
              gymStore: LocalGymStore(),
              preferences: prefs,
              training: training,
              settingsSync: sync,
            )
          : DashboardScreen(
              runStore: runStore,
              routeStore: LocalRouteStore(),
              gymStore: LocalGymStore(),
              foodStore: LocalFoodStore(),
              preferences: prefs,
              training: training,
              settingsSync: sync,
              onStartRun: () {},
              onStartWorkout: (_) {},
            ),
    ));
  });
  addTearDown(() => dir.deleteSync(recursive: true));
  await pumpUntil(tester, ready, describe: 'the dashboard to mount its hero');
  await tester.pump();
  return sync;
}

TodayHeroState _state(WidgetTester tester) =>
    tester.widget<DashboardTodayHero>(_hero).state;

double _top(WidgetTester tester, Finder f) => tester.getTopLeft(f).dy;

/// The hero is the first card: above the progress summary, and nothing
/// card-shaped sits between the toolbar and it.
void _expectHeroFirst(WidgetTester tester) {
  final heroTop = _top(tester, _hero);
  expect(heroTop, lessThan(_top(tester, _summary)),
      reason: 'the Today hero sits above the progress summary');
  for (final card in tester.widgetList<Card>(find.byType(Card))) {
    final f = find.byWidget(card);
    if (find.ancestor(of: f, matching: _hero).evaluate().isNotEmpty) continue;
    expect(_top(tester, f), greaterThanOrEqualTo(heroTop),
        reason: 'no card outside the hero may sit above it');
  }
}

Finder _inHero(Finder f) => find.descendant(of: _hero, matching: f);

void main() {
  for (final scale in [1.0, 2.0]) {
    group('at ${scale}x text', () {
      testWidgets('a plan workout today leads, with its Start and readiness',
          (tester) async {
        await _mount(
          tester,
          runs: _pastRuns,
          textScale: scale,
          training: _FakeTraining(_overview(today: _workout('easy'))),
          ready: () =>
              _hero.evaluate().isNotEmpty &&
              _state(tester) == TodayHeroState.planToday,
        );
        expect(_inHero(find.byKey(const Key('todaysWorkoutStart'))),
            findsOneWidget);
        expect(_inHero(find.byKey(const Key('dashboardHeroReadiness'))),
            findsOneWidget);
        _expectHeroFirst(tester);
        expect(tester.takeException(), isNull);
      });

      testWidgets('a run started today leads when there is no plan',
          (tester) async {
        await _mount(
          tester,
          runs: [..._pastRuns, _run('r-0', DateTime.now())],
          textScale: scale,
          ready: () => _hero.evaluate().isNotEmpty,
        );
        expect(_state(tester), TodayHeroState.ranToday);
        expect(_inHero(find.byKey(const Key('dashboardLatestRun'))),
            findsOneWidget);
        expect(_inHero(find.byKey(const Key('dashboardHeroStart'))),
            findsOneWidget);
        _expectHeroFirst(tester);
        expect(tester.takeException(), isNull);
      });

      testWidgets('a plan day with nothing scheduled is a rest day',
          (tester) async {
        await _mount(
          tester,
          runs: _pastRuns,
          textScale: scale,
          training: _FakeTraining(_overview()),
          ready: () =>
              _hero.evaluate().isNotEmpty &&
              _state(tester) == TodayHeroState.restDay,
        );
        expect(_inHero(find.byKey(const Key('dashboardHeroRestDay'))),
            findsOneWidget);
        expect(_inHero(find.byKey(const Key('dashboardHeroRestGrisnir'))),
            findsOneWidget);
        _expectHeroFirst(tester);
        expect(tester.takeException(), isNull);
      });

      testWidgets('with no plan and no run today, readiness and Start lead',
          (tester) async {
        await _mount(
          tester,
          runs: _pastRuns,
          textScale: scale,
          ready: () => _hero.evaluate().isNotEmpty,
        );
        expect(_state(tester), TodayHeroState.noPlan);
        expect(_inHero(find.text('Nothing planned today')), findsOneWidget);
        expect(_inHero(find.byKey(const Key('dashboardHeroReadinessCard'))),
            findsOneWidget);
        expect(_inHero(find.byKey(const Key('dashboardHeroStart'))),
            findsOneWidget);
        _expectHeroFirst(tester);
        expect(tester.takeException(), isNull);
      });

      testWidgets('a new account opens on the welcome block, with no hero',
          (tester) async {
        await _mount(
          tester,
          runs: const [],
          textScale: scale,
          ready: () => find.text('Welcome!').evaluate().isNotEmpty,
        );
        expect(_hero, findsNothing);
        expect(_summary, findsNothing);
        expect(tester.takeException(), isNull);
      });
    });
  }

  // Grisnir rests on a scheduled rest workout too, never on a run day, and
  // the runner's `show_mascot` off leaves him out (#1360).
  testWidgets('a scheduled rest workout shows Grisnir resting',
      (tester) async {
    await _mount(
      tester,
      runs: _pastRuns,
      training: _FakeTraining(_overview(today: _workout('rest'))),
      ready: () =>
          _hero.evaluate().isNotEmpty &&
          _state(tester) == TodayHeroState.restDay,
    );
    expect(_inHero(find.byKey(const Key('dashboardHeroRestGrisnir'))),
        findsOneWidget);
    expect(find.text("Back by morning, like Thor's goats."), findsOneWidget);
  });

  testWidgets('a run day has no Grisnir', (tester) async {
    await _mount(
      tester,
      runs: _pastRuns,
      training: _FakeTraining(_overview(today: _workout('easy'))),
      ready: () =>
          _hero.evaluate().isNotEmpty &&
          _state(tester) == TodayHeroState.planToday,
    );
    expect(find.byKey(const Key('dashboardHeroRestGrisnir')), findsNothing);
  });

  testWidgets('show_mascot off keeps him off the rest day', (tester) async {
    await _mount(
      tester,
      runs: _pastRuns,
      bag: const {'show_mascot': false},
      training: _FakeTraining(_overview()),
      ready: () =>
          _hero.evaluate().isNotEmpty &&
          _state(tester) == TodayHeroState.restDay,
    );
    expect(_inHero(find.byKey(const Key('dashboardHeroRestDay'))),
        findsOneWidget);
    expect(find.byKey(const Key('dashboardHeroRestGrisnir')), findsNothing);
  });

  testWidgets('race day puts the race first in the hero', (tester) async {
    await _mount(
      tester,
      runs: _pastRuns,
      training: _FakeTraining(_overview(endDate: _today)),
      ready: () =>
          _hero.evaluate().isNotEmpty &&
          _state(tester) == TodayHeroState.raceDay,
    );
    expect(_inHero(find.byKey(const Key('dashboardNextRace'))), findsOneWidget);
    _expectHeroFirst(tester);
  });

  testWidgets('readiness is in the hero, not in Progress\'s trend groups, '
      'and the load views are one card', (tester) async {
    await _mount(
      progress: true,
      tester,
      runs: _pastRuns,
      ready: () => find
          .byKey(const ValueKey('dashboard-trend-fitness'))
          .evaluate()
          .isNotEmpty,
    );
    final fitness = find.byKey(const ValueKey('dashboard-trend-fitness'));
    expect(
        find.descendant(
            of: fitness,
            matching: find.byKey(const Key('dashboardTrainingLoadCard'))),
        findsOneWidget);
    expect(
        find.descendant(of: fitness, matching: find.text('Readiness')),
        findsNothing);
  });

  testWidgets('long-pressing a trend heading hides that group, universally',
      (tester) async {
    final sync = await _mount(
      progress: true,
      tester,
      runs: _pastRuns,
      ready: () => find
          .byKey(const ValueKey('dashboard-trend-volume'))
          .evaluate()
          .isNotEmpty,
    );
    await tester.longPress(find.text('Volume'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('disclosureSectionHide')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byKey(const ValueKey('dashboard-trend-volume')), findsNothing);
    expect(find.byKey(const ValueKey('dashboard-trend-fitness')),
        findsOneWidget,
        reason: 'a hide is per group');
    expect(sync.writes.last, {
      kDashboardHiddenCardsKey: ['volume'],
    });
    // Let the banner's timer run out.
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('a group hidden in the settings bag is not built',
      (tester) async {
    await _mount(
      progress: true,
      tester,
      runs: _pastRuns,
      bag: {
        kDashboardHiddenCardsKey: ['fitness', 'not-a-group'],
      },
      ready: () => find
          .byKey(const ValueKey('dashboard-trend-volume'))
          .evaluate()
          .isNotEmpty,
    );
    expect(find.byKey(const ValueKey('dashboard-trend-fitness')), findsNothing);
    expect(find.byKey(const ValueKey('dashboard-trend-volume')), findsOneWidget);
  });
}
