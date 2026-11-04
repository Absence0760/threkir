import 'dart:io';

import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/local_food_store.dart';
import '../lib/local_gym_store.dart';
import '../lib/local_route_store.dart';
import '../lib/local_run_store.dart';
import '../lib/preferences.dart';
import '../lib/screens/dashboard_screen.dart';
import '../lib/widgets/gym_summary_card.dart';
import '../lib/widgets/nutrition_rings_card.dart';
import 'pump_until.dart';

/// multi_modal.md § Home rule 2: what was logged today leads the Today block,
/// most recently started first, and the last run from an earlier day follows
/// it (issue #1187).

final _latestRun = find.byKey(const Key('dashboardLatestRun'));
final _gym = find.byType(GymSummaryCard);
final _nutrition = find.byType(NutritionRingsCard);

typedef _Stores = ({
  LocalRunStore runStore,
  LocalGymStore gymStore,
  LocalFoodStore foodStore,
  Preferences prefs,
});

DateTime get _dayStart {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

Future<_Stores> _seed(
  WidgetTester tester, {
  required DateTime runAt,
  DateTime? liftAt,
  DateTime? foodAt,
}) async {
  late _Stores out;
  await tester.runAsync(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = Preferences();
    await prefs.init();
    final runsDir = Directory.systemTemp.createTempSync('today_order_runs_');
    final gymDir = Directory.systemTemp.createTempSync('today_order_gym_');
    final foodDir = Directory.systemTemp.createTempSync('today_order_food_');
    addTearDown(() {
      for (final d in [runsDir, gymDir, foodDir]) {
        if (d.existsSync()) d.deleteSync(recursive: true);
      }
    });
    final seed = LocalRunStore();
    await seed.init(overrideDirectory: runsDir);
    await seed.save(Run(
      id: 'r1',
      startedAt: runAt,
      duration: const Duration(minutes: 30),
      distanceMetres: 5000,
      source: RunSource.app,
    ));
    final runStore = LocalRunStore();
    await runStore.init(overrideDirectory: runsDir);
    final gymStore = LocalGymStore();
    await gymStore.init(overrideDirectory: gymDir);
    if (liftAt != null) {
      await gymStore.createLocal(
        title: 'Push day',
        startedAt: liftAt,
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
      );
    }
    final foodStore = LocalFoodStore();
    await foodStore.init(overrideDirectory: foodDir);
    if (foodAt != null) {
      await foodStore.createLocal(
          startedAt: foodAt, itemName: 'Oats', calories: 350);
    }
    out = (
      runStore: runStore,
      gymStore: gymStore,
      foodStore: foodStore,
      prefs: prefs,
    );
  });
  return out;
}

Future<void> _pumpHome(WidgetTester tester, _Stores s,
    {required Finder until}) async {
  await tester.pumpWidget(MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: DashboardScreen(
      apiClient: null,
      training: null,
      runStore: s.runStore,
      routeStore: LocalRouteStore(),
      gymStore: s.gymStore,
      foodStore: s.foodStore,
      preferences: s.prefs,
      settingsSync: null,
    ),
  ));
  await pumpUntil(
    tester,
    () => _latestRun.evaluate().isNotEmpty && until.evaluate().isNotEmpty,
    describe: 'the last run and today\'s logged cards to render',
  );
}

double _top(WidgetTester tester, Finder f) => tester.getTopLeft(f).dy;

void main() {
  group('Home Today block order (phone)', () {
    testWidgets('a lift logged today leads a last run from an earlier day',
        (tester) async {
      final s = await _seed(
        tester,
        runAt: _dayStart.subtract(const Duration(days: 2, hours: -8)),
        liftAt: _dayStart.add(const Duration(minutes: 1)),
      );
      await _pumpHome(tester, s, until: _gym);
      expect(_top(tester, _gym), lessThan(_top(tester, _latestRun)));
    });

    testWidgets('meals logged today lead a last run from an earlier day',
        (tester) async {
      final s = await _seed(
        tester,
        runAt: _dayStart.subtract(const Duration(days: 1, hours: -8)),
        foodAt: _dayStart.add(const Duration(minutes: 1)),
      );
      await _pumpHome(tester, s, until: _nutrition);
      expect(_top(tester, _nutrition), lessThan(_top(tester, _latestRun)));
    });

    testWidgets('a run started after today\'s lift leads it', (tester) async {
      final s = await _seed(
        tester,
        liftAt: _dayStart.add(const Duration(minutes: 1)),
        runAt: _dayStart.add(const Duration(minutes: 2)),
      );
      await _pumpHome(tester, s, until: _gym);
      expect(_top(tester, _latestRun), lessThan(_top(tester, _gym)));
    });

    testWidgets('a lift started after today\'s run leads it', (tester) async {
      final s = await _seed(
        tester,
        runAt: _dayStart.add(const Duration(minutes: 1)),
        liftAt: _dayStart.add(const Duration(minutes: 2)),
      );
      await _pumpHome(tester, s, until: _gym);
      expect(_top(tester, _gym), lessThan(_top(tester, _latestRun)));
    });

    testWidgets('the newest of the lift and the meals decides the pair\'s '
        'place against today\'s run', (tester) async {
      final s = await _seed(
        tester,
        liftAt: _dayStart.add(const Duration(minutes: 1)),
        runAt: _dayStart.add(const Duration(minutes: 2)),
        foodAt: _dayStart.add(const Duration(minutes: 3)),
      );
      await _pumpHome(tester, s, until: _nutrition);
      expect(_top(tester, _nutrition), lessThan(_top(tester, _latestRun)));
      expect(_top(tester, _gym), lessThan(_top(tester, _latestRun)));
    });

    testWidgets('the whole Today block stays above the Trends divider',
        (tester) async {
      final s = await _seed(
        tester,
        runAt: _dayStart.subtract(const Duration(days: 3, hours: -8)),
        liftAt: _dayStart.add(const Duration(minutes: 1)),
      );
      await _pumpHome(tester, s, until: _gym);
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      final divider = find.text(l10n.dashboardTrendsDivider);
      await tester.dragUntilVisible(
          divider, find.byType(Scrollable).first, const Offset(0, -200));
      expect(_top(tester, _latestRun), lessThan(_top(tester, divider)));
    });
  });

  testWidgets('tablet lead column puts today\'s lift above an older last run',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final s = await _seed(
      tester,
      runAt: _dayStart.subtract(const Duration(days: 2, hours: -8)),
      liftAt: _dayStart.add(const Duration(minutes: 1)),
    );
    await _pumpHome(tester, s, until: _gym);
    expect(_top(tester, _gym), lessThan(_top(tester, _latestRun)));
  });
}
