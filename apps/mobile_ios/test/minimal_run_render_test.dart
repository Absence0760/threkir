import 'dart:convert';
import 'dart:io';

import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart' hide Route;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/goals.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/local_food_store.dart';
import '../lib/local_gym_store.dart';
import '../lib/local_route_store.dart';
import '../lib/local_run_store.dart';
import '../lib/preferences.dart';
import '../lib/screens/dashboard_screen.dart';
import '../lib/screens/run_detail_screen.dart';
import '../lib/screens/runs_screen.dart';
import '../lib/widgets/run_list_tile.dart';
import 'pump_until.dart';
import 'rendered_text_sweep.dart';
import 'store_write_watch.dart';

// The smallest accounts a runner can produce: a run stopped seconds after it
// started, a run that never moved, and tracks of one point or none. Every
// surface that derives a number from a run divides by its distance or its
// duration somewhere, and each of these makes one of those zero or nearly so.

const _metresPerDegreeLat = 111320.0;

Waypoint _wp(DateTime start, double northMetres, int second) => Waypoint(
      lat: -37.8136 + northMetres / _metresPerDegreeLat,
      lng: 144.9631,
      timestamp: start.add(Duration(seconds: second)),
    );

typedef _Fixture = ({
  String name,
  double metres,
  Duration duration,
  List<Waypoint> Function(DateTime start) track,
});

final List<_Fixture> _fixtures = [
  (
    name: '10 s / 3 m over a two-point track',
    metres: 3,
    duration: const Duration(seconds: 10),
    track: (s) => [_wp(s, 0, 0), _wp(s, 3, 10)],
  ),
  (
    name: '10 s / 3 m with a one-point track',
    metres: 3,
    duration: const Duration(seconds: 10),
    track: (s) => [_wp(s, 0, 0)],
  ),
  (
    name: '10 s / 3 m with no track',
    metres: 3,
    duration: const Duration(seconds: 10),
    track: (_) => const [],
  ),
  (
    name: '10 s / 0 m with a one-point track',
    metres: 0,
    duration: const Duration(seconds: 10),
    track: (s) => [_wp(s, 0, 0)],
  ),
  (
    name: '10 s / 0 m with no track',
    metres: 0,
    duration: const Duration(seconds: 10),
    track: (_) => const [],
  ),
  (
    name: '0 s / 0 m with no track',
    metres: 0,
    duration: Duration.zero,
    track: (_) => const [],
  ),
];

Run _runOf(_Fixture f,
    {String id = 'run-min', String activity = 'run', DateTime? start}) {
  final at = start ?? DateTime.now().subtract(const Duration(hours: 1));
  return Run(
    id: id,
    startedAt: at,
    duration: f.duration,
    distanceMetres: f.metres,
    source: RunSource.app,
    metadata: <String, dynamic>{'activity_type': activity},
    track: f.track(at),
  );
}

final _dirs = <Directory>[];

Directory _tmp(String tag) {
  final d = Directory.systemTemp.createTempSync('minimal_run_$tag');
  _dirs.add(d);
  return d;
}

Future<Preferences> _prefs(
    {bool miles = false, Map<String, Object>? extra}) async {
  SharedPreferences.setMockInitialValues({
    if (miles) 'use_miles': true,
    ...?extra,
  });
  final prefs = Preferences();
  await prefs.init();
  return prefs;
}

