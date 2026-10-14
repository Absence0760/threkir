// The centre button's long-press menu (decisions § R10MENU-1): which items it
// offers in each state, which plan workout counts as "today's", which saved
// routes sit inline, and the sheet itself. The shell's routing of each item is pinned in home_screen_test.dart.

import 'package:core_models/core_models.dart';
import 'package:core_models/core_models.dart' as cm;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/widgets/runner_menu.dart';

cm.Route _route(String id, {String? name, DateTime? createdAt}) => cm.Route(
      id: id,
      userId: 'u1',
      name: name ?? 'Route $id',
      waypoints: const [],
      distanceMetres: 5000,
      isPublic: false,
      createdAt: createdAt,
    );

cm.Run _run(String id, {String? routeId, required DateTime at}) => cm.Run(
      id: id,
      startedAt: at,
      duration: const Duration(minutes: 30),
      distanceMetres: 5000,
      routeId: routeId,
      source: cm.RunSource.app,
    );

PlanWorkoutRow _workout({
  String id = 'w1',
  DateTime? day,
  String kind = 'easy',
  double? distanceM = 5000,
  dynamic structure,
  bool done = false,
  String? completedRunId,
  DateTime? skippedAt,
}) =>
    PlanWorkoutRow(
      id: id,
      weekId: 'wk-1',
      scheduledDate: day ?? DateTime(2026, 10, 14),
      kind: kind,
      targetDistanceM: distanceM,
      structure: structure,
      manuallyCompleted: done,
      completedRunId: completedRunId,
      skippedAt: skippedAt,
    );

