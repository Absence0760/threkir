// ignore_for_file: avoid_relative_lib_imports
import 'dart:io';

import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/local_food_store.dart';
import '../lib/local_gym_store.dart';
import '../lib/local_route_store.dart';
import '../lib/local_run_store.dart';
import '../lib/preferences.dart';
import '../lib/screens/fitness_hub_screen.dart';
import '../lib/screens/global_segments_screen.dart';
import '../lib/screens/gym_screen.dart';
import '../lib/screens/nutrition_screen.dart';
import '../lib/screens/plans_screen.dart';
import '../lib/screens/races_screen.dart';
import '../lib/screens/routes_screen.dart';
import '../lib/screens/runs_screen.dart';
import '../lib/training_service.dart';
import '../lib/widgets/activity_timeline_list.dart';
import '../lib/widgets/surface_peer_strip.dart';

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

  Run runRow(String id, {double dist = 5000, int dur = 1500}) => Run(
        id: id,
        startedAt: DateTime.now(),
        duration: Duration(seconds: dur),
        distanceMetres: dist,
        source: RunSource.app,
      );

  ({Map<String, dynamic> workout, List<Map<String, dynamic>> sets}) liftRow(
    String id,
    String title,
  ) =>
      (
        workout: {
          'id': id,
          'title': title,
          'started_at': DateTime.now().toUtc().toIso8601String(),
        },
        sets: [
          {'exercise_name': 'Squat', 'set_index': 0, 'reps': 5, 'weight_kg': 100},
        ],
      );

  // api: null keeps Gym/Nutrition/Runs from hitting the (uninitialised)
  // Supabase server on mount — the timeline is assembled purely from the
  // seeded local stores, which is the offline-first contract.
  //
  // Both modalities are switched on unless a test says otherwise, so the
  // tests about the strip's mechanics see all four tabs; the visibility
  // tests pass their own [storedPrefs].
  Future<Preferences> pump(
    WidgetTester tester, {
    List<Run> runs = const [],
    List<Run> unsyncedRuns = const [],
    List<({Map<String, dynamic> workout, List<Map<String, dynamic>> sets})> lifts =
        const [],
    List<Map<String, dynamic>> meals = const [],
    FitnessTab initialTab = FitnessTab.history,
    ValueNotifier<FitnessTab>? selectedTab,
    Map<String, Object> storedPrefs = const {
      'show_gym': true,
      'show_nutrition': true,
    },
  }) async {
    SharedPreferences.setMockInitialValues(storedPrefs);
    final prefs = Preferences();
    await prefs.init();
    final runStore = LocalRunStore();
    await runStore.init(overrideDirectory: tmp('hub_runs_'));
    final routeStore = LocalRouteStore();
    await routeStore.init(overrideDirectory: tmp('hub_routes_'));
    final gymStore = LocalGymStore();
    await gymStore.init(overrideDirectory: tmp('hub_gym_'));
    final foodStore = LocalFoodStore();
    await foodStore.init(overrideDirectory: tmp('hub_food_'));

    // Store writes do real async file I/O that deadlocks the fake-async test
    // zone — seed inside runAsync (CLAUDE.md gotcha).
    await tester.runAsync(() async {
      if (runs.isNotEmpty) await runStore.saveManyFromRemote(runs);
      for (final r in unsyncedRuns) {
        await runStore.save(r);
      }
      if (lifts.isNotEmpty) await gymStore.replaceFromServer(lifts);
      if (meals.isNotEmpty) {
        await foodStore.replaceFromServer(meals);
      }
    });

    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: FitnessHubScreen(
        apiClient: null,
        runStore: runStore,
        routeStore: routeStore,
        gymStore: gymStore,
        foodStore: foodStore,
        preferences: prefs,
        training: TrainingService(),
        selectedTab: selectedTab ?? ValueNotifier(initialTab),
      ),
    ));
    await tester.pumpAndSettle();
    return prefs;
  }

  List<String?> stripLabels(WidgetTester tester) => [
        for (final t in tester.widget<TabBar>(find.byType(TabBar)).tabs)
          (t as Tab).text,
      ];

  testWidgets('renders the four sub-tabs History / Runs / Gym / Nutrition',
      (tester) async {
    await pump(tester, runs: [runRow('r1')]);
    final tabBar = tester.widget<TabBar>(find.byType(TabBar));
    expect(tabBar.tabs.length, 4);
    final labels = [
      for (final t in tabBar.tabs) (t as Tab).text,
    ];
    // The first tab used to read "All" over a child AppBar reading "History"
    // — two names for one surface, stacked (#666 I9). Every tab now agrees
    // with the screen it mounts.
    expect(labels, ['History', 'Runs', 'Gym', 'Nutrition']);
  });

  testWidgets('History tab shows the unified timeline when stores are seeded',
      (tester) async {
    await pump(tester,
        runs: [runRow('r1')], lifts: [liftRow('l1', 'Leg day')]);
    // The All tab hosts RunsScreen WITH the gym+food stores → the unified
    // cross-modal timeline (the absorbed History content), with its own kind
    // chips suppressed (the hub TabBar owns that axis).
    expect(find.byType(ActivityTimelineList), findsOneWidget);
    expect(find.text('Leg day'), findsOneWidget);
    // The tab and the AppBar 48dp below it now say the same thing. This is
    // the mount where the contradiction showed: the timeline title only
    // renders once a second modality has data (#666 I9).
    expect(find.text('History'), findsNWidgets(2));
    // No in-screen kind chips — the hub TabBar is the single kind selector.
    expect(find.text('Lifts'), findsNothing);
  });

  testWidgets('Runs sub-tab renders the labelled peer strip',
      (tester) async {
    await pump(tester, runs: [runRow('r1')]);
    await tester.tap(find.text('Runs').first);
    await tester.pumpAndSettle();
    // Every run-planning surface is a named peer, not a tooltip-only glyph.
    final strip = find.byType(SurfacePeerStrip);
    expect(strip, findsOneWidget);
    for (final label in ['Runs', 'Routes', 'Segments', 'Plans', 'Races']) {
      expect(find.descendant(of: strip, matching: find.text(label)),
          findsOneWidget);
    }
  });

  testWidgets('the Races peer opens the race calendar with no provider key',
      (tester) async {
    await pump(tester, runs: [runRow('r1')]);
    await tester.tap(find.text('Runs').first);
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
        of: find.byType(SurfacePeerStrip), matching: find.text('Races')));
    await tester.pumpAndSettle();
    // No RunSignUp / ChronoTrack key and no signed-in client: the calendar is
    // still reachable, it just has nothing to list.
    expect(find.byType(RacesScreen), findsOneWidget);
  });

  testWidgets('the Routes peer opens the relocated route library',
      (tester) async {
    await pump(tester, runs: [runRow('r1')]);
    await tester.tap(find.text('Runs').first);
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
        of: find.byType(SurfacePeerStrip), matching: find.text('Routes')));
    await tester.pumpAndSettle();
    expect(find.byType(RoutesScreen), findsOneWidget);
  });

  testWidgets('the Segments peer opens the famous-segment catalogue',
      (tester) async {
    await pump(tester, runs: [runRow('r1')]);
    await tester.tap(find.text('Runs').first);
    await tester.pumpAndSettle();
    final peer = find.descendant(
        of: find.byType(SurfacePeerStrip), matching: find.text('Segments'));
    await tester.ensureVisible(peer);
    await tester.tap(peer);
    await tester.pumpAndSettle();
    expect(find.byType(GlobalSegmentsScreen), findsOneWidget);
  });

  testWidgets('the Plans peer opens the training plan library', (tester) async {
    await pump(tester, runs: [runRow('r1')]);
    await tester.tap(find.text('Runs').first);
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
        of: find.byType(SurfacePeerStrip), matching: find.text('Plans')));
    await tester.pumpAndSettle();
    expect(find.byType(PlansScreen), findsOneWidget);
  });

  testWidgets('Runs sub-tab hides the cloud sync slot; All keeps it',
      (tester) async {
    await pump(tester, runs: [runRow('r1')]);
    // All tab (api: null, signed out) renders the cloud slot's offline state.
    expect(find.byIcon(Icons.cloud_off), findsOneWidget);
    await tester.tap(find.text('Runs').first);
    await tester.pumpAndSettle();
    // The Runs sub-tab passes showSyncActions: false — no cloud slot at all,
    // in any of its three states.
    expect(find.byIcon(Icons.cloud_off), findsNothing);
    expect(find.byIcon(Icons.cloud_upload_outlined), findsNothing);
    expect(find.byIcon(Icons.cloud_download), findsNothing);
  });

  testWidgets(
      'Runs sub-tab titles itself "Runs" and moves the range status into '
      'the filter header', (tester) async {
    await pump(tester, runs: [runRow('r1')]);
    await tester.tap(find.text('Runs').first);
    await tester.pumpAndSettle();
    // "Runs" appears three times: the hub's tab label, the sub-tab's static
    // AppBar title (matching the Gym / Nutrition siblings), and the current
    // peer in the surface strip.
    expect(find.text('Runs'), findsNWidgets(3));
    // The range + count status the title otherwise carries renders as the
    // filter header's leading row instead (default range = This week).
    expect(find.text('This week · 1 run'), findsOneWidget);
  });

  testWidgets('Gym sub-tab hosts GymScreen with its empty-onboarding state',
      (tester) async {
    await pump(tester, runs: [runRow('r1')]);
    await tester.tap(find.text('Gym').first);
    await tester.pumpAndSettle();
    expect(find.byType(GymScreen), findsOneWidget);
  });

  testWidgets('Nutrition sub-tab hosts NutritionScreen', (tester) async {
    await pump(tester, runs: [runRow('r1')]);
    await tester.tap(find.text('Nutrition').first);
    await tester.pumpAndSettle();
    expect(find.byType(NutritionScreen), findsOneWidget);
  });

  // The hub's TabBarView is a PageView with no cache extent, so before the
  // keep-alive mixin every tap on the strip destroyed one screen and rebuilt
  // the next from nothing — re-running its arrival fetches and resetting its
  // filters, paging and scroll. Identity of the State object is the property
  // that says the screen survived; a rebuilt tab gets a fresh one.
  testWidgets('a tab switch keeps the sibling screens alive', (tester) async {
    await pump(tester, runs: [runRow('r1')]);
    State stateFor(String key) =>
        tester.state(find.byKey(PageStorageKey<String>(key)));

    final history = stateFor('fitness-all');
    await tester.tap(find.text('Gym').first);
    await tester.pumpAndSettle();
    final gym = stateFor('fitness-gym');

    await tester.tap(find.text('History').first);
    await tester.pumpAndSettle();
    expect(identical(stateFor('fitness-all'), history), isTrue,
        reason: 'History was rebuilt from scratch on the way back');

    await tester.tap(find.text('Gym').first);
    await tester.pumpAndSettle();
    expect(identical(stateFor('fitness-gym'), gym), isTrue,
        reason: 'Gym was rebuilt from scratch on the way back');
  });

  // Before this, the add affordance moved as you walked the strip — a
  // bottom-right FAB on History and Runs, a top-right glyph on Gym and
  // Nutrition — and on History it sat beside the shell's centre Log button
  // opening the same run / lift / meal picker. Now each modality tab carries
  // one FAB and the cross-modal History tab defers to the shell.
  testWidgets('every modality tab puts its add in the same place; History '
      'defers to the shell', (tester) async {
    await pump(tester, runs: [runRow('r1')]);
    expect(find.byType(FloatingActionButton), findsNothing);
    expect(find.byIcon(Icons.add), findsNothing);

    await tester.tap(find.text('Runs').first);
    await tester.pumpAndSettle();
    expect(find.byType(FloatingActionButton), findsOneWidget);

    await tester.tap(find.text('Gym').first);
    await tester.pumpAndSettle();
    expect(find.byType(FloatingActionButton), findsOneWidget);
    // And no second add hiding in the toolbar it used to live in.
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.byIcon(Icons.add)),
      findsNothing,
    );
  });

  // The selected tab started life as a raw int documented in a comment. No
  // production caller passed a non-default value, so the § 490 bug was not live
  // here — but the seam was the same shape that produced it, where a stale
  // literal stays in range after the tab set changes and the wrong tab opens in
  // silence. With an enum, out of range is unrepresentable; what is worth
  // pinning instead is the property no clamp could give.
  testWidgets('every FitnessTab opens its own tab, and the strip is exactly as '
      'long as the enum', (tester) async {
    for (final tab in FitnessTab.values) {
      // Unmount first — see the SocialTab twin: pumping another hub over the
      // previous one reuses the element and keeps its TabController.
      await tester.pumpWidget(const SizedBox.shrink());
      await pump(tester, runs: [runRow('r1')], initialTab: tab);
      final tabBar = tester.widget<TabBar>(find.byType(TabBar).first);
      expect(tabBar.controller!.index, tab.index,
          reason: '$tab did not open its own tab');
      expect(tabBar.tabs.length, FitnessTab.values.length,
          reason: 'the strip and the enum disagree on how many tabs exist');
    }
    // Assert the population: an empty enum would satisfy the loop above.
    expect(FitnessTab.values.length, greaterThan(1));
  });

  // The shell reaches Gym and Nutrition through this hub, so the selected tab
  // has to travel both ways: the host selects one when the Log action fires,
  // and the host has to know which one a tap or swipe moved to — otherwise
  // Log → Food onto the Nutrition tab already showing reads as a dropped tap.
  testWidgets('the selected tab travels both ways through the host notifier',
      (tester) async {
    final selected = ValueNotifier(FitnessTab.history);
    addTearDown(selected.dispose);
    await pump(tester, runs: [runRow('r1')], selectedTab: selected);
    final controller = tester.widget<TabBar>(find.byType(TabBar)).controller!;

    selected.value = FitnessTab.nutrition;
    await tester.pumpAndSettle();
    expect(controller.index, FitnessTab.nutrition.index,
        reason: 'the host selecting a tab did not move the strip');
    expect(find.byType(NutritionScreen), findsOneWidget);

    await tester.tap(find.text('Gym').first);
    await tester.pumpAndSettle();
    expect(selected.value, FitnessTab.gym,
        reason: 'a tap on the strip never reached the host');
  });

  group('Gym and Nutrition visibility', () {
    testWidgets('a runner who has logged neither sees Runs alone, with no '
        'one-tab strip and no History', (tester) async {
      // History is the cross-modal timeline; with only runs in it, it is the
      // Runs tab a second time.
      final selected = ValueNotifier(FitnessTab.history);
      addTearDown(selected.dispose);
      await pump(tester,
          runs: [runRow('r1')], storedPrefs: const {}, selectedTab: selected);
      expect(find.byType(TabBar), findsNothing);
      expect(find.byType(RunsScreen), findsOneWidget);
      expect(find.byType(GymScreen), findsNothing);
      expect(find.byType(NutritionScreen), findsNothing);
      // The Runs surface keeps its peer strip when it stands alone.
      final strip = find.byType(SurfacePeerStrip);
      expect(strip, findsOneWidget);
      for (final label in ['Runs', 'Routes', 'Segments', 'Plans', 'Races']) {
        expect(find.descendant(of: strip, matching: find.text(label)),
            findsOneWidget);
      }
      expect(selected.value, FitnessTab.runs,
          reason: 'a selection on the missing History tab must fall back to '
              'a tab that exists');
    });

    testWidgets('Runs standing alone carries the cloud slot History had, so '
        'an unsynced run still shows its badge and Sync all', (tester) async {
      await pump(tester,
          unsyncedRuns: [runRow('r1')], storedPrefs: const {});
      expect(find.byType(TabBar), findsNothing);
      expect(find.byIcon(Icons.cloud_upload), findsOneWidget);
      expect(find.byTooltip('Sync 1 run'), findsOneWidget);
    });

    testWidgets('with History back, the cloud slot moves to it and leaves Runs',
        (tester) async {
      await pump(tester,
          unsyncedRuns: [runRow('r1')],
          storedPrefs: const {'show_gym': true});
      expect(stripLabels(tester), ['History', 'Runs', 'Gym']);
      expect(find.byIcon(Icons.cloud_upload), findsOneWidget);
      await tester.tap(find.text('Runs').first);
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.cloud_upload), findsNothing);
    });

    testWidgets('Runs standing alone tells a runner with no runs to tap Start '
        'run, which is what the centre button now says', (tester) async {
      await pump(tester, storedPrefs: const {});
      expect(find.textContaining('Tap Start run'), findsOneWidget);
      expect(find.textContaining('Tap Log'), findsNothing);
    });

    testWidgets('a logged lift keeps Gym, and History with it, without anyone '
        'opening Settings', (tester) async {
      await pump(tester,
          lifts: [liftRow('l1', 'Leg day')], storedPrefs: const {});
      expect(stripLabels(tester), ['History', 'Runs', 'Gym']);
    });

    testWidgets('an explicit off hides a modality that has data',
        (tester) async {
      await pump(tester,
          lifts: [liftRow('l1', 'Leg day')],
          storedPrefs: const {'show_gym': false});
      expect(find.byType(TabBar), findsNothing);
      expect(find.byType(RunsScreen), findsOneWidget);
    });

    for (final (name, turnOn, tabs) in [
      (
        'Gym',
        (Preferences p) => p.setShowGym(true),
        ['History', 'Runs', 'Gym'],
      ),
      (
        'Nutrition',
        (Preferences p) => p.setShowNutrition(true),
        ['History', 'Runs', 'Nutrition'],
      ),
    ]) {
      testWidgets('History returns as soon as $name is switched on, and a '
          'Runs selection survives the strip coming back', (tester) async {
        final selected = ValueNotifier(FitnessTab.history);
        addTearDown(selected.dispose);
        final prefs = await pump(tester,
            runs: [runRow('r1')], storedPrefs: const {}, selectedTab: selected);
        expect(find.byType(TabBar), findsNothing);
        expect(selected.value, FitnessTab.runs);

        await turnOn(prefs);
        await tester.pumpAndSettle();
        expect(stripLabels(tester), tabs);
        expect(selected.value, FitnessTab.runs);
        expect(tester.widget<TabBar>(find.byType(TabBar)).controller!.index,
            tabs.indexOf('Runs'));
      });
    }

    testWidgets('switching the open tab off falls back to History while '
        'another modality is still shown', (tester) async {
      final selected = ValueNotifier(FitnessTab.history);
      addTearDown(selected.dispose);
      final prefs = await pump(tester,
          runs: [runRow('r1')],
          storedPrefs: const {'show_gym': true},
          selectedTab: selected);

      await prefs.setShowNutrition(true);
      await tester.pumpAndSettle();
      expect(stripLabels(tester), ['History', 'Runs', 'Gym', 'Nutrition']);

      await tester.tap(find.text('Nutrition').first);
      await tester.pumpAndSettle();
      expect(selected.value, FitnessTab.nutrition);

      await prefs.setShowNutrition(false);
      await tester.pumpAndSettle();
      expect(stripLabels(tester), ['History', 'Runs', 'Gym']);
      expect(selected.value, FitnessTab.history,
          reason: 'a hidden tab cannot stay selected');
      expect(
          tester.widget<TabBar>(find.byType(TabBar)).controller!.index, 0);
    });

    testWidgets('switching the last modality off falls back to Runs alone',
        (tester) async {
      final selected = ValueNotifier(FitnessTab.nutrition);
      addTearDown(selected.dispose);
      final prefs = await pump(tester,
          runs: [runRow('r1')],
          storedPrefs: const {'show_nutrition': true},
          selectedTab: selected);
      expect(find.byType(NutritionScreen), findsOneWidget);

      await prefs.setShowNutrition(false);
      await tester.pumpAndSettle();
      expect(find.byType(TabBar), findsNothing);
      expect(find.byType(NutritionScreen), findsNothing);
      expect(find.byType(RunsScreen), findsOneWidget);
      expect(selected.value, FitnessTab.runs);
    });

    test('fitnessHubTabs drops History only when neither modality is shown',
        () {
      expect(fitnessHubTabs(gymShown: false, nutritionShown: false),
          [FitnessTab.runs]);
      expect(fitnessHubTabs(gymShown: true, nutritionShown: false),
          [FitnessTab.history, FitnessTab.runs, FitnessTab.gym]);
      expect(fitnessHubTabs(gymShown: false, nutritionShown: true),
          [FitnessTab.history, FitnessTab.runs, FitnessTab.nutrition]);
      expect(fitnessHubTabs(gymShown: true, nutritionShown: true),
          FitnessTab.values);
    });
  });
}
