import 'dart:async';
import 'dart:io';

import 'package:core_models/core_models.dart' as cm;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wakelock_plus_platform_interface/wakelock_plus_platform_interface.dart';

import '../lib/audio_cues.dart';
import '../lib/ble_heart_rate.dart';
import '../lib/ble_treadmill.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/local_route_store.dart';
import '../lib/local_run_store.dart';
import '../lib/preferences.dart';
import '../lib/race_controller.dart';
import '../lib/run_stop_dock.dart';
import '../lib/screens/route_picker_screen.dart';
import '../lib/screens/run_screen.dart';
import '../lib/social_service.dart';
import '../lib/training_service.dart';
import '../lib/widgets/todays_workout_card.dart';
import '../lib/widgets/top_banner.dart' show kTopBannerMaxDuration;
import 'pre_run_dialogs.dart';
import 'pump_until.dart';

/// The Run start screen's setup state (issue #1226): what the runner loads
/// before GO must be visible, removable, and must not outlive the run it was
/// loaded for. Driven through the REAL recorder, because the workout leak only
/// shows in what the save path writes.

class _FakeGeolocatorPlatform extends GeolocatorPlatform {
  StreamController<Position>? _positions;

  @override
  Future<bool> isLocationServiceEnabled() async => true;

  @override
  Future<LocationPermission> checkPermission() async =>
      LocationPermission.always;

  @override
  Future<LocationPermission> requestPermission() async =>
      LocationPermission.always;

  @override
  Future<LocationAccuracyStatus> getLocationAccuracy() async =>
      LocationAccuracyStatus.precise;

  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) {
    _positions ??= StreamController<Position>.broadcast();
    return _positions!.stream;
  }

  void emit(Position p) {
    _positions ??= StreamController<Position>.broadcast();
    _positions!.add(p);
  }

  Future<void> dispose() async {
    await _positions?.close();
    _positions = null;
  }
}

class _NoOpWakelock extends WakelockPlusPlatformInterface {
  bool _on = false;

  @override
  bool get isMock => true;

  @override
  Future<void> toggle({required bool enable}) async => _on = enable;

  @override
  Future<bool> get enabled async => _on;
}

class _CapturingRunStore extends LocalRunStore {
  final List<cm.Run> captured = [];

  @override
  Future<cm.Run> save(run) async {
    captured.add(run);
    return run;
  }

  @override
  Future<void> saveInProgress(run) async {}

  @override
  Future<void> clearInProgress() async {}
}

/// No plan behind a loaded workout, so no backend round-trip. With [today]
/// the active plan has that workout scheduled for today.
class _IdleTraining extends TrainingService {
  final cm.PlanWorkoutRow? today;
  _IdleTraining({this.today});

  @override
  Future<cm.TrainingPlanRow?> fetchPlanForWorkout(cm.PlanWorkoutRow wo) async =>
      null;

  @override
  Future<ActivePlanOverview?> fetchActiveOverview() async {
    final wo = today;
    if (wo == null) return null;
    final now = DateTime.now();
    return ActivePlanOverview(
      plan: cm.TrainingPlanRow(
        id: 'plan-1',
        userId: 'u1',
        name: 'Autumn 10K block',
        goalEvent: '10k',
        goalDistanceM: 10000,
        startDate: now.subtract(const Duration(days: 14)),
        endDate: now.add(const Duration(days: 30)),
        daysPerWeek: 4,
        status: 'active',
        source: 'app',
        isTemplate: false,
        isPublicTemplate: false,
      ),
      weeks: [
        cm.PlanWeekRow(
          id: 'wk-1',
          planId: 'plan-1',
          weekIndex: 2,
          phase: 'build',
          targetVolumeM: 30000,
        ),
      ],
      workouts: [wo],
      todayWorkout: wo,
      completionPct: 20,
      currentWeekIndex: 2,
    );
  }
}

