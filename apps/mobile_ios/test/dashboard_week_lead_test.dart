// The week lead that opens Home for an account with runs (#905 workstream 3,
// web `DashboardWeekLead.svelte`). The numbers are pinned by the
// `week_lead.dart` parity pair's own suite; this one pins what the screen does
// with them: where the card sits, which yardstick line it shows, the
// next-session half appearing only with an active plan, the unit preference,
// the two actions, and the card staying off the runless welcome state.

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
import '../lib/screens/dashboard_screen.dart';
import '../lib/training_service.dart';
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
      home: DashboardScreen(
        runStore: runStore,
        routeStore: LocalRouteStore(),
        gymStore: LocalGymStore(),
        foodStore: LocalFoodStore(),
        preferences: prefs,
        training: training,
      ),
    ));
  });
  addTearDown(() => dir.deleteSync(recursive: true));
  await pumpUntil(tester, ready, describe: describe);
  return (prefs: prefs, dir: dir);
}

final _lead = find.byKey(const Key('dashboardWeekLead'));

void main() {
  testWidgets(
      'an account with runs opens on the week lead, measured against its own '
      'average when there is no plan or weekly goal', (tester) async {
    final now = DateTime.now();
    await _mount(
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

    expect(
      find.descendant(
          of: find.byKey(const Key('dashboardWeekLeadDistance')),
          matching: find.text(UnitFormat.distance(5000, DistanceUnit.km))),
      findsOneWidget,
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
    expect(find.byKey(const Key('dashboardWeekLeadAddRun')), findsOneWidget);
    expect(find.descendant(of: _lead, matching: find.text('Import runs')),
        findsOneWidget);

    // It is the first card under the toolbar: above the period strip.
    expect(tester.getBottomLeft(_lead).dy,
        lessThan(tester.getTopLeft(find.text('WEEK')).dy));
  });

  testWidgets('the distance honours the miles preference', (tester) async {
    final now = DateTime.now();
    await _mount(
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
      'with an active plan it leads above the plan hero and names the next '
      'open session', (tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final todays = _workout('wo-today', today, 'long', distanceM: 16000);
    await _mount(
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
    expect(tester.getBottomLeft(_lead).dy,
        lessThan(tester.getTopLeft(find.text("TODAY'S WORKOUT")).dy));
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

  testWidgets('Add a run opens the manual add-run form', (tester) async {
    final now = DateTime.now();
    await _mount(
      tester,
      runs: [_run('r1', now, 5000)],
      ready: () => _lead.evaluate().isNotEmpty,
      describe: 'the week lead to mount',
    );
    await tester.tap(find.byKey(const Key('dashboardWeekLeadAddRun')));
    await pumpUntil(
      tester,
      () => find.byType(AddRunScreen).evaluate().isNotEmpty,
      describe: 'the add-run form to open',
    );
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
}
