import 'dart:async';
import 'dart:io';

import 'package:core_models/core_models.dart' as cm;
import 'package:core_models/core_models.dart' show DistanceUnit;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus_platform_interface/wakelock_plus_platform_interface.dart';

import '../lib/audio_cues.dart';
import '../lib/ble_heart_rate.dart';
import '../lib/ble_treadmill.dart';
import '../lib/gate_crossing.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/local_route_store.dart';
import '../lib/local_run_store.dart';
import '../lib/preferences.dart';
import '../lib/race_controller.dart';
import '../lib/run_haptics_bridge.dart';
import '../lib/screens/run_screen.dart';
import '../lib/segments.dart';
import '../lib/social_service.dart';
import '../lib/training_service.dart';
import 'pre_run_dialogs.dart';
import 'pump_until.dart';
import 'supabase_test_init.dart';

/// Drives the REAL RunScreen and the REAL recorder over a park course the
/// runner follows (#1446): "Timing started" on leaving the start box,
/// "Finished! 0:50" at the finish, each with a buzz and a voice cue, and the
/// stopped-short line on the summary. Every cue is an L4 effect, so a TTS
/// engine and a vibrator that both throw must leave the recording intact.

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

class _NoOpWakelock extends WakelockPlusPlatformInterface {
  bool _on = false;

  @override
  bool get isMock => true;

  @override
  Future<void> toggle({required bool enable}) async => _on = enable;

  @override
  Future<bool> get enabled async => _on;
}

class _SpyAudioCues extends AudioCues {
  _SpyAudioCues({this.throwOnCue = false});

  final bool throwOnCue;
  final List<String> spoken = [];

  @override
  Future<void> announceGuidedCue(String text) async {
    spoken.add(text);
    if (throwOnCue) throw StateError('TTS engine is gone');
  }

  @override
  Future<void> announceStart() async {}

