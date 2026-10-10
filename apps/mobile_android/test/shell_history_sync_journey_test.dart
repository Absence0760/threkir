// "My run shows up": a run recorded through the real shell, then found where a
// runner goes looking for it, signed out and signed in.
//
// runs_screen and run_detail tests mount their screen alone over a seeded
// store, and sync_service_test drives the queue with no screen at all, so
// nothing followed one run from the docked Stop to its row, its detail page
// and its upload. These tests own that seam the way shell_run_journey_test
// does: they only tap what a runner taps, and assert what a runner reads.
import 'dart:async';
import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart' as cm;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;
import 'package:wakelock_plus_platform_interface/wakelock_plus_platform_interface.dart';

import '../lib/audio_cues.dart';
import '../lib/ble_heart_rate.dart';
import '../lib/ble_treadmill.dart';
import '../lib/l10n/date_format.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/l10n/locale_support.dart';
import '../lib/local_food_store.dart';
import '../lib/local_gear_store.dart';
import '../lib/local_gym_store.dart';
import '../lib/local_route_store.dart';
import '../lib/local_run_store.dart';
import '../lib/preferences.dart';
import '../lib/race_controller.dart';
import '../lib/screens/home_screen.dart';
import '../lib/screens/run_detail_screen.dart';
import '../lib/screens/run_screen.dart';
import '../lib/screens/runs_screen.dart';
import '../lib/social_service.dart';
import '../lib/training_service.dart';
import '../lib/widgets/run_list_tile.dart';
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

/// A signed-in account that consented and onboarded at sign-up, so neither
/// the age gate nor the setup wizard stands between the shell and the runner.
/// The run upload goes through the two calls the app actually makes: the
/// stop path's `saveRun` and the Runs list's Sync, which is `saveRunsBatch`
/// as SyncService's is. [offline] fails both the way a dropped connection
/// does.
class _JourneyApi extends ApiClient {
  _JourneyApi({this.offline = false});

  bool offline;
  int saveRunAttempts = 0;
  final savedRunIds = <String>[];
  final batchedRunIds = <List<String>>[];

  static final _stamp = DateTime.utc(2026, 10, 1);

  @override
  String? get userId => 'journey-runner';

  @override
  Stream<String?> get authUserChanges => const Stream<String?>.empty();

  @override
  Future<cm.UserProfileRow?> fetchMyProfile() async => cm.UserProfileRow(
    shadowHidden: false,
    id: 'journey-runner',
    displayName: null,
    ageConfirmedAt: _stamp,
    termsAcceptedAt: _stamp,
    onboardedAt: _stamp,
  );

  @override
  Future<List<cm.Run>> getRuns({
    int limit = 50,
    DateTime? before,
    DateTime? updatedSince,
  }) async => const <cm.Run>[];

  @override
  Future<List<cm.RouteMatchCandidate>> fetchRoutesIntersectingTrack(
    List<cm.Waypoint> track, {
    double toleranceMetres = 100,
    int maxResults = 10,
  }) async => const <cm.RouteMatchCandidate>[];

  @override
  Future<void> saveRun(cm.Run run, {bool? isPublic}) async {
    saveRunAttempts++;
    if (offline) throw const SocketException('network unreachable');
    savedRunIds.add(run.id);
  }

  @override
  Future<cm.RunPushOutcome> saveRunsBatch(
    List<cm.Run> runs, {
    int uploadConcurrency = 8,
    int rowChunkSize = 100,
    void Function(int saved)? onProgress,
  }) async {
    if (offline) throw const SocketException('network unreachable');
    batchedRunIds.add(runs.map((r) => r.id).toList());
    return const cm.RunPushOutcome();
  }
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
  final l10n = lookupAppLocalizations(const Locale('en'));

