import 'package:api_client/api_client.dart';
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
/// only the TabBar chrome (mirrors `social_screen.dart`'s host shape). The
/// self-hiding contract holds — empty Gym/Nutrition tabs render their own
/// onboarding empty state, never a forced card.
///
/// The Gym and Nutrition tabs are also where the shell's centre Log action
/// lands, so these are the app's only instances of those two screens rather
/// than review copies of capture pages held elsewhere ([`selectedTab`],
/// decisions § 1652).
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
    with SingleTickerProviderStateMixin {
  late final TabController _controller;
  late final RaceService _raceService = RaceService();

  late final ValueNotifier<FitnessTab> _tab =
      widget.selectedTab ?? ValueNotifier(FitnessTab.history);
  late final bool _ownsTab = widget.selectedTab == null;

  @override
  void initState() {
    super.initState();
    _controller = TabController(
      length: FitnessTab.values.length,
      vsync: this,
      initialIndex: _tab.value.index,
    );
    _controller.addListener(_publishTab);
    _tab.addListener(_adoptTab);
  }

  /// Mid-animation the index has not committed yet, and publishing then would
  /// come straight back through [_adoptTab] and snap the transition.
  void _publishTab() {
    if (_controller.indexIsChanging) return;
    _tab.value = FitnessTab.values[_controller.index];
  }

  void _adoptTab() {
    if (_tab.value.index != _controller.index) {
      _controller.index = _tab.value.index;
    }
  }

  @override
  void dispose() {
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
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 0,
        bottom: AppTabBar(
          controller: _controller,
          labels: [
            for (final t in FitnessTab.values) t.label(l10n),
          ],
        ),
      ),
      body: TabBarView(
        controller: _controller,
        children: [
          RunsScreen(
            key: const PageStorageKey('fitness-all'),
            apiClient: widget.apiClient,
            runStore: widget.runStore,
            routeStore: widget.routeStore,
            preferences: widget.preferences,
            settingsSync: widget.settingsSync,
            gymStore: widget.gymStore,
            foodStore: widget.foodStore,
            showKindChips: false,
            // The shell's centre Log button, one row below this tab, already
            // opens the cross-modal run / lift / meal picker this tab's own
            // FAB opened. The modality tabs keep theirs — those add into one
            // modality, which the shell's picker does not.
            showAddFab: false,
          ),
          RunsScreen(
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
            showSyncActions: false,
            titleText: l10n.fitnessTabRuns,
          ),
          GymScreen(
            key: const PageStorageKey('fitness-gym'),
            api: widget.apiClient,
            store: widget.gymStore,
            social: widget.social,
          ),
          NutritionScreen(
            key: const PageStorageKey('fitness-nutrition'),
            api: widget.apiClient,
            store: widget.foodStore,
            settingsSync: widget.settingsSync,
          ),
        ],
      ),
    );
  }
}
