// The week lead (#905 workstream 3, web `DashboardWeekLead.svelte`), which
// opens the Progress page since issue #1374 moved it off Home. The numbers are
// pinned by the `week_lead.dart` parity pair's own suite; this one pins what
// the screen does with them: where the card sits, which yardstick line it
// shows, the next-session half appearing only with an active plan, the unit
// preference, and on Home: the two actions in Home's overflow, the hero's
// Start, and no lead on the runless welcome state.

import 'dart:io';

import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/goals.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/local_food_store.dart';
import '../lib/local_gym_store.dart';
import '../lib/local_route_store.dart';
import '../lib/local_run_store.dart';
import '../lib/preferences.dart';
import '../lib/screens/add_run_screen.dart';
import '../lib/screens/today_screen.dart';
import '../lib/screens/import_screen.dart';
import '../lib/screens/period_summary_screen.dart';
import '../lib/screens/progress_screen.dart';
import '../lib/screens/run_screen.dart' show runRecordingActive;
import '../lib/training_service.dart';
import '../lib/widgets/this_week_strip.dart';
import '../lib/widgets/todays_workout_card.dart';
import 'pump_until.dart';

class _FakeTraining extends TrainingService {
  final ActivePlanOverview? overview;
  _FakeTraining(this.overview);
  @override
  Future<ActivePlanOverview?> fetchActiveOverview() async => overview;
}

ActivePlanOverview _overview(List<PlanWorkoutRow> workouts,
    {PlanWorkoutRow? today}) {
  final now = DateTime.now();
  return ActivePlanOverview(
    plan: TrainingPlanRow(
      id: 'plan-1',
      userId: 'u1',
      name: 'Spring 10k',
      goalEvent: '10k',
      goalDistanceM: 10000,
      startDate: now.subtract(const Duration(days: 28)),
      endDate: now.add(const Duration(days: 56)),
      daysPerWeek: 4,
      status: 'active',
      source: 'app',
      isTemplate: false,
      isPublicTemplate: false,
    ),
    weeks: [
      PlanWeekRow(
          id: 'wk-1', planId: 'plan-1', weekIndex: 4, phase: 'build'),
    ],
    workouts: workouts,
    todayWorkout: today,
    completionPct: 40,
    currentWeekIndex: 4,
  );
}

PlanWorkoutRow _workout(String id, DateTime day, String kind,
        {double? distanceM, bool done = false}) =>
    PlanWorkoutRow(
      id: id,
      weekId: 'wk-1',
      scheduledDate: day,
      kind: kind,
      targetDistanceM: distanceM,
      manuallyCompleted: done,
    );

Run _run(String id, DateTime startedAt, double metres) => Run(
      id: id,
      startedAt: startedAt,
      duration: const Duration(minutes: 30),
      distanceMetres: metres,
      source: RunSource.app,
    );

/// Seeds [runs] to disk, mounts the dashboard, and waits for the card the
/// test is about to read. Store I/O runs on the real event loop, so the whole
/// mount sits inside `runAsync` and the wait is a [pumpUntil], never a delay.
Future<({Preferences prefs, Directory dir})> _mount(
  WidgetTester tester, {
  required List<Run> runs,
  TrainingService? training,
  bool useMiles = false,
  List<RunGoal> goals = const [],
  VoidCallback? onStartRun,
  ValueChanged<PlanWorkoutRow>? onStartWorkout,
  bool progress = false,
  required bool Function() ready,
  required String describe,
}) async {
  tester.view.physicalSize = const Size(400, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  late Preferences prefs;
  late Directory dir;
  await tester.runAsync(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = Preferences();
    await prefs.init();
    if (useMiles) await prefs.setUseMiles(true);
    for (final g in goals) {
      await prefs.upsertGoal(g);
    }
    dir = Directory.systemTemp.createTempSync('dashboard_week_lead_');
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
      home: progress
          ? ProgressScreen(
              runStore: runStore,
              routeStore: LocalRouteStore(),
              gymStore: LocalGymStore(),
              preferences: prefs,
              training: training,
            )
          : DashboardScreen(
              runStore: runStore,
              routeStore: LocalRouteStore(),
              gymStore: LocalGymStore(),
              foodStore: LocalFoodStore(),
              preferences: prefs,
              training: training,
              onStartRun: onStartRun,
              onStartWorkout: onStartWorkout,
            ),
    ));
  });
  addTearDown(() => dir.deleteSync(recursive: true));
  await pumpUntil(tester, ready, describe: describe);
  return (prefs: prefs, dir: dir);
}

