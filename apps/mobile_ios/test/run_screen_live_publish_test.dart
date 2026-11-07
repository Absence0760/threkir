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
import 'pre_run_dialogs.dart';
import 'supabase_test_init.dart';

/// Pins what a live share publishes (issue #1300 BUG-003 / BUG-007): never
/// a fix the recorder's movement filter rejected, and a flagged weak-GPS fix
/// when no fix clears the 20 m map gate.
///
/// Harness mirrors run_screen_live_visibility_test.dart.

/// Signed-in fake that records the visibility + broadcast calls the stop
/// path makes. Every remote leg the stop path touches is overridden so
/// nothing reaches the (uninitialised-network) Supabase client.
class _LiveApi extends ApiClient {
  final List<String> calls = [];
  final List<({double lat, double lng, bool weakGps})> pings = [];

  @override
  String? get userId => 'user-1';

  @override
  Future<void> beginLiveBroadcast({
    required String runId,
    required DateTime startedAt,
    String activityType = 'run',
    bool safetyAudience = false,
  }) async {
    calls.add('begin');
  }

  @override
  Future<void> insertLivePing({
    required String runId,
    required double lat,
    required double lng,
    double? distanceM,
    int? elapsedS,
    int? bpm,
    double? ele,
    bool weakGps = false,
  }) async {
    pings.add((lat: lat, lng: lng, weakGps: weakGps));
  }

  @override
  Future<List<RouteMatchCandidate>> fetchRoutesIntersectingTrack(
    List<Waypoint> track, {
    double toleranceMetres = 100,
    int maxResults = 10,
  }) async =>
      const [];

  @override
  Future<void> saveRun(Run run, {bool? isPublic, bool followersOnly = false}) async {
    calls.add('saveRun(isPublic: $isPublic)');
  }

  @override
  Future<void> makeRunPublic(String runId) async {
    calls.add('makeRunPublic');
  }

  @override
  Future<void> makeRunPrivate(String runId) async {
    calls.add('makeRunPrivate');
  }

