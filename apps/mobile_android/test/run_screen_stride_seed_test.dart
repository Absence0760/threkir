import 'dart:async';
import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart' hide Route;
import 'package:flutter/material.dart' hide Route;
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
import '../lib/screens/run_screen.dart';
import '../lib/social_service.dart';
import '../lib/training_service.dart';
import 'pump_until.dart';
import 'pre_run_dialogs.dart';

/// Pins the run screen's stride persistence end to end: the stride the
/// estimator learned on this runner's earlier runs of an activity seeds the
/// recorder on a fresh start AND on a crash-recovered resume, and the stride
/// the run ends with is written back on stop.
///
/// The recorder is private to the screen, so the seed is observed through the
/// one place it surfaces: with the pedometer silent the estimator never learns
/// a stride of its own, so `RunRecorder.strideMetres` at stop is exactly the
/// seed it was prepared with, or null when it was given none. Each test stores
/// a seed, lets the screen read it, overwrites the preference with a different
/// value mid-run, and finishes. The seed coming back proves both halves: a
/// screen that never passed it would leave the overwrite in place (null
/// stride, nothing written), and one that never saved would too.
///
/// Harness mirrors run_screen_conclude_retry_test.dart (geolocator / wakelock
/// / permission / tts / notification-bridge mocks; spy run store so the save
/// stays on the fake clock).

/// Signed-in fake: the stride is keyed by account, so the screen reads
/// [userId]. Every remote leg the stop path touches is overridden so nothing
/// reaches the (uninitialised-network) Supabase client.
class _SignedInApi extends ApiClient {
  @override
  String? get userId => 'user-1';

  @override
  Future<List<RouteMatchCandidate>> fetchRoutesIntersectingTrack(
    List<Waypoint> track, {
    double toleranceMetres = 100,
    int maxResults = 10,
  }) async => const [];

  @override
  Future<void> saveRun(
    Run run, {
    bool? isPublic,
    bool followersOnly = false,
  }) async {}

  @override
  Future<void> makeRunPublic(String runId) async {}

  @override
  Future<void> makeRunPrivate(String runId) async {}

  @override
  Future<void> concludeLiveBroadcast(String runId) async {}
}

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

  void emit(Position p) {
    _positions ??= StreamController<Position>.broadcast();
    _positions!.add(p);
  }

  Future<void> dispose() async {
    await _positions?.close();
    _positions = null;
  }
}

/// Spy store — captures saves in memory so the Finish flow stays on the
/// fake clock (see run_screen_recording_flow_test.dart for the rationale).
class _CapturingRunStore extends LocalRunStore {
  final List<dynamic> captured = [];

  @override
  Future<Run> save(run) async {
    captured.add(run);
    // save() returns the RESIDENT instance so markManySynced can identify it;
    // the spy has no store, so the argument IS the resident copy here.
    return run;
  }

  @override
  Future<void> clearInProgress() async {}

  @override
  Future<void> markSynced(String id) async {}
}

class _NoOpWakelock extends WakelockPlusPlatformInterface {
  bool _on = false;

  @override
  bool get isMock => true;

  @override
  Future<void> toggle({required bool enable}) async {
    _on = enable;
  }

  @override
  Future<bool> get enabled async => _on;
}

Position _pos({required double metresEast, required int secondsFromStart}) {
  const lat = 47.37;
  const lngBase = 8.54;
  const metrePerDegLng = 111320 * 0.6773;
  return Position(
    longitude: lngBase + metresEast / metrePerDegLng,
    latitude: lat,
    timestamp: DateTime(2026, 4, 10, 10, 0, secondsFromStart),
    accuracy: 5,
    altitude: 400,
    altitudeAccuracy: 2,
    heading: 90,
    headingAccuracy: 5,
    speed: 2.5,
    speedAccuracy: 1,
  );
}

