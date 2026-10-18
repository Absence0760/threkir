import 'dart:async';
import 'dart:io';

import 'package:core_models/core_models.dart' as cm;
import 'package:core_models/core_models.dart' show DistanceUnit;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:run_recorder/run_recorder.dart' show WorkoutStep;
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
import '../lib/run_haptics_bridge.dart';
import '../lib/screens/run_screen.dart';
import '../lib/social_service.dart';
import '../lib/training_service.dart';
import '../lib/widgets/workout_execution_band.dart';
import 'pre_run_dialogs.dart';
import 'pump_until.dart';

/// Drives the REAL RunScreen with a planned workout through the REAL recorder
/// tick and asserts the step changes reach `run_app/haptics` (issue #1186):
/// the first snapshot enters the warm-up, a skip enters the rep. Each gate is
/// pinned too — the per-device setting silences it, and turning the voice off
/// does NOT, because the buzz is the non-audio cue.

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
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) {
    _positions ??= StreamController<Position>.broadcast();
    return _positions!.stream;
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

class _SilentAudioCues extends AudioCues {
  @override
  Future<void> announceStart() async {}

  @override
  Future<void> announceWorkoutStepTransition(
      WorkoutStep step, DistanceUnit unit) async {}

  @override
  Future<void> announceFinish({
    required double distanceMetres,
    required Duration elapsed,
    required DistanceUnit unit,
  }) async {}
}

class _CapturingRunStore extends LocalRunStore {
  @override
  Future<cm.Run> save(run) async => run;

  @override
  Future<void> saveInProgress(run) async {}

  @override
  Future<void> clearInProgress() async {}
}

/// No plan behind the workout, so no backend round-trip: the runner falls
/// back to its default paces.
class _NoPlanTraining extends TrainingService {
  @override
  Future<cm.TrainingPlanRow?> fetchPlanForWorkout(cm.PlanWorkoutRow wo) async =>
      null;
}

final _workout = cm.PlanWorkoutRow(
  id: 'wo-haptics',
  weekId: 'wk-1',
  scheduledDate: DateTime(2026, 10, 18),
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

void main() {
  late _FakeGeolocatorPlatform geolocator;
  late Directory runsDir;
  late List<Object?> played;
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
    played = [];

    mock(const MethodChannel('flutter.baseflow.com/permissions/methods'),
        (call) async {
      if (call.arguments is List) {
        return {for (final p in (call.arguments as List)) p: 1};
      }
      return 1;
    });
    mock(const MethodChannel('flutter_tts'), (call) async => 1);
    mock(const MethodChannel('run_app/run_notification'), (call) async => null);
    mock(const MethodChannel('step_count'), (call) async => null);
    mock(const MethodChannel('step_detection'), (call) async => null);
    mock(const MethodChannel(RunHapticsBridge.channelName), (call) async {
      if (call.method == 'play') played.add(call.arguments);
      return true;
    });

    runsDir = Directory.systemTemp.createTempSync('run_screen_haptics_');
  });

  tearDown(() async {
    for (final c in mocked) {
      messenger().setMockMethodCallHandler(c, null);
    }
    mocked.clear();
    await geolocator.dispose();
    if (runsDir.existsSync()) runsDir.deleteSync(recursive: true);
  });

  Future<void> pumpRunScreen(
    WidgetTester tester, {
    Future<void> Function(Preferences prefs)? configure,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = Preferences();
    await prefs.init();
    await markPreRunDialogsSeen(prefs);
    await configure?.call(prefs);

    final runStore = _CapturingRunStore();
    await runStore.init(overrideDirectory: runsDir);
    final social = SocialService();

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: RunScreen(
          apiClient: null,
          runStore: runStore,
          routeStore: LocalRouteStore(),
          preferences: prefs,
          audioCues: _SilentAudioCues(),
          social: social,
          raceController: RaceController(social),
          training: _NoPlanTraining(),
          heartRate: BleHeartRate(),
          treadmill: BleTreadmill(),
          initialWorkout: _workout,
        ),
      ),
    );
    await tester.pump();
  }

  /// START → countdown → recording, then [ticks] further recorder snapshots.
  Future<void> startRecording(WidgetTester tester, {int ticks = 3}) async {
    await tester.tap(find.text('START'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    tester.takeException();
    for (var i = 0; i < ticks; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    tester.takeException();
  }

  Future<void> skipStep(WidgetTester tester) async {
    tester.widget<WorkoutExecutionBand>(find.byType(WorkoutExecutionBand))
        .onSkip();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  Future<void> stop(WidgetTester tester) async {
    // Unmount so the recorder's periodic tick stops before the test ends.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  testWidgets('entering a step and skipping to the next one both vibrate',
      (tester) async {
    await pumpRunScreen(tester);
    await startRecording(tester);
    await pumpUntil(tester, () => played.isNotEmpty,
        describe: 'the warm-up step to reach the vibration channel');
    expect(played, ['step_ease'],
        reason: 'the first snapshot enters the warm-up, once');

    await skipStep(tester);
    await pumpUntil(tester, () => played.length == 2,
        describe: 'the skip into rep 1 to reach the vibration channel');
    expect(played, ['step_ease', 'step_work']);
    await stop(tester);
  });

  testWidgets('the vibration setting silences it', (tester) async {
    await pumpRunScreen(tester,
        configure: (prefs) => prefs.setHapticFeedback(false));
    await startRecording(tester);
    await skipStep(tester);
    await tester.pump(const Duration(seconds: 1));
    expect(played, isEmpty);
    await stop(tester);
  });

  testWidgets('voice off still vibrates — it is the non-audio cue',
      (tester) async {
    await pumpRunScreen(tester, configure: (prefs) async {
      await prefs.setAudioCues(false);
      await prefs.setVoiceFeedbackVerbosity('minimal');
    });
    await startRecording(tester);
    await pumpUntil(tester, () => played.isNotEmpty,
        describe: 'the warm-up buzz with the voice off');
    expect(played, ['step_ease']);
    await stop(tester);
  });
}
