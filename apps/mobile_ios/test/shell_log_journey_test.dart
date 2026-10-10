// The centre button's lift and food journeys, driven through the real shell
// with the real Gym and Nutrition screens and their real composers inside it.
//
// home_screen_test.dart pins where each Log action lands, and the composer
// suites mount each sheet alone, so nothing walked a lift or a meal from the
// centre button to the saved row on screen. These tests own that seam: they
// only tap what a person taps, and assert what they see and what the store
// now holds.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/date_symbol_data_local.dart';
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
import '../lib/offline_sync_store.dart' show SyncState;
import '../lib/preferences.dart';
import '../lib/race_controller.dart';
import '../lib/screens/gym_screen.dart';
import '../lib/screens/home_screen.dart';
import '../lib/screens/nutrition_screen.dart';
import '../lib/screens/run_screen.dart' show runRecordingActive;
import '../lib/social_service.dart';
import '../lib/training_service.dart';
import '../lib/widgets/gym_compose_sheet.dart';
import '../lib/widgets/nutrition_log_sheet.dart';
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

typedef _Shell = ({
  LocalGymStore gymStore,
  LocalFoodStore foodStore,
  Preferences prefs,
});

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
    // The gym list renders a localised date through intl's DateFormat.
    await initializeDateFormatting();
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
    for (final dir in tempDirs) {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    }
    tempDirs.clear();
  });

  /// Mounts the shell signed out, with nothing logged. [showGym] and
  /// [showNutrition] are the runner's own Settings choices; left null, each
  /// modality stays hidden until it has data, as on a new account.
  Future<_Shell> pumpShell(WidgetTester tester,
      {bool? showGym, bool? showNutrition}) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = Preferences();
    await prefs.init();
    if (showGym != null) await prefs.setShowGym(showGym);
    if (showNutrition != null) await prefs.setShowNutrition(showNutrition);
    final runStore = LocalRunStore();
    await runStore.init(overrideDirectory: tempDir('log_journey_runs_'));
    final gearStore = LocalGearStore();
    await gearStore.init(overrideDirectory: tempDir('log_journey_gear_'));
    final gymStore = LocalGymStore();
    await gymStore.init(overrideDirectory: tempDir('log_journey_gym_'));
    final foodStore = LocalFoodStore();
    await foodStore.init(overrideDirectory: tempDir('log_journey_food_'));
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
    return (gymStore: gymStore, foodStore: foodStore, prefs: prefs);
  }

  double shellPage(WidgetTester tester) {
    final controller =
        tester.widget<PageView>(find.byType(PageView).first).controller!;
    return controller.hasClients
        ? controller.page!
        : controller.initialPage.toDouble();
  }

  /// The shell's centre button. Gym's own add is a FloatingActionButton too,
  /// so the type alone matches two on that tab; the centre one is the only
  /// FAB under the shell's manually triggered tooltip.
  Finder centreButton() => find.descendant(
      of: find.byWidgetPredicate((w) =>
          w is Tooltip && w.triggerMode == TooltipTriggerMode.manual),
      matching: find.byType(FloatingActionButton));

  /// An item on the open fan. Nutrition's own add carries the same "Log
  /// food" tooltip, so the item is read off the fan alone.
  Finder fanItem(String label) => find.descendant(
      of: find.byWidgetPredicate(
          (w) => w.runtimeType.toString() == '_LogSpeedDial'),
      matching: find.byTooltip(label));

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    tester.takeException(); // LiveRunMap tile-fetch noise on the Run page
  }

  Future<void> openFan(WidgetTester tester) async {
    await tester.tap(centreButton());
    await settle(tester);
    expect(fanItem('Log run'), findsOneWidget,
        reason: 'with a second modality shown the centre tap fans the menu');
  }

  Future<void> pick(WidgetTester tester, String label) async {
    await openFan(tester);
    await tester.tap(fanItem(label));
    await settle(tester);
    // A tab change inside the hub animates after the page settles.
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// Gym's own add, the composer it opens, one exercise with one set, Save.
  /// Returns once the store has written the workout and the composer is gone.
  Future<void> logALift(WidgetTester tester, LocalGymStore gymStore) async {
    final add = find.descendant(
        of: find.byType(GymScreen), matching: find.byTooltip('Log workout'));
    expect(add, findsOneWidget);
    await tester.tap(add);
    await settle(tester);
    expect(find.byType(GymComposeSheet), findsOneWidget);

    // Title, exercise name, reps, weight — the composer's field order.
    final fields = find.descendant(
        of: find.byType(GymComposeSheet), matching: find.byType(TextField));
    await tester.enterText(fields.at(0), 'Leg day');
    await tester.enterText(fields.at(1), 'Squat');
    await tester.enterText(fields.at(2), '5');
    await tester.enterText(fields.at(3), '100');
    await tester.pump();

    // The store notifies once the row and the index are both on disk.
    var written = false;
    gymStore.addListener(() => written = true);
    await tester.tap(find.text('Save workout'));
    await pumpUntil(tester, () => written,
        describe: "the composer's workout to land on disk");
    await pumpUntil(
        tester, () => !tester.any(find.byType(GymComposeSheet)),
        describe: 'the composer to close after its save');
    await settle(tester);
  }

  /// Nutrition's own add, the manual entry, Add. Returns once the store has
  /// written the entry and the composer is gone.
  Future<void> logAMeal(WidgetTester tester, LocalFoodStore foodStore) async {
    final add = find.descendant(
        of: find.byType(NutritionScreen), matching: find.byTooltip('Log food'));
    expect(add, findsOneWidget);
    await tester.tap(add);
    await settle(tester);
    expect(find.byType(NutritionLogSheet), findsOneWidget);

    await tester.tap(find.text('Enter manually'));
    await tester.pump();
    await tester.enterText(
        find.widgetWithText(TextField, 'Item name'), 'Banana');
    await tester.enterText(find.widgetWithText(TextField, 'Calories'), '105');
    await tester.pump();
    final addButton = find.widgetWithText(FilledButton, 'Add');
    await tester.ensureVisible(addButton);
    await tester.pump();

    var written = false;
    foodStore.addListener(() => written = true);
    await tester.tap(addButton);
    await pumpUntil(tester, () => written,
        describe: "the meal's row and index to land on disk");
    await pumpUntil(
        tester, () => !tester.any(find.byType(NutritionLogSheet)),
        describe: 'the composer to close after its save');
    await settle(tester);
  }

  Future<void> unmount(WidgetTester tester) async {
    await pumpUntilStoreWritesSettle(tester);
    await tester.pumpWidget(const SizedBox());
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    tester.takeException();
  }

  group('logging a lift from the centre button', () {
    testWidgets('Log lift, the Gym tab, its composer, and the saved workout',
        (tester) async {
      final s = await pumpShell(tester, showGym: true);

      await pick(tester, 'Log lift');
      expect(shellPage(tester), 1, reason: 'Gym is a tab of the Fitness hub');
      expect(find.byType(GymScreen), findsOneWidget);
      expect(find.byType(BottomAppBar), findsOneWidget,
          reason: 'a dwell-in surface, not a modal over the shell');

      await logALift(tester, s.gymStore);

      expect(shellPage(tester), 1, reason: 'saving keeps you on Gym');
      expect(
          find.descendant(
              of: find.byType(GymScreen), matching: find.text('Leg day')),
          findsOneWidget);
      expect(s.gymStore.workouts, hasLength(1));
      final w = s.gymStore.workouts.single;
      expect(w.syncState, SyncState.pendingCreate,
          reason: 'signed out, the workout waits on this device to sync');
      expect(w.sets, hasLength(1));
      expect(w.sets.single['exercise_name'], 'Squat');
      expect(w.sets.single['reps'], 5);
      expect(w.sets.single['weight_kg'], 100.0);

      await unmount(tester);
    });

    testWidgets('after a lift, Log run lands on the start screen',
        (tester) async {
      final s = await pumpShell(tester, showGym: true);
      await pick(tester, 'Log lift');
      await logALift(tester, s.gymStore);

      await pick(tester, 'Log run');
      expect(shellPage(tester), 2);
      expect(find.text('START'), findsOneWidget);
      expect(find.textContaining('already on'), findsNothing);
      expect(s.gymStore.workouts, hasLength(1));

      await unmount(tester);
    });
  });

  group('logging a meal from the centre button', () {
    testWidgets('Log food, the Nutrition tab, its composer, and the saved meal',
        (tester) async {
      final s = await pumpShell(tester, showNutrition: true);

      await pick(tester, 'Log food');
      expect(shellPage(tester), 1);
      expect(find.byType(NutritionScreen), findsOneWidget);
      expect(find.byType(BottomAppBar), findsOneWidget);

      await logAMeal(tester, s.foodStore);

      expect(shellPage(tester), 1, reason: 'saving keeps you on Nutrition');
      // The day's list sits under the rings and water cards, below the fold
      // of the shell's shorter viewport — scroll to it as a person would.
      final banana = find.descendant(
          of: find.byType(NutritionScreen), matching: find.text('Banana'));
      await tester.scrollUntilVisible(banana, 100,
          scrollable: find
              .descendant(
                  of: find.byType(NutritionScreen),
                  matching: find.byType(Scrollable))
              .first);
      expect(banana, findsOneWidget,
          reason: "the meal shows in the day's list");
      expect(s.foodStore.rows, hasLength(1));
      expect(s.foodStore.rows.single['item_name'], 'Banana');
      expect(s.foodStore.rows.single['calories'], 105.0);
      expect(s.foodStore.hasPending, isTrue,
          reason: 'signed out, the meal waits on this device to sync');

      await unmount(tester);
    });

    testWidgets('from Gym, Log food moves the hub to Nutrition',
        (tester) async {
      await pumpShell(tester, showGym: true, showNutrition: true);
      await pick(tester, 'Log lift');
      expect(find.byType(GymScreen), findsOneWidget);

      await pick(tester, 'Log food');
      expect(shellPage(tester), 1, reason: 'the same hub, another tab');
      expect(find.byType(NutritionScreen), findsOneWidget);
      // The hub's tab label and the Nutrition screen's own title.
      expect(find.text('Nutrition'), findsNWidgets(2));
      expect(find.textContaining('already on'), findsNothing);

      await unmount(tester);
    });
  });

  group('the first lift of a runner whose Gym is hidden', () {
    testWidgets('the welcome link, a logged lift, and the centre button now '
        'offers it', (tester) async {
      final s = await pumpShell(tester);
      expect(s.prefs.showGym, isNull);

      await tester.ensureVisible(find.text('Log a gym session'));
      await tester.tap(find.text('Log a gym session'));
      await settle(tester);
      expect(find.byType(GymScreen), findsOneWidget);
      expect(find.text('Gym is now shown'), findsOneWidget);
      // Read the banner out; it auto-dismisses after six seconds.
      await tester.pump(const Duration(seconds: 7));
      expect(find.text('Gym is now shown'), findsNothing);

      await logALift(tester, s.gymStore);
      expect(
          find.descendant(
              of: find.byType(GymScreen), matching: find.text('Leg day')),
          findsOneWidget);
      expect(s.gymStore.workouts, hasLength(1));
      expect(s.gymStore.workouts.single.syncState, SyncState.pendingCreate);

      // The centre button no longer starts a run outright: there is a lift
      // to log as well, so it fans the menu with Log lift on it.
      expect(find.text('Start run'), findsNothing);
      await openFan(tester);
      expect(fanItem('Log lift'), findsOneWidget);

      await unmount(tester);
    });
  });

  group('closing the fan', () {
    testWidgets('back on Home closes the fan and stays in the app',
        (tester) async {
      final exits = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'SystemNavigator.pop') exits.add(call.method);
          return null;
        },
      );
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));
      await pumpShell(tester, showGym: true);

      await openFan(tester);
      await tester.binding.handlePopRoute();
      await settle(tester);

      expect(fanItem('Log run'), findsNothing);
      expect(exits, isEmpty, reason: 'back closed the fan, not the app');
      expect(shellPage(tester), 0);

      await unmount(tester);
    });

    testWidgets('back on Gym closes the fan and leaves Gym showing',
        (tester) async {
      await pumpShell(tester, showGym: true);
      await pick(tester, 'Log lift');
      expect(shellPage(tester), 1);

      await openFan(tester);
      await tester.binding.handlePopRoute();
      await settle(tester);

      expect(fanItem('Log run'), findsNothing);
      expect(shellPage(tester), 1,
          reason: 'one back closes the fan; it does not also walk Home');
      expect(find.byType(GymScreen), findsOneWidget);

      await unmount(tester);
    });
  });
}
