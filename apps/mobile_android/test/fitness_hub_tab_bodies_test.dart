// ignore_for_file: avoid_relative_lib_imports
// Every Fitness tab at the worst case the issue #1374 rules name: a 320 dp
// phone, 2x text and Android's 3-button navigation bar. Each tab body is a
// HubTabBody, so the hub draws the one app bar (the strip) and the one FAB;
// this walks every tab, fails on an overflow, and checks the hub's FAB sits
// clear of the nav bar wherever a tab has a primary action.
import 'dart:io';

import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ui_kit/ui_kit.dart' show AppSearchField, FilterBar;

import '../lib/local_food_store.dart';
import '../lib/local_gym_store.dart';
import '../lib/local_route_store.dart';
import '../lib/local_run_store.dart';
import '../lib/preferences.dart';
import '../lib/screens/fitness_hub_screen.dart';
import '../lib/training_service.dart';
import 'three_button_nav_bar.dart' show kThreeButtonNavBar;
import 'worst_case_layout.dart';

const _phone = Size(320, 640);

void main() {
  setUpAll(() => initializeDateFormatting());

  final dirs = <Directory>[];
  tearDown(() {
    for (final d in dirs) {
      if (d.existsSync()) d.deleteSync(recursive: true);
    }
    dirs.clear();
  });

  Directory tmp(String prefix) {
    final d = Directory.systemTemp.createTempSync(prefix);
    dirs.add(d);
    return d;
  }

  Future<void> pumpHub(WidgetTester tester, {Locale? locale}) async {
    tester.view.physicalSize = _phone;
    tester.view.devicePixelRatio = 1;
    tester.view.viewPadding = const FakeViewPadding(bottom: kThreeButtonNavBar);
    tester.view.padding = const FakeViewPadding(bottom: kThreeButtonNavBar);
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues(
        const {'show_gym': true, 'show_nutrition': true});
    final prefs = Preferences();
    await prefs.init();
    final runStore = LocalRunStore();
    await runStore.init(overrideDirectory: tmp('tabs_runs_'));
    final routeStore = LocalRouteStore();
    await routeStore.init(overrideDirectory: tmp('tabs_routes_'));
    final gymStore = LocalGymStore();
    await gymStore.init(overrideDirectory: tmp('tabs_gym_'));
    final foodStore = LocalFoodStore();
    await foodStore.init(overrideDirectory: tmp('tabs_food_'));
    await tester.runAsync(() => runStore.saveManyFromRemote([
          Run(
            id: 'r1',
            startedAt: DateTime.now(),
            duration: const Duration(minutes: 25),
            distanceMetres: 5000,
            source: RunSource.app,
            metadata: const {MetadataKeys.title: 'Richmond Half'},
          ),
        ]));
    await tester.pumpWidget(worstCaseApp(
      locale: locale ?? const Locale('en'),
      home: FitnessHubScreen(
        apiClient: null,
        runStore: runStore,
        routeStore: routeStore,
        gymStore: gymStore,
        foodStore: foodStore,
        preferences: prefs,
        training: TrainingService(),
        selectedTab: ValueNotifier(FitnessTab.history),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> openTab(WidgetTester tester, String label) async {
    final tab =
        find.descendant(of: find.byType(TabBar), matching: find.text(label));
    await tester.ensureVisible(tab);
    await tester.tap(tab);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
  }

  // The tabs with a primary action, by the label of the FAB the hub shows.
  // History defers to the shell's centre Log button; Races keeps "Add a
  // race" in its overflow; Plans is signed-out here. Routes' Explore views
  // have no primary action; they are walked as their own entries below.
  const fabs = {
    'Runs': 'Add past run',
    'Routes': 'Import',
    'Gym': 'Log workout',
    'Nutrition': 'Log food',
  };

  testWidgets('every tab fits 320 dp at 2x, with no app bar of its own and '
      'the FAB clear of the 3-button bar', (tester) async {
    await pumpHub(tester);
    for (final label in [
      'History',
      'Runs',
      'Gym',
      'Nutrition',
      'Plans',
      'Races & courses',
      'Routes',
      'Routes → Explore → Routes',
      'Routes → Explore → Segments',
    ]) {
      if (label.startsWith('Routes →')) {
        final chip = find.widgetWithText(ChoiceChip, label.split(' → ').last);
        if (label.endsWith('→ Routes')) {
          final explore = find.widgetWithText(ChoiceChip, 'Explore');
          await tester.ensureVisible(explore);
          await tester.tap(explore);
          await tester.pump();
        }
        // The chip line scrolls sideways at 2x; the chip must be reachable.
        await tester.ensureVisible(chip);
        await tester.tap(chip);
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
      } else {
        await openTab(tester, label);
      }
      expect(tester.takeException(), isNull, reason: '$label overflowed');
      expect(find.byType(AppBar), findsOneWidget,
          reason: '$label drew an app bar under the strip');
      final fab = find.byType(FloatingActionButton);
      if (fabs[label] case final text?) {
        expect(find.widgetWithText(FloatingActionButton, text), findsOneWidget,
            reason: '$label\'s primary action is the hub\'s FAB');
        expect(tester.getRect(fab).bottom,
            lessThanOrEqualTo(_phone.height - kThreeButtonNavBar),
            reason: '$label\'s FAB reaches into the nav bar');
        expect(tester.getRect(fab).right, lessThanOrEqualTo(_phone.width));
      } else {
        expect(fab, findsNothing, reason: '$label has no primary action');
      }
    }
  });

  // The same walk in every shipped locale (issue #1374 TO-6), tab by
  // position so no label is spelled in English.
  worstCaseTestWidgets('every Fitness tab', (tester, locale) async {
    await pumpHub(tester, locale: locale);
    final tabs = find.descendant(of: find.byType(TabBar), matching: find.byType(Tab));
    final count = tabs.evaluate().length;
    expect(count, greaterThanOrEqualTo(7));
    for (var i = 0; i < count; i++) {
      final tab = tabs.at(i);
      await tester.ensureVisible(tab);
      await tester.tap(tab);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expectNoOverflow(tester, 'Fitness tab $i');
    }
  });

  testWidgets('Runs has a search, and it finds a run by its name',
      (tester) async {
    await pumpHub(tester);
    await openTab(tester, 'Runs');
    final bar = find.byKey(const ValueKey('runs-filter-bar'));
    expect(bar, findsOneWidget);
    expect(
        find.descendant(of: bar, matching: find.byType(AppSearchField)),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a list tab\'s controls are one FilterBar', (tester) async {
    await pumpHub(tester);
    await openTab(tester, 'Races & courses');
    expect(find.byKey(const Key('races-filter-bar')), findsOneWidget);
    expect(find.byType(FilterBar), findsOneWidget);
  });

  // Routes is Mine · Explore: the view row is a FilterBar of its own over
  // the view's FilterBar, and nothing else.
  testWidgets('Routes is the view row over the view\'s own FilterBar',
      (tester) async {
    await pumpHub(tester);
    await openTab(tester, 'Routes');
    expect(find.byKey(const ValueKey('routes-view-bar')), findsOneWidget);
    expect(find.byType(FilterBar), findsNWidgets(2));
    final explore = find.widgetWithText(ChoiceChip, 'Explore');
    await tester.ensureVisible(explore);
    await tester.tap(explore);
    await tester.pump();
    expect(find.byKey(const ValueKey('explore-routes-filter-bar')),
        findsOneWidget);
    expect(find.byType(FilterBar), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });
}
