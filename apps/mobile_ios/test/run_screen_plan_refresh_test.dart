import 'dart:io';

import 'package:core_models/core_models.dart'
    show PlanWeekRow, PlanWorkoutRow, TrainingPlanRow;
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../lib/audio_cues.dart';
import '../lib/ble_heart_rate.dart';
import '../lib/ble_treadmill.dart';
import '../lib/fab_clearance.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/local_route_store.dart';
import '../lib/local_run_store.dart';
import '../lib/preferences.dart';
import '../lib/race_controller.dart';
import '../lib/run_upload_signal.dart';
import '../lib/screens/run_screen.dart';
import '../lib/social_service.dart';
import '../lib/training_service.dart';
import '../lib/widgets/todays_workout_card.dart';
import 'pump_until.dart';

// A plain run that covers today's plan workout is linked to it by the server
// as the row is written (decisions § 2079), so nothing on the phone writes to
// the plan. The Run page is kept alive behind the other tabs, and its card
// used to keep offering "Start workout" for a session Home already showed as
// done. These pin the three things that now re-read it: a run reaching the
// server, the page coming back into view, and the app resuming.

const _startKey = Key('todaysWorkoutStart');
const _debounce = Duration(milliseconds: 600);

bool _supabaseReady = false;
late Directory _runsDir;

Future<void> _ensureSupabase() async {
  if (_supabaseReady) return;
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  await Supabase.initialize(
    url: 'http://127.0.0.1:24321',
    anonKey: 'eyJ.local.test',
  );
  _supabaseReady = true;
}

/// Serves today's 4 mi easy run, unmatched until [linkRun] is called.
class _MatchingTraining extends TrainingService {
  String? _completedRunId;
  int fetches = 0;

  void linkRun(String runId) => _completedRunId = runId;

  @override
  Future<ActivePlanOverview?> fetchActiveOverview() async {
    fetches++;
    final today = DateTime.now();
    final workout = PlanWorkoutRow(
      id: 'wo-1',
      weekId: 'wk-1',
      scheduledDate: today,
      kind: 'easy',
      targetDistanceM: 6437,
      manuallyCompleted: false,
      completedRunId: _completedRunId,
    );
    return ActivePlanOverview(
      plan: TrainingPlanRow(
        id: 'plan-1',
        userId: 'u1',
        name: 'Richmond Marathon block',
        goalEvent: 'marathon',
        goalDistanceM: 42195,
        startDate: today.subtract(const Duration(days: 30)),
        endDate: today.add(const Duration(days: 30)),
        daysPerWeek: 5,
        status: 'active',
        source: 'app',
        isTemplate: false,
        isPublicTemplate: false,
      ),
      weeks: [
        PlanWeekRow(
          id: 'wk-1',
          planId: 'plan-1',
          weekIndex: 4,
          phase: 'build',
          targetVolumeM: 60000,
        ),
      ],
      workouts: [workout],
      todayWorkout: workout,
      completionPct: 50,
      currentWeekIndex: 4,
    );
  }
}

Future<void> _pump(
  WidgetTester tester,
  _MatchingTraining training, {
  ValueListenable<bool>? shown,
}) async {
  tester.view.devicePixelRatio = 3.0;
  tester.view.physicalSize = const Size(400, 900) * 3.0;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  final prefs = Preferences();
  await tester.runAsync(prefs.init);
  _runsDir = Directory.systemTemp.createTempSync('run_plan_refresh_test_');
  final runStore = LocalRunStore();
  await tester.runAsync(() => runStore.init(overrideDirectory: _runsDir));
  final social = SocialService();
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: DockedFabInset(
          height: kDockedFabOverhang,
          child: RunScreen(
            apiClient: null,
            runStore: runStore,
            routeStore: LocalRouteStore(),
            preferences: prefs,
            audioCues: AudioCues(),
            social: social,
            raceController: RaceController(social),
            training: training,
            heartRate: BleHeartRate(),
            treadmill: BleTreadmill(),
            shown: shown,
          ),
        ),
      ),
    ),
  );
  await pumpUntil(
    tester,
    () => find.byType(TodaysWorkoutCard).evaluate().isNotEmpty,
    describe: "today's plan workout card to load",
  );
}

Future<void> _waitForFetches(
  WidgetTester tester,
  _MatchingTraining training,
  int count,
) async {
  await tester.pump(_debounce);
  await pumpUntil(
    tester,
    () => training.fetches >= count,
    describe: '$count plan overview reads',
  );
  await tester.pump();
}

void main() {
  setUpAll(_ensureSupabase);

  tearDown(() {
    if (_runsDir.existsSync()) _runsDir.deleteSync(recursive: true);
  });

  testWidgets('the card flips to done once a run reaches the server', (
    tester,
  ) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    final training = _MatchingTraining();
    final landed = RunUploadSignal();
    training.followRunsLanded(landed);
    await _pump(tester, training);

    expect(find.byKey(_startKey), findsOneWidget);
    expect(find.text(l10n.todaysWorkoutDone), findsNothing);

    training.linkRun('run-4mi');
    landed.fire();
    await _waitForFetches(tester, training, 2);

    expect(find.byKey(_startKey), findsNothing);
    expect(find.text(l10n.todaysWorkoutDone), findsOneWidget);
  });

  testWidgets('coming back to the Run page re-reads the plan', (tester) async {
    final training = _MatchingTraining();
    final shown = ValueNotifier<bool>(true);
    addTearDown(shown.dispose);
    await _pump(tester, training, shown: shown);
    final afterOpen = training.fetches;

    shown.value = false;
    await tester.pump(_debounce);
    expect(
      training.fetches,
      afterOpen,
      reason: 'leaving the page must not spend a read',
    );

    training.linkRun('run-from-web');
    shown.value = true;
    await _waitForFetches(tester, training, afterOpen + 1);

    expect(find.byKey(_startKey), findsNothing);
  });

  testWidgets('resuming the app re-reads the plan while the page shows', (
    tester,
  ) async {
    final training = _MatchingTraining();
    await _pump(tester, training);
    final afterOpen = training.fetches;

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    training.linkRun('run-from-watch');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _waitForFetches(tester, training, afterOpen + 1);

    expect(find.byKey(_startKey), findsNothing);
  });

  testWidgets('resuming on another tab leaves the hidden page alone', (
    tester,
  ) async {
    final training = _MatchingTraining();
    final shown = ValueNotifier<bool>(false);
    addTearDown(shown.dispose);
    await _pump(tester, training, shown: shown);
    final afterOpen = training.fetches;

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(_debounce);

    expect(training.fetches, afterOpen);
  });
}
