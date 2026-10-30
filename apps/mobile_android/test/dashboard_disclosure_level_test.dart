// Progressive disclosure on Home (#905, #1187): at `simple` the fitness card
// and the training-load chart fold into one named "Training load" expander
// inside the Fitness and form group, remembered per account in the universal
// `dashboard_training_load_expanded` key; at `standard` / `full` the group is
// unchanged. Nothing is removed at any level. Web twin:
// `apps/web/tests-e2e/dashboard/disclosure.spec.ts`.

import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ui_kit/ui_kit.dart';

import '../lib/disclosure.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/local_food_store.dart';
import '../lib/local_gym_store.dart';
import '../lib/local_route_store.dart';
import '../lib/local_run_store.dart';
import '../lib/preferences.dart';
import '../lib/screens/dashboard_screen.dart';
import '../lib/settings_sync.dart';
import '../lib/widgets/training_load_chart.dart';
import 'pump_until.dart';

Run _run(String id, DateTime startedAt) => Run(
      id: id,
      startedAt: startedAt,
      duration: const Duration(minutes: 25),
      distanceMetres: 5000,
      source: RunSource.app,
    );

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
  final _Service _service;
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

  /// A change landing in the bag from elsewhere — Settings, another device.
  void put(String key, Object? value) {
    if (value == null) {
      _service.values.remove(key);
    } else {
      _service.values[key] = value;
    }
    notifyListeners();
  }
}

class _Harness {
  final Directory dir;
  final Preferences prefs;
  final LocalRunStore runStore;
  _Harness(this.dir, this.prefs, this.runStore);
}

Future<_Harness> _seed(WidgetTester tester, {required int runs}) async {
  late _Harness h;
  await tester.runAsync(() async {
    final prefs = Preferences();
    await prefs.init();
    final dir = Directory.systemTemp.createTempSync('dashboard_disclosure_');
    final now = DateTime.now().toUtc();
    final seed = LocalRunStore();
    await seed.init(overrideDirectory: dir);
    for (var i = 0; i < runs; i++) {
      await seed.save(_run('r$i', now.subtract(Duration(days: i))));
    }
    final runStore = LocalRunStore();
    await runStore.init(overrideDirectory: dir);
    h = _Harness(dir, prefs, runStore);
  });
  return h;
}

Future<_Sync> _pump(
  WidgetTester tester,
  _Harness h,
  Map<String, dynamic> bag, {
  bool writeFails = false,
  Key? key,
}) async {
  final sync = _Sync(h.prefs, _Service(Map.of(bag)), writeFails: writeFails);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: DashboardScreen(
      key: key,
      runStore: h.runStore,
      routeStore: LocalRouteStore(),
      gymStore: LocalGymStore(),
      foodStore: LocalFoodStore(),
      preferences: h.prefs,
      settingsSync: sync,
    ),
  ));
  await pumpUntil(
    tester,
    () => find
        .byKey(const ValueKey('dashboard-trend-fitness'))
        .evaluate()
        .isNotEmpty,
    describe: 'the dashboard to mount its Fitness and form group',
  );
  return sync;
}

