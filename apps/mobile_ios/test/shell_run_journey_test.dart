// The everyday run journeys, driven through the real shell with the real
// recorder inside it.
//
// home_screen_test.dart fakes the recorder's state by writing the notifiers it
// publishes, and run_screen_recording_flow_test.dart mounts RunScreen alone,
// so nothing walked a run from the centre button to the next one. That gap is
// how a stopped run's summary read as "already on Run" and left the centre
// button with nowhere to go. These tests own the seam: they only tap what a
// runner taps, and assert what a runner sees.
import 'dart:async';
import 'dart:io';

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
    speed: 2.5,
    speedAccuracy: 1,
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
  /// button's tap starts a run — the default a new account sees.
  Future<LocalRunStore> pumpShell(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = Preferences();
    await prefs.init();
    final runStore = LocalRunStore();
    await runStore.init(overrideDirectory: tempDir('journey_runs_'));
    final gearStore = LocalGearStore();
    await gearStore.init(overrideDirectory: tempDir('journey_gear_'));
    final gymStore = LocalGymStore();
    await gymStore.init(overrideDirectory: tempDir('journey_gym_'));
    final foodStore = LocalFoodStore();
    await foodStore.init(overrideDirectory: tempDir('journey_food_'));
    final social = SocialService();

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: HomeScreen(
          apiClient: null,
          runStore: runStore,
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
        ),
      ),
    );
    await tester.pump();
    return runStore;
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

  Future<void> back(WidgetTester tester) async {
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// START, the countdown, and a short track — a run in progress.
  Future<void> recordARun(WidgetTester tester, {int fromSecond = 0}) async {
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
    for (var i = 0; i < 6; i++) {
      geolocator.emit(_pos(
          metresEast: i * 12.0, secondsFromStart: fromSecond + i * 2));
      await tester.pump(const Duration(milliseconds: 50));
    }
    tester.takeException();
  }

  /// A completed hold on the shell's docked Stop. The 800 ms hold itself is
  /// pinned by home_screen_test; this invokes what a completed hold fires and
  /// waits for the summary, which shows once the local save has landed.
  Future<void> holdDockedStop(WidgetTester tester) async {
    final stop = find.byType(HoldToStopButton).hitTestable();
    expect(stop, findsOneWidget,
        reason: 'on the Run page mid-run the centre button is the Stop');
    final button = tester.widget<HoldToStopButton>(stop);
    await tester.runAsync(() async => button.onHoldComplete());
    await pumpUntil(tester, () => runSummaryShowing.value,
        describe: 'the finished summary after the Stop hold');
    tester.takeException();
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    tester.takeException();
  }

  group('a run, start to finish, through the shell', () {
    testWidgets('the centre button reaches the start screen and records',
        (tester) async {
      await pumpShell(tester);
      expect(shellPage(tester), 0, reason: 'the app opens on Home');
      expect(centreLabelled('Start a run'), findsOneWidget);

      await tapCentre(tester);
      expect(shellPage(tester), 2);
      expect(find.text('START'), findsOneWidget);

      await recordARun(tester);
      expect(find.byType(HoldToStopButton), findsOneWidget,
          reason: 'the docked centre button is the Stop while recording');

      await unmount(tester);
    });

    testWidgets('stopping saves the run and shows its summary',
        (tester) async {
      final runStore = await pumpShell(tester);
      await tapCentre(tester);
      await recordARun(tester);

      await holdDockedStop(tester);
      expect(runStore.runs, hasLength(1));
      expect(find.text('Done'), findsOneWidget);
      expect(runRecordingActive.value, isFalse);
      expect(centreLabelled('Start a run'), findsOneWidget,
          reason: 'with the run over, the Stop turns back into Start run');

      await unmount(tester);
    });

    testWidgets(
        'Start run from the summary opens the start screen, not an '
        '"already on Run" banner', (tester) async {
      final runStore = await pumpShell(tester);
      await tapCentre(tester);
      await recordARun(tester);
      await holdDockedStop(tester);

      await tapCentre(tester);
      expect(find.text('START'), findsOneWidget);
      expect(find.text('Done'), findsNothing);
      expect(find.textContaining('already on'), findsNothing);
      expect(runStore.runs, hasLength(1),
          reason: 'leaving the summary keeps the saved run');

      await unmount(tester);
    });

    testWidgets('Done on the summary returns to the start screen',
        (tester) async {
      final runStore = await pumpShell(tester);
      await tapCentre(tester);
      await recordARun(tester);
      await holdDockedStop(tester);

      await tester.tap(find.text('Done'));
      await tester.pump();
      expect(find.text('START'), findsOneWidget);
      expect(runSummaryShowing.value, isFalse);
      expect(runStore.runs, hasLength(1));

      await unmount(tester);
    });

    testWidgets('a second run saves a second, separate run', (tester) async {
      final runStore = await pumpShell(tester);
      await tapCentre(tester);
      await recordARun(tester);
      await holdDockedStop(tester);
      await tapCentre(tester);

      await recordARun(tester, fromSecond: 600);
      await holdDockedStop(tester);

      expect(runStore.runs, hasLength(2));
      expect(runStore.runs.map((r) => r.id).toSet(), hasLength(2),
          reason: 'the second recording must not overwrite the first');

      await unmount(tester);
    });
  });

  group('leaving the Run page and coming back', () {
    testWidgets('mid-run, back goes Home and the centre button returns to '
        'the same recording', (tester) async {
      final runStore = await pumpShell(tester);
      await tapCentre(tester);
      await recordARun(tester);

      await back(tester);
      expect(shellPage(tester), 0);
      expect(runRecordingActive.value, isTrue,
          reason: 'leaving the page must not end the run');
      expect(centreLabelled('Return to your run'), findsOneWidget);

      await tapCentre(tester);
      expect(shellPage(tester), 2);
      expect(runRecordingActive.value, isTrue);
      expect(find.text('START'), findsNothing,
          reason: 'returning must not reset the recorder');

      await holdDockedStop(tester);
      expect(runStore.runs, hasLength(1));

      await unmount(tester);
    });

    testWidgets('from the summary, back then Start run lands on the start '
        'screen, not the old summary', (tester) async {
      final runStore = await pumpShell(tester);
      await tapCentre(tester);
      await recordARun(tester);
      await holdDockedStop(tester);

      await back(tester);
      expect(shellPage(tester), 0);

      await tapCentre(tester);
      expect(shellPage(tester), 2);
      expect(find.text('START'), findsOneWidget);
      expect(find.text('Done'), findsNothing);
      expect(runStore.runs, hasLength(1));

      await unmount(tester);
    });
  });

  group('throwing a run away', () {
    testWidgets('Discard mid-run saves nothing and returns to the start '
        'screen', (tester) async {
      final runStore = await pumpShell(tester);
      await tapCentre(tester);
      await recordARun(tester);

      await tester.tap(labelled('Discard run'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Discard run?'), findsOneWidget);
      await tester.tap(find.descendant(
          of: find.byType(AlertDialog), matching: find.text('Discard')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      tester.takeException();

      expect(find.text('START'), findsOneWidget);
      expect(runRecordingActive.value, isFalse);
      expect(runSummaryShowing.value, isFalse);
      expect(runStore.runs, isEmpty);
      expect(centreLabelled('Start a run'), findsOneWidget);

      await unmount(tester);
    });
  });
}
