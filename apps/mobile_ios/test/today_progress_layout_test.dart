// ignore_for_file: avoid_relative_lib_imports
// Home's Today and the Progress page it opens (issue #1374), at the worst case
// the issue's rules name: a 320 dp phone, 2x text and Android's 3-button
// navigation bar. Today is about six blocks in a fixed order and ends on one
// progress summary card; the trends, PBs, streak, full goals and recap are a
// pushed page one tap from it, not a tab and not a long scroll under Today.
import 'dart:io';

import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ui_kit/ui_kit.dart' show AppTheme;

import '../lib/fab_clearance.dart';
import '../lib/goals.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/local_food_store.dart';
import '../lib/local_gym_store.dart';
import '../lib/local_route_store.dart';
import '../lib/local_run_store.dart';
import '../lib/preferences.dart';
import '../lib/screens/today_screen.dart';
import '../lib/screens/home_screen.dart' show bottomNavMetrics;
import '../lib/screens/progress_screen.dart';
import '../lib/training_service.dart';
import 'pump_until.dart';
import 'three_button_nav_bar.dart' show kThreeButtonNavBar;

const _phone = Size(320, 640);
const _fabKey = ValueKey('test-docked-fab');

class _PlanTraining extends TrainingService {
  @override
  Future<ActivePlanOverview?> fetchActiveOverview() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final workout = PlanWorkoutRow(
      id: 'wo-1',
      weekId: 'wk-1',
      scheduledDate: today,
      kind: 'tempo',
      targetDistanceM: 10000,
      manuallyCompleted: false,
    );
    return ActivePlanOverview(
      plan: TrainingPlanRow(
        id: 'plan-1',
        userId: 'u1',
        name: 'Richmond Marathon block',
        goalEvent: 'marathon',
        goalDistanceM: 42195,
        startDate: today.subtract(const Duration(days: 30)),
        endDate: today.add(const Duration(days: 60)),
        daysPerWeek: 5,
        status: 'active',
        source: 'app',
        isTemplate: false,
        isPublicTemplate: false,
      ),
      weeks: [
        PlanWeekRow(
            id: 'wk-1', planId: 'plan-1', weekIndex: 4, phase: 'build'),
      ],
      workouts: [workout],
      todayWorkout: workout,
      completionPct: 40,
      currentWeekIndex: 4,
    );
  }
}

Run _run(String id, DateTime startedAt) => Run(
      id: id,
      startedAt: startedAt,
      duration: const Duration(minutes: 30),
      distanceMetres: 6000,
      source: RunSource.app,
    );

