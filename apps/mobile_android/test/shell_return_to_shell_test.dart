// ignore_for_file: avoid_relative_lib_imports
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/audio_cues.dart';
import '../lib/ble_heart_rate.dart';
import '../lib/ble_treadmill.dart';
import '../lib/fitness_surface_requests.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/local_food_store.dart';
import '../lib/local_gear_store.dart';
import '../lib/local_gym_store.dart';
import '../lib/local_route_store.dart';
import '../lib/local_run_store.dart';
import '../lib/preferences.dart';
import '../lib/race_controller.dart';
import '../lib/screens/add_run_screen.dart';
import '../lib/screens/fitness_hub_screen.dart';
import '../lib/screens/home_screen.dart';
import '../lib/social_service.dart';
import '../lib/training_service.dart';

/// Issue #1374 NS-1: a request for a Fitness tab (a "your plan" push, a help
/// link, the home-screen widget) closed every route above the shell with
/// `popUntil`, which never asks a `PopScope`, so a half-filled form was lost
/// with no prompt. The shell now walks the stack through `returnToShell`.

void main() {
  setUpAll(() => initializeDateFormatting());

  final tmpDirs = <Directory>[];
  tearDown(() {
    for (final d in tmpDirs) {
      if (d.existsSync()) d.deleteSync(recursive: true);
    }
    tmpDirs.clear();
  });

  Directory tmp(String prefix) {
    final d = Directory.systemTemp.createTempSync(prefix);
    tmpDirs.add(d);
    return d;
  }

  Future<Widget> shell(WidgetTester tester) async {
    // Nutrition has no data here, so it is only reachable switched on.
    SharedPreferences.setMockInitialValues(
        {'show_gym': true, 'show_nutrition': true});
    final prefs = Preferences();
    await prefs.init();
    final runStore = LocalRunStore();
    await runStore.init(overrideDirectory: tmp('ident_runs_'));
    final routeStore = LocalRouteStore();
    final gearStore = LocalGearStore();
    await gearStore.init(overrideDirectory: tmp('ident_gear_'));
    final gymStore = LocalGymStore();
    await gymStore.init(overrideDirectory: tmp('ident_gym_'));
    final foodStore = LocalFoodStore();
    await foodStore.init(overrideDirectory: tmp('ident_food_'));
    // A logged lift is what puts the capture fan back on the Log button's tap
    // rather than a one-tap run start (decisions § 63 self-hiding).
    await tester.runAsync(() async {
      await gymStore.createLocal(title: 'Push day', startedAt: DateTime.now());
    });
    final social = SocialService();
    return HomeScreen(
      apiClient: null,
      runStore: runStore,
      routeStore: routeStore,
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
    );
  }

  // pumpAndSettle hangs on the recorder's animations, so every step steps the
  // clock explicitly past the tab / page transition instead.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> openDirtyAddRun(WidgetTester tester, LocalRunStore runs,
      LocalRouteStore routes, Preferences prefs) async {
    final nav = Navigator.of(tester.element(find.byType(HomeScreen)));
    nav.push(MaterialPageRoute<void>(
      builder: (_) => AddRunScreen(
        runStore: runs,
        routeStore: routes,
        preferences: prefs,
      ),
    ));
    await settle(tester);
    await tester.enterText(find.byType(TextFormField).first, '5.0');
    await tester.pump();
  }

  testWidgets('a tab request asks a dirty form first; Cancel keeps it',
      (tester) async {
    final home = await shell(tester) as HomeScreen;
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: home,
    ));
    await tester.pump();
    await openDirtyAddRun(
        tester, home.runStore, home.routeStore, home.preferences);

    expect(fitnessSurfaceRequests.request(FitnessTab.runs), isTrue);
    await settle(tester);
    expect(find.text('Discard changes?'), findsOneWidget);

    await tester.tap(find.descendant(
        of: find.byType(AlertDialog), matching: find.text('Cancel')));
    await settle(tester);
    await settle(tester);
    expect(find.text('Discard changes?'), findsNothing);
    expect(find.byType(AddRunScreen), findsOneWidget);
    expect(find.text('5.0'), findsOneWidget);
    expect(find.byType(FitnessHubScreen).hitTestable(), findsNothing);
  });

  testWidgets('Discard closes the form and opens the tab', (tester) async {
    final home = await shell(tester) as HomeScreen;
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: home,
    ));
    await tester.pump();
    await openDirtyAddRun(
        tester, home.runStore, home.routeStore, home.preferences);

    fitnessSurfaceRequests.request(FitnessTab.runs);
    await settle(tester);
    await tester.tap(find.descendant(
        of: find.byType(AlertDialog), matching: find.text('Discard')));
    await settle(tester);
    await settle(tester);
    expect(find.byType(AddRunScreen), findsNothing);
    expect(home.runStore.runs, isEmpty);
    expect(find.byType(FitnessHubScreen).hitTestable(), findsOneWidget);
  });
}
