import 'package:api_client/api_client.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:ui_kit/ui_kit.dart';

import '../fab_clearance.dart';
import '../fitness_surface_requests.dart' show FitnessHubViews;
import '../l10n/gen/app_localizations.dart';
import '../local_food_store.dart';
import '../local_gym_store.dart';
import '../local_route_store.dart';
import '../local_run_store.dart';
import '../preferences.dart';
import '../race_service.dart';
import '../settings_sync.dart';
import '../social_service.dart';
import '../training_service.dart';
import 'gym_screen.dart';
import 'nutrition_screen.dart';
import 'plans_screen.dart';
import 'races_screen.dart';
import 'routes_screen.dart';
import 'runs_screen.dart';

/// The Fitness modality hub — the shell's one home for each modality, and
/// the run surface's sections with it. One top tab strip (`AppTabBar` over a
/// `TabBarView`, the shape `social_screen.dart` has) switches between:
///   - History: the unified cross-modal activity timeline — `RunsScreen`
///     mounted WITH the gym + food stores, with its own kind chips suppressed
///     since the hub's strip owns that axis.
///   - Runs: the offline-first run list (`RunsScreen` WITHOUT a gym store).
///   - Gym: `GymScreen`. Nutrition: `NutritionScreen`. Third and fourth,
///     beside the other logs, rather than past the run surface's planning
///     tabs, where at 360 dp they sat off screen (issue #1374, owner
///     decision 1).
///   - Plans, Races & courses, Routes: the run surface's planning and
///     discovery sections, each mounted here as a tab body rather than pushed
///     over the hub (decisions § 2437, superseding the peer strip of § 488 on
///     mobile). Races & courses is the race calendar plus the park courses
///     you can run any time (issue #1352). Routes is `Mine · Explore`, and
///     the segment catalogue is Explore's Segments chip rather than a tab of
///     its own (issue #1374, owner decision 1).
///
/// The hub owns the only app bar (the strip, no title) and the one FAB, as
/// the Social hub does: every tab body is a ui_kit `HubTabBody`, which inside
/// the hub's [HubTabScope] draws no app bar or title of its own, puts its
/// secondary actions in its control row and hands its primary action to the
/// hub, which shows the active tab's as its FAB (issue #1374). One strip in
/// every configuration: gym and food join the same row rather than stacking a
/// second strip inside Runs.
///
/// Gym and Nutrition are only in the strip while [modalityShown] says so: off
/// for a runner who has logged neither until they switch them on in Settings,
/// on for anyone who already logs them, and whatever the runner chose once
/// they have chosen. The strip is rebuilt when that answer changes. With
/// neither shown, History goes too: a timeline of nothing but runs is the
/// Runs tab a second time ([fitnessHubTabs]).
///
/// The Gym and Nutrition tabs are also where the shell's centre Log action
/// lands, so these are the app's only instances of those two screens rather
/// than review copies of capture pages held elsewhere ([`selectedTab`],
/// decisions § 1654). A link to Plans, Races, Routes or the segment
/// catalogue from anywhere else in the app selects the tab and its view here
/// too (`fitness_surface_requests.dart`) instead of pushing a second copy.
///
/// The Fitness hub's tabs, in strip order. Named + ordered rather than the
/// raw int this was, for the reason § 490 records — see `SocialTab`.
enum FitnessTab {
  history,
  runs,
  gym,
  nutrition,
  plans,
  races,
  routes;

  String label(AppLocalizations l10n) => switch (this) {
        // The hub's tabs are destinations, not kind filters: web's equivalent
        // of this one IS `/history`, and the RunsScreen it mounts titles its
        // own AppBar `navHistory` 48dp below. Naming the tab "All" put two
        // different names for one surface directly on top of each other
        // (#666 I9).
        FitnessTab.history => l10n.navHistory,
        FitnessTab.runs => l10n.fitnessTabRuns,
        FitnessTab.plans => l10n.runSurfaceTabPlans,
        FitnessTab.races => l10n.runSurfaceTabRacesCourses,
        FitnessTab.routes => l10n.fitnessRunsRoutes,
        FitnessTab.gym => l10n.fitnessTabGym,
        FitnessTab.nutrition => l10n.fitnessTabNutrition,
      };
}

/// The hub's tabs for a given modality visibility, in strip order. The first
/// is where a hidden selection falls back to and where the shell starts.
List<FitnessTab> fitnessHubTabs({
  required bool gymShown,
  required bool nutritionShown,
}) =>
    [
      if (gymShown || nutritionShown) FitnessTab.history,
      FitnessTab.runs,
      if (gymShown) FitnessTab.gym,
      if (nutritionShown) FitnessTab.nutrition,
      FitnessTab.plans,
      FitnessTab.races,
      FitnessTab.routes,
    ];

class FitnessHubScreen extends StatefulWidget {
  final ApiClient? apiClient;
  final SocialService? social;
  final LocalRunStore runStore;
  final LocalRouteStore routeStore;
  final LocalGymStore gymStore;
  final LocalFoodStore foodStore;
  final Preferences preferences;
  final SettingsSyncService? settingsSync;
  final TrainingService training;


