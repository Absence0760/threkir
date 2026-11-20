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
import '../lib/live_course_timing.dart';
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

/// [metresEast] along the course, [metresNorth] off it.
Position _posAt(double metresEast, double metresNorth, int secondsFromStart) {
  final p = _pos(metresEast, secondsFromStart);
  return Position(
    longitude: p.longitude,
    latitude: _lat + metresNorth / 111320,
    timestamp: p.timestamp,
    accuracy: 5,
    altitude: 400,
    altitudeAccuracy: 2,
    heading: 90,
    headingAccuracy: 5,
    speed: 4,
    speedAccuracy: 1,
  );
}

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

/// The same course with checkpoints 100 m and 160 m along it.
final _courseWithCheckpoints = GlobalSegmentGeometry(
  points: _course.points,
  distanceM: 200,
  checkpoints: [
    cm.Waypoint(lat: _lat, lng: _lng + 100 / _metrePerDegLng),
    cm.Waypoint(lat: _lat, lng: _lng + 160 / _metrePerDegLng),
  ],
  startGate: _course.startGate,
  endGate: _course.endGate,
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
    bool followRoute = true,
    Future<List<LiveCourseCandidate>> Function(double lat, double lng)? nearby,
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
        initialRoute: followRoute ? _route : null,
        liveCourseLookup: (id) async {
          looked.add(id);
          return id == _routeId ? course : null;
        },
        liveCourseNearbyLookup: nearby ?? (lat, lng) async => const [],
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

  /// One fix every second, 4 m apart, through each (east, north) point.
  Future<void> runThrough(
      WidgetTester tester, List<(double, double)> points) async {
    for (var k = 0; k + 1 < points.length; k++) {
      final (e0, n0) = points[k];
      final (e1, n1) = points[k + 1];
      final d = Offset(e1 - e0, n1 - n0).distance;
      final steps = (d / 4).ceil().clamp(1, 1000);
      for (var j = k == 0 ? 0 : 1; j <= steps; j++) {
        final f = j / steps;
        geolocator.emit(_posAt(e0 + (e1 - e0) * f, n0 + (n1 - n0) * f, clock++));
        await tester.pump(const Duration(milliseconds: 50));
      }
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

  const offCheckpoint1 = "You're off the course. Head back to checkpoint 1.";

  testWidgets(
      'straying off a timed course says which checkpoint to head back to, '
      'once, with a buzz, and clears back on the line', (tester) async {
    final s = await pumpRunScreen(tester, course: _courseWithCheckpoints);
    await startRecording(tester);
    await runEast(tester, -20, 40);
    expect(find.text('Timing started'), findsOneWidget);

    await runThrough(tester, [(40, 0), (60, 60), (80, 60)]);
    expect(find.text(offCheckpoint1), findsOneWidget);
    expect(find.byKey(const ValueKey('course-off-course')), findsOneWidget);
    expect(s.cues.spoken.where((t) => t == offCheckpoint1), hasLength(1),
        reason: 'said once while the runner stays off');
    expect(haptics, contains('pace_speed_up'));
    expect(find.textContaining('Off route'), findsNothing,
        reason: "the course's warning stands in for the route's");

    await runThrough(tester, [(80, 60), (90, 0), (120, 0)]);
    expect(find.byKey(const ValueKey('course-off-course')), findsNothing);
    expect(s.cues.spoken.where((t) => t == offCheckpoint1), hasLength(1));

    await holdFinish(tester);
    expect(s.runStore.captured, hasLength(1));
    await unmount(tester);
  });

  testWidgets('the live map numbers each checkpoint and ticks it once passed',
      (tester) async {
    // A tall view, so both checkpoints are inside the followed camera at
    // its recording zoom and the map does not cull their markers.
    tester.view.physicalSize = const Size(2400, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpRunScreen(tester, course: _courseWithCheckpoints);
    await startRecording(tester);
    await runEast(tester, -20, 60);
    expect(find.byKey(const ValueKey('live-checkpoint-1-ahead')), findsOneWidget);
    expect(find.byKey(const ValueKey('live-checkpoint-2-ahead')), findsOneWidget);
    expect(find.byIcon(Icons.check), findsNothing);

    await runEast(tester, 64, 120);
    expect(
        find.byKey(const ValueKey('live-checkpoint-1-passed')), findsOneWidget);
    expect(find.byKey(const ValueKey('live-checkpoint-2-ahead')), findsOneWidget);
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('live-checkpoint-1-passed')),
            matching: find.byIcon(Icons.check)),
        findsOneWidget,
        reason: 'a tick, not colour alone');

    await holdFinish(tester);
    await unmount(tester);
  });

  testWidgets(
      'without a followed course, a park course started nearby is timed and '
      'named', (tester) async {
    final looks = <(double, double)>[];
    final s = await pumpRunScreen(
      tester,
      followRoute: false,
      nearby: (lat, lng) async {
        looks.add((lat, lng));
        return [LiveCourseCandidate(name: 'Lake loop', segment: _course)];
      },
    );
    await startRecording(tester);
    await runEast(tester, -20, 60);
    expect(find.text('Timing started: Lake loop'), findsOneWidget);
    expect(s.cues.spoken, contains('Timing started: Lake loop'));

    await runEast(tester, 64, 240);
    expect(s.cues.spoken.where((t) => t.startsWith('Finished! ')),
        hasLength(1));
    expect(looks, hasLength(1), reason: 'found at the first look');

    await holdFinish(tester);
    expect(s.runStore.captured, hasLength(1));
    await unmount(tester);
  });

  testWidgets(
      'offline, the nearby-course read fails silently, looks once more after '
      '200 m, and the run records as before', (tester) async {
    var looks = 0;
    final s = await pumpRunScreen(
      tester,
      followRoute: false,
      nearby: (lat, lng) async {
        looks++;
        throw const SocketException('offline');
      },
    );
    await startRecording(tester);
    await runEast(tester, -20, 320);
    expect(find.byKey(const ValueKey('course-timing-cue')), findsNothing);
    expect(s.cues.spoken, isEmpty);
    expect(looks, 2, reason: 'once at the start, once more 200 m in');

    await holdFinish(tester);
    expect(s.runStore.captured, hasLength(1));
    expect(s.runStore.captured.single.distanceMetres, greaterThan(300));
    await unmount(tester);
  });

  testWidgets(
      'off course with a voice engine and a vibrator that both throw, the '
      'warning still shows and every fix is recorded', (tester) async {
    hapticsThrow = true;
    final s = await pumpRunScreen(tester,
        throwOnCue: true, course: _courseWithCheckpoints);
    await startRecording(tester);
    await runEast(tester, -20, 40);
    await runThrough(
        tester, [(40, 0), (60, 60), (140, 60), (150, 0), (240, 0)]);

    expect(s.cues.spoken, contains(offCheckpoint1));
    expect(haptics, contains('pace_speed_up'));
    expect(find.textContaining('Finished! '), findsNothing,
        reason: 'checkpoint 1 was missed, so the board would not time it');

    await holdFinish(tester);
    expect(s.runStore.captured, hasLength(1));
    expect(s.runStore.captured.single.track.length, greaterThan(60));
    await unmount(tester);
  });
}