  @override
  Future<void> announceFinish({
    required double distanceMetres,
    required Duration elapsed,
    required DistanceUnit unit,
  }) async {}
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

const _lat = 47.37;
const _lng = 8.54;
const _metrePerDegLng = 111320 * 0.6773;

Position _pos(double metresEast, int secondsFromStart) => Position(
      longitude: _lng + metresEast / _metrePerDegLng,
      latitude: _lat,
      timestamp: DateTime(2026, 4, 10, 10, 0, secondsFromStart),
      accuracy: 5,
      altitude: 400,
      altitudeAccuracy: 2,
      heading: 90,
      headingAccuracy: 5,
      speed: 4,
      speedAccuracy: 1,
    );

/// 200 m due east: the start line at 0 m, the finish line at 200 m.
final _course = GlobalSegmentGeometry(
  points: [
    cm.Waypoint(lat: _lat, lng: _lng),
    cm.Waypoint(lat: _lat, lng: _lng + 200 / _metrePerDegLng),
  ],
  distanceM: 200,
  startGate: const Gate(lat: _lat, lng: _lng, bearingDeg: 90, halfWidthM: 15),
  endGate: const Gate(
      lat: _lat,
      lng: _lng + 200 / _metrePerDegLng,
      bearingDeg: 90,
      halfWidthM: 15),
);

const _routeId = 'park-course-route';

final _route = cm.Route(
  id: _routeId,
  userId: 'u1',
  name: 'Lake loop',
  distanceMetres: 200,
  isPublic: true,
  waypoints: _course.points,
);

void main() {
  late _FakeGeolocatorPlatform geolocator;
  late Directory runsDir;
  late List<String> haptics;
  var hapticsThrow = false;
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

  setUp(() async {
    geolocator = _FakeGeolocatorPlatform();
    GeolocatorPlatform.instance = geolocator;
    WakelockPlusPlatformInterface.instance = _NoOpWakelock();
    haptics = [];
    hapticsThrow = false;

    mockMethodChannel('flutter.baseflow.com/permissions/methods', (call) async {
      if (call.arguments is List) {
        return {for (final p in (call.arguments as List)) p: 1};
      }
      return 1;
    });
    mockMethodChannel('flutter_tts', (call) async => 1);
    mockMethodChannel('run_app/run_notification', (call) async => null);
    mockMethodChannel(RunHapticsBridge.channelName, (call) async {
      haptics.add(call.arguments as String);
      if (hapticsThrow) {
        throw PlatformException(code: 'no_vibrator', message: 'gone');
      }
      return null;
    });
    mockEventChannelAsSilent('step_count');
    mockEventChannelAsSilent('step_detection');

    runsDir = Directory.systemTemp.createTempSync('run_screen_live_course_');
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

  Future<({_SpyAudioCues cues, _CapturingRunStore runStore})> pumpRunScreen(
    WidgetTester tester, {
    bool throwOnCue = false,
    GlobalSegmentGeometry? course,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = Preferences();
    await prefs.init();
    await markPreRunDialogsSeen(prefs);

    final runStore = _CapturingRunStore();
    await runStore.init(overrideDirectory: runsDir);
    final social = SocialService();
    final cues = _SpyAudioCues(throwOnCue: throwOnCue);
    final looked = <String>[];

    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: RunScreen(
        apiClient: null,
        runStore: runStore,
        routeStore: LocalRouteStore(),
        preferences: prefs,
        audioCues: cues,
        social: social,
        raceController: RaceController(social),
        training: TrainingService(),
        heartRate: BleHeartRate(),
        treadmill: BleTreadmill(),
        initialRoute: _route,
        liveCourseLookup: (id) async {
          looked.add(id);
          return id == _routeId ? course : null;
        },
      ),
    ));
    await tester.pump();
    return (cues: cues, runStore: runStore);
  }

  Future<void> startRecording(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('run-idle-start')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    tester.takeException();
  }

  /// One fix every second, 4 m apart, from [fromM] to [toM] east.
  var clock = 0;
  Future<void> runEast(WidgetTester tester, double fromM, double toM) async {
    for (var m = fromM; m <= toM; m += 4) {
      geolocator.emit(_pos(m, clock++));
      await tester.pump(const Duration(milliseconds: 50));
    }
    tester.takeException();
  }

  Future<void> unmount(WidgetTester tester) async {
    tester.takeException();
    await tester.pumpWidget(const SizedBox());
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    tester.takeException();
  }

  setUp(() => clock = 0);

  testWidgets(
      'leaving the start box says "Timing started" and the finish says the '
      'course time, each with a buzz and a voice cue', (tester) async {
    final s = await pumpRunScreen(tester, course: _course);
    await startRecording(tester);

    await runEast(tester, -20, 60);
    expect(find.text('Timing started'), findsOneWidget);
    expect(s.cues.spoken, contains('Timing started'));
    expect(haptics, contains('step_work'));
    expect(find.textContaining('Finished!'), findsNothing);

    await runEast(tester, 64, 240);
    final finished = s.cues.spoken.where((t) => t.startsWith('Finished! '));
    expect(finished, hasLength(1), reason: 'the finish is said once');
    expect(find.text(finished.single), findsOneWidget,
        reason: 'the same words, big, on the screen');
    expect(finished.single, matches(RegExp(r'^Finished! 0:\d\d$')));
    expect(haptics, contains('workout_complete'));

    await holdFinish(tester);
    expect(s.runStore.captured, hasLength(1));
    expect(find.byKey(const ValueKey('course-stopped-short')), findsNothing,
        reason: 'a finished course is not stopped short');
    await unmount(tester);
  });

  testWidgets(
      'stopping after the start and before the finish says it will not '
      'count, and the run is still saved', (tester) async {
    final s = await pumpRunScreen(tester, course: _course);
    await startRecording(tester);
    await runEast(tester, -20, 100);
    expect(find.text('Timing started'), findsOneWidget);

    await holdFinish(tester);
    expect(s.runStore.captured, hasLength(1),
        reason: 'stopping is never held up by the course');
    expect(
        find.text("This won't count as a course time. Your run is still saved."),
        findsOneWidget);
    await unmount(tester);
  });

  testWidgets('a voice engine and a vibrator that both throw cost nothing',
      (tester) async {
    hapticsThrow = true;
    final s = await pumpRunScreen(tester, throwOnCue: true, course: _course);
    await startRecording(tester);
    await runEast(tester, -20, 240);

    expect(s.cues.spoken, contains('Timing started'));
    expect(haptics, containsAll(['step_work', 'workout_complete']));
    expect(find.textContaining('Finished! '), findsOneWidget,
        reason: 'the card still shows when the other cues throw');

    await holdFinish(tester);
    expect(s.runStore.captured, hasLength(1));
    final saved = s.runStore.captured.single;
    expect(saved.track.length, greaterThan(40),
        reason: 'every fix after the throwing cues was still recorded');
    expect(saved.distanceMetres, greaterThan(200));
    await unmount(tester);
  });

  testWidgets('a route that is no park course says nothing', (tester) async {
    final s = await pumpRunScreen(tester, course: null);
    await startRecording(tester);
    await runEast(tester, -20, 240);
    expect(find.byKey(const ValueKey('course-timing-cue')), findsNothing);
    expect(s.cues.spoken, isEmpty);

    await holdFinish(tester);
    expect(find.byKey(const ValueKey('course-stopped-short')), findsNothing);
    await unmount(tester);
  });
}