  void mockChannel(
    MethodChannel channel,
    Future<Object?> Function(MethodCall) handler,
  ) {
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
    await initializeDateFormatting();
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
    mockChannel(
      const MethodChannel('flutter.baseflow.com/permissions/methods'),
      (call) async {
        if (call.arguments is List) {
          return {for (final p in (call.arguments as List)) p: 1};
        }
        return 1;
      },
    );
    mockChannel(const MethodChannel('flutter_tts'), (call) async => 1);
    mockChannel(
      const MethodChannel('run_app/run_notification'),
      (call) async => null,
    );
    mockChannel(
      const MethodChannel('step_count', StandardMethodCodec()),
      (call) async => null,
    );
    mockChannel(
      const MethodChannel('step_detection', StandardMethodCodec()),
      (call) async => null,
    );
  });

  tearDown(() async {
    for (final channel in mockedChannels) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    }
    mockedChannels.clear();
    await geolocator.dispose();
    runRecordingActive.value = false;
    for (final dir in tempDirs) {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    }
    tempDirs.clear();
  });

  /// Mounts the shell for a runner with no lift or meal logged, so the centre
  /// button's tap starts a run. [api] null is a signed-out runner.
  Future<({LocalRunStore runStore, Preferences prefs})> pumpShell(
    WidgetTester tester, {
    ApiClient? api,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = Preferences();
    await prefs.init();
    final runStore = LocalRunStore();
    await runStore.init(overrideDirectory: tempDir('history_runs_'));
    final gearStore = LocalGearStore();
    await gearStore.init(overrideDirectory: tempDir('history_gear_'));
    final gymStore = LocalGymStore();
    await gymStore.init(overrideDirectory: tempDir('history_gym_'));
    final foodStore = LocalFoodStore();
    await foodStore.init(overrideDirectory: tempDir('history_food_'));
    final social = SocialService();

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: HomeScreen(
          apiClient: api,
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
    // The sign-in gates run post-frame; a consented, onboarded profile passes
    // straight through them.
    await tester.pump();
    return (runStore: runStore, prefs: prefs);
  }

  Future<void> tapCentre(WidgetTester tester) async {
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    tester.takeException(); // LiveRunMap tile-fetch noise
  }

  /// A tap on the shell's nav item reading [label].
  Future<void> tapNav(WidgetTester tester, String label) async {
    await tester.tap(
      find.descendant(
        of: find.byType(BottomAppBar),
        matching: find.text(label),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
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
    expect(
      runRecordingActive.value,
      isTrue,
      reason: 'the countdown ends in a recording',
    );
    for (var i = 0; i < 6; i++) {
      geolocator.emit(_pos(metresEast: i * 12.0, secondsFromStart: i * 2));
      await tester.pump(const Duration(milliseconds: 50));
    }
    tester.takeException();
  }

  /// A completed hold on the shell's docked Stop, then the finished summary,
  /// which shows once the local save has landed. The 800 ms hold itself is
  /// pinned by home_screen_test; this invokes what a completed hold fires.
  Future<void> holdDockedStop(WidgetTester tester) async {
    final stop = find.byType(HoldToStopButton).hitTestable();
    expect(
      stop,
      findsOneWidget,
      reason: 'on the Run page mid-run the centre button is the Stop',
    );
    final button = tester.widget<HoldToStopButton>(stop);
    await tester.runAsync(() async => button.onHoldComplete());
    await pumpUntil(
      tester,
      () => tester.any(
        find.descendant(
          of: find.byType(FinishedSummary),
          matching: find.text(l10n.runDone),
        ),
      ),
      describe: 'the finished summary after the Stop hold',
    );
    tester.takeException();
  }

  Finder summaryText(String text) => find.descendant(
    of: find.byType(FinishedSummary),
    matching: find.text(text),
  );

  /// The run's row on the visible run list.
  Finder runRow(String runId) => find.descendant(
    of: find.byType(RunsScreen),
    matching: find.byWidgetPredicate(
      (w) => w is RunListTile && w.key == ValueKey(runId),
    ),
  );

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    tester.takeException();
  }

  group('a stopped run shows up where a runner looks for it', () {
    testWidgets(
      'the Runs list carries it with the distance and date the runner '
      'saw, and its row opens the same run',
      (tester) async {
        final s = await pumpShell(tester);
        await tapCentre(tester);
        await recordARun(tester);
        await holdDockedStop(tester);

        expect(s.runStore.runs, hasLength(1));
        final run = s.runStore.runs.single;
        final unit = s.prefs.unit;
        final distance = UnitFormat.distance(run.distanceMetres, unit);
        expect(
          summaryText(distance),
          findsOneWidget,
          reason: 'the summary reads the distance the run was saved with',
        );

        await tapNav(tester, l10n.navTraining);
        final row = runRow(run.id);
        expect(row, findsOneWidget, reason: 'the run just recorded is listed');
        final tag = localeToTag(Localizations.localeOf(tester.element(row)));
        expect(
          find.descendant(of: row, matching: find.text(distance)),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: row,
            matching: find.textContaining(formatDateShort(run.startedAt, tag)),
          ),
          findsOneWidget,
        );

        await tester.tap(row);
        await pumpUntil(
          tester,
          () => tester.any(find.byType(RunDetailScreen)),
          describe: 'the run detail screen after tapping the row',
        );
        await tester.pump(const Duration(milliseconds: 400));
        tester.takeException();
        final detail = find.byType(RunDetailScreen);
        expect(
          find.descendant(
            of: detail,
            matching: find.text(
              UnitFormat.distanceValue(run.distanceMetres, unit),
            ),
          ),
          findsWidgets,
          reason: 'the detail page shows the distance the row did',
        );
        expect(
          find.descendant(
            of: detail,
            matching: find.text(UnitFormat.distanceLabel(unit)),
          ),
          findsWidgets,
        );

        await unmount(tester);
      },
    );

    testWidgets(
      'with a second modality switched on, the History tab lists it too',
      (tester) async {
        final s = await pumpShell(tester);
        await tapCentre(tester);
        await recordARun(tester);
        await holdDockedStop(tester);
        final run = s.runStore.runs.single;

        // The History tab only exists beside Gym or Nutrition; a runner turns
        // one on in Settings (fitnessHubTabs).
        await tester.runAsync(() => s.prefs.setShowNutrition(true));
        await tester.pump();

        await tapNav(tester, l10n.navFitness);
        await tester.tap(find.widgetWithText(Tab, l10n.navHistory));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        tester.takeException();

        final history = find.byKey(const PageStorageKey<String>('fitness-all'));
        expect(history, findsOneWidget, reason: 'the History tab is showing');
        final row = find.descendant(of: history, matching: runRow(run.id));
        expect(row, findsOneWidget);
        expect(
          find.descendant(
            of: row,
            matching: find.text(
              UnitFormat.distance(run.distanceMetres, s.prefs.unit),
            ),
          ),
          findsOneWidget,
        );

        await unmount(tester);
      },
    );
  });

  group('signed in, the run reaches the cloud', () {
    testWidgets(
      'the docked Stop uploads the run once, marks it synced, and the '
      'summary says Synced',
      (tester) async {
        final api = _JourneyApi();
        final s = await pumpShell(tester, api: api);
        await tapCentre(tester);
        await recordARun(tester);
        await holdDockedStop(tester);

        await pumpUntil(
          tester,
          () => tester.any(summaryText(l10n.runSynced)),
          describe: 'the summary to report the upload',
        );
        final run = s.runStore.runs.single;
        expect(api.savedRunIds, [run.id]);
        expect(
          s.runStore.unsyncedRuns,
          isEmpty,
          reason: 'an uploaded run must not stay queued for another push',
        );

        await tapNav(tester, l10n.navTraining);
        await pumpUntil(
          tester,
          () => tester.any(find.byTooltip(l10n.historyRefreshTooltip)),
          describe: "the Runs list's first fetch to settle",
        );
        final row = runRow(run.id);
        expect(row, findsOneWidget);
        expect(
          find.descendant(
            of: row,
            matching: find.byTooltip(l10n.historyQueuedToSync),
          ),
          findsNothing,
          reason: 'a synced run carries no queued-to-sync mark',
        );
        expect(
          api.saveRunAttempts,
          1,
          reason: 'opening the list must not upload the run again',
        );
        expect(api.batchedRunIds, isEmpty);

        await unmount(tester);
      },
    );

    testWidgets(
      'a failed upload keeps the run, says it saved offline, and Sync in '
      'Runs sends it once the connection is back',
      (tester) async {
        final api = _JourneyApi(offline: true);
        final s = await pumpShell(tester, api: api);
        await tapCentre(tester);
        await recordARun(tester);
        await holdDockedStop(tester);

        await pumpUntil(
          tester,
          () => tester.any(summaryText(l10n.runSyncFailedSaveOffline)),
          describe: 'the summary to report the failed upload',
        );
        expect(summaryText(l10n.runSynced), findsNothing);
        expect(api.saveRunAttempts, 1);
        expect(api.savedRunIds, isEmpty);
        final run = s.runStore.runs.single;
        expect(
          s.runStore.unsyncedRuns.map((r) => r.id),
          [run.id],
          reason: 'the run stays queued for a later retry',
        );

        await tapNav(tester, l10n.navTraining);
        final syncButton = find.byTooltip(l10n.historySyncTooltip(1));
        await pumpUntil(
          tester,
          () => tester.any(syncButton),
          describe: "the Runs list's Sync button for the one queued run",
        );
        final row = runRow(run.id);
        expect(row, findsOneWidget);
        expect(
          find.descendant(
            of: row,
            matching: find.byTooltip(l10n.historyQueuedToSync),
          ),
          findsOneWidget,
        );

        api.offline = false;
        await tester.tap(syncButton);
        await tester.pump();
        await pumpUntil(
          tester,
          () =>
              s.runStore.unsyncedRuns.isEmpty &&
              tester.any(find.text(l10n.historySyncAllDone(1))),
          describe: 'the retried upload to land and be reported',
        );
        await tester.pump();
        expect(s.runStore.unsyncedRuns, isEmpty);
        expect(api.batchedRunIds, [
          [run.id],
        ]);
        expect(api.saveRunAttempts, 1);
        expect(
          find.descendant(
            of: row,
            matching: find.byTooltip(l10n.historyQueuedToSync),
          ),
          findsNothing,
        );

        // Let the confirmation banner run out before the tree goes.
        await tester.pump(const Duration(seconds: 4));
        await tester.pump(const Duration(milliseconds: 500));
        await unmount(tester);
      },
    );
  });
}
