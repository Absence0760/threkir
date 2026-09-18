// ignore_for_file: avoid_relative_lib_imports
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
import '../lib/screens/gym_screen.dart';
import '../lib/screens/home_screen.dart';
import '../lib/screens/nutrition_screen.dart';
import '../lib/social_service.dart';
import '../lib/training_service.dart';

/// Gym and Nutrition are each ONE surface reached by two entry points — the
/// Fitness hub's sub-tab and the centre Log action. These tests address the
/// pair, which is where the defect lived: either entry point on its own looked
/// perfectly correct.
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
    SharedPreferences.setMockInitialValues({});
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

  Future<void> pumpShell(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: await shell(tester),
    ));
    await tester.pump();
  }

  /// Always from Home. Each modality surface carries its own FAB tooltipped
  /// with the same string the speed-dial item uses, so firing the shell's Log
  /// action while standing on one of them finds two (decisions § 1647) — and
  /// leaving and coming back is the journey these tests are about anyway.
  Future<void> logFromHome(WidgetTester tester, String item) async {
    await tester.tap(find.text('Home').first);
    await settle(tester);
    await tester.tap(find.byTooltip('Log'));
    await settle(tester);
    await tester.tap(find.byTooltip(item));
    await settle(tester);
  }

  Future<void> openFitnessTab(WidgetTester tester, String label) async {
    await tester.tap(find.text('Fitness').first);
    await settle(tester);
    await tester.tap(find.text(label).first);
    await settle(tester);
  }

  testWidgets('the Log action and the Fitness tab reach ONE Nutrition surface',
      (tester) async {
    await pumpShell(tester);
    await openFitnessTab(tester, 'Nutrition');
    await logFromHome(tester, 'Log food');
    // Both entry points had built their own keep-alive instance, so the tree
    // carried two. Offstage counts: a kept-alive page is in the tree whether
    // or not it is the visible one, which is exactly the duplication.
    expect(find.byType(NutritionScreen, skipOffstage: false), findsOneWidget);
  });

  testWidgets('the Log action and the Fitness tab reach ONE Gym surface',
      (tester) async {
    await pumpShell(tester);
    await openFitnessTab(tester, 'Gym');
    await logFromHome(tester, 'Log lift');
    expect(find.byType(GymScreen, skipOffstage: false), findsOneWidget);
  });

  // The opposite failure mode to the day freeze, and the one #923 closed: one
  // instance is only an improvement if that instance is the one still there
  // after you leave. Identity of the State object is what says it survived.
  testWidgets('the surface survives leaving the shell page and coming back',
      (tester) async {
    await pumpShell(tester);
    await openFitnessTab(tester, 'Gym');
    final gym = tester.state(find.byType(GymScreen));
    await logFromHome(tester, 'Log lift');
    expect(identical(tester.state(find.byType(GymScreen)), gym), isTrue,
        reason: 'Gym was rebuilt from scratch on the way back');
  });

  testWidgets('Log food opens the day the diary was left on, not today',
      (tester) async {
    await pumpShell(tester);
    await openFitnessTab(tester, 'Nutrition');
    await tester.tap(find.byTooltip('Previous day'));
    await settle(tester);
    expect(find.text('Yesterday'), findsOneWidget,
        reason: 'the diary did not step back a day');

    // Leave the surface and come back by the other door. The runner who
    // stepped back to backfill yesterday's dinner and then tapped Log meant
    // the day they were reading, not the day the second instance was born on.
    await logFromHome(tester, 'Log food');
    expect(find.text('Yesterday'), findsOneWidget,
        reason:
            'Log food landed on a different day than the diary was showing');
    // The backfill hint only renders off today, so it also says the log would
    // land on the day being read rather than on the one the clock says.
    expect(find.text('Anything you log here is added to this day.'),
        findsOneWidget);
  });
}
