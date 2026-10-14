// The centre button's long-press menu (decisions § R10MENU-1): which items it
// offers in each state, which plan workout counts as "today's", and the sheet
// itself. The shell's routing of each item is pinned in home_screen_test.dart.

import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/widgets/runner_menu.dart';

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

  group('showRunnerMenu', () {
    /// Mounts an empty app, opens the menu over it, and lets the sheet's
    /// entrance run. Resolves to the sheet's eventual result.
    Future<Future<RunnerMenuAction?>> open(
      WidgetTester tester,
      List<RunnerMenuAction> actions, {
      PlanWorkoutRow? workout,
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
      final result =
          showRunnerMenu(context: ctx, actions: actions, todaysWorkout: workout);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      return result;
    }

    testWidgets('lists each item under its label, titled for a screen reader',
        (tester) async {
      final handle = tester.ensureSemantics();
      await open(tester, RunnerMenuAction.values, workout: _workout());

      expect(find.text('More options'), findsOneWidget);
      expect(find.text("Start today's workout"), findsOneWidget);
      expect(find.text('Easy'), findsOneWidget,
          reason: "the workout row names today's session");
      expect(find.text('Choose route'), findsOneWidget);
      expect(find.text('Add past run'), findsOneWidget);
      expect(find.text('Log lift'), findsOneWidget);
      expect(find.text('Log food'), findsOneWidget);
      expect(find.bySemanticsLabel('More options'), findsWidgets);
      handle.dispose();
    });

    testWidgets('a row resolves to its action', (tester) async {
      final result = await open(tester, const [
        RunnerMenuAction.followRoute,
        RunnerMenuAction.pastRun,
      ]);
      await tester.tap(find.text('Add past run'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(await result, RunnerMenuAction.pastRun);
    });

    testWidgets('a dismissed menu resolves to nothing', (tester) async {
      final result = await open(tester, const [RunnerMenuAction.pastRun]);
      await tester.tapAt(const Offset(20, 20));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(await result, isNull);
    });

    testWidgets('five rows at the largest text size scroll rather than '
        'overflow', (tester) async {
      await open(tester, RunnerMenuAction.values,
          workout: _workout(), textScale: 3.2);
      expect(tester.takeException(), isNull);
      expect(find.byType(SingleChildScrollView), findsOneWidget);
    });
  });
}
