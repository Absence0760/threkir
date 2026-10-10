// The recorder's own controls, the tablet shell, and a run brought back from a
// killed process, driven through the real shell with the real recorder inside
// it.
//
// shell_run_journey_test.dart walks the everyday start-to-finish run. This
// suite walks what happens in the middle of one and around it: Pause and Lap
// on the panel, the rail layout where the panel keeps its own Stop, and the
// cold start that hands HomeScreen a partial to resume. Same rule as there:
// tap only what a runner taps, assert what a runner sees.
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
import '../lib/in_progress_recovery.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/local_food_store.dart';
import '../lib/local_gear_store.dart';
import '../lib/local_gym_store.dart';
import '../lib/local_route_store.dart';
import '../lib/local_run_store.dart';
import '../lib/preferences.dart';
import '../lib/race_controller.dart';
import '../lib/screens/home_screen.dart';
import '../lib/screens/run_screen.dart';
import '../lib/social_service.dart';
import '../lib/training_service.dart';
import 'pump_until.dart';
import 'store_write_watch.dart';

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
  Future<void> toggle({required bool enable}) async {
    _on = enable;
  }

  @override
  Future<bool> get enabled async => _on;
}

const _originLat = 47.37;
const _originLng = 8.54;
const _metrePerDegLat = 111320.0;
const _metrePerDegLng = 111320 * 0.6773;