final _workout = cm.PlanWorkoutRow(
  id: 'wo-idle-setup',
  weekId: 'wk-1',
  scheduledDate: DateTime(2026, 10, 23),
  kind: 'interval',
  manuallyCompleted: false,
  structure: const <String, dynamic>{
    'warmup': {'distance_m': 1000, 'pace': 'easy'},
    'repeats': {
      'count': 2,
      'rep': {'distance_m': 400, 'pace_sec_per_km': 240},
      'recovery': {'distance_m': 200, 'pace': 'easy'},
    },
    'cooldown': {'distance_m': 1000, 'pace': 'easy'},
  },
);

Position _pos({required double metresEast, required int secondsFromStart}) {
  const metrePerDegLng = 111320 * 0.6773;
  return Position(
    longitude: 8.54 + metresEast / metrePerDegLng,
    latitude: 47.37,
    timestamp: DateTime(2026, 4, 10, 10, 0, secondsFromStart),
    accuracy: 5,
    altitude: 400,
    altitudeAccuracy: 2,
    heading: 90,
    headingAccuracy: 5,
    speed: 6,
    speedAccuracy: 1,
  );
}

final _loop = cm.Route(
  id: 'route-loop',
  userId: 'u1',
  name: 'River loop',
  distanceMetres: 5000,
  waypoints: const [
    cm.Waypoint(lat: 47.37, lng: 8.54),
    cm.Waypoint(lat: 47.371, lng: 8.541),
  ],
);

const _workoutKeys = [
  cm.MetadataKeys.planWorkoutId,
  cm.MetadataKeys.workoutStepResults,
  'workout_adherence',
];

