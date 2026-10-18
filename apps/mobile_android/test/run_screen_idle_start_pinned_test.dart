import 'dart:io';

import 'package:core_models/core_models.dart' as cm;
import 'package:core_models/core_models.dart'
    show PlanWeekRow, PlanWorkoutRow, TrainingPlanRow;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import '../lib/screens/home_screen.dart' show bottomNavMetrics;
import '../lib/screens/run_screen.dart';
import '../lib/social_service.dart';
import '../lib/training_service.dart';
import '../lib/widgets/todays_workout_card.dart';
import 'pump_until.dart';

// The idle Start used to end the scroll, below every auxiliary card. With a
// plan workout due today and a recent run on file the stack outgrew a phone
// and Start sat under the bottom bar until the runner scrolled for it. These
// cases pin it to the visible area above the bar and the docked centre FAB.

const _startKey = ValueKey('run-idle-start');
const _navKey = ValueKey('test-bottom-bar');
const _fabKey = ValueKey('test-docked-fab');

bool _supabaseReady = false;
late Directory _runsDir;

Future<void> _ensureSupabase() async {
  if (_supabaseReady) return;
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  // supabase_flutter opens an app_links deep-link stream on init. The mount
  // runs under runAsync, so without a stub the real event loop turns and the
  // MissingPluginException lands as an unhandled error in the first case.
  for (final name in const [
    'com.llfbandit.app_links/events',
    'com.llfbandit.app_links/messages',
  ]) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            MethodChannel(name, const StandardMethodCodec()),
            (call) async => null);
  }
  await Supabase.initialize(
    url: 'http://127.0.0.1:24321',
    anonKey: 'eyJ.local.test',
  );
  _supabaseReady = true;
}