  /// Which sub-tab is showing — shared with the host rather than owned here.
  ///
  /// The shell reaches Gym and Nutrition through this hub as well as through
  /// its own tab strip, so "which modality am I looking at" is state both
  /// entry points read and write. Held by the host so a Log action can select
  /// a tab before the hub has been built (it is a lazy page), and written back
  /// on every tap and swipe so the host can tell that a Log action would land
  /// on the tab already showing.
  ///
  /// Null in standalone mounts and tests, where the hub owns one of its own.
  final ValueNotifier<FitnessTab>? selectedTab;

  /// The views of Races & courses and Routes, held by the host beside
  /// [selectedTab] so a link can select a tab and its view together. Null in
  /// standalone mounts, where each tab owns its own.
  final FitnessHubViews? views;

  const FitnessHubScreen({
    super.key,
    this.apiClient,
    this.social,
    required this.runStore,
    required this.routeStore,
    required this.gymStore,
    required this.foodStore,
    required this.preferences,
    required this.training,
    this.settingsSync,
    this.selectedTab,
    this.views,
  });

  @override
  State<FitnessHubScreen> createState() => _FitnessHubScreenState();
}

class _FitnessHubScreenState extends State<FitnessHubScreen>
    with TickerProviderStateMixin {
  late TabController _controller;
  late List<FitnessTab> _tabs;
  late bool _centreOpensRecorder;
  late final RaceService _raceService = RaceService();
  final _actions = HubPrimaryActions();

  late final ValueNotifier<FitnessTab> _tab = widget.selectedTab ??
      ValueNotifier(_storedTab() ?? FitnessTab.history);
  late final bool _ownsTab = widget.selectedTab == null;

  /// The selection is also written to the enclosing [PageStorage], so a hub
  /// mounted without a host notifier comes back on the tab it was left on
  /// when its route is rebuilt. With a host notifier the host's value wins.
  static const _storageId = 'fitness-hub-tab';

  FitnessTab? _storedTab() {
    final name = PageStorage.maybeOf(context)
        ?.readState(context, identifier: _storageId);
    for (final t in FitnessTab.values) {
      if (t.name == name) return t;
    }
    return null;
  }

  void _rememberTab() => PageStorage.maybeOf(context)
      ?.writeState(context, _tab.value.name, identifier: _storageId);

  @override
  void initState() {
    super.initState();
    _tabs = _visibleTabs();
    _centreOpensRecorder = _resolveCentreOpensRecorder();
    _controller = _buildController();
    _settleSelection();
    _tab
      ..addListener(_adoptTab)
      ..addListener(_rememberTab);
    widget.preferences.addListener(_onVisibilityInputs);
    widget.gymStore.addListener(_onVisibilityInputs);
    widget.foodStore.addListener(_onVisibilityInputs);
  }

  bool get _gymShown =>
      widget.preferences.gymShown(hasData: widget.gymStore.workouts.isNotEmpty);

  bool get _nutritionShown => widget.preferences
      .nutritionShown(hasData: widget.foodStore.rows.isNotEmpty);

  List<FitnessTab> _visibleTabs() =>
      fitnessHubTabs(gymShown: _gymShown, nutritionShown: _nutritionShown);

  bool _resolveCentreOpensRecorder() => runIsPrimaryLogAction(
        keepRunPrimary: widget.preferences.keepRunPrimary,
        gymShown: _gymShown,
        nutritionShown: _nutritionShown,
      );

  TabController _buildController() {
    final index = _tabs.indexOf(_tab.value);
    final controller = TabController(
      length: _tabs.length,
      vsync: this,
      initialIndex: index < 0 ? 0 : index,
    );
    controller.addListener(_publishTab);
    return controller;
  }

  /// A tab that has just been hidden can't stay selected. Run only once the
  /// new controller is in [_controller]: the write notifies [_adoptTab],
  /// which would otherwise drive the controller just disposed.
  void _settleSelection() {
    if (!_tabs.contains(_tab.value)) _tab.value = _tabs.first;
  }

  /// Rebuilds the strip only when the set of tabs actually changes — the
  /// stores notify on every logged entry, and a fresh controller each time
  /// would reset the strip's animation for nothing.
  void _onVisibilityInputs() {
    final next = _visibleTabs();
    final opensRecorder = _resolveCentreOpensRecorder();
    final tabsChanged = !listEquals(next, _tabs);
    if (!tabsChanged && opensRecorder == _centreOpensRecorder) return;
    setState(() {
      _centreOpensRecorder = opensRecorder;
      if (!tabsChanged) return;
      _controller
        ..removeListener(_publishTab)
        ..dispose();
      _tabs = next;
      _controller = _buildController();
      _settleSelection();
    });
  }

  /// Mid-animation the index has not committed yet, and publishing then would
  /// come straight back through [_adoptTab] and snap the transition.
  void _publishTab() {
    if (_controller.indexIsChanging) return;
    _tab.value = _tabs[_controller.index];
  }

  void _adoptTab() {
    final index = _tabs.indexOf(_tab.value);
    if (index >= 0 && index != _controller.index) {
      _controller.index = index;
    }
  }

  @override
  void dispose() {
    widget.foodStore.removeListener(_onVisibilityInputs);
    widget.gymStore.removeListener(_onVisibilityInputs);
    widget.preferences.removeListener(_onVisibilityInputs);
    _tab
      ..removeListener(_rememberTab)
      ..removeListener(_adoptTab);
    _controller.removeListener(_publishTab);
    _controller.dispose();
    if (_ownsTab) _tab.dispose();
    _actions.dispose();
    super.dispose();
  }

  /// The race calendar is a public search — no provider key, and no sign-in,
  /// gates reaching it (decisions § 488). The MapTiler key only powers the
  /// optional "near a place" geocode, so an uninitialised dotenv degrades to
  /// name + distance search rather than blocking the tab.
  late final String? _mapTilerKey = () {
    try {
      final raw = (dotenv.env['MAPTILER_KEY'] ?? '').trim();
      if (raw.isNotEmpty) return raw;
    } catch (e) {
      debugPrint('fitness_hub: MAPTILER_KEY unreadable: $e');
    }
    return null;
  }();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 0,
        bottom: AppTabBar(
          controller: _controller,
          labels: [
            for (final t in _tabs) t.label(l10n),
          ],
        ),
      ),
      body: TabBarView(
        controller: _controller,
        children: [
          for (final t in _tabs)
            HubTabScope(tab: t, actions: _actions, child: _body(t, l10n)),
        ],
      ),
      floatingActionButtonLocation: pageFabLocation(context),
      floatingActionButton: ValueListenableBuilder<FitnessTab>(
        valueListenable: _tab,
        builder: (_, tab, _) => HubFab(actions: _actions, tab: tab),
      ),
    );
  }

  /// The cloud slot (unsynced badge, Sync all, parked-run badge) lives on one
  /// run list only, so two side-by-side tabs don't duplicate it. Pinning it to
  /// History by name left a runner with no History tab — neither modality
  /// shown — without any sign that a run hadn't uploaded, so it goes to
  /// whichever run list leads the strip.
  bool _ownsSyncActions(FitnessTab tab) => tab == _tabs.first;

  Widget _body(FitnessTab tab, AppLocalizations l10n) => switch (tab) {
        FitnessTab.history => RunsScreen(
            key: const PageStorageKey('fitness-all'),
            apiClient: widget.apiClient,
            runStore: widget.runStore,
            routeStore: widget.routeStore,
            preferences: widget.preferences,
            settingsSync: widget.settingsSync,
            social: widget.social,
            gymStore: widget.gymStore,
            foodStore: widget.foodStore,
            showKindChips: false,
            showSyncActions: _ownsSyncActions(tab),
            centreOpensRecorder: _centreOpensRecorder,
            // The shell's centre Log button, one row below this tab, already
            // opens the cross-modal run / lift / meal picker this tab's own
            // FAB opened. The modality tabs keep theirs — those add into one
            // modality, which the shell's picker does not.
            showAddFab: false,
          ),
        FitnessTab.runs => RunsScreen(
            key: const PageStorageKey('fitness-runs'),
            apiClient: widget.apiClient,
            runStore: widget.runStore,
            routeStore: widget.routeStore,
            preferences: widget.preferences,
            settingsSync: widget.settingsSync,
            social: widget.social,
            showSyncActions: _ownsSyncActions(tab),
            centreOpensRecorder: _centreOpensRecorder,
          ),
        // These three keep no state alive of their own, and a TabBarView page
        // is disposed once it scrolls out of view: without the wrapper a tab
        // switch would re-run each one's arrival fetch and drop its filters.
        FitnessTab.plans => KeepAliveTab(
            child: PlansScreen(
              key: const PageStorageKey('fitness-plans'),
              training: widget.training,
              apiClient: widget.apiClient,
              runStore: widget.runStore,
            ),
          ),
        FitnessTab.races => KeepAliveTab(
            child: RacesScreen(
              key: const PageStorageKey('fitness-races'),
              service: _raceService,
              mapTilerKey: _mapTilerKey,
              api: widget.apiClient,
              show: widget.views?.races,
            ),
          ),
        FitnessTab.routes => KeepAliveTab(
            child: RoutesScreen(
              key: const PageStorageKey('fitness-routes'),
              apiClient: widget.apiClient,
              routeStore: widget.routeStore,
              runStore: widget.runStore,
              preferences: widget.preferences,
              social: widget.social,
              show: widget.views?.routes,
            ),
          ),
        FitnessTab.gym => GymScreen(
            key: const PageStorageKey('fitness-gym'),
            api: widget.apiClient,
            store: widget.gymStore,
            social: widget.social,
          ),
        FitnessTab.nutrition => NutritionScreen(
            key: const PageStorageKey('fitness-nutrition'),
            api: widget.apiClient,
            store: widget.foodStore,
            settingsSync: widget.settingsSync,
          ),
      };
}