void main() {
  late _FakeGeolocatorPlatform geolocator;
  late Directory runsDir;
  bool supabaseReady = false;

  final mockedMethodChannels = <String>[];
  final mockedEventChannels = <String>[];

  void mockMethodChannel(
    String name,
    Future<Object?> Function(MethodCall) handler,
  ) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(MethodChannel(name), handler);
    mockedMethodChannels.add(name);
  }

  void mockEventChannelAsSilent(String name) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          MethodChannel(name, const StandardMethodCodec()),
          (call) async => null,
        );
    mockedEventChannels.add(name);
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

    mockMethodChannel('flutter.baseflow.com/permissions/methods', (call) async {
      switch (call.method) {
        case 'checkPermissionStatus':
        case 'requestPermissions':
          if (call.arguments is List) {
            return {for (final p in (call.arguments as List)) p: 1};
          }
          return 1;
        default:
          return null;
      }
    });
    mockMethodChannel('flutter_tts', (call) async => 1);
    mockMethodChannel('run_app/run_notification', (call) async => null);
    mockEventChannelAsSilent('step_count');
    mockEventChannelAsSilent('step_detection');

    runsDir = Directory.systemTemp.createTempSync('run_screen_stride_');
  });

  /// The store the last `pumpRunScreen` built, so the teardown can wait on
  /// the in-progress recording write before deleting the directory under it.
  _CapturingRunStore? lastRunStore;

  tearDown(() async {
    for (final name in mockedMethodChannels) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel(name), null);
    }
    for (final name in mockedEventChannels) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            MethodChannel(name, const StandardMethodCodec()),
            null,
          );
    }
    mockedMethodChannels.clear();
    mockedEventChannels.clear();
    await geolocator.dispose();
    // The incremental-save Timer.periodic drives `saveInProgress` fire-and-
    // forget, and that path is deliberately off the store's write chain, so
    // `debugWritesSettled()` does not answer for it. Deleting `runsDir` with
    // an append still in the air is the § 723 race — wait on the path's own
    // signal first (decisions § 1012).
    await lastRunStore?.debugInProgressSettled();
    lastRunStore = null;
    if (runsDir.existsSync()) runsDir.deleteSync(recursive: true);
  });

  const seed = 1.23;
  const overwritten = 0.9;

  Future<Preferences> freshPrefs() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = Preferences();
    await prefs.init();
    await markPreRunDialogsSeen(prefs);
    return prefs;
  }

  Future<_CapturingRunStore> pumpRunScreen(
    WidgetTester tester, {
    required Preferences prefs,
    required ApiClient api,
    Run? resumable,
  }) async {
    final runStore = _CapturingRunStore();
    lastRunStore = runStore;
    await runStore.init(overrideDirectory: runsDir);
    final social = SocialService();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: RunScreen(
          apiClient: api,
          runStore: runStore,
          routeStore: LocalRouteStore(),
          preferences: prefs,
          audioCues: AudioCues(),
          social: social,
          raceController: RaceController(social),
          training: TrainingService(),
          heartRate: BleHeartRate(),
          treadmill: BleTreadmill(),
          initialResumablePartial: resumable,
        ),
      ),
    );
    // First pump mounts; second lets a resume prompt's post-frame open it.
    await tester.pump();
    await tester.pump();
    return runStore;
  }

  Future<void> startAndRecord(WidgetTester tester) async {
    await tester.tap(find.text('START'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    tester.takeException(); // LiveRunMap tile-fetch noise
    for (var i = 0; i < 5; i++) {
      geolocator.emit(_pos(metresEast: i * 12.0, secondsFromStart: i * 2));
      await tester.pump(const Duration(milliseconds: 50));
    }
    tester.takeException();
  }

  Future<void> drainAndUnmount(WidgetTester tester) async {
    tester.takeException();
    await tester.pumpWidget(const SizedBox());
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    tester.takeException();
  }

  Run resumablePartial() => Run(
    id: 'resume-stride-1',
    startedAt: DateTime(2026, 4, 10, 9, 0, 0),
    duration: const Duration(minutes: 20),
    distanceMetres: 4000,
    track: List.generate(
      6,
      (i) => Waypoint(
        lat: 47.37,
        lng: 8.54 + i * 0.0002,
        timestamp: DateTime(2026, 4, 10, 9, 0, i * 5),
      ),
    ),
    source: RunSource.app,
    metadata: {
      'activity_type': 'run',
      'in_progress_saved_at': DateTime(2026, 4, 10, 9, 20, 0).toIso8601String(),
    },
  );

  group('RunScreen — the persisted stride', () {
    testWidgets('seeds a fresh run and is saved back when it stops', (
      tester,
    ) async {
      final prefs = await freshPrefs();
      await prefs.setLearnedStrideM('user-1', 'run', seed);
      final runStore = await pumpRunScreen(
        tester,
        prefs: prefs,
        api: _SignedInApi(),
      );

      await startAndRecord(tester);
      await prefs.setLearnedStrideM('user-1', 'run', overwritten);

      await holdFinish(tester);
      expect(runStore.captured, hasLength(1));
      await pumpUntil(
        tester,
        () => prefs.learnedStrideM('user-1', 'run') == seed,
        describe: 'the stop to write back the stride the run was seeded with',
      );

      await drainAndUnmount(tester);
    });

    testWidgets('seeds a resumed run and is saved back when it stops', (
      tester,
    ) async {
      final prefs = await freshPrefs();
      await prefs.setLearnedStrideM('user-1', 'run', seed);
      final runStore = await pumpRunScreen(
        tester,
        prefs: prefs,
        api: _SignedInApi(),
        resumable: resumablePartial(),
      );

      await tester.tap(find.text('Resume'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      tester.takeException();
      expect(find.text('Resume your run?'), findsNothing);
      for (var i = 0; i < 3; i++) {
        geolocator.emit(
          _pos(metresEast: 1000 + i * 12.0, secondsFromStart: i * 2),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
      tester.takeException();
      await prefs.setLearnedStrideM('user-1', 'run', overwritten);

      await holdFinish(tester);
      expect(runStore.captured.single.id, 'resume-stride-1');
      await pumpUntil(
        tester,
        () => prefs.learnedStrideM('user-1', 'run') == seed,
        describe: 'the resumed run to write back the stride it was seeded with',
      );

      await drainAndUnmount(tester);
    });

    testWidgets("is keyed by account: another runner's stride never seeds "
        'this one', (tester) async {
      const otherSeed = 1.05;
      final prefs = await freshPrefs();
      await prefs.setLearnedStrideM('user-1', 'run', otherSeed);
      await prefs.setLearnedStrideM('user-2', 'run', seed);
      final runStore = await pumpRunScreen(
        tester,
        prefs: prefs,
        api: _SignedInApi(),
      );

      await startAndRecord(tester);
      await prefs.setLearnedStrideM('user-1', 'run', overwritten);

      await holdFinish(tester);
      expect(runStore.captured, hasLength(1));
      await pumpUntil(
        tester,
        () => prefs.learnedStrideM('user-1', 'run') == otherSeed,
        describe: "the stop to write back user-1's own stride",
      );
      expect(
        prefs.learnedStrideM('user-2', 'run'),
        seed,
        reason: "user-2's stride is neither read nor overwritten",
      );

      await drainAndUnmount(tester);
    });
  });
}
