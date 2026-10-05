// Gym and Nutrition are off on mobile until the runner switches them on (or
// already logs them). These pin the Settings rows that do the switching.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/local_food_store.dart';
import '../lib/local_gym_store.dart';
import '../lib/preferences.dart';
import '../lib/screens/settings_preferences_screen.dart';

void main() {
  setUp(initializeDateFormatting);

  Directory tmp(String prefix) {
    final d = Directory.systemTemp.createTempSync(prefix);
    addTearDown(() {
      if (d.existsSync()) d.deleteSync(recursive: true);
    });
    return d;
  }

  Future<({Preferences prefs, LocalGymStore gym, LocalFoodStore food})>
      stores(WidgetTester tester, {bool loggedLift = false}) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = Preferences();
    await prefs.init();
    final gym = LocalGymStore();
    await gym.init(overrideDirectory: tmp('settings_vis_gym_'));
    final food = LocalFoodStore();
    await food.init(overrideDirectory: tmp('settings_vis_food_'));
    if (loggedLift) {
      await tester.runAsync(() async {
        await gym.createLocal(title: 'Push day', startedAt: DateTime.now());
      });
    }
    return (prefs: prefs, gym: gym, food: food);
  }

  Future<void> pump(
    WidgetTester tester,
    Preferences prefs, {
    LocalGymStore? gym,
    LocalFoodStore? food,
  }) async {
    tester.view.physicalSize = const Size(400, 8000) * 2;
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: SettingsPreferencesScreen(
        preferences: prefs,
        settingsSync: null,
        gymStore: gym,
        foodStore: food,
      ),
    ));
    await tester.pumpAndSettle();
  }

  SwitchListTile row(WidgetTester tester, String title) =>
      tester.widget<SwitchListTile>(
          find.widgetWithText(SwitchListTile, title));

  testWidgets('both start off for a runner who has logged neither',
      (tester) async {
    final s = await stores(tester);
    await pump(tester, s.prefs, gym: s.gym, food: s.food);
    expect(row(tester, 'Show Gym').value, isFalse);
    expect(row(tester, 'Show Nutrition').value, isFalse);
  });

  testWidgets('a logged lift reads as on before any choice is made',
      (tester) async {
    final s = await stores(tester, loggedLift: true);
    await pump(tester, s.prefs, gym: s.gym, food: s.food);
    expect(row(tester, 'Show Gym').value, isTrue);
    expect(s.prefs.showGym, isNull, reason: 'nothing was stored on render');
  });

  testWidgets('flipping a switch stores an explicit choice', (tester) async {
    final s = await stores(tester, loggedLift: true);
    await pump(tester, s.prefs, gym: s.gym, food: s.food);

    await tester.tap(find.widgetWithText(SwitchListTile, 'Show Nutrition'));
    await tester.pumpAndSettle();
    expect(s.prefs.showNutrition, isTrue);
    expect(row(tester, 'Show Nutrition').value, isTrue);

    await tester.tap(find.widgetWithText(SwitchListTile, 'Show Gym'));
    await tester.pumpAndSettle();
    expect(s.prefs.showGym, isFalse,
        reason: 'an explicit off must beat the logged lift');
    expect(row(tester, 'Show Gym').value, isFalse);
  });

  testWidgets('a mount without the stores leaves the section out',
      (tester) async {
    final s = await stores(tester);
    await pump(tester, s.prefs);
    expect(find.text('Show Gym'), findsNothing);
    expect(find.text('Show Nutrition'), findsNothing);
  });

  test('sign-out clears the choice back to the data default', () async {
    SharedPreferences.setMockInitialValues(
        {'show_gym': true, 'show_nutrition': false});
    final prefs = Preferences();
    await prefs.init();
    expect(prefs.showGym, isTrue);
    expect(prefs.showNutrition, isFalse);
    await prefs.resetAccountScopedPrefs();
    expect(prefs.showGym, isNull);
    expect(prefs.showNutrition, isNull);
  });
}