void main() {
  setUpAll(() => initializeDateFormatting());

  final dirs = <Directory>[];
  tearDown(() {
    for (final d in dirs) {
      if (d.existsSync()) d.deleteSync(recursive: true);
    }
    dirs.clear();
  });

  Future<void> pumpToday(WidgetTester tester, {double height = 640}) async {
    tester.view.physicalSize = Size(_phone.width, height);
    tester.view.devicePixelRatio = 1;
    tester.view.viewPadding = const FakeViewPadding(bottom: kThreeButtonNavBar);
    tester.view.padding = const FakeViewPadding(bottom: kThreeButtonNavBar);
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = Preferences();
      await prefs.init();
      await prefs.upsertGoal(const RunGoal(
          id: 'g1', period: GoalPeriod.week, distanceMetres: 30000));
      final dir = Directory.systemTemp.createTempSync('today_layout_');
      dirs.add(dir);
      final seed = LocalRunStore();
      await seed.init(overrideDirectory: dir);
      final now = DateTime.now();
      for (var i = 1; i <= 12; i++) {
        await seed.save(_run('r$i', now.subtract(Duration(days: i * 2))));
      }
      final runStore = LocalRunStore();
      await runStore.init(overrideDirectory: dir);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2.0)),
          child: child!,
        ),
        // The phone shell's geometry: a bottom bar sized like the real one
        // for the text scale, and a centre button docked on its top edge.
        home: Builder(
          builder: (context) => Scaffold(
            body: DockedFabInset(
              height: kDockedFabOverhang,
              child: TodayScreen(
                runStore: runStore,
                routeStore: LocalRouteStore(),
                gymStore: LocalGymStore(),
                foodStore: LocalFoodStore(),
                preferences: prefs,
                training: _PlanTraining(),
                onStartRun: () {},
                onStartWorkout: (_) {},
              ),
            ),
            floatingActionButton: FloatingActionButton(
              key: _fabKey,
              onPressed: () {},
              child: const Icon(Icons.play_arrow),
            ),
            floatingActionButtonLocation:
                FloatingActionButtonLocation.centerDocked,
            bottomNavigationBar: BottomAppBar(
              height: bottomNavMetrics(
                      MediaQuery.textScalerOf(context).scale(1))
                  .height,
              padding: EdgeInsets.zero,
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ));
    });
    await pumpUntil(
      tester,
      () => find
          .byKey(const Key('todaysWorkoutStart'))
          .evaluate()
          .isNotEmpty,
      describe: "today's workout in the hero",
    );
    await tester.pump();
  }

  /// A lazy list only knows its extent once the items near the end are
  /// built, so the jump repeats until the end stops moving.
  Future<void> scrollToEnd(WidgetTester tester, Finder scrollable) async {
    final position = tester.state<ScrollableState>(scrollable).position;
    for (var i = 0; i < 20; i++) {
      final end = position.maxScrollExtent;
      position.jumpTo(end);
      await tester.pump();
      if (position.maxScrollExtent == end) return;
    }
  }

  void expectAboveNavBar(WidgetTester tester, Finder f) {
    expect(tester.getRect(f).bottom,
        lessThanOrEqualTo(_phone.height - kThreeButtonNavBar),
        reason: 'the last block must scroll clear of the 3-button bar');
  }

  testWidgets('Today is its blocks in order at 320 dp and 2x', (tester) async {
    // Tall, so every block is built and measured without scrolling; a
    // RenderFlex overflow anywhere fails the test by itself.
    await pumpToday(tester, height: 3000);

    final hero = find.byKey(const Key('dashboardTodayHero'));
    final lastRun = find.byKey(const Key('dashboardLatestRun'));
    final goals = find.byKey(const Key('todayGoalsStrip'));
    final summary = find.byKey(const Key('todayProgressSummary'));
    final order = <Finder>[hero, lastRun, goals, summary];
    for (final f in order) {
      expect(f, findsOneWidget);
    }
    for (var i = 1; i < order.length; i++) {
      expect(tester.getTopLeft(order[i]).dy,
          greaterThan(tester.getBottomLeft(order[i - 1]).dy),
          reason: "Today's order: hero, last run, goals, progress summary");
    }

    // What left Today for the Progress page.
    expect(find.text('MONTH'), findsNothing);
    expect(find.text('Volume'), findsNothing);
    expect(find.byKey(const Key('dashboardWeekLead')), findsNothing);
    expect(find.byKey(const Key('dashboardStreakRow')), findsNothing);
  });

  testWidgets(
      'at the end of Today the summary clears the docked Start and the '
      '3-button bar', (tester) async {
    await pumpToday(tester);
    final summary = find.byKey(const Key('todayProgressSummary'));
    await scrollToEnd(tester, find.byType(Scrollable).first);
    expect(tester.getRect(summary).bottom,
        lessThanOrEqualTo(tester.getRect(find.byKey(_fabKey)).top),
        reason: 'the last block scrolls clear of the docked Start');
    expect(tester.getRect(summary).bottom,
        lessThanOrEqualTo(_phone.height - kThreeButtonNavBar));
  });

  testWidgets('the progress summary opens the Progress page as a pushed page',
      (tester) async {
    await pumpToday(tester);
    final summary = find.byKey(const Key('todayProgressSummary'));
    await scrollToEnd(tester, find.byType(Scrollable).first);
    expect(
        find.descendant(of: summary, matching: find.text('Your progress')),
        findsOneWidget);

    await tester.tap(summary);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(ProgressScreen), findsOneWidget);
    expect(find.widgetWithText(AppBar, 'Progress'), findsOneWidget);
    expect(find.byType(BackButton), findsOneWidget,
        reason: 'a page one tap from Today, with the way back on it');
    tester.takeException();
  });

  Future<void> openProgress(WidgetTester tester) async {
    final summary = find.byKey(const Key('todayProgressSummary'));
    await scrollToEnd(tester, find.byType(Scrollable).first);
    await tester.tap(summary);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await pumpUntil(
      tester,
      () => find.byKey(const Key('dashboardWeekLead')).evaluate().isNotEmpty,
      describe: 'the Progress page to open on the week lead',
    );
  }

  testWidgets('the Progress page fits 320 dp at 2x', (tester) async {
    // Tall, so every group is built at once; an overflow fails the test.
    await pumpToday(tester, height: 9000);
    await openProgress(tester);
    for (final key in const [
      Key('progressGoals'),
      Key('dashboardStreakRow'),
      ValueKey('dashboard-trend-volume'),
      ValueKey('dashboard-trend-fitness'),
      ValueKey('dashboard-trend-performance'),
    ]) {
      expect(find.byKey(key), findsOneWidget);
    }
  });

  testWidgets('the Progress page\'s last group clears the 3-button bar',
      (tester) async {
    await pumpToday(tester);
    await openProgress(tester);
    final scrollable = find
        .descendant(
            of: find.byType(ProgressScreen), matching: find.byType(Scrollable))
        .first;
    await scrollToEnd(tester, scrollable);
    final lastGroup = find.byKey(const ValueKey('dashboard-trend-performance'));
    expect(lastGroup, findsOneWidget);
    expectAboveNavBar(tester, lastGroup);
  });
}