  @override
  Future<void> concludeLiveBroadcast(String runId) async {
    calls.add('conclude');
  }
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

Position _pos({
  required double metresEast,
  required int secondsFromStart,
  double accuracy = 5,
}) {
  const lat = 47.37;
  const lngBase = 8.54;
  const metrePerDegLng = 111320 * 0.6773;
  return Position(
    longitude: lngBase + metresEast / metrePerDegLng,
    latitude: lat,
    timestamp: DateTime(2026, 4, 10, 10, 0, secondsFromStart),
    accuracy: accuracy,
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
      String name, Future<Object?> Function(MethodCall) handler) {
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
      await initializeTestSupabase();
      supabaseReady = true;
    }
  });

  var clockSkew = Duration.zero;

  setUp(() async {
    clockSkew = Duration.zero;
    geolocator = _FakeGeolocatorPlatform();
    GeolocatorPlatform.instance = geolocator;
    WakelockPlusPlatformInterface.instance = _NoOpWakelock();

    mockMethodChannel('flutter.baseflow.com/permissions/methods',
        (call) async {
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
    // share_plus — the pre-start "Share live link" hands the URL to the OS
    // sheet; resolve it so the test doesn't rely on the caught
    // MissingPluginException path.
    mockMethodChannel('dev.fluttercommunity.plus/share', (call) async => '');
    mockEventChannelAsSilent('step_count');
    mockEventChannelAsSilent('step_detection');

    runsDir = Directory.systemTemp.createTempSync('run_screen_live_pub_');
  });

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
    if (runsDir.existsSync()) runsDir.deleteSync(recursive: true);
  });

  Future<({_LiveApi api, _CapturingRunStore runStore, Preferences prefs})>
      pumpLiveRunScreen(WidgetTester tester,
          {String privacyDefault = 'private'}) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = Preferences();
    await prefs.init();
    await markPreRunDialogsSeen(prefs);
    await prefs.setPrivacyDefault(privacyDefault);

    final api = _LiveApi();
    final runStore = _CapturingRunStore();
    await runStore.init(overrideDirectory: runsDir);
    final social = SocialService();

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: RunScreen(
          apiClient: api,
          liveClock: () => DateTime.now().add(clockSkew),
          runStore: runStore,
          routeStore: LocalRouteStore(),
          preferences: prefs,
          audioCues: AudioCues(),
          social: social,
          raceController: RaceController(social),
          training: TrainingService(),
          heartRate: BleHeartRate(),
          treadmill: BleTreadmill(),
        ),
      ),
    );
    await tester.pump();
    return (api: api, runStore: runStore, prefs: prefs);
  }

  /// Share the live link pre-start (attaches the broadcaster via the fake
  /// api) and run through the countdown. The caller feeds the fixes.
  Future<void> shareAndStart(WidgetTester tester, _LiveApi api) async {
    await tester.tap(find.text('Share live link'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(api.calls, contains('begin'),
        reason: 'the pre-start share must begin the live broadcast');

    await tester.tap(find.text('START'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    tester.takeException(); // LiveRunMap tile-fetch noise
  }

  /// Moves the broadcaster's clock past its 5 s ping window.
  void outlastPingThrottle() {
    clockSkew += const Duration(milliseconds: 5200);
  }

  Future<void> drainAndUnmount(WidgetTester tester) async {
    tester.takeException();
    await tester.pumpWidget(const SizedBox());
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    tester.takeException();
  }

  group('RunScreen — live publish (issue #1300)', () {
    testWidgets('a teleport the recorder rejected is never published',
        (tester) async {
      final s = await pumpLiveRunScreen(tester);
      await shareAndStart(tester, s.api);

      for (var i = 0; i < 3; i++) {
        geolocator.emit(_pos(metresEast: i * 12.0, secondsFromStart: i * 2));
        await tester.pump(const Duration(milliseconds: 50));
      }
      tester.takeException();
      expect(s.api.pings, isNotEmpty);

      outlastPingThrottle();
      // 3 km east two seconds later: an implausible hop the movement
      // filter rejects, while the fix itself is fresh and precise.
      geolocator.emit(_pos(metresEast: 3000, secondsFromStart: 6));
      await tester.pump(const Duration(milliseconds: 50));
      tester.takeException();

      final lastGood = _pos(metresEast: 24, secondsFromStart: 4);
      final teleport = _pos(metresEast: 3000, secondsFromStart: 6);
      expect(s.api.pings.length, greaterThanOrEqualTo(2),
          reason: 'the fresh snapshot after the throttle still publishes');
      for (final p in s.api.pings) {
        expect(p.lng, isNot(closeTo(teleport.longitude, 1e-6)),
            reason: 'the spectator must never be sent the rejected fix');
      }
      expect(s.api.pings.last.lng, closeTo(lastGood.longitude, 1e-9),
          reason: 'it is sent the end of the recorder line instead');
      expect(s.api.pings.last.weakGps, false);

      await drainAndUnmount(tester);
    });

    testWidgets(
        'a phone that never clears the 20 m gate publishes weak-GPS fixes',
        (tester) async {
      final s = await pumpLiveRunScreen(tester);
      await shareAndStart(tester, s.api);

      for (var i = 0; i < 3; i++) {
        geolocator.emit(_pos(
            metresEast: i * 12.0, secondsFromStart: i * 2, accuracy: 35));
        await tester.pump(const Duration(milliseconds: 50));
      }
      tester.takeException();

      expect(s.api.pings, isNotEmpty,
          reason: 'a 35 m phone used to leave the spectator on Connecting');
      expect(s.api.pings.first.weakGps, true);
      expect(s.api.pings.first.lng,
          closeTo(_pos(metresEast: 0, secondsFromStart: 0).longitude, 1e-9));

      await drainAndUnmount(tester);
    });
  });
}