void main() {
  group('runnerMenuActions', () {
    test('a pure runner gets the shortcuts, never a modality', () {
      expect(
        runnerMenuActions(
          tapFans: false,
          hasTodaysWorkout: true,
          hasRoutes: true,
          gymShown: false,
          nutritionShown: false,
        ),
        [
          RunnerMenuAction.todaysWorkout,
          RunnerMenuAction.followRoute,
          RunnerMenuAction.pastRun,
        ],
      );
    });

    test('no workout today and no saved route leaves only the past run', () {
      expect(
        runnerMenuActions(
          tapFans: false,
          hasTodaysWorkout: false,
          hasRoutes: false,
          gymShown: false,
          nutritionShown: false,
        ),
        [RunnerMenuAction.pastRun],
      );
    });

    test('when the tap starts a run, a shown modality is listed, since the '
        'long-press is then its only way in from this button', () {
      expect(
        runnerMenuActions(
          tapFans: false,
          hasTodaysWorkout: true,
          hasRoutes: true,
          gymShown: true,
          nutritionShown: true,
        ),
        [
          RunnerMenuAction.todaysWorkout,
          RunnerMenuAction.followRoute,
          RunnerMenuAction.pastRun,
          RunnerMenuAction.lift,
          RunnerMenuAction.food,
        ],
      );
    });

    test('when the tap fans Run / Lift / Food, the menu does not repeat them',
        () {
      expect(
        runnerMenuActions(
          tapFans: true,
          hasTodaysWorkout: false,
          hasRoutes: true,
          gymShown: true,
          nutritionShown: true,
        ),
        [RunnerMenuAction.followRoute, RunnerMenuAction.pastRun],
      );
    });

    test('never more than five items', () {
      for (final tapFans in [true, false]) {
        for (final flags in [
          for (var i = 0; i < 16; i++) i,
        ]) {
          final n = runnerMenuActions(
            tapFans: tapFans,
            hasTodaysWorkout: flags & 1 != 0,
            hasRoutes: flags & 2 != 0,
            gymShown: flags & 4 != 0,
            nutritionShown: flags & 8 != 0,
          ).length;
          expect(n, inInclusiveRange(1, 5));
        }
      }
    });
  });

  group('todaysOpenWorkout', () {
    final now = DateTime(2026, 10, 14, 7, 30);

    test("today's open workout is offered", () {
      final w = _workout();
      expect(todaysOpenWorkout([w], now), same(w));
    });

    test('a workout on another day is not', () {
      expect(
          todaysOpenWorkout([_workout(day: DateTime(2026, 10, 13))], now),
          isNull);
    });

    test('rest, completed, run-completed and skipped workouts are not', () {
      expect(todaysOpenWorkout([_workout(kind: 'rest')], now), isNull);
      expect(todaysOpenWorkout([_workout(done: true)], now), isNull);
      expect(todaysOpenWorkout([_workout(completedRunId: 'r1')], now), isNull);
      expect(
          todaysOpenWorkout([_workout(skippedAt: DateTime(2026, 10, 14))], now),
          isNull);
    });

    test('a workout the recorder could not follow is not', () {
      // No structure and no target distance: the recorder answers "no
      // structure", so the item would open onto a dead end.
      expect(todaysOpenWorkout([_workout(distanceM: null)], now), isNull);
    });

    test('a structured workout without a target distance still is', () {
      final w = _workout(distanceM: null, structure: {
        'warmup': {'distance_m': 1000, 'pace': 'easy'},
      });
      expect(todaysOpenWorkout([w], now), same(w));
    });

    test('the first open workout of the day wins over a finished one', () {
      final done = _workout(id: 'a', done: true);
      final open = _workout(id: 'b');
      expect(todaysOpenWorkout([done, open], now), same(open));
    });
  });

  group('workoutCardSummary', () {
    test('a steady run is its target distance, one step', () {
      final s = workoutCardSummary(_workout(distanceM: 8000));
      expect(s.distanceMetres, 8000);
      expect(s.steps, 1);
    });

    test('a structured session without a target sums its distance steps', () {
      final s = workoutCardSummary(_workout(distanceM: null, structure: {
        'warmup': {'distance_m': 1000, 'pace': 'easy'},
        'cooldown': {'distance_m': 1000, 'pace': 'easy'},
      }));
      expect(s.steps, 2);
      expect(s.distanceMetres, 2000);
    });
  });

  group('recentRoutes', () {
    test('no saved route, nothing inline', () {
      expect(recentRoutes(const [], const []), isEmpty);
    });

    test('the most recently followed route leads, and at most three show',
        () {
      final routes = [for (final id in ['a', 'b', 'c', 'd']) _route(id)];
      final runs = [
        _run('r1', routeId: 'b', at: DateTime(2026, 10, 1)),
        _run('r2', routeId: 'd', at: DateTime(2026, 10, 9)),
        _run('r3', routeId: 'b', at: DateTime(2026, 10, 3)),
        _run('r4', at: DateTime(2026, 10, 12)),
      ];
      expect(recentRoutes(routes, runs).map((r) => r.id), ['d', 'b', 'a']);
    });

    test('routes never run follow, newest saved first, undated last', () {
      final routes = [
        _route('old', createdAt: DateTime(2025, 1, 1)),
        _route('undated'),
        _route('new', createdAt: DateTime(2026, 9, 1)),
      ];
      expect(recentRoutes(routes, const []).map((r) => r.id),
          ['new', 'old', 'undated']);
    });
  });

  group('showRunnerMenu', () {
    /// Mounts an empty app, opens the menu over it, and lets the sheet's
    /// entrance run. Resolves to the sheet's eventual result.
    Future<Future<RunnerMenuChoice?>> open(
      WidgetTester tester,
      List<RunnerMenuAction> actions, {
      PlanWorkoutRow? workout,
      List<cm.Route> routes = const [],
      bool hasMoreRoutes = false,
      double textScale = 1,
    }) async {
      late BuildContext ctx;
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Builder(builder: (c) {
          ctx = c;
          return const Scaffold();
        }),
      ));
      final result = showRunnerMenu(
        context: ctx,
        actions: actions,
        unit: DistanceUnit.km,
        todaysWorkout: workout,
        routes: routes,
        hasMoreRoutes: hasMoreRoutes,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      return result;
    }

    Future<void> settle(WidgetTester tester) async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    final three = [for (final id in ['a', 'b', 'c']) _route(id)];

    testWidgets('lists each item under its label, titled for a screen reader',
        (tester) async {
      final handle = tester.ensureSemantics();
      await open(tester, RunnerMenuAction.values,
          workout: _workout(), routes: three, hasMoreRoutes: true);

      expect(find.text('More options'), findsOneWidget);
      expect(find.text("Start today's workout"), findsOneWidget);
      expect(find.text('Follow a route'), findsOneWidget);
      expect(find.text('All routes…'), findsOneWidget);
      expect(find.text('Add past run'), findsOneWidget);
      expect(find.text('Log lift'), findsOneWidget);
      expect(find.text('Log food'), findsOneWidget);
      expect(find.bySemanticsLabel('More options'), findsWidgets);
      expect(find.bySemanticsLabel('Follow Route a, 5.00 km'), findsOneWidget,
          reason: 'a route chip is announced as what tapping it does');
      handle.dispose();
    });

    testWidgets("the workout card names the session's kind and size, and "
        'starts it in one tap', (tester) async {
      final result = await open(tester, const [
        RunnerMenuAction.todaysWorkout,
        RunnerMenuAction.pastRun,
      ], workout: _workout(distanceM: null, structure: {
        'warmup': {'distance_m': 1000, 'pace': 'easy'},
        'cooldown': {'distance_m': 1000, 'pace': 'easy'},
      }));
      expect(find.text('Easy'), findsOneWidget);
      expect(find.text('2.00 km · 2 steps'), findsOneWidget);

      await tester.tap(find.text('Easy'));
      await settle(tester);
      final choice = await result;
      expect(choice, isA<RunnerMenuActionChoice>().having(
          (c) => c.action, 'action', RunnerMenuAction.todaysWorkout));
    });

    testWidgets('a steady workout shows its distance with no step count',
        (tester) async {
      await open(tester, const [
        RunnerMenuAction.todaysWorkout,
        RunnerMenuAction.pastRun,
      ], workout: _workout());
      expect(find.text('5.00 km'), findsOneWidget);
    });

    testWidgets('with no saved route there is no route section',
        (tester) async {
      await open(tester, const [RunnerMenuAction.pastRun]);
      expect(find.text('Follow a route'), findsNothing);
      expect(find.text('All routes…'), findsNothing);
    });

    testWidgets('one saved route sits inline, with no All routes to repeat it',
        (tester) async {
      await open(tester,
          const [RunnerMenuAction.followRoute, RunnerMenuAction.pastRun],
          routes: [_route('a')]);
      expect(find.text('Route a'), findsOneWidget);
      expect(find.text('All routes…'), findsNothing);
    });

    testWidgets('more than fit: three inline, and All routes opens the picker',
        (tester) async {
      final result = await open(tester,
          const [RunnerMenuAction.followRoute, RunnerMenuAction.pastRun],
          routes: three, hasMoreRoutes: true);
      for (final id in ['a', 'b', 'c']) {
        expect(find.text('Route $id'), findsOneWidget);
      }
      await tester.tap(find.text('All routes…'));
      await settle(tester);
      expect(await result, isA<RunnerMenuActionChoice>().having(
          (c) => c.action, 'action', RunnerMenuAction.followRoute));
    });

    testWidgets('tapping a route resolves to that route', (tester) async {
      final result = await open(tester,
          const [RunnerMenuAction.followRoute, RunnerMenuAction.pastRun],
          routes: three);
      await tester.tap(find.text('Route b'));
      await settle(tester);
      final choice = await result;
      expect(choice, isA<RunnerMenuRouteChoice>());
      expect((choice! as RunnerMenuRouteChoice).route.id, 'b');
    });

    testWidgets('a row resolves to its action', (tester) async {
      final result = await open(tester, const [RunnerMenuAction.pastRun]);
      await tester.tap(find.text('Add past run'));
      await settle(tester);
      expect(await result, isA<RunnerMenuActionChoice>().having(
          (c) => c.action, 'action', RunnerMenuAction.pastRun));
    });

    testWidgets('a dismissed menu resolves to nothing', (tester) async {
      final result = await open(tester, const [RunnerMenuAction.pastRun]);
      await tester.tapAt(const Offset(20, 20));
      await settle(tester);
      expect(await result, isNull);
    });

    testWidgets('the full sheet at the largest text size scrolls rather than '
        'overflows', (tester) async {
      await open(tester, RunnerMenuAction.values,
          workout: _workout(),
          routes: [
            _route('a', name: 'A very long route name that will not fit on '
                'one line at any text size'),
            _route('b'),
            _route('c'),
          ],
          hasMoreRoutes: true,
          textScale: 3.2);
      expect(tester.takeException(), isNull);
      expect(find.byType(SingleChildScrollView), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Log food'), 200,
          scrollable: find.byType(Scrollable).last);
      expect(tester.takeException(), isNull);
    });
  });
}