Position _pos({
  required double metresEast,
  double metresNorth = 0,
  required int secondsFromStart,
}) {
  return Position(
    longitude: _originLng + metresEast / _metrePerDegLng,
    latitude: _originLat + metresNorth / _metrePerDegLat,
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

double _metresNorthOf(cm.Waypoint w) => (w.lat - _originLat) * _metrePerDegLat;

/// A run whose process was killed 20 minutes before the app reopened: 40
/// minutes in, one lap marked, the last checkpoint recent enough to resume.
cm.Run _killedPartial() {
  return cm.Run(
    id: 'resume-me-1',
    startedAt: DateTime(2026, 4, 10, 9, 0, 0),
    duration: const Duration(minutes: 40),
    distanceMetres: 6700,
    track: List.generate(
      6,
      (i) => cm.Waypoint(
        lat: _originLat,
        lng: _originLng + i * 0.0002,
        timestamp: DateTime(2026, 4, 10, 9, 0, i * 5),
      ),
    ),
    source: cm.RunSource.app,
    metadata: {
      'activity_type': 'run',
      'in_progress_saved_at':
          DateTime(2026, 4, 10, 9, 40, 0).toIso8601String(),
      'laps': [
        {
          'index': 1,
          'start_offset_s': 0,
          'distance_m': 6700.0,
          'duration_s': 2400,
        },
      ],
    },
  );
}

void main() {
  late _FakeGeolocatorPlatform geolocator;
  final tempDirs = <Directory>[];
  final mockedChannels = <MethodChannel>[];
  var supabaseReady = false;

  void mockChannel(MethodChannel channel,
      Future<Object?> Function(MethodCall) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, handler);
    mockedChannels.add(channel);
  }

  Directory tempDir(String prefix) {
    final dir = Directory.systemTemp.createTempSync(prefix);
    tempDirs.add(dir);
    return dir;
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

  setUp(() {
    geolocator = _FakeGeolocatorPlatform();
    GeolocatorPlatform.instance = geolocator;
    WakelockPlusPlatformInterface.instance = _NoOpWakelock();
    mockChannel(const MethodChannel('flutter.baseflow.com/permissions/methods'),
        (call) async {
      if (call.arguments is List) {
        return {for (final p in (call.arguments as List)) p: 1};
      }
      return 1;
    });
    mockChannel(const MethodChannel('flutter_tts'), (call) async => 1);
    mockChannel(
        const MethodChannel('run_app/run_notification'), (call) async => null);
    mockChannel(const MethodChannel('step_count', StandardMethodCodec()),
        (call) async => null);
    mockChannel(const MethodChannel('step_detection', StandardMethodCodec()),
        (call) async => null);
  });

  tearDown(() async {
    for (final channel in mockedChannels) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    }
    mockedChannels.clear();
    await geolocator.dispose();
    runRecordingActive.value = false;
    runSummaryShowing.value = false;
    for (final dir in tempDirs) {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    }
    tempDirs.clear();
  });

  /// Mounts the shell for a runner with no lift or meal logged, so the centre
  /// button's tap starts a run. [runStore] and [resumablePartial] stand in for
  /// what main.dart hands HomeScreen after its cold-start recovery pass.
  Future<LocalRunStore> pumpShell(
    WidgetTester tester, {
    LocalRunStore? runStore,
    cm.Run? resumablePartial,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = Preferences();
    await prefs.init();
    final store = runStore ?? LocalRunStore();
    if (runStore == null) {
      await store.init(overrideDirectory: tempDir('controls_runs_'));
    }
    final gearStore = LocalGearStore();
    await gearStore.init(overrideDirectory: tempDir('controls_gear_'));
    final gymStore = LocalGymStore();
    await gymStore.init(overrideDirectory: tempDir('controls_gym_'));
    final foodStore = LocalFoodStore();
    await foodStore.init(overrideDirectory: tempDir('controls_food_'));
    final social = SocialService();

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: HomeScreen(
          apiClient: null,
          runStore: store,
          routeStore: LocalRouteStore(),
          gearStore: gearStore,
          gymStore: gymStore,
          foodStore: foodStore,
          preferences: prefs,
          audioCues: AudioCues(),
          social: social,
          raceController: RaceController(social),
          training: TrainingService(),
          heartRate: BleHeartRate(),
          treadmill: BleTreadmill(),
          resumablePartial: resumablePartial,
        ),
      ),
    );
    await tester.pump();
    return store;
  }

  double shellPage(WidgetTester tester) {
    final controller =
        tester.widget<PageView>(find.byType(PageView).first).controller!;
    return controller.hasClients
        ? controller.page!
        : controller.initialPage.toDouble();
  }

  Finder centreLabelled(String label) => find.ancestor(
      of: find.byType(FloatingActionButton),
      matching: find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.label == label));

  Finder labelled(String label) => find.byWidgetPredicate(
      (w) => w is Semantics && w.properties.label == label);

  Future<void> tapCentre(WidgetTester tester) async {
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    tester.takeException(); // LiveRunMap tile-fetch noise
  }

  Future<void> tapControl(WidgetTester tester, String label) async {
    await tester.tap(labelled(label));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    tester.takeException();
  }

  Future<void> emitFixes(
    WidgetTester tester,
    Iterable<Position> fixes,
  ) async {
    for (final fix in fixes) {
      geolocator.emit(fix);
      await tester.pump(const Duration(milliseconds: 50));
    }
    tester.takeException();
  }

  /// START, the countdown, and a short track — a run in progress.
  Future<void> recordARun(WidgetTester tester) async {
    await tester.tap(find.text('START'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    tester.takeException();
    expect(runRecordingActive.value, isTrue,
        reason: 'the countdown ends in a recording');
    await emitFixes(tester, [
      for (var i = 0; i < 6; i++)
        _pos(metresEast: i * 12.0, secondsFromStart: i * 2),
    ]);
  }

  /// A completed hold on whichever Stop the layout shows. The 800 ms hold
  /// itself is pinned by home_screen_test; this invokes what a completed hold
  /// fires and waits for the summary, which shows once the local save has
  /// landed.
  Future<void> holdStop(WidgetTester tester, {required String reason}) async {
    final stop = find.byType(HoldToStopButton).hitTestable();
    expect(stop, findsOneWidget, reason: reason);
    final button = tester.widget<HoldToStopButton>(stop);
    await tester.runAsync(() async => button.onHoldComplete());
    // Wait on the summary, not runSummaryShowing: the rail panel's Stop is
    // `_stop` itself, so the runAsync above already awaited the whole stop
    // and the flag is set before any frame has built the summary.
    await pumpUntil(tester, () => tester.any(find.byType(FinishedSummary)),
        describe: 'the finished summary after the Stop hold');
    tester.takeException();
  }

  Future<void> holdDockedStop(WidgetTester tester) => holdStop(tester,
      reason: 'on the Run page mid-run the centre button is the Stop');

  // The shell hydrates and syncs its stores in the background, so a write
  // can still be open at the end of a journey, and teardown deletes the
  // temp directories it writes into. Wait it out on both sides of the
  // unmount: dispose can queue one too.
  Future<void> unmount(WidgetTester tester) async {
    await pumpUntilStoreWritesSettle(tester);
    await tester.pumpWidget(const SizedBox());
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await pumpUntilStoreWritesSettle(tester);
    tester.takeException();
  }

  group('pause and resume mid-run, through the shell', () {
    testWidgets(
        'a paused run keeps recording, drops the fixes taken while paused, '
        'and saves as one run', (tester) async {
      final runStore = await pumpShell(tester);
      await tapCentre(tester);
      await recordARun(tester);

      await tapControl(tester, 'Pause run');
      expect(labelled('Resume run'), findsOneWidget,
          reason: 'the paused panel offers Resume in place of Pause');
      expect(runRecordingActive.value, isTrue,
          reason: 'a pause is not the end of the run');
      expect(find.byType(HoldToStopButton).hitTestable(), findsOneWidget,
          reason: 'the docked Stop stays while paused');
      expect(find.text('START'), findsNothing);

      // The runner walks 300 m north to a water fountain with the run paused.
      await emitFixes(tester, [
        for (var i = 1; i <= 3; i++)
          _pos(
              metresEast: 60,
              metresNorth: i * 100.0,
              secondsFromStart: 20 + i * 40),
      ]);

      await tapControl(tester, 'Resume run');
      expect(labelled('Pause run'), findsOneWidget);
      expect(runRecordingActive.value, isTrue);

      // And carries on from 400 m north once resumed.
      await emitFixes(tester, [
        for (var i = 0; i < 6; i++)
          _pos(
              metresEast: 60 + i * 12.0,
              metresNorth: 400,
              secondsFromStart: 200 + i * 2),
      ]);

      await holdDockedStop(tester);
      expect(runStore.runs, hasLength(1),
          reason: 'a pause and resume is one run, not two');
      final saved = runStore.runs.single;
      final northings = saved.track.map(_metresNorthOf).toList();
      expect(northings.where((n) => n > 50 && n < 350), isEmpty,
          reason: 'the recorder drops every fix taken while paused, so the '
              'walk to the fountain is not in the track');
      expect(northings.any((n) => n < 50), isTrue,
          reason: 'the stretch before the pause is in the track');
      expect(northings.any((n) => n > 350), isTrue,
          reason: 'the stretch after Resume is in the track');
      expect(saved.distanceMetres, lessThan(300),
          reason: 'the first fix after Resume is a fresh anchor, so the '
              '400 m covered while paused is not credited as distance');

      await unmount(tester);
    });
  });

  group('laps, through the shell', () {
    testWidgets('laps marked mid-run are announced and saved on the run',
        (tester) async {
      final runStore = await pumpShell(tester);
      await tapCentre(tester);
      await recordARun(tester);

      await tapControl(tester, 'Mark lap');
      expect(find.text('Lap 1 marked'), findsOneWidget);
      expect(labelled('Mark lap, 1 so far'), findsOneWidget);

      await emitFixes(tester, [
        for (var i = 6; i < 12; i++)
          _pos(metresEast: i * 12.0, secondsFromStart: i * 2),
      ]);
      await tapControl(tester, 'Mark lap, 1 so far');
      expect(find.text('Lap 2 marked'), findsOneWidget);
      expect(labelled('Mark lap, 2 so far'), findsOneWidget);

      await holdDockedStop(tester);
      expect(runStore.runs, hasLength(1));
      final saved = runStore.runs.single;
      final laps = (saved.metadata?['laps'] as List?)
          ?.cast<Map<String, dynamic>>();
      expect(laps, isNotNull, reason: 'the saved run carries its laps');
      expect(laps!.map((l) => l['index']), [1, 2]);
      expect(laps.first['start_offset_s'], 0,
          reason: 'the first lap starts at the start of the run');
      expect(laps[1]['start_offset_s'],
          (laps[0]['start_offset_s'] as int) + (laps[0]['duration_s'] as int),
          reason: 'a lap starts where the one before it ended');
      for (final lap in laps) {
        expect(lap['distance_m'], isA<num>());
        expect(lap['distance_m'] as num, greaterThanOrEqualTo(0));
        expect(lap['duration_s'], isA<int>());
      }
      final lapped = laps.fold<double>(
          0, (sum, l) => sum + (l['distance_m'] as num).toDouble());
      expect(lapped, lessThanOrEqualTo(saved.distanceMetres + 0.5),
          reason: 'per-lap distances are deltas, never more than the run');

      await unmount(tester);
    });
  });

  group('the tablet shell', () {
    Finder railFab() => find.descendant(
        of: find.byType(NavigationRail),
        matching: find.byType(FloatingActionButton));

    Future<void> tapRailFab(WidgetTester tester) async {
      await tester.tap(railFab());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      tester.takeException();
    }

    testWidgets(
        'the rail starts a run, the panel keeps its own Stop, and a new run '
        'from the summary lands on START', (tester) async {
      tester.view.physicalSize = const Size(2560, 1440);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);
      final runStore = await pumpShell(tester);
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(BottomAppBar), findsNothing);
      expect(centreLabelled('Start a run'), findsOneWidget);

      await tapRailFab(tester);
      expect(shellPage(tester), 2);
      expect(find.text('START'), findsOneWidget);

      await recordARun(tester);
      expect(
          find.descendant(
              of: find.byType(NavigationRail),
              matching: find.byType(HoldToStopButton)),
          findsNothing,
          reason: 'the rail has no docked Stop');
      expect(railFab(), findsOneWidget,
          reason: 'the rail keeps its leading button mid-run');
      expect(centreLabelled('Return to your run'), findsOneWidget);

      await holdStop(tester,
          reason: 'on the rail the run panel carries its own Stop');
      expect(runStore.runs, hasLength(1));
      expect(shellPage(tester), 2, reason: 'stopping keeps you on Run');
      expect(find.byType(ErrorWidget), findsNothing,
          reason: 'nothing on the shell failed to build after the stop');
      expect(find.byType(FinishedSummary), findsOneWidget,
          reason: 'the Run page shows the finished summary');
      expect(find.text('Done'), findsOneWidget);
      expect(runRecordingActive.value, isFalse);
      expect(centreLabelled('Start a run'), findsOneWidget);

      await tapRailFab(tester);
      expect(shellPage(tester), 2);
      expect(find.text('START'), findsOneWidget);
      expect(find.text('Done'), findsNothing);
      expect(find.textContaining('already on'), findsNothing);
      expect(runStore.runs, hasLength(1),
          reason: 'leaving the summary keeps the saved run');

      await unmount(tester);
    });
  });

  group('a run brought back after the process was killed', () {
    /// What main.dart does at cold start: the in-progress checkpoint is on
    /// disk, the store loads it, and the recovery pass classifies it as
    /// resumable before HomeScreen is built with it.
    Future<(LocalRunStore, Directory)> seedKilledRun(
        WidgetTester tester) async {
      final dir = tempDir('controls_resume_');
      final store = LocalRunStore();
      await store.init(overrideDirectory: dir);
      cm.Run? loaded;
      await tester.runAsync(() async {
        await store.saveInProgress(_killedPartial());
        loaded = await store.loadInProgress();
      });
      expect(loaded, isNotNull,
          reason: 'the checkpoint written before the kill reads back');
      final evaluation = evaluateInProgressPartial(loaded,
          now: DateTime(2026, 4, 10, 10, 0, 0));
      expect(evaluation.outcome, InProgressOutcome.resumable);
      await pumpShell(tester,
          runStore: store, resumablePartial: evaluation.resumablePartial);
      return (store, dir);
    }

    Future<void> awaitPrompt(WidgetTester tester) async {
      // The shell jumps to the Run page on its first frame, and the recorder
      // asks on the frame after it builds.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      tester.takeException();
      expect(shellPage(tester), 2,
          reason: 'a resumable run opens the app on the Run page');
      expect(find.text('Resume your run?'), findsOneWidget);
    }

    Finder dialogAction(String label) => find.descendant(
        of: find.byType(AlertDialog), matching: find.text(label));

    testWidgets('Resume continues the same run and Stop saves it as one',
        (tester) async {
      final (runStore, dir) = await seedKilledRun(tester);
      await awaitPrompt(tester);

      await tester.tap(dialogAction('Resume'));
      await tester.pump();
      // Past the dialog's exit transition (150 ms), on the fake clock.
      await tester.pump(const Duration(milliseconds: 300));
      tester.takeException();
      expect(find.text('Resume your run?'), findsNothing);
      await pumpUntil(tester, () => runRecordingActive.value,
          describe: 'the resumed recording');
      expect(find.text('START'), findsNothing,
          reason: 'Resume goes straight back to recording, no countdown');
      expect(find.byType(HoldToStopButton).hitTestable(), findsOneWidget,
          reason: 'the resumed run gets the docked Stop like any other');

      await tester.pump(const Duration(seconds: 1));
      tester.takeException();
      await emitFixes(tester, [
        for (var i = 0; i < 3; i++)
          _pos(metresEast: 1000 + i * 12.0, secondsFromStart: i * 2),
      ]);

      await holdDockedStop(tester);
      expect(runStore.runs, hasLength(1),
          reason: 'finishing a resumed run saves ONE run, not a second record');
      final saved = runStore.runs.single;
      expect(saved.id, 'resume-me-1',
          reason: 'the finished run is the same run that was resumed');
      expect(saved.duration, greaterThanOrEqualTo(const Duration(minutes: 40)),
          reason: 'the clock carries on from before the kill');
      expect(saved.distanceMetres, greaterThanOrEqualTo(6700),
          reason: 'the distance banked before the kill is kept');
      final laps = saved.metadata?['laps'] as List?;
      expect(laps, isNotNull);
      expect((laps!.first as Map)['index'], 1,
          reason: 'the lap marked before the kill survives the resume');
      await pumpUntil(
          tester, () => !File('${dir.path}/in_progress.json').existsSync(),
          describe: 'the checkpoint to be cleared once the run is saved');

      await unmount(tester);
    });

    testWidgets('Discard returns to START with nothing saved', (tester) async {
      final (runStore, dir) = await seedKilledRun(tester);
      await awaitPrompt(tester);

      await tester.tap(dialogAction('Discard'));
      await tester.pump();
      await pumpUntil(
          tester, () => !File('${dir.path}/in_progress.json').existsSync(),
          describe: 'Discard to drop the checkpoint');
      // pumpUntil never advances the fake clock; the dialog's exit
      // transition (150 ms) needs it.
      await tester.pump(const Duration(milliseconds: 300));
      tester.takeException();

      expect(find.text('Resume your run?'), findsNothing);
      expect(find.text('START'), findsOneWidget);
      expect(runRecordingActive.value, isFalse);
      expect(runSummaryShowing.value, isFalse);
      expect(runStore.runs, isEmpty, reason: 'Discard saves nothing');
      expect(centreLabelled('Start a run'), findsOneWidget);

      await unmount(tester);
    });
  });
}
