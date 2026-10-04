import 'package:api_client/api_client.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:ui_kit/ui_kit.dart';

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
import '../widgets/surface_peer_strip.dart';
import 'global_segments_screen.dart';
import 'gym_screen.dart';
import 'nutrition_screen.dart';
import 'plans_screen.dart';
import 'races_screen.dart';
import 'routes_screen.dart';
import 'runs_screen.dart';

/// The Fitness modality hub — the shell's one home for each modality. A top
/// sub-tab strip switches between four surfaces:
///   - History: the unified cross-modal activity timeline (the former
///     standalone History tab, absorbed here) — `RunsScreen` mounted WITH the
///     gym + food stores, with its own kind chips suppressed since the hub's
///     TabBar owns that axis.
///   - Runs: the dedicated offline-first run list (`RunsScreen` WITHOUT a gym
///     store) plus a Routes entry, relocated here out of Social.
///   - Gym: `GymScreen`.
///   - Nutrition: `NutritionScreen`.
///
/// Each sub-tab body owns its own Scaffold/AppBar/composer; the hub provides
/// only the TabBar chrome (mirrors `social_screen.dart`'s host shape).
///
/// Gym and Nutrition are only in the strip while [modalityShown] says so: off
/// for a runner who has logged neither until they switch them on in Settings,
/// on for anyone who already logs them, and whatever the runner chose once
/// they have chosen. The strip is rebuilt when that answer changes.
///
/// With neither shown, History goes too: a timeline of nothing but runs is
/// the Runs tab a second time. That leaves one surface, so the hub renders
/// Runs directly rather than a strip with a single tab in it
/// ([fitnessHubTabs]).
///
/// The Gym and Nutrition tabs are also where the shell's centre Log action
/// lands, so these are the app's only instances of those two screens rather
/// than review copies of capture pages held elsewhere ([`selectedTab`],
/// decisions § 1654).
///
/// The Runs sub-tab additionally carries the labelled peer strip
/// `Runs · Routes · Segments · Plans · Races` (mirroring web's
/// `RunSurfaceTabs`), so run planning has a named destination instead of
/// hanging off tooltip-only glyphs (decisions § 488).
///
/// The Fitness hub's sub-tabs, in strip order. Named + ordered rather than the
/// raw int this was, for the reason § 490 records — see `SocialTab`.
enum FitnessTab {
  history,
  runs,
  gym,
  nutrition;

  String label(AppLocalizations l10n) => switch (this) {
        // The hub's tabs are destinations, not kind filters: web's equivalent
        // of this one IS `/history`, and the RunsScreen it mounts titles its
        // own AppBar `navHistory` 48dp below. Naming the tab "All" put two
        // different names for one surface directly on top of each other
        // (#666 I9).
        FitnessTab.history => l10n.navHistory,
        FitnessTab.runs => l10n.fitnessTabRuns,
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
  });

  @override
  State<FitnessHubScreen> createState() => _FitnessHubScreenState();
}

class _FitnessHubScreenState extends State<FitnessHubScreen>
    with TickerProviderStateMixin {
  late TabController _controller;
  late List<FitnessTab> _tabs;
  late bool _centreStartsRun;
  late final RaceService _raceService = RaceService();

  late final ValueNotifier<FitnessTab> _tab =
      widget.selectedTab ?? ValueNotifier(FitnessTab.history);
  late final bool _ownsTab = widget.selectedTab == null;

  @override
  void initState() {
    super.initState();
    _tabs = _visibleTabs();
    _centreStartsRun = _resolveCentreStartsRun();
    _controller = _buildController();
    _tab.addListener(_adoptTab);
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

  bool _resolveCentreStartsRun() => runIsPrimaryLogAction(
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
    // A tab that has just been hidden can't stay selected.
    if (index < 0) _tab.value = _tabs.first;
    return controller;
  }

  /// Rebuilds the strip only when the set of tabs actually changes — the
  /// stores notify on every logged entry, and a fresh controller each time
  /// would reset the strip's animation for nothing.
  void _onVisibilityInputs() {
    final next = _visibleTabs();
    final startsRun = _resolveCentreStartsRun();
    final tabsChanged = !listEquals(next, _tabs);
    if (!tabsChanged && startsRun == _centreStartsRun) return;
    setState(() {
      _centreStartsRun = startsRun;
      if (!tabsChanged) return;
      _controller
        ..removeListener(_publishTab)
        ..dispose();
      _tabs = next;
      _controller = _buildController();
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
    _tab.removeListener(_adoptTab);
    _controller.removeListener(_publishTab);
    _controller.dispose();
    if (_ownsTab) _tab.dispose();
    super.dispose();
  }

  void _openRoutes() {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => RoutesScreen(
        apiClient: widget.apiClient,
        routeStore: widget.routeStore,
        runStore: widget.runStore,
        preferences: widget.preferences,
        social: widget.social,
      ),
    ));
  }

  void _openSegments() {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => GlobalSegmentsScreen(api: widget.apiClient),
    ));
  }

  void _openPlans() {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => PlansScreen(
        training: widget.training,
        apiClient: widget.apiClient,
        runStore: widget.runStore,
      ),
    ));
  }

  void _openRaces() {
    // The race calendar is a public search — no provider key, and no sign-in,
    // gates reaching it (decisions § 488). The MapTiler key only powers the
    // optional "near a place" geocode, so an uninitialised dotenv degrades to
    // name + distance search rather than blocking the push.
    String? key;
    try {
      final raw = (dotenv.env['MAPTILER_KEY'] ?? '').trim();
      if (raw.isNotEmpty) key = raw;
    } catch (e) {
      debugPrint('fitness_hub: MAPTILER_KEY unreadable: $e');
    }
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => RacesScreen(service: _raceService, mapTilerKey: key),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // The controller is kept at length 1 so a modality switched back on only
    // has to grow it, the same rebuild every other visibility change takes.
    if (_tabs.length == 1) return _body(_tabs.single, l10n);
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
        children: [for (final t in _tabs) _body(t, l10n)],
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
            gymStore: widget.gymStore,
            foodStore: widget.foodStore,
            showKindChips: false,
            showSyncActions: _ownsSyncActions(tab),
            centreStartsRun: _centreStartsRun,
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
            surfacePeers: [
              SurfacePeer(label: l10n.fitnessTabRuns),
              SurfacePeer(label: l10n.fitnessRunsRoutes, onTap: _openRoutes),
              SurfacePeer(
                  label: l10n.runSurfaceTabSegments, onTap: _openSegments),
              SurfacePeer(label: l10n.runSurfaceTabPlans, onTap: _openPlans),
              SurfacePeer(label: l10n.runSurfaceTabRaces, onTap: _openRaces),
            ],
            showSyncActions: _ownsSyncActions(tab),
            titleText: l10n.fitnessTabRuns,
            centreStartsRun: _centreStartsRun,
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