void main() {
  late _FakeGeolocatorPlatform geolocator;
  late Directory runsDir;
  bool supabaseReady = false;

  TestDefaultBinaryMessenger messenger() =>
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final mocked = <MethodChannel>[];

  void mock(MethodChannel channel, Future<Object?> Function(MethodCall) h) {
    messenger().setMockMethodCallHandler(channel, h);
    mocked.add(channel);
  }

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    dotenv.loadFromString(
      envString: 'TILE_URL_TEMPLATE=offline-no-network://tiles/{z}/{x}/{y}.png',
      isOptional: true,
    );
    if (!supabaseReady) {
      await Supabase.initialize(
        url: 'http://127.0.0.1:24321',
        anonKey: 'eyJ.local.test',
      );
      supabaseReady = true;
    }
  });

  setUp(() async {
    geolocator = _FakeGeolocatorPlatform();
    GeolocatorPlatform.instance = geolocator;
    WakelockPlusPlatformInterface.instance = _NoOpWakelock();
    mock(const MethodChannel('flutter.baseflow.com/permissions/methods'),
        (call) async {
      if (call.arguments is List) {
        return {for (final p in (call.arguments as List)) p: 1};
      }
      return 1;
    });
    mock(const MethodChannel('flutter_tts'), (call) async => 1);
    mock(const MethodChannel('run_app/run_notification'), (call) async => null);
    mock(const MethodChannel('run_app/haptics'), (call) async => true);
    mock(const MethodChannel('step_count'), (call) async => null);
    mock(const MethodChannel('step_detection'), (call) async => null);
    runsDir = Directory.systemTemp.createTempSync('run_screen_idle_setup_');
  });

  tearDown(() async {
    for (final c in mocked) {
      messenger().setMockMethodCallHandler(c, null);
    }
    mocked.clear();
    await geolocator.dispose();
    if (runsDir.existsSync()) runsDir.deleteSync(recursive: true);
  });

  Future<_CapturingRunStore> pumpRunScreen(
    WidgetTester tester, {
    cm.PlanWorkoutRow? initialWorkout,
    List<cm.Route> routes = const [],
    cm.Route? initialRoute,
    cm.PlanWorkoutRow? todayWorkout,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = Preferences();
    await prefs.init();
    await markPreRunDialogsSeen(prefs);
    final runStore = _CapturingRunStore();
    await runStore.init(overrideDirectory: runsDir);
    final social = SocialService();
    final routeStore = LocalRouteStore()..debugSeed(routes);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: RunStopDock(
          docked: true,
          child: RunScreen(
            apiClient: null,
            runStore: runStore,
            routeStore: routeStore,
            preferences: prefs,
            audioCues: AudioCues(),
            social: social,
            raceController: RaceController(social),
            training: _IdleTraining(today: todayWorkout),
            heartRate: BleHeartRate(),
            treadmill: BleTreadmill(),
            initialWorkout: initialWorkout,
            initialRoute: initialRoute,
          ),
        ),
      ),
    );
    await tester.pump();
    return runStore;
  }

  Future<void> tapStart(WidgetTester tester) async {
    await tester.tap(find.text('START'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  Future<void> reachRecording(WidgetTester tester) async {
    await tapStart(tester);
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    tester.takeException();
  }

  /// Record a short run, stop it, and close the summary back to idle.
  Future<void> recordAndFinish(
      WidgetTester tester, _CapturingRunStore store) async {
    final before = store.captured.length;
    await reachRecording(tester);
    for (var i = 0; i < 6; i++) {
      geolocator.emit(_pos(metresEast: i * 12.0, secondsFromStart: i * 2));
      await tester.pump(const Duration(milliseconds: 50));
    }
    tester.takeException();
    await tester.runAsync(() async => runStopRequests.request());
    await pumpUntil(tester, () => store.captured.length > before,
        describe: 'the stop to save the run');
    await pumpUntil(tester, () => runSummaryShowing.value,
        describe: 'the finished summary');
    runSummaryDismissRequests.request();
    await tester.pump();
    expect(find.text('START'), findsOneWidget);
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    tester.takeException();
  }

  group('a loaded plan workout', () {
    testWidgets('is spent by the run it was loaded for, so the next run '
        'carries no workout metadata', (tester) async {
      final store = await pumpRunScreen(tester, initialWorkout: _workout);

      await recordAndFinish(tester, store);
      expect(store.captured.single.metadata?[cm.MetadataKeys.planWorkoutId],
          _workout.id,
          reason: 'the workout run is linked to its workout');

      await recordAndFinish(tester, store);
      final second = store.captured.last.metadata ?? const {};
      for (final key in _workoutKeys) {
        expect(second.containsKey(key), isFalse,
            reason: 'the second run never ran the workout, so "$key" '
                'must not link it there');
      }
      await unmount(tester);
    });

    testWidgets('survives a cancelled countdown, so the run that follows is '
        'still the workout run', (tester) async {
      final store = await pumpRunScreen(tester, initialWorkout: _workout);

      await tapStart(tester);
      // Tap-anywhere on the countdown scrim cancels back to idle.
      await tester.tapAt(const Offset(200, 200));
      await tester.pump();
      expect(find.text('START'), findsOneWidget);

      await recordAndFinish(tester, store);
      expect(store.captured.single.metadata?[cm.MetadataKeys.planWorkoutId],
          _workout.id);
      await unmount(tester);
    });
  });

  group('the followed route', () {
    Future<void> openPicker(WidgetTester tester) async {
      await tester.tap(find.text('Change route'));
      await tester.pumpAndSettle();
      expect(find.byType(RoutePickerScreen), findsOneWidget);
    }

    testWidgets('survives backing out of the picker', (tester) async {
      await pumpRunScreen(tester, routes: [_loop], initialRoute: _loop);
      expect(find.text('FOLLOWING'), findsOneWidget);

      await openPicker(tester);
      // System back, the gesture a runner uses to leave a list.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('FOLLOWING'), findsOneWidget,
          reason: 'looking at the list and backing out changes nothing');
      expect(find.text('River loop'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('is cleared by "No route"', (tester) async {
      await pumpRunScreen(tester, routes: [_loop], initialRoute: _loop);

      await openPicker(tester);
      await tester.tap(find.descendant(
          of: find.byType(AppBar), matching: find.text('No route')));
      await tester.pumpAndSettle();

      expect(find.text('FOLLOWING'), findsNothing);
      expect(find.text('Choose route'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('is cleared by the x on its card, with no confirm',
        (tester) async {
      await pumpRunScreen(tester, routes: [_loop], initialRoute: _loop);

      final clear = find.byTooltip('Remove route');
      expect(clear, findsOneWidget);
      expectTouchTarget(tester, clear);
      await tester.tap(clear);
      await tester.pump();

      expect(find.byType(AlertDialog), findsNothing,
          reason: 'picking the route again undoes it, so nothing to confirm');
      expect(find.text('FOLLOWING'), findsNothing);
      expect(find.text('River loop'), findsNothing);
      expect(find.text('Choose route'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('opens the picker when its card is tapped', (tester) async {
      await pumpRunScreen(tester, routes: [_loop], initialRoute: _loop);

      await tester.tap(find.text('FOLLOWING'));
      await tester.pumpAndSettle();
      expect(find.byType(RoutePickerScreen), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('FOLLOWING'), findsOneWidget);
      await unmount(tester);
    });
  });

  group('the loaded-workout card', () {
    testWidgets('shows the workout the next run will execute',
        (tester) async {
      await pumpRunScreen(tester, initialWorkout: _workout);
      await pumpUntil(tester,
          () => find.text('Workout loaded: Intervals').evaluate().isNotEmpty,
          describe: 'the loaded-workout card');
      await unmount(tester);
    });

    testWidgets('its x unloads the workout, so the run that follows is a '
        'free run', (tester) async {
      final store = await pumpRunScreen(tester, initialWorkout: _workout);
      await pumpUntil(tester,
          () => find.text('Workout loaded: Intervals').evaluate().isNotEmpty,
          describe: 'the loaded-workout card');

      final unload = find.byTooltip('Unload workout');
      expectTouchTarget(tester, unload);
      await tester.tap(unload);
      await tester.pump();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Workout loaded: Intervals'), findsNothing);

      await recordAndFinish(tester, store);
      final meta = store.captured.single.metadata ?? const {};
      for (final key in _workoutKeys) {
        expect(meta.containsKey(key), isFalse, reason: key);
      }
      await unmount(tester);
    });

    testWidgets("loading today's workout swaps its card for the loaded one",
        (tester) async {
      await pumpRunScreen(tester, todayWorkout: _workout);
      await pumpUntil(
          tester, () => find.byType(TodaysWorkoutCard).evaluate().isNotEmpty,
          describe: "today's workout card");

      await tester.tap(find.byKey(const Key('todaysWorkoutStart')));
      await pumpUntil(tester,
          () => find.text('Workout loaded: Intervals').evaluate().isNotEmpty,
          describe: 'the loaded-workout card');
      expect(find.byType(TodaysWorkoutCard), findsNothing,
          reason: 'one card for one workout');

      await tester.tap(find.byTooltip('Unload workout'));
      await tester.pump();
      expect(find.byType(TodaysWorkoutCard), findsOneWidget,
          reason: 'unloaded, the workout is offered again');
      // Let the "workout loaded" banner's timer run out.
      await tester.pump(kTopBannerMaxDuration);
      await unmount(tester);
    });
  });

  group('the card stack', () {
    testWidgets("a followed route keeps today's workout card on screen",
        (tester) async {
      await pumpRunScreen(tester,
          routes: [_loop], initialRoute: _loop, todayWorkout: _workout);
      await pumpUntil(
          tester, () => find.byType(TodaysWorkoutCard).evaluate().isNotEmpty,
          describe: "today's workout card");

      expect(find.text('FOLLOWING'), findsOneWidget);
      expect(find.byType(TodaysWorkoutCard), findsOneWidget,
          reason: 'a runner on their route on a plan day still needs the '
              'card that loads the workout');
      await unmount(tester);
    });
  });
}

/// Material's 48 dp minimum interactive size, measured on the button that
/// owns [finder] (a tooltip wraps only the 40 dp visual, not the padded
/// target around it).
void expectTouchTarget(WidgetTester tester, Finder finder) {
  final button = find.ancestor(of: finder, matching: find.byType(IconButton));
  final size = tester.getSize(button.first);
  expect(size.width, greaterThanOrEqualTo(48), reason: 'target width');
  expect(size.height, greaterThanOrEqualTo(48), reason: 'target height');
}