class _TodayPlanTraining extends TrainingService {
  @override
  Future<ActivePlanOverview?> fetchActiveOverview() async {
    final today = DateTime.now();
    final workout = PlanWorkoutRow(
      id: 'wo-1',
      weekId: 'wk-1',
      scheduledDate: today,
      kind: 'tempo',
      targetDistanceM: 10000,
      targetPaceSecPerKm: 300,
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

Future<RunScreen> _screen(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = Preferences();
  await tester.runAsync(prefs.init);
  _runsDir = Directory.systemTemp.createTempSync('run_idle_start_test_');
  final runStore = LocalRunStore();
  await tester.runAsync(() async {
    await runStore.init(overrideDirectory: _runsDir);
    await runStore.save(
      cm.Run(
        id: 'last-run-1',
        startedAt: DateTime.now().subtract(const Duration(hours: 20)),
        duration: const Duration(minutes: 30),
        distanceMetres: 5000,
        source: cm.RunSource.app,
      ),
    );
  });
  final social = SocialService();
  return RunScreen(
    apiClient: null,
    runStore: runStore,
    routeStore: LocalRouteStore(),
    preferences: prefs,
    audioCues: AudioCues(),
    social: social,
    raceController: RaceController(social),
    training: _TodayPlanTraining(),
    heartRate: BleHeartRate(),
    treadmill: BleTreadmill(),
  );
}

/// The phone shell's geometry: a bottom bar sized like the real one for the
/// text scale, and a centre FAB docked on its top edge.
Widget _shell(Widget page, double textScale) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(
      context,
    ).copyWith(textScaler: TextScaler.linear(textScale)),
    child: child!,
  ),
  home: Scaffold(
    body: DockedFabInset(height: kDockedFabOverhang, child: page),
    floatingActionButton: FloatingActionButton(
      key: _fabKey,
      onPressed: () {},
      child: const Icon(Icons.add),
    ),
    floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
    bottomNavigationBar: Builder(
      builder: (context) => BottomAppBar(
        key: _navKey,
        height: bottomNavMetrics(
          MediaQuery.textScalerOf(context).scale(1),
        ).height,
        padding: EdgeInsets.zero,
        child: const SizedBox.expand(),
      ),
    ),
  ),
);

void _useSurface(WidgetTester tester, Size logical) {
  tester.view.devicePixelRatio = 3.0;
  tester.view.physicalSize = logical * 3.0;
  // A status bar and a gesture-navigation inset, in physical pixels.
  tester.view.padding = const FakeViewPadding(top: 72, bottom: 72);
  tester.view.viewPadding = const FakeViewPadding(top: 72, bottom: 72);
  addTearDown(tester.view.reset);
}

Future<void> _pumpIdle(WidgetTester tester, double textScale) async {
  final screen = await _screen(tester);
  await tester.pumpWidget(_shell(screen, textScale));
  await pumpUntil(
    tester,
    () => find.byType(TodaysWorkoutCard).evaluate().isNotEmpty,
    describe: "today's plan workout card to load",
  );
}

void _expectStartClear(WidgetTester tester, Size logical) {
  final start = tester.getRect(find.byKey(_startKey));
  final bar = tester.getRect(find.byKey(_navKey));
  final fab = tester.getRect(find.byKey(_fabKey));
  expect(
    start.top,
    greaterThanOrEqualTo(72 / 3),
    reason: 'Start must sit below the status bar',
  );
  expect(start.left, greaterThanOrEqualTo(0));
  expect(start.right, lessThanOrEqualTo(logical.width));
  expect(
    start.bottom,
    lessThanOrEqualTo(bar.top),
    reason:
        'Start must sit wholly above the bottom bar, got $start '
        'against a bar at ${bar.top}',
  );
  expect(
    start.overlaps(fab),
    isFalse,
    reason: 'the docked centre FAB must not cover Start ($start vs $fab)',
  );
  expect(
    find.byKey(_startKey).hitTestable(),
    findsOneWidget,
    reason: 'a tap on Start must land on Start',
  );
}

void main() {
  setUpAll(_ensureSupabase);

  tearDown(() {
    if (_runsDir.existsSync()) _runsDir.deleteSync(recursive: true);
  });

  for (final textScale in const [1.0, 1.3, 2.0]) {
    testWidgets(
      'Start stays visible above the tabs with a plan workout showing '
      '(360x640, text x$textScale)',
      (tester) async {
        const logical = Size(360, 640);
        _useSurface(tester, logical);
        await _pumpIdle(tester, textScale);
        _expectStartClear(tester, logical);
      },
    );
  }

  testWidgets('the last card scrolls clear of the pinned Start', (
    tester,
  ) async {
    const logical = Size(360, 640);
    _useSurface(tester, logical);
    await _pumpIdle(tester, 2.0);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    final lastRun = find.text(l10n.runLastRun);
    await tester.ensureVisible(lastRun);
    await tester.pump();
    final start = tester.getRect(find.byKey(_startKey));
    expect(
      tester.getRect(lastRun).bottom,
      lessThanOrEqualTo(start.top),
      reason:
          'the auxiliary stack must be reachable above Start, '
          'not hidden behind it',
    );
    expect(lastRun.hitTestable(), findsOneWidget);
    _expectStartClear(tester, logical);
  });

  testWidgets('a landscape phone still shows Start, smaller', (tester) async {
    const logical = Size(640, 360);
    _useSurface(tester, logical);
    await _pumpIdle(tester, 1.0);
    _expectStartClear(tester, logical);
    expect(tester.getSize(find.byKey(_startKey)).height, lessThan(140));
  });

  group('idleStartButtonSize', () {
    test('is the designed 140 when there is room', () {
      expect(idleStartButtonSize(800), 140);
      expect(idleStartButtonSize(double.infinity), 140);
    });

    test('gives way on a short view but keeps a floor', () {
      expect(idleStartButtonSize(400), closeTo(112, 0.001));
      expect(idleStartButtonSize(200), 96);
    });
  });
}
