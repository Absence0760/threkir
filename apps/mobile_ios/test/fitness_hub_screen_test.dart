// ignore_for_file: avoid_relative_lib_imports
import 'dart:io';

import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/fitness_surface_requests.dart';
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
    FitnessHubViews? views,
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
        views: views,
      ),
    ));
    await tester.pumpAndSettle();
    return prefs;
  }

  /// The strip for a given modality visibility: History with either, then
  /// Runs, then Gym and Nutrition beside it, then the run surface's planning
  /// tabs (issue #1354; issue #1374 owner decision 1 moved Gym and Nutrition
  /// to 3-4 and folded Segments into Routes).
  List<String> strip({bool gym = false, bool nutrition = false}) => [
        if (gym || nutrition) 'History',
        'Runs',
        if (gym) 'Gym',
        if (nutrition) 'Nutrition',
        'Plans',
        'Races & courses',
        'Routes',
      ];

  List<String?> stripLabels(WidgetTester tester) => [
        for (final t in tester.widget<TabBar>(find.byType(TabBar)).tabs)
          (t as Tab).text,
      ];

  testWidgets('with gym and food on, one flat strip: History, Runs, Gym and '
      'Nutrition, then the planning tabs', (tester) async {
    await pump(tester, runs: [runRow('r1')]);
    // One strip, not the hub's strip over a second peer strip inside Runs.
    expect(find.byType(TabBar), findsOneWidget);
    // The first tab used to read "All" over a child AppBar reading "History"
    // — two names for one surface, stacked (#666 I9). Every tab now agrees
    // with the screen it mounts.
    expect(stripLabels(tester), [
      'History',
      'Runs',
      'Gym',
      'Nutrition',
      'Plans',
      'Races & courses',
      'Routes',
    ]);
    expect(find.text('Segments'), findsNothing,
        reason: 'the catalogue is Routes → Explore, not a tab');
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
    // The strip names the tab; the body draws no title bar of its own under
    // it (#666 I9 showed two names stacked here; issue #1374 removed the
    // second bar altogether).
    expect(find.text('History'), findsOneWidget);
    expect(find.byType(AppBar), findsOneWidget, reason: 'only the hub\'s');
    // No in-screen kind chips — the hub TabBar is the single kind selector.
    expect(find.text('Lifts'), findsNothing);
  });

  Finder tab(String label) =>
      find.descendant(of: find.byType(TabBar), matching: find.text(label));

  Future<void> openTab(WidgetTester tester, String label) async {
    await tester.ensureVisible(tab(label));
    await tester.tap(tab(label));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    // A tab body hands the hub its primary action after the frame it first
    // builds in, so the hub's FAB lands one frame later.
    await tester.pump();
  }

  int routeCount(WidgetTester tester) {
    var n = 0;
    Navigator.of(tester.element(find.byType(FitnessHubScreen)))
        .popUntil((route) {
      n++;
      return true;
    });
    return n;
  }

  // Each surface used to be pushed over the hub from a peer strip inside
  // Runs, leaving the Fitness tab behind a back arrow. Now each is a tab
  // body: the selection moves, the route stack does not.
  for (final (label, type, tabValue) in [
    ('Plans', PlansScreen, FitnessTab.plans),
    ('Races & courses', RacesScreen, FitnessTab.races),
    ('Routes', RoutesScreen, FitnessTab.routes),
  ]) {
    testWidgets('tapping $label mounts it as a tab body, not a pushed route',
        (tester) async {
      final selected = ValueNotifier(FitnessTab.history);
      addTearDown(selected.dispose);
      await pump(tester,
          runs: [runRow('r1')], storedPrefs: const {}, selectedTab: selected);
      expect(routeCount(tester), 1);
      await openTab(tester, label);
      expect(find.byType(type), findsOneWidget);
      expect(routeCount(tester), 1,
          reason: '$label was pushed instead of shown in its tab');
      expect(selected.value, tabValue);
      expect(
          find.ancestor(
              of: find.byType(type), matching: find.byType(TabBarView)),
          findsOneWidget);
    });
  }

  testWidgets('a swipe moves to the next surface without a push',
      (tester) async {
    final selected = ValueNotifier(FitnessTab.runs);
    addTearDown(selected.dispose);
    // No runs, and the fling starts low in the body: a run row is itself
    // swipeable, and the filter header scrolls sideways.
    await pump(tester, storedPrefs: const {}, selectedTab: selected);
    final view = tester.getRect(find.byType(TabBarView));
    // From the middle: the hub's FAB sits at the bottom-right.
    await tester.flingFrom(
        Offset(view.center.dx, view.bottom - 60), const Offset(-600, 0), 2000);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(selected.value, FitnessTab.plans);
    expect(find.byType(PlansScreen), findsOneWidget);
    expect(routeCount(tester), 1);
  });

  // The hub owns the strip and the one FAB, as Social does: a tab body keeps
  // its secondary actions in its own control row, hands its primary action to
  // the hub, and draws no app bar of its own (issue #1374).
  testWidgets('the hub owns the only app bar and the FAB; each tab keeps its '
      'secondary actions', (tester) async {
    await pump(tester, runs: [runRow('r1')], storedPrefs: const {});
    await openTab(tester, 'Races & courses');
    expect(find.byType(AppBar), findsOneWidget);
    // Add a race is rare, so it waits in the overflow and the tab has no FAB.
    expect(find.byType(FloatingActionButton), findsNothing);
    expect(
        find.descendant(
            of: find.byType(RacesScreen),
            matching: find.byKey(const Key('help-how-this-works'))),
        findsOneWidget);

    await openTab(tester, 'Routes');
    expect(find.byType(AppBar), findsOneWidget);
    expect(find.widgetWithText(FloatingActionButton, 'Import'), findsOneWidget);
    expect(
        find.descendant(
            of: find.byType(RoutesScreen),
            matching: find.byType(FloatingActionButton)),
        findsNothing,
        reason: 'the FAB is the hub\'s, not drawn inside the tab');

    // Explore has no primary action, and its Segments chip keeps the Park
    // courses link in its control row.
    await tester.tap(find.widgetWithText(ChoiceChip, 'Explore'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(FloatingActionButton), findsNothing);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Segments'));
    await tester.pump();
    expect(find.byType(AppBar), findsOneWidget);
    expect(
        find.descendant(
            of: find.byType(GlobalSegmentsScreen),
            matching: find.byKey(const Key('segments-parks-link'))),
        findsOneWidget);
  });

  // A link from elsewhere (a notification, the Run page, the Coach) reaches
  // the hub through the host's notifier; it must select the tab rather than
  // push a second Plans over the shell.
  testWidgets('an external "open Plans" switches the tab with no new route',
      (tester) async {
    final selected = ValueNotifier(FitnessTab.runs);
    addTearDown(selected.dispose);
    await pump(tester,
        runs: [runRow('r1')], storedPrefs: const {}, selectedTab: selected);
    selected.value = FitnessTab.plans;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.widget<TabBar>(find.byType(TabBar)).controller!.index,
        fitnessHubTabs(gymShown: false, nutritionShown: false)
            .indexOf(FitnessTab.plans));
    expect(find.byType(PlansScreen), findsOneWidget);
    expect(routeCount(tester), 1);
  });

  // Park courses live in Races & courses (decisions § 2480): Segments' Park
  // courses action asks the shell for that tab on its Courses view, and the
  // hub hands the view to the tab, with no route pushed.
  testWidgets('Park courses on Segments selects Races & courses on Courses',
      (tester) async {
    final selected = ValueNotifier(FitnessTab.runs);
    final views = FitnessHubViews();
    addTearDown(selected.dispose);
    addTearDown(views.dispose);
    void shell() {
      final request = fitnessSurfaceRequests.take();
      if (request == null) return;
      views.apply(request);
      selected.value = request.tab;
    }

    fitnessSurfaceRequests.addListener(shell);
    addTearDown(() => fitnessSurfaceRequests.removeListener(shell));
    views.routes.value = RoutesShow.segments;
    await pump(tester,
        runs: [runRow('r1')],
        storedPrefs: const {},
        selectedTab: selected,
        views: views);
    await openTab(tester, 'Routes');
    await tester.tap(find.byKey(const Key('segments-parks-link')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(selected.value, FitnessTab.races);
    expect(tester.widget<TabBar>(find.byType(TabBar)).controller!.index,
        fitnessHubTabs(gymShown: false, nutritionShown: false)
            .indexOf(FitnessTab.races));
    expect(tester.widget<RacesScreen>(find.byType(RacesScreen)).show!.value,
        RacesShow.courses);
    expect(routeCount(tester), 1);
  });

  // The segment catalogue is Routes → Explore on Segments (issue #1374, owner
  // decision 1). A link to it (a run's Browse all) asks the shell for that
  // tab and view, and the hub shows it with nothing pushed.
  testWidgets('a request for the catalogue selects Routes on Explore → '
      'Segments with no route pushed', (tester) async {
    final selected = ValueNotifier(FitnessTab.runs);
    final views = FitnessHubViews();
    addTearDown(selected.dispose);
    addTearDown(views.dispose);
    void shell() {
      final request = fitnessSurfaceRequests.take();
      if (request == null) return;
      views.apply(request);
      selected.value = request.tab;
    }

    fitnessSurfaceRequests.addListener(shell);
    addTearDown(() => fitnessSurfaceRequests.removeListener(shell));
    await pump(tester,
        runs: [runRow('r1')],
        storedPrefs: const {},
        selectedTab: selected,
        views: views);
    expect(
        fitnessSurfaceRequests.request(FitnessTab.routes,
            routesShow: RoutesShow.segments),
        isTrue);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(selected.value, FitnessTab.routes);
    expect(tester.widget<TabBar>(find.byType(TabBar)).controller!.index,
        fitnessHubTabs(gymShown: false, nutritionShown: false)
            .indexOf(FitnessTab.routes));
    expect(find.byType(GlobalSegmentsScreen), findsOneWidget);
    expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Segments'))
            .selected,
        isTrue);
    expect(routeCount(tester), 1);
  });

  testWidgets('a hub with no host notifier comes back on the tab it was left '
      'on, through PageStorage', (tester) async {
    SharedPreferences.setMockInitialValues(const {});
    final prefs = Preferences();
    await prefs.init();
    final runStore = LocalRunStore();
    await runStore.init(overrideDirectory: tmp('hub_ps_runs_'));
    final routeStore = LocalRouteStore();
    await routeStore.init(overrideDirectory: tmp('hub_ps_routes_'));
    final gymStore = LocalGymStore();
    await gymStore.init(overrideDirectory: tmp('hub_ps_gym_'));
    final foodStore = LocalFoodStore();
    await foodStore.init(overrideDirectory: tmp('hub_ps_food_'));
    final bucket = PageStorageBucket();
    Widget app(bool shown) => MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: PageStorage(
            bucket: bucket,
            child: shown
                ? FitnessHubScreen(
                    key: const PageStorageKey('fitness'),
                    apiClient: null,
                    runStore: runStore,
                    routeStore: routeStore,
                    gymStore: gymStore,
                    foodStore: foodStore,
                    preferences: prefs,
                    training: TrainingService(),
                  )
                : const SizedBox.shrink(),
          ),
        );
    await tester.pumpWidget(app(true));
    await tester.pump();
    await openTab(tester, 'Routes');
    expect(find.byType(RoutesScreen), findsOneWidget);

    await tester.pumpWidget(app(false));
    await tester.pumpWidget(app(true));
    await tester.pump();
    expect(tester.widget<TabBar>(find.byType(TabBar)).controller!.index,
        fitnessHubTabs(gymShown: false, nutritionShown: false)
            .indexOf(FitnessTab.routes));
    expect(find.byType(RoutesScreen), findsOneWidget);
  });

  testWidgets('at 360 dp and 2x text the strip scrolls and nothing overflows',
      (tester) async {
    tester.view.physicalSize = const Size(360, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues(const {});
    final prefs = Preferences();
    await prefs.init();
    final runStore = LocalRunStore();
    await runStore.init(overrideDirectory: tmp('hub_big_runs_'));
    final routeStore = LocalRouteStore();
    await routeStore.init(overrideDirectory: tmp('hub_big_routes_'));
    final gymStore = LocalGymStore();
    await gymStore.init(overrideDirectory: tmp('hub_big_gym_'));
    final foodStore = LocalFoodStore();
    await foodStore.init(overrideDirectory: tmp('hub_big_food_'));
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: const TextScaler.linear(2.0)),
        child: child!,
      ),
      home: FitnessHubScreen(
        apiClient: null,
        runStore: runStore,
        routeStore: routeStore,
        gymStore: gymStore,
        foodStore: foodStore,
        preferences: prefs,
        training: TrainingService(),
      ),
    ));
    await tester.pump();
    expect(tester.widget<TabBar>(find.byType(TabBar)).isScrollable, isTrue);
    for (final label in ['Plans', 'Races & courses', 'Routes']) {
      await openTab(tester, label);
      expect(tester.takeException(), isNull, reason: '$label overflowed');
    }
    // Every tab still carries its name for a screen reader.
    for (final label in ['Runs', 'Plans', 'Races & courses', 'Routes']) {
      expect(find.bySemanticsLabel(RegExp('^${RegExp.escape(label)}')),
          findsWidgets);
    }
  });

  testWidgets('Runs sub-tab hides the cloud sync slot; All keeps it',
      (tester) async {
    await pump(tester, runs: [runRow('r1')]);
    // All tab (api: null, signed out) renders the cloud slot's offline state.
    expect(find.byIcon(Icons.cloud_off), findsOneWidget);
    await openTab(tester, 'Runs');
    // The Runs sub-tab passes showSyncActions: false — no cloud slot at all,
    // in any of its three states.
    expect(find.byIcon(Icons.cloud_off), findsNothing);
    expect(find.byIcon(Icons.cloud_upload_outlined), findsNothing);
    expect(find.byIcon(Icons.cloud_download), findsNothing);
  });

  testWidgets(
      'Runs sub-tab carries no title of its own and shows the range status '
      'in the filter header', (tester) async {
    await pump(tester, runs: [runRow('r1')]);
    await openTab(tester, 'Runs');
    // "Runs" appears once, on the strip: the tab draws no title bar of its
    // own under it.
    expect(find.text('Runs'), findsOneWidget);
    // The range + count status the title otherwise carries renders as the
    // filter header's leading row instead (default range = This week).
    expect(find.text('This week · 1 run'), findsOneWidget);
  });

  testWidgets('Gym sub-tab hosts GymScreen with its empty-onboarding state',
      (tester) async {
    await pump(tester, runs: [runRow('r1')]);
    await openTab(tester, 'Gym');
    expect(find.byType(GymScreen), findsOneWidget);
  });

  testWidgets('Nutrition sub-tab hosts NutritionScreen', (tester) async {
    await pump(tester, runs: [runRow('r1')]);
    await openTab(tester, 'Nutrition');
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
    await openTab(tester, 'Gym');
    final gym = stateFor('fitness-gym');

    await openTab(tester, 'History');
    expect(identical(stateFor('fitness-all'), history), isTrue,
        reason: 'History was rebuilt from scratch on the way back');

    await openTab(tester, 'Gym');
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

    await openTab(tester, 'Runs');
    expect(find.byType(FloatingActionButton), findsOneWidget);

    await openTab(tester, 'Gym');
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

    await openTab(tester, 'Gym');
    expect(selected.value, FitnessTab.gym,
        reason: 'a tap on the strip never reached the host');
  });

  group('Gym and Nutrition visibility', () {
    testWidgets('a runner who has logged neither gets the run surface alone, '
        'in strip order, with no History', (tester) async {
      // History is the cross-modal timeline; with only runs in it, it is the
      // Runs tab a second time.
      final selected = ValueNotifier(FitnessTab.history);
      addTearDown(selected.dispose);
      await pump(tester,
          runs: [runRow('r1')], storedPrefs: const {}, selectedTab: selected);
      expect(find.byType(TabBar), findsOneWidget);
      expect(stripLabels(tester), strip());
      expect(find.byType(RunsScreen), findsOneWidget);
      expect(find.byType(GymScreen), findsNothing);
      expect(find.byType(NutritionScreen), findsNothing);
      expect(selected.value, FitnessTab.runs,
          reason: 'a selection on the missing History tab must fall back to '
              'a tab that exists');
    });

    testWidgets('Runs standing alone carries the cloud slot History had, so '
        'an unsynced run still shows its badge and Sync all', (tester) async {
      await pump(tester,
          unsyncedRuns: [runRow('r1')], storedPrefs: const {});
      expect(stripLabels(tester).first, 'Runs');
      expect(find.byIcon(Icons.cloud_upload), findsOneWidget);
      expect(find.byTooltip('Sync 1 run'), findsOneWidget);
    });

    testWidgets('with History back, the cloud slot moves to it and leaves Runs',
        (tester) async {
      await pump(tester,
          unsyncedRuns: [runRow('r1')],
          storedPrefs: const {'show_gym': true});
      expect(stripLabels(tester), strip(gym: true));
      expect(find.byIcon(Icons.cloud_upload), findsOneWidget);
      await openTab(tester, 'Runs');
      expect(find.byIcon(Icons.cloud_upload), findsNothing);
    });

    testWidgets('Runs standing alone tells a runner with no runs to tap Run, '
        'which is what the centre button now says', (tester) async {
      await pump(tester, storedPrefs: const {});
      expect(find.textContaining('Tap Run'), findsOneWidget);
      expect(find.textContaining('Tap Log'), findsNothing);
    });

    testWidgets('a logged lift keeps Gym, and History with it, without anyone '
        'opening Settings', (tester) async {
      await pump(tester,
          lifts: [liftRow('l1', 'Leg day')], storedPrefs: const {});
      expect(stripLabels(tester), strip(gym: true));
    });

    testWidgets('an explicit off hides a modality that has data',
        (tester) async {
      await pump(tester,
          lifts: [liftRow('l1', 'Leg day')],
          storedPrefs: const {'show_gym': false});
      expect(stripLabels(tester), strip());
      expect(find.byType(RunsScreen), findsOneWidget);
    });

    for (final (name, turnOn, tabs) in [
      (
        'Gym',
        (Preferences p) => p.setShowGym(true),
        strip(gym: true),
      ),
      (
        'Nutrition',
        (Preferences p) => p.setShowNutrition(true),
        strip(nutrition: true),
      ),
    ]) {
      testWidgets('History returns as soon as $name is switched on, and a '
          'Runs selection survives the strip coming back', (tester) async {
        final selected = ValueNotifier(FitnessTab.history);
        addTearDown(selected.dispose);
        final prefs = await pump(tester,
            runs: [runRow('r1')], storedPrefs: const {}, selectedTab: selected);
        expect(stripLabels(tester), strip());
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
      expect(
          stripLabels(tester), strip(gym: true, nutrition: true));

      await openTab(tester, 'Nutrition');
      expect(selected.value, FitnessTab.nutrition);

      await prefs.setShowNutrition(false);
      await tester.pumpAndSettle();
      expect(stripLabels(tester), strip(gym: true));
      expect(selected.value, FitnessTab.history,
          reason: 'a hidden tab cannot stay selected');
      expect(
          tester.widget<TabBar>(find.byType(TabBar)).controller!.index, 0);
    });

    testWidgets('switching the last modality off falls back to Runs',
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
      expect(stripLabels(tester), strip());
      expect(find.byType(NutritionScreen), findsNothing);
      expect(find.byType(RunsScreen), findsOneWidget);
      expect(selected.value, FitnessTab.runs);
    });

    test('fitnessHubTabs: the run surface always, History with either '
        'modality, Gym and Nutrition third and fourth',
        () {
      const planning = [
        FitnessTab.plans,
        FitnessTab.races,
        FitnessTab.routes,
      ];
      expect(fitnessHubTabs(gymShown: false, nutritionShown: false),
          [FitnessTab.runs, ...planning]);
      expect(fitnessHubTabs(gymShown: true, nutritionShown: false),
          [FitnessTab.history, FitnessTab.runs, FitnessTab.gym, ...planning]);
      expect(fitnessHubTabs(gymShown: false, nutritionShown: true), [
        FitnessTab.history,
        FitnessTab.runs,
        FitnessTab.nutrition,
        ...planning,
      ]);
      expect(fitnessHubTabs(gymShown: true, nutritionShown: true),
          FitnessTab.values);
    });
  });
}
