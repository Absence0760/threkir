import 'dart:io';

import 'package:core_models/core_models.dart' as cm;
import 'package:core_models/core_models.dart'
    show PlanWeekRow, PlanWorkoutRow, TrainingPlanRow;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
import 'pump_until.dart';
import 'supabase_test_init.dart';

// The idle Start used to end the scroll, below every auxiliary card, and the
// stack outgrew a phone, so Start sat under the bottom bar until the runner
// scrolled for it. These cases pin it to the visible area above the bar and a
// docked centre FAB. On the phone shell the docked centre button is itself the
// Start (RunStopDock, issue #1374), so the panel's own circle is what a recorder
// shows with nothing docked: the rail layout, or the keyboard up. That circle
// is what these cases measure; the docked case is in
// run_screen_recording_flow_test.dart.

const _startKey = ValueKey('run-idle-start');
const _navKey = ValueKey('test-bottom-bar');
const _fabKey = ValueKey('test-docked-fab');

bool _supabaseReady = false;
late Directory _runsDir;

Future<void> _ensureSupabase() async {
  if (_supabaseReady) return;
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  await initializeTestSupabase();
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

final _route = cm.Route(
  id: 'route-river',
  userId: 'u1',
  name: 'River loop',
  distanceMetres: 5000,
  waypoints: const [
    cm.Waypoint(lat: 47.37, lng: 8.54),
    cm.Waypoint(lat: 47.371, lng: 8.541),
    cm.Waypoint(lat: 47.372, lng: 8.543),
  ],
);

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
    initialRoute: _route,
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
    () => find.text('Richmond Marathon block').evaluate().isNotEmpty,
    describe: 'the plan chip to load',
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
      'Start stays visible above the tabs with a followed route showing '
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
    final lastCard = find.text(_route.name);
    await tester.ensureVisible(lastCard);
    await tester.pump();
    final start = tester.getRect(find.byKey(_startKey));
    expect(
      tester.getRect(lastCard).bottom,
      lessThanOrEqualTo(start.top),
      reason:
          'the auxiliary stack must be reachable above Start, '
          'not hidden behind it',
    );
    expect(lastCard.hitTestable(), findsOneWidget);
    _expectStartClear(tester, logical);
  });

  for (final textScale in const [1.0, 2.0]) {
    testWidgets(
      'the cards scroll on behind Start and the last one clears it '
      '(360x640, text x$textScale)',
      (tester) async {
        const logical = Size(360, 640);
        _useSurface(tester, logical);
        await _pumpIdle(tester, textScale);
        final scroll = find.byKey(const ValueKey('run-idle-scroll'));
        final start = tester.getRect(find.byKey(_startKey));
        expect(
          tester.getRect(scroll).bottom,
          greaterThan(start.bottom),
          reason: 'the scroll must run on behind Start, not end above it',
        );

        final startSize = tester.getSize(find.byKey(_startKey)).height;
        final padding = tester
            .widget<SingleChildScrollView>(scroll)
            .padding!
            .resolve(TextDirection.ltr);
        expect(
          padding.bottom,
          greaterThanOrEqualTo(
            idleStartAreaHeight(startSize, kDockedFabOverhang),
          ),
          reason: 'the scroll must leave room for the area Start floats in',
        );

        final position = tester
            .state<ScrollableState>(
              find.descendant(of: scroll, matching: find.byType(Scrollable)),
            )
            .position;
        position.jumpTo(position.maxScrollExtent);
        await tester.pump();
        final lastCard = find.text(_route.name);
        expect(
          tester.getRect(lastCard).bottom,
          lessThanOrEqualTo(tester.getRect(find.byKey(_startKey)).top),
          reason: 'at the end of the scroll the last card sits above Start',
        );
        expect(lastCard.hitTestable(), findsOneWidget);
        _expectStartClear(tester, logical);
      },
    );
  }

  testWidgets('the fade over the cards lets taps through', (tester) async {
    const logical = Size(360, 640);
    _useSurface(tester, logical);
    await _pumpIdle(tester, 1.0);
    final scrim = find.byKey(const ValueKey('run-idle-start-scrim'));
    expect(tester.widget<IgnorePointer>(scrim).ignoring, isTrue);
    final scrimRect = tester.getRect(scrim);
    final start = tester.getRect(find.byKey(_startKey));
    expect(scrimRect.top, lessThan(start.top));
    expect(scrimRect.bottom, greaterThanOrEqualTo(start.bottom));
    // A point in the fade beside Start lands on the scroll beneath it.
    final beside = Offset(scrimRect.left + 8, scrimRect.top + 8);
    final result = tester.hitTestOnBinding(beside);
    final scrollBox = tester.renderObject(
      find.byKey(const ValueKey('run-idle-scroll')),
    );
    expect(
      result.path.any((entry) => entry.target == scrollBox),
      isTrue,
      reason: 'a tap on the fade must reach the cards behind it',
    );
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
