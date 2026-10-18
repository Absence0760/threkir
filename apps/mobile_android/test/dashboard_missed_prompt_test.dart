import 'dart:io';

import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/local_food_store.dart';
import '../lib/local_gym_store.dart';
import '../lib/local_route_store.dart';
import '../lib/local_run_store.dart';
import '../lib/preferences.dart';
import '../lib/screens/dashboard_screen.dart';
import '../lib/screens/plan_detail_screen.dart';
import '../lib/training_service.dart';
import 'pump_until.dart';
import 'store_write_watch.dart';

/// Home asks once about the plan's most recent missed workout, above the
/// Today card (decisions § 2122).
class _Training extends TrainingService {
  _Training({this.ended = false, this.longMiss = false});
  final bool ended;
  final bool longMiss;
  int overviewReads = 0;
  final answered = <String>{};

  @override
  Future<ActivePlanOverview?> fetchActiveOverview() async {
    overviewReads++;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    DateTime day(int offset) => today.add(Duration(days: offset));
    final start = ended ? day(-20) : day(-9);
    final todays = PlanWorkoutRow(
      id: 'today',
      weekId: 'wk-1',
      scheduledDate: today,
      kind: 'easy',
      targetDistanceM: 5000,
      manuallyCompleted: false,
    );
    final missed = PlanWorkoutRow(
      id: 'missed',
      weekId: 'wk-1',
      scheduledDate: day(-1),
      kind: longMiss ? 'long' : 'easy',
      targetDistanceM: longMiss ? 16000 : 6000,
      manuallyCompleted: false,
      missedAckAt: answered.contains('missed') ? now : null,
    );
    final next = PlanWorkoutRow(
      id: 'next',
      weekId: 'wk-2',
      scheduledDate: day(6),
      kind: 'long',
      targetDistanceM: 14000,
      manuallyCompleted: false,
    );
    PlanWeekRow week(String id, int i) => PlanWeekRow(
        id: id, planId: 'plan-1', weekIndex: i, phase: 'build', targetVolumeM: 30000);
    return ActivePlanOverview(
      plan: TrainingPlanRow(
        id: 'plan-1',
        userId: 'u1',
        name: 'Spring Half',
        goalEvent: 'distance_half',
        goalDistanceM: 21097.5,
        startDate: start,
        endDate: ended ? day(-1) : day(40),
        daysPerWeek: 4,
        status: 'active',
        source: 'generated',
        isTemplate: false,
        isPublicTemplate: false,
      ),
      weeks: [week('wk-1', 1), week('wk-2', 2)],
      workouts: [missed, todays, next],
      todayWorkout: ended ? null : todays,
      completionPct: 0,
      currentWeekIndex: 1,
    );
  }

  @override
  Future<void> answerMissedWorkouts({
    required String planId,
    required List<String> workoutIds,
    Map<String, double> distances = const {},
  }) async {
    answered.addAll(workoutIds);
  }

  @override
  Future<
      ({
        TrainingPlanRow? plan,
        List<PlanWeekRow> weeks,
        List<PlanWorkoutRow> workouts
      })> fetchPlan(String id) async =>
      (plan: null, weeks: const <PlanWeekRow>[], workouts: const <PlanWorkoutRow>[]);
}

final _dirs = <Directory>[];

Future<Directory> _tmp(String tag) async {
  final d = Directory.systemTemp.createTempSync('dash_missed_$tag');
  _dirs.add(d);
  return d;
}

Future<AppLocalizations> _pump(WidgetTester tester, _Training training) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = Preferences();
  final runStore = LocalRunStore();
  final gymStore = LocalGymStore();
  final foodStore = LocalFoodStore();
  await tester.runAsync(() async {
    await prefs.init();
    await runStore.init(overrideDirectory: await _tmp('runs'));
    await gymStore.init(overrideDirectory: await _tmp('gym'));
    await foodStore.init(overrideDirectory: await _tmp('food'));
  });
  await tester.pumpWidget(MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: DashboardScreen(
      training: training,
      runStore: runStore,
      routeStore: LocalRouteStore(),
      gymStore: gymStore,
      foodStore: foodStore,
      preferences: prefs,
    ),
  ));
  await pumpUntil(tester, () => training.overviewReads > 0,
      describe: 'the plan overview read');
  await tester.pump();
  return AppLocalizations.delegate.load(const Locale('en'));
}

void main() {
  installStoreWriteWatch();
  setUpAll(() => initializeDateFormatting());

  tearDown(() {
    for (final d in _dirs) {
      if (d.existsSync()) d.deleteSync(recursive: true);
    }
    _dirs.clear();
  });

  testWidgets('asks about yesterday above the Today card, and Let it go '
      'answers it', (tester) async {
    final training = _Training();
    final l10n = await _pump(tester, training);

    final prompt = find.byKey(const ValueKey('dashboardMissedPrompt-missed'));
    expect(prompt, findsOneWidget);
    expect(tester.getTopLeft(prompt).dy,
        lessThan(tester.getTopLeft(find.text(l10n.todaysWorkoutToday)).dy));
    expect(find.byKey(const Key('missedPromptMakeUp')), findsNothing);

    final reads = training.overviewReads;
    await tester.tap(find.byKey(const Key('missedPromptLetGo')));
    await pumpUntil(tester, () => training.overviewReads > reads,
        describe: 'Home to re-read its plan');
    await tester.pump();
    expect(training.answered, {'missed'});
    expect(find.byKey(const Key('missedPrompt')), findsNothing);
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('a plan whose dates have run out asks nothing', (tester) async {
    await _pump(tester, _Training(ended: true));
    expect(find.byKey(const Key('missedPrompt')), findsNothing);
  });

  testWidgets('Make it up opens the plan with its make-up previewed',
      (tester) async {
    final training = _Training(longMiss: true);
    await _pump(tester, training);

    await tester.tap(find.byKey(const Key('missedPromptMakeUp')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    final detail =
        tester.widget<PlanDetailScreen>(find.byType(PlanDetailScreen));
    expect(detail.planId, 'plan-1');
    expect(detail.openMakeUp, isTrue);
    expect(training.answered, isEmpty);
  });
}