final _lead = find.byKey(const Key('dashboardWeekLead'));
final _summary = find.byKey(const Key('todayProgressSummary'));

void main() {
  testWidgets(
      'an account with runs opens on the week lead, measured against its own '
      'average when there is no plan or weekly goal', (tester) async {
    final now = DateTime.now();
    await _mount(
      progress: true,
      tester,
      runs: [
        // Stamped at mount time, so it is inside this calendar week whatever
        // day the suite runs on.
        _run('this-week', now, 5000),
        _run('history', now.subtract(const Duration(days: 15)), 12000),
      ],
      ready: () => _lead.evaluate().isNotEmpty,
      describe: 'the week lead to mount',
    );

    // Read off the keyed Text itself: a Text renders a RichText, so a
    // find.text descendant of it matches nothing even when the value is right.
    expect(
      tester
          .widget<Text>(find.byKey(const Key('dashboardWeekLeadDistance')))
          .data,
      UnitFormat.distance(5000, DistanceUnit.km),
    );
    expect(find.descendant(of: _lead, matching: find.text('1 activity')),
        findsOneWidget);
    final vs = tester.widget<Text>(find.byKey(const Key('dashboardWeekLeadVs')));
    expect(vs.data, contains('km'));
    expect(vs.data,
        anyOf(startsWith('Last week'), startsWith('Your weekly average')));
    // The average is a reference, not a target, so it draws no meter.
    expect(find.byKey(const Key('dashboardWeekLeadMeter')), findsNothing);
    // No active plan, so no next-session half at all.
    expect(find.text('Next session'), findsNothing);
    // Compact: the occasional Add a run / Import moved to Home's overflow
    // (decisions § 2281).
    expect(find.descendant(of: _lead, matching: find.text('Add a run')),
        findsNothing);
    expect(find.descendant(of: _lead, matching: find.text('Import runs')),
        findsNothing);

    // It is the page's first card: above the period strip.
    expect(tester.getBottomLeft(_lead).dy,
        lessThan(tester.getTopLeft(find.text('MONTH')).dy));
  });

  testWidgets('the distance honours the miles preference', (tester) async {
    final now = DateTime.now();
    await _mount(
      progress: true,
      tester,
      useMiles: true,
      runs: [_run('r1', now, 8046.72)],
      ready: () => _lead.evaluate().isNotEmpty,
      describe: 'the week lead to mount',
    );
    final distance = tester
        .widget<Text>(find.byKey(const Key('dashboardWeekLeadDistance')));
    expect(distance.data, UnitFormat.distance(8046.72, DistanceUnit.mi));
    expect(distance.data, endsWith('mi'));
  });

  testWidgets(
      'a weekly distance goal is the yardstick, with a meter, when there is no '
      'plan', (tester) async {
    final now = DateTime.now();
    await _mount(
      progress: true,
      tester,
      goals: const [
        RunGoal(id: 'g1', period: GoalPeriod.week, distanceMetres: 20000),
      ],
      runs: [_run('r1', now, 5000)],
      ready: () => _lead.evaluate().isNotEmpty,
      describe: 'the week lead to mount',
    );
    final vs = tester.widget<Text>(find.byKey(const Key('dashboardWeekLeadVs')));
    expect(
      vs.data,
      '${UnitFormat.distance(5000, DistanceUnit.km)} of your '
      '${UnitFormat.distance(20000, DistanceUnit.km)} weekly goal',
    );
    expect(find.byKey(const Key('dashboardWeekLeadMeter')), findsOneWidget);
  });

  testWidgets(
      'with an active plan it names the next open session', (tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final todays = _workout('wo-today', today, 'long', distanceM: 16000);
    await _mount(
      progress: true,
      tester,
      training: _FakeTraining(_overview([
        _workout('wo-done', today.subtract(const Duration(days: 1)), 'easy',
            distanceM: 5000, done: true),
        todays,
      ], today: todays)),
      runs: [_run('r1', now, 5000)],
      ready: () =>
          find.byKey(const Key('dashboardWeekLeadNext')).evaluate().isNotEmpty,
      describe: 'the next-session row to mount',
    );

    final next = find.byKey(const Key('dashboardWeekLeadNext'));
    expect(find.descendant(of: next, matching: find.text('Today')),
        findsOneWidget);
    expect(
      find.descendant(
          of: next,
          matching: find.text(
              'Long run · ${UnitFormat.distance(16000, DistanceUnit.km)}')),
      findsOneWidget,
    );
    // The plan puts distance in this calendar week, so it is the yardstick.
    expect(
      tester.widget<Text>(find.byKey(const Key('dashboardWeekLeadVs'))).data,
      endsWith('planned'),
    );
  });

  testWidgets('a plan with nothing left open says so instead of a session',
      (tester) async {
    final now = DateTime.now();
    final yesterday = DateTime(now.year, now.month, now.day - 1);
    await _mount(
      progress: true,
      tester,
      training: _FakeTraining(_overview([
        _workout('wo-past', yesterday, 'easy', distanceM: 5000, done: true),
      ])),
      runs: [_run('r1', now, 5000)],
      ready: () =>
          find.byKey(const Key('dashboardWeekLeadNoNext')).evaluate().isNotEmpty,
      describe: 'the no-next-session line to mount',
    );
    expect(find.text('No more sessions scheduled in your plan.'),
        findsOneWidget);
    expect(find.byKey(const Key('dashboardWeekLeadNext')), findsNothing);
  });

  testWidgets('Home\'s overflow offers Add a run, which opens the manual '
      'add-run form', (tester) async {
    final now = DateTime.now();
    await _mount(
      tester,
      runs: [_run('r1', now, 5000)],
      ready: () => _summary.evaluate().isNotEmpty,
      describe: 'Today to mount',
    );
    await tester.tap(find.byKey(const Key('dashboardMoreMenu')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('dashboardMenuImport')), findsOneWidget);
    await tester.tap(find.byKey(const Key('dashboardMenuAddRun')));
    await pumpUntil(
      tester,
      () => find.byType(AddRunScreen).evaluate().isNotEmpty,
      describe: 'the add-run form to open',
    );
  });

  testWidgets('Home\'s overflow offers Import runs, which opens the import '
      'screen, on the welcome state too', (tester) async {
    await _mount(
      tester,
      runs: const [],
      ready: () => find.text('Welcome!').evaluate().isNotEmpty,
      describe: 'the welcome state to mount',
    );
    await tester.tap(find.byKey(const Key('dashboardMoreMenu')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const Key('dashboardMenuImport')));
    await pumpUntil(
      tester,
      () => find.byType(ImportScreen).evaluate().isNotEmpty,
      describe: 'the import screen to open',
    );
  });

  testWidgets('the lead is the one this-week view, and its chevron opens '
      'the weekly summary', (tester) async {
    await _mount(
      progress: true,
      tester,
      runs: [_run('r1', DateTime.now(), 5000)],
      ready: () => _lead.evaluate().isNotEmpty,
      describe: 'the week lead to mount',
    );
    // decisions § 2283: no This Week strip and no Week stat cell.
    expect(find.byType(ThisWeekStrip), findsNothing);
    expect(find.text('WEEK'), findsNothing);
    await tester.tap(find.byKey(const Key('dashboardWeekLeadOpenWeek')));
    await pumpUntil(
      tester,
      () => find.byType(PeriodSummaryScreen).evaluate().isNotEmpty,
      describe: 'the weekly summary to open',
    );
    expect(find.text('Weekly Summary'), findsOneWidget);
  });

  testWidgets('the runless first-run state carries no week lead',
      (tester) async {
    await _mount(
      tester,
      runs: const [],
      ready: () => find.text('Welcome!').evaluate().isNotEmpty,
      describe: 'the welcome state to mount',
    );
    expect(_lead, findsNothing);
  });

  group('Home\'s Start (decisions § 2282, § 2385)', () {
    final heroStart = find.byKey(const Key('dashboardHeroStart'));
    final cardStart = find.byKey(const Key('todaysWorkoutStart'));

    testWidgets('without a plan the Today hero carries the Start, captioned '
        'for the default activity, and it opens the recorder', (tester) async {
      var started = 0;
      await _mount(
        tester,
        runs: [_run('r1', DateTime.now(), 5000)],
        onStartRun: () => started++,
        ready: () => heroStart.evaluate().isNotEmpty,
        describe: 'the hero Start to mount',
      );
      expect(
          find.descendant(
              of: find.byKey(const Key('dashboardTodayHero')),
              matching: heroStart),
          findsOneWidget);
      expect(find.descendant(of: _lead, matching: find.byType(FilledButton)),
          findsNothing,
          reason: 'the lead carries no Start of its own any more');
      expect(find.descendant(of: heroStart, matching: find.text('Start run')),
          findsOneWidget);
      await tester.tap(heroStart);
      expect(started, 1);
    });

    testWidgets('an open workout today takes the Start, which loads that '
        'workout, and the hero carries no second one', (tester) async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final todays = _workout('wo-today', today, 'easy', distanceM: 6000);
      PlanWorkoutRow? loaded;
      await _mount(
        tester,
        training: _FakeTraining(_overview([todays], today: todays)),
        runs: [_run('r1', now, 5000)],
        onStartRun: () {},
        onStartWorkout: (w) => loaded = w,
        ready: () => cardStart.evaluate().isNotEmpty,
        describe: 'the workout card Start to mount',
      );
      expect(heroStart, findsNothing);
      await tester.tap(cardStart);
      expect(loaded?.id, 'wo-today');
    });

    testWidgets('a workout already done today leaves the hero its own Start',
        (tester) async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final todays =
          _workout('wo-today', today, 'easy', distanceM: 6000, done: true);
      await _mount(
        tester,
        training: _FakeTraining(_overview([todays], today: todays)),
        runs: [_run('r1', now, 5000)],
        onStartRun: () {},
        onStartWorkout: (_) {},
        ready: () =>
            find.byType(TodaysWorkoutCard).evaluate().isNotEmpty &&
            heroStart.evaluate().isNotEmpty,
        describe: 'the done workout card and the hero Start to mount',
      );
      expect(cardStart, findsNothing);
    });

    testWidgets('no Start anywhere while a run records', (tester) async {
      runRecordingActive.value = true;
      addTearDown(() => runRecordingActive.value = false);
      await _mount(
        tester,
        runs: [_run('r1', DateTime.now(), 5000)],
        onStartRun: () {},
        ready: () => _summary.evaluate().isNotEmpty,
        describe: 'Today to mount',
      );
      expect(heroStart, findsNothing);
      expect(cardStart, findsNothing);
    });

    testWidgets('no Start when the host cannot reach the recorder',
        (tester) async {
      await _mount(
        tester,
        runs: [_run('r1', DateTime.now(), 5000)],
        ready: () => _summary.evaluate().isNotEmpty,
        describe: 'Today to mount',
      );
      expect(heroStart, findsNothing);
    });
  });
}
