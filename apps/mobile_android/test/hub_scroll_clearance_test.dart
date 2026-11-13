// ignore_for_file: avoid_relative_lib_imports
// The last row of a hub tab's list scrolls fully clear of the hub's FAB and
// the shell's docked centre button, at the worst case (320 dp, 2x text, the
// 3-button bar), in every locale. The hub is mounted inside a frame that
// reproduces the phone shell's slots: a bottom NavigationBar, the centre
// button docked over it and the DockedFabInset it publishes (issue #1374, the
// owner's Routes → Mine screenshot: Build over the last card's star).
import 'dart:io';

import 'package:core_models/core_models.dart' as cm;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/fab_clearance.dart';
import '../lib/local_food_store.dart';
import '../lib/local_gym_store.dart';
import '../lib/local_route_store.dart';
import '../lib/local_run_store.dart';
import '../lib/preferences.dart';
import '../lib/screens/fitness_hub_screen.dart';
import '../lib/training_service.dart';
import 'worst_case_layout.dart';

/// The phone shell's slots around [hub]: what `HomeScreen` builds on a phone.
Widget _shellFrame(Widget hub) => Scaffold(
      body: DockedFabInset(height: kDockedFabOverhang, child: hub),
      floatingActionButton: FloatingActionButton(
        key: const ValueKey('centre-button'),
        onPressed: () {},
        child: const Icon(Icons.play_arrow),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: NavigationBar(
        labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.directions_run), label: 'Training'),
          NavigationDestination(icon: SizedBox.shrink(), label: 'Run'),
          NavigationDestination(icon: Icon(Icons.public), label: 'Social'),
          NavigationDestination(icon: Icon(Icons.person), label: 'You'),
        ],
      ),
    );

/// Fails when [target] overlaps a floating button (the hub's FAB or the
/// shell's docked centre button).
void expectClearOfFabs(WidgetTester tester, Finder target, String where) {
  final rect = tester.getRect(target);
  for (final fab in find.byType(FloatingActionButton).evaluate()) {
    final fabRect = tester.getRect(find.byWidget(fab.widget));
    expect(fabRect.overlaps(rect), isFalse,
        reason: '$where at $rect sits under a floating button at $fabRect');
  }
}

/// Fails unless a tap at the centre of [target] reaches it, rather than a
/// floating button drawn over it, and it overlaps no floating button.
void expectTappable(WidgetTester tester, Finder target, String where) {
  expectClearOfFabs(tester, target, where);
  final rect = tester.getRect(target);
  final hit = tester.hitTestOnBinding(rect.center);
  final ro = tester.renderObject(target);
  expect(hit.path.any((e) => e.target == ro), isTrue,
      reason: 'a tap on $where lands on something drawn over it');
}

/// Scrolls the tab's list to its very end. A builder list only estimates its
/// extent until the tail is laid out, so jump until the end stops moving.
Future<void> scrollToEnd(WidgetTester tester) async {
  final position =
      tester.state<ScrollableState>(primaryScrollable()).position;
  for (var i = 0; i < 20 && position.pixels != position.maxScrollExtent; i++) {
    position.jumpTo(position.maxScrollExtent);
    await tester.pump();
  }
  expect(position.pixels, position.maxScrollExtent);
}

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

  Future<void> pumpHub(WidgetTester tester, Locale locale, FitnessTab tab,
      {List<cm.Route> routes = const [], List<cm.Run> runs = const []}) async {
    SharedPreferences.setMockInitialValues(const {});
    final prefs = Preferences();
    await prefs.init();
    final runStore = LocalRunStore();
    await runStore.init(overrideDirectory: tmp('clear_runs_'));
    if (runs.isNotEmpty) {
      await tester.runAsync(() => runStore.saveManyFromRemote(runs));
    }
    // ignore: invalid_use_of_visible_for_testing_member
    final routeStore = LocalRouteStore()..debugSeed(routes);
    final gymStore = LocalGymStore();
    await gymStore.init(overrideDirectory: tmp('clear_gym_'));
    final foodStore = LocalFoodStore();
    await foodStore.init(overrideDirectory: tmp('clear_food_'));
    await tester.pumpWidget(worstCaseApp(
      locale: locale,
      home: _shellFrame(FitnessHubScreen(
        apiClient: null,
        runStore: runStore,
        routeStore: routeStore,
        gymStore: gymStore,
        foodStore: foodStore,
        preferences: prefs,
        training: TrainingService(),
        selectedTab: ValueNotifier(tab),
      )),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  worstCaseTestWidgets('Routes → Mine scrolled to its end', (tester, locale) async {
    await pumpHub(tester, locale, FitnessTab.routes, routes: [
      for (var i = 0; i < 12; i++)
        cm.Route(
          id: 'r$i',
          userId: 'test-user',
          name: 'Pocahontas Lakeview Loop $i',
          waypoints: const [],
          distanceMetres: 21320,
          elevationGainMetres: 189,
        ),
    ]);
    await scrollToEnd(tester);
    final stars = find.byIcon(Icons.star_border);
    expect(stars, findsWidgets);
    expectTappable(
        tester,
        find.ancestor(of: stars.last, matching: find.byType(IconButton)),
        'the last route\'s star');
    expectClearOfFabs(tester, find.byType(Card).last, 'the last route card');
  });

  worstCaseTestWidgets('Runs scrolled to its end', (tester, locale) async {
    final now = DateTime.now();
    await pumpHub(tester, locale, FitnessTab.runs, runs: [
      for (var i = 0; i < 12; i++)
        cm.Run(
          id: 'run$i',
          startedAt: now.subtract(Duration(days: i)),
          duration: const Duration(minutes: 33),
          distanceMetres: 8000,
          source: cm.RunSource.app,
        ),
    ]);
    await scrollToEnd(tester);
    final cards = find.byType(Card);
    expect(cards, findsWidgets);
    expectTappable(tester, cards.last, 'the last run');
  });
}
