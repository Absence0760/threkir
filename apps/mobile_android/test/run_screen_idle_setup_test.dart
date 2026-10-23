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
import '../lib/screens/run_screen.dart';
import '../lib/social_service.dart';
import '../lib/training_service.dart';
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

/// No plan behind the workout, so no backend round-trip.
class _NoPlanTraining extends TrainingService {
  @override
  Future<cm.TrainingPlanRow?> fetchPlanForWorkout(cm.PlanWorkoutRow wo) async =>
      null;
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
  }) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = Preferences();
    await prefs.init();
    await markPreRunDialogsSeen(prefs);
    final runStore = _CapturingRunStore();
    await runStore.init(overrideDirectory: runsDir);
    final social = SocialService();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: RunStopDock(
          docked: true,
          child: RunScreen(
            apiClient: null,
            runStore: runStore,
            routeStore: LocalRouteStore(),
            preferences: prefs,
            audioCues: AudioCues(),
            social: social,
            raceController: RaceController(social),
            training: _NoPlanTraining(),
            heartRate: BleHeartRate(),
            treadmill: BleTreadmill(),
            initialWorkout: initialWorkout,
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
}