/// Tall enough that every lazily-built list child on these surfaces is laid
/// out, so the sweep reads the whole screen rather than its first viewport.
/// Narrow enough to keep the compact (phone) composition.
Future<void> _tallPhone(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(400, 9000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

Widget _app(Widget home) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: home,
    );

void main() {
  setUpAll(() async {
    dotenv.loadFromString(isOptional: true);
    await initializeDateFormatting();
  });

  tearDown(() {
    for (final d in _dirs) {
      if (d.existsSync()) d.deleteSync(recursive: true);
    }
    _dirs.clear();
  });

  group('the sweep itself', () {
    testWidgets('flags each degenerate number wherever the tree carries it',
        (tester) async {
      await tester.pumpWidget(_app(Scaffold(
        body: Column(children: [
          const Text('0.00 km'),
          const Text('NaN /km'),
          const Text('-0.00 km'),
          Semantics(label: 'Infinity km/h', child: const SizedBox()),
          const Tooltip(message: '−0:00', child: SizedBox()),
          const Text('Apr 15, 2026-04-15'),
          const Text('--:-- /km'),
          const Text('-0:30 /km'),
        ]),
      )));

      final flagged = [
        for (final s in renderedStrings(tester))
          if (degenerateNumber.hasMatch(s)) s,
      ];
      expect(flagged,
          unorderedEquals(['NaN /km', '-0.00 km', 'Infinity km/h', '−0:00']));
    });

    test('reads intl\'s own spellings of the degenerate values', () {
      // formatFixed hands NaN / infinity / a negative sub-unit value to intl,
      // which prints them as these rather than as Dart's toString would.
      for (final s in ['NaN', '∞', '-∞', '-0.0', '-0,00']) {
        expect(degenerateNumber.hasMatch(s), isTrue, reason: s);
      }
    });
  });

  group('run detail renders a minimal run', () {
    for (final f in _fixtures) {
      for (final miles in [false, true]) {
        testWidgets('${f.name} (${miles ? 'mi' : 'km'})', (tester) async {
          await _tallPhone(tester);
          final prefs = await _prefs(miles: miles);
          final runStore = LocalRunStore();
          await runStore.init(overrideDirectory: _tmp('detail_'));

          await tester.pumpWidget(_app(RunDetailScreen(
            run: _runOf(f),
            runStore: runStore,
            routeStore: LocalRouteStore(),
            preferences: prefs,
          )));
          // One pump cycle; pumpAndSettle would spin LiveRunMap's pulse.
          await tester.pump();
          await tester.pump(Duration.zero);

          expect(tester.takeException(), isNull);
          // Under 10 m there is no pace to state, so the cell says so.
          expect(find.text('--:--'), findsOneWidget);
          expectNoDegenerateNumbers(tester, surface: 'run detail, ${f.name}');
        });
      }
    }

    for (final f in [_fixtures[0], _fixtures[4], _fixtures[5]]) {
      testWidgets('${f.name}, recorded as a ride', (tester) async {
        await _tallPhone(tester);
        final prefs = await _prefs();
        final runStore = LocalRunStore();
        await runStore.init(overrideDirectory: _tmp('detail_ride_'));

        await tester.pumpWidget(_app(RunDetailScreen(
          run: _runOf(f, activity: 'cycle'),
          runStore: runStore,
          routeStore: LocalRouteStore(),
          preferences: prefs,
        )));
        await tester.pump();
        await tester.pump(Duration.zero);

        expect(tester.takeException(), isNull);
        // A speed-first activity reads the same missing value as "--" km/h.
        expect(find.text('--'), findsOneWidget);
        expectNoDegenerateNumbers(tester,
            surface: 'run detail, ${f.name} as a ride');
      });
    }
  });

  group('a history row renders a minimal run', () {
    for (final f in _fixtures) {
      for (final activity in ['run', 'cycle']) {
        testWidgets('${f.name} ($activity)', (tester) async {
          await tester.pumpWidget(_app(Scaffold(
            body: RunListTile.owned(
              run: _runOf(f, activity: activity),
              unit: DistanceUnit.km,
              api: null,
              onTap: () {},
            ),
          )));
          await tester.pump();

          expect(tester.takeException(), isNull);
          expect(find.text('0.00 km'), findsOneWidget);
          expect(find.text(activity == 'cycle' ? '--' : '--:--'),
              findsOneWidget);
          expectNoDegenerateNumbers(tester, surface: 'run row, ${f.name}');
        });
      }
    }
  });

  group('history renders an account of only minimal runs', () {
    for (final miles in [false, true]) {
      testWidgets('every minimal run at once, sorted fastest first '
          '(${miles ? 'mi' : 'km'})', (tester) async {
        await _tallPhone(tester);
        // The fastest sort is the one ordering that divides by distance; the
        // range is pinned to all so no row is filtered out by the clock.
        final prefs = await _prefs(miles: miles, extra: {
          'runs_filters_v1': jsonEncode({'range': 'all', 'sort': 'fastest'}),
        });
        final now = DateTime.now();
        final runs = [
          for (final (i, f) in _fixtures.indexed)
            _runOf(f,
                id: 'run-$i', start: now.subtract(Duration(hours: i + 1))),
        ];
        // ignore: invalid_use_of_visible_for_testing_member
        final runStore = LocalRunStore()..debugSeed(runs, dir: _tmp('hist_'));

        await tester.pumpWidget(_app(RunsScreen(
          apiClient: null,
          runStore: runStore,
          routeStore: LocalRouteStore(),
          preferences: prefs,
        )));
        await pumpUntil(
            tester,
            () =>
                find.byType(RunListTile, skipOffstage: false).evaluate().length ==
                _fixtures.length,
            describe: 'every minimal run to be listed');

        expect(tester.takeException(), isNull);
        expectNoDegenerateNumbers(tester, surface: 'history');
      });
    }
  });

  group('the dashboard renders an account of only minimal runs', () {
    Future<void> pumpDashboard(WidgetTester tester, List<Run> runs,
        {bool miles = false, RunGoal? goal}) async {
      await _tallPhone(tester);
      final prefs = await _prefs(miles: miles);
      if (goal != null) await prefs.upsertGoal(goal);
      final runStore = LocalRunStore();
      await runStore.init(overrideDirectory: _tmp('dash_runs_'));
      final gymStore = LocalGymStore();
      await gymStore.init(overrideDirectory: _tmp('dash_gym_'));
      final foodStore = LocalFoodStore();
      await foodStore.init(overrideDirectory: _tmp('dash_food_'));
      await tester.runAsync(() => runStore.saveManyFromRemote(runs));

      await tester.pumpWidget(_app(DashboardScreen(
        runStore: runStore,
        routeStore: LocalRouteStore(),
        gymStore: gymStore,
        foodStore: foodStore,
        preferences: prefs,
      )));
      await tester.pump();
      await tester.pump();
    }

    for (final f in _fixtures) {
      testWidgets('one run: ${f.name}', (tester) async {
        await pumpDashboard(tester, [_runOf(f)]);

        expect(tester.takeException(), isNull);
        expect(find.text('Welcome!'), findsNothing,
            reason: 'a run, however small, is a history');
        expect(find.text('ALL TIME'), findsOneWidget);
        expect(find.byKey(const Key('dashboardLatestRun')), findsOneWidget);
        expectNoDegenerateNumbers(tester, surface: 'dashboard, ${f.name}');
        await pumpUntilStoreWritesSettle(tester);
      });
    }

    for (final miles in [false, true]) {
      testWidgets('every minimal run at once (${miles ? 'mi' : 'km'})',
          (tester) async {
        final now = DateTime.now();
        await pumpDashboard(tester, [
          for (final (i, f) in _fixtures.indexed)
            _runOf(f,
                id: 'run-$i',
                start: now.subtract(Duration(minutes: 10 * (i + 1)))),
        ], miles: miles);

        expect(tester.takeException(), isNull);
        expect(find.text('ALL TIME'), findsOneWidget);
        expectNoDegenerateNumbers(tester, surface: 'dashboard, all minimal');
        await pumpUntilStoreWritesSettle(tester);
      });
    }

    // The goal card prints a progress figure per target, and the average pace
    // target divides the period's time by its distance — by zero when every
    // run in the week stood still.
    for (final (label, runs) in [
      ('every minimal run', _fixtures),
      ('only the 0 m runs', [for (final f in _fixtures) if (f.metres == 0) f]),
    ]) {
      testWidgets('$label under a weekly goal on every target', (tester) async {
        final now = DateTime.now();
        await pumpDashboard(
          tester,
          [
            for (final (i, f) in runs.indexed)
              _runOf(f, id: 'run-$i', start: now.subtract(Duration(minutes: i))),
          ],
          goal: const RunGoal(
            id: 'g1',
            period: GoalPeriod.week,
            distanceMetres: 20000,
            timeSeconds: 7200,
            avgPaceSecPerKm: 330,
            runCount: 3,
          ),
        );

        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('dashboardWeekLeadVs')), findsOneWidget,
            reason: 'the week lead measures the minimal week against the goal');
        expectNoDegenerateNumbers(tester, surface: 'dashboard, $label, goal');
        await pumpUntilStoreWritesSettle(tester);
      });
    }
  });
}
