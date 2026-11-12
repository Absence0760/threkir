// Home's break offer (decisions § 2128): it outranks the missed-workout
// prompt and the plan nudge while it shows; keeping the plan brings the
// prompt back; after the break is applied the prompt stays quiet; and a cold
// run store on an account that has run shows no offer. Web twin:
// apps/web/tests-e2e/plans/break-reschedule.spec.ts.

import 'dart:io';

import 'package:api_client/api_client.dart';
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
import '../lib/plan_break.dart';
import '../lib/preferences.dart';
import '../lib/screens/dashboard_screen.dart';
import '../lib/training_service.dart';
import '../lib/widgets/plan_break_card.dart';
import 'pump_until.dart';
import 'store_write_watch.dart';

/// Ten build weeks from 30 days ago, no race: a long run on each week's
/// first day (weeks 0 and 1 done) and an easy run on its fourth. Nothing
/// since week 1's long run, so the runner is 22 days into a break.
class _Training extends TrainingService {
  int overviewReads = 0;
  final acked = <String>{};
  final calls = <BreakChange>[];

  DateTime get _today {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  @override
  Future<ActivePlanOverview?> fetchActiveOverview() async {
    overviewReads++;
    final start = _today.subtract(const Duration(days: 30));
    final weeks = [
      for (var i = 0; i < 10; i++)
        PlanWeekRow(
            id: 'w$i',
            planId: 'plan-1',
            weekIndex: i,
            phase: 'build',
            targetVolumeM: 20000),
    ];
    final workouts = [
      for (var i = 0; i < 10; i++) ...[
        PlanWorkoutRow(
          id: 'long$i',
          weekId: 'w$i',
          scheduledDate: start.add(Duration(days: 7 * i)),
          kind: 'long',
          targetDistanceM: 14000,
          manuallyCompleted: i <= 1,
          missedAckAt: acked.contains('long$i') ? DateTime.now() : null,
        ),
        PlanWorkoutRow(
          id: 'easy$i',
          weekId: 'w$i',
          scheduledDate: start.add(Duration(days: 7 * i + 3)),
          kind: 'easy',
          targetDistanceM: 6000,
          manuallyCompleted: false,
          missedAckAt: acked.contains('easy$i') ? DateTime.now() : null,
        ),
      ],
    ];
    return ActivePlanOverview(
      plan: TrainingPlanRow(
        id: 'plan-1',
        userId: 'u1',
        name: 'Base Block',
        goalEvent: 'distance_10k',
        goalDistanceM: 10000,
        startDate: start,
        endDate: start.add(const Duration(days: 69)),
        daysPerWeek: 3,
        status: 'active',
        source: 'generated',
        isTemplate: false,
        isPublicTemplate: false,
      ),
      weeks: weeks,
      workouts: workouts,
      todayWorkout: null,
      completionPct: 0,
      currentWeekIndex: 4,
    );
  }

  /// What the RPC does to the prompt: every open workout the break covered
  /// is answered in the same transaction.
  @override
  Future<void> reschedulePlanAfterBreak(String planId, BreakChange change,
      String breakFromIso, String todayIso) async {
    calls.add(change);
    for (var i = 0; i < 5; i++) {
      if (i > 1) acked.add('long$i');
      acked.add('easy$i');
    }
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

/// An account the server says has run, so a device whose run store is still
/// empty does not know this runner's runs yet.
class _HasRunApi extends ApiClient {
  @override
  String? get userId => 'u1';

  @override
  Future<List<({Map<String, dynamic> workout, List<Map<String, dynamic>> sets})>>
      fetchGymWorkoutsWithSets({int limit = 50}) async => const [];

  @override
  Future<List<Run>> getRuns({int limit = 50, DateTime? before}) async => [
        Run(
          id: 'r0',
          startedAt: DateTime.now().subtract(const Duration(days: 2)),
          duration: const Duration(minutes: 30),
          distanceMetres: 5000,
          source: RunSource.app,
        ),
      ];

  @override
  Future<List<FoodLogRow>> fetchFoodLog(
          {required DateTime from, required DateTime to}) async =>
      const [];

  @override
  Future<List<PersonalRecordRow>> fetchPersonalRecords() async => const [];

  @override
  Future<UserProfileRow?> fetchMyProfile() async => null;
}

final _dirs = <Directory>[];

Future<Directory> _tmp(String tag) async {
  final d = Directory.systemTemp.createTempSync('dash_break_$tag');
  _dirs.add(d);
  return d;
}

Object? _pref;
final _writes = <Map<String, dynamic>>[];

Future<void> _pump(WidgetTester tester, _Training training,
    {ApiClient? api, bool gymSession = false}) async {
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
    if (gymSession) {
      await gymStore.createLocal(
          startedAt: DateTime.now().subtract(const Duration(days: 40)));
    }
  });
  tester.view.physicalSize = const Size(420, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: DashboardScreen(
      apiClient: api,
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
}

final _missedPrompt = find.byKey(const Key('missedPrompt'));
final _breakCard = find.byKey(const Key('dashboardPlanBreak'));

void main() {
  installStoreWriteWatch();
  setUpAll(() => initializeDateFormatting());

  setUp(() {
    _pref = null;
    _writes.clear();
    planBreakDismissalReader = () => (loaded: true, value: _pref);
    planBreakDismissalWriter = (v) async {
      _writes.add(v);
      _pref = v;
    };
  });

  tearDown(() {
    for (final d in _dirs) {
      if (d.existsSync()) d.deleteSync(recursive: true);
    }
    _dirs.clear();
  });

  testWidgets('the break offer outranks the missed prompt and the plan nudge',
      (tester) async {
    await _pump(tester, _Training());
    expect(_breakCard, findsOneWidget);
    expect(_missedPrompt, findsNothing);
    expect(find.byKey(const Key('planNudgeCard')), findsNothing);
  });

  testWidgets('keeping the plan as it is brings the missed prompt back',
      (tester) async {
    await _pump(tester, _Training());
    await tester.tap(find.byKey(const Key('planBreakDismiss')));
    await tester.pump();
    await tester.pump();
    expect(_writes.single['plan_id'], 'plan-1');
    expect(_writes.single['until'], isA<String>());
    expect(_breakCard, findsNothing);
    expect(_missedPrompt, findsOneWidget);
  });

  testWidgets('after the break is applied the missed prompt stays quiet',
      (tester) async {
    final training = _Training();
    await _pump(tester, training);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await tester.tap(find.byKey(const Key('planBreakRepeat')));
    await tester.pumpAndSettle();
    final reads = training.overviewReads;
    await tester.tap(find.text(l10n.planBreakConfirmApply));
    await pumpUntil(tester, () => training.overviewReads > reads,
        describe: 'Home to re-read its plan');
    await tester.pump();
    expect(training.calls.single.repeatWeekIds, ['w4']);
    expect(_breakCard, findsNothing);
    expect(_missedPrompt, findsNothing);
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('a cold run store on an account that has run shows no offer',
      (tester) async {
    await _pump(tester, _Training(), api: _HasRunApi(), gymSession: true);
    await pumpUntil(tester, () => tester.any(_missedPrompt),
        describe: 'the plan cards once the account history is known');
    expect(_breakCard, findsNothing);
    await pumpUntilStoreWritesSettle(tester);
  });
}