final _expander = find.byKey(const Key('dashboardTrainingLoadDisclosure'));
Finder get _expanderHeading =>
    find.descendant(of: _expander, matching: find.text('Training load'));

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  void tall(WidgetTester tester) {
    tester.view.physicalSize = const Size(400, 8000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  testWidgets('at simple the training-load block folds into a closed expander',
      (tester) async {
    tall(tester);
    final h = await _seed(tester, runs: 40);
    addTearDown(() => h.dir.deleteSync(recursive: true));
    await _pump(tester, h, {disclosureLevelKey: 'simple'});

    expect(_expander, findsOneWidget);
    expect(_expanderHeading, findsOneWidget);
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('dashboard-trend-fitness')),
            matching: _expander),
        findsOneWidget,
        reason: 'the fold lives inside the Fitness and form group, as on web');
    expect(find.byType(TrainingLoadChart), findsNothing,
        reason: 'closed by default: the collapsed state is what simple asked for');
    expect(find.byType(TrainingLoadChart, skipOffstage: false), findsOneWidget,
        reason: 'folded, never dropped');
  });

  for (final level in ['standard', 'full']) {
    testWidgets('at $level the group is unchanged and nothing folds',
        (tester) async {
      tall(tester);
      final h = await _seed(tester, runs: 5);
      addTearDown(() => h.dir.deleteSync(recursive: true));
      await _pump(tester, h, {disclosureLevelKey: level});

      expect(_expander, findsNothing);
      expect(find.byType(TrainingLoadChart), findsOneWidget);
    });
  }

  testWidgets('opening the expander shows the block and remembers it',
      (tester) async {
    tall(tester);
    final h = await _seed(tester, runs: 40);
    addTearDown(() => h.dir.deleteSync(recursive: true));
    final sync = await _pump(tester, h, {disclosureLevelKey: 'simple'});

    await tester.tap(_expanderHeading);
    await tester.pump();
    expect(find.byType(TrainingLoadChart), findsOneWidget);
    expect(sync.writes, [
      {SettingsKeys.dashboardTrainingLoadExpanded: true},
    ]);

    await tester.tap(_expanderHeading);
    await tester.pump();
    expect(find.byType(TrainingLoadChart), findsNothing);
    expect(sync.writes.last, {SettingsKeys.dashboardTrainingLoadExpanded: false});
  });

  testWidgets('a remembered open expander opens on the next visit',
      (tester) async {
    tall(tester);
    final h = await _seed(tester, runs: 40);
    addTearDown(() => h.dir.deleteSync(recursive: true));
    await _pump(tester, h, {
      disclosureLevelKey: 'simple',
      SettingsKeys.dashboardTrainingLoadExpanded: true,
    });

    expect(_expander, findsOneWidget);
    expect(find.byType(TrainingLoadChart), findsOneWidget);
  });

  testWidgets('a non-bool remembered value reads as closed', (tester) async {
    tall(tester);
    final h = await _seed(tester, runs: 40);
    addTearDown(() => h.dir.deleteSync(recursive: true));
    await _pump(tester, h, {
      disclosureLevelKey: 'simple',
      SettingsKeys.dashboardTrainingLoadExpanded: 'yes',
    });

    expect(_expander, findsOneWidget);
    expect(find.byType(TrainingLoadChart), findsNothing);
  });

  testWidgets('a refused write keeps the section the way the reader put it',
      (tester) async {
    tall(tester);
    final h = await _seed(tester, runs: 40);
    addTearDown(() => h.dir.deleteSync(recursive: true));
    final sync = await _pump(tester, h, {disclosureLevelKey: 'simple'},
        writeFails: true);

    await tester.tap(_expanderHeading);
    await tester.pump();
    expect(sync.writes, hasLength(1));
    expect(find.byType(TrainingLoadChart), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('with no stored level the derivation decides', () {
    testWidgets('a new account with no goal folds', (tester) async {
      tall(tester);
      final h = await _seed(tester, runs: disclosureStandardRuns - 1);
      addTearDown(() => h.dir.deleteSync(recursive: true));
      await _pump(tester, h, const {});
      expect(_expander, findsOneWidget);
    });

    testWidgets('the history floor reaches standard at ten runs',
        (tester) async {
      tall(tester);
      final h = await _seed(tester, runs: disclosureStandardRuns);
      addTearDown(() => h.dir.deleteSync(recursive: true));
      await _pump(tester, h, const {});
      expect(_expander, findsNothing);
      expect(find.byType(TrainingLoadChart), findsOneWidget);
    });

    testWidgets('a marathon goal opens everything from the first run',
        (tester) async {
      tall(tester);
      final h = await _seed(tester, runs: 1);
      addTearDown(() => h.dir.deleteSync(recursive: true));
      await _pump(tester, h, {SettingsKeys.primaryGoal: 'marathon'});
      expect(_expander, findsNothing);
    });

    testWidgets('an unrecognised stored level falls through to it',
        (tester) async {
      tall(tester);
      final h = await _seed(tester, runs: 1);
      addTearDown(() => h.dir.deleteSync(recursive: true));
      await _pump(tester, h, {disclosureLevelKey: 'everything'});
      expect(_expander, findsOneWidget);
    });
  });

  testWidgets('a level changed in Settings reaches Home without a remount',
      (tester) async {
    tall(tester);
    final h = await _seed(tester, runs: 40);
    addTearDown(() => h.dir.deleteSync(recursive: true));
    final sync = await _pump(tester, h, {disclosureLevelKey: 'simple'});
    expect(_expander, findsOneWidget);

    sync.put(disclosureLevelKey, 'full');
    await tester.pump();
    expect(_expander, findsNothing);
    expect(find.byType(TrainingLoadChart), findsOneWidget);

    // Automatic deletes the key; 40 runs derive standard.
    sync.put(disclosureLevelKey, null);
    await tester.pump();
    expect(_expander, findsNothing);
  });
}
