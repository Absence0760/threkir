import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart' as cm;

import '../adaptive_width.dart';
import '../audio_cues.dart';
import '../auth_change_aware.dart';
import '../ble_heart_rate.dart';
import '../ble_treadmill.dart';
import '../club_invite_link.dart' show pendingClubInviteToken;
import '../entity_link.dart';
import '../hr_prescription_gate.dart';
import '../l10n/gen/app_localizations.dart';
import '../local_food_store.dart';
import '../local_gear_store.dart';
import '../local_gym_store.dart';
import '../local_route_store.dart';
import '../local_run_store.dart';
import '../main.dart'
    show
        pendingArmGuidedRun,
        pendingStartWorkout,
        pendingStartRunWithRoute,
        pendingPushTarget;
import '../preferences.dart';
import '../push_target.dart';
import 'plan_target_screen.dart';
import '../race_controller.dart';
import '../race_service.dart';
import '../run_stop_dock.dart';
import '../settings_destination.dart';
import '../settings_sync.dart';
import '../sync_service.dart';
import '../shared_file_import.dart' show incomingRouteImport;
import '../social_service.dart';
import '../training_service.dart';
import '../today_widget.dart' show TodayWidgetBridge;
import '../watch_workout_push.dart' show WatchWorkoutBridge;
import '../fab_clearance.dart';
import '../help_destination.dart';
import '../help_guides.dart';
import '../widgets/billing_issue_banner.dart';
import '../widgets/confirm_destructive.dart';
import '../widgets/log_sheet.dart';
import '../widgets/log_speed_dial.dart';
import '../widgets/runner_menu.dart';
import '../widgets/top_banner.dart';
import 'add_run_screen.dart';
import 'challenges_screen.dart';
import 'club_detail_screen.dart';
import 'club_invite_screen.dart';
import 'clubs_screen.dart';
import 'confirm_age_screen.dart';
import 'dashboard_screen.dart';
import 'event_detail_screen.dart';
import 'fitness_hub_screen.dart';
import 'message_thread_screen.dart';
import 'messages_screen.dart';
import '../onboarding.dart';
import 'plan_new_screen.dart';
import 'plans_screen.dart';
import 'profile_screen.dart';
import 'public_route_screen.dart';
import 'public_run_screen.dart';
import 'races_screen.dart';
import 'route_detail_screen.dart';
import 'route_picker_screen.dart';
import 'run_detail_screen.dart';
import 'run_screen.dart';
import 'settings_about_screen.dart';
import 'settings_account_screen.dart';
import 'settings_body_metrics_screen.dart';
import 'settings_integrations_screen.dart';
import 'settings_preferences_screen.dart';
import 'settings_pro_screen.dart';
import 'settings_safety_screen.dart';
import 'setup_wizard_screen.dart';
import 'social_screen.dart';
import 'you_screen.dart';

/// The deferred half of the setup wizard's offline fail-safe exit
/// (issue #246). When the wizard was dismissed via "Finish later" while
/// the `onboarded_at` stamp couldn't reach the server, the gate must NOT
/// re-push the wizard — it retries the minimal [ApiClient.markOnboarded]
/// stamp instead, clearing the flag once one lands. Returns true when the
/// dismissal flag consumed the gate (whether or not the stamp landed).
@visibleForTesting
Future<bool> deferredOnboardingStampHandled(
  ApiClient api,
  Preferences preferences,
) async {
  if (!preferences.setupWizardDismissed) return false;
  try {
    await api.markOnboarded();
    await preferences.setSetupWizardDismissed(false);
  } catch (e) {
    debugPrint('deferred onboarding stamp failed (kept queued): $e');
  }
  return true;
}

class HomeScreen extends StatefulWidget {
  final ApiClient? apiClient;
  final LocalRunStore runStore;
  final LocalRouteStore routeStore;
  final LocalGearStore gearStore;
  final LocalGymStore gymStore;
  final LocalFoodStore foodStore;
  final Preferences preferences;
  final AudioCues audioCues;
  final SocialService social;
  final RaceController raceController;
  final TrainingService training;
  final BleHeartRate heartRate;
  final BleTreadmill treadmill;
  final SettingsSyncService? settingsSync;

  /// The run drain, so Home's pending-sync banner can retry runs. Null in
  /// tests and leaves runs counted there but not retried.
  final SyncService? syncService;
  final cm.Run? recoveredRun;

  /// Banner copy emitted by the in-progress recovery helper at app
  /// start. Surfaced once on the first build of the Home tab. Covers
  /// both "Recovered a 2.3 km partial..." and the new
  /// "Discarded a 38 m partial recording..." case (Casual #3). Null
  /// when the recovery pass had nothing to say.
  final String? recoveryBannerMessage;

  /// A recent in-progress partial left over from a process-kill. When set,
  /// HomeScreen jumps to the Run page on first frame and RunScreen prompts the
  /// user to Resume / Finish / Discard it (resume the primary path) so a
  /// multi-day effort continues as ONE run instead of two.
  final cm.Run? resumablePartial;

  const HomeScreen({
    super.key,
    this.apiClient,
    required this.runStore,
    required this.routeStore,
    required this.gearStore,
    required this.gymStore,
    required this.foodStore,
    required this.preferences,
    required this.audioCues,
    required this.social,
    required this.raceController,
    required this.training,
    required this.heartRate,
    required this.treadmill,
    this.settingsSync,
    this.syncService,
    this.recoveredRun,
    this.recoveryBannerMessage,
    this.resumablePartial,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with AuthChangeAware<HomeScreen> {
  // PageView page indices. The bottom nav exposes four destinations
  // (Home / Fitness / Social / You) plus a centre Log action; the Run page
  // has no nav destination but stays a keep-alive PageView page so an
  // in-progress recording survives navigating away (multi_modal.md §
  // Bottom nav). Fitness is the modality hub (All/Runs/Gym/Nutrition); the
  // former standalone History tab is absorbed into its All sub-tab, and
  // Settings folds into You.
  static const _pageHome = 0;
  static const _pageFitness = 1;
  // Run has no bottom-nav destination — it is the dwell-in capture surface the
  // centre Log action reaches, a keep-alive page so a live recording survives
  // swiping to Home and back. It can't be anything else: a foreground-service
  // GPS session can't collapse into a modal, and it is a screen of its own
  // (`RunScreen`, the recorder) rather than a second copy of the run list.
  //
  // Gym and Nutrition have no page here, because they have no screen of their
  // own: `Log lift` and `Log food` open the Fitness hub's Gym and Nutrition
  // tabs, which are the same dwell-in workspaces with the composer one tap
  // away. They used to be mounted BOTH here and in the hub, which meant two
  // keep-alive copies of one surface with independent state — and a runner who
  // stepped the diary back to yesterday in the hub and then tapped Log → Food
  // landed on an identical-looking screen showing today (decisions § 1654).
  static const _pageRun = 2;
  static const _pageSocial = 3;
  static const _pageYou = 4;
  static const _initialIndex = _pageHome;

  /// Which Fitness sub-tab the hub is showing. Owned here rather than inside
  /// the hub because the centre Log action selects one, and the hub is a lazy
  /// page that may not be built yet when it does. Starts on the hub's first
  /// tab, which is Runs rather than History when neither Gym nor Nutrition is
  /// shown, because History is not in the hub then.
  late final _fitnessTab = ValueNotifier<FitnessTab>(fitnessHubTabs(
    gymShown: _gymShown,
    nutritionShown: _nutritionShown,
  ).first);

  /// Current page index. A `ValueNotifier` instead of a `setState` int so
  /// page changes during a swipe only rebuild the bottom bar — not the
  /// entire 5-page subtree. The PageView's children are built once in
  /// `initState` and never re-created.
  final _currentIndex = ValueNotifier<int>(_initialIndex);

  /// Everything the centre button's look reads: whether a run is recording,
  /// and whether a tap starts one, which turns on the preferences and on
  /// whether a lift or a meal exists. The button and its caption rebuild on
  /// any of them.
  late final Listenable _centreInputs = Listenable.merge([
    runRecordingActive,
    widget.preferences,
    widget.gymStore,
    widget.foodStore,
  ]);

  /// The nav bar and rail read the page, and the hub's label reads the same
  /// visibility the centre button does. The docked centre button reads the
  /// page too: it is the Stop while a run records on the Run page.
  late final Listenable _navInputs =
      Listenable.merge([_currentIndex, _centreInputs]);

  late final PageController _pageController =
      PageController(initialPage: _initialIndex);

  cm.Route? _preselectedRoute;

  /// Built once and cached, so each page change during a swipe reuses the
  /// same widget instances instead of recreating them and relying on
  /// Flutter's reconciliation step.
  late List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _rebuildPages();
    pendingStartWorkout.addListener(_onPendingStartWorkout);
    pendingArmGuidedRun.addListener(_onPendingArmGuidedRun);
    pendingStartRunWithRoute.addListener(_onPendingStartRunWithRoute);
    widget.training.addListener(_onTrainingChange);
    incomingRouteImport.addListener(_onIncomingRouteImport);
    pendingPushTarget.addListener(_onPendingPushTarget);
    pendingSettingsDestination.addListener(_onPendingSettingsDestination);
    pendingHelpDestination.addListener(_onPendingHelpDestination);
    pendingClubInviteToken.addListener(_onPendingClubInvite);
    pendingEntityLink.addListener(_onPendingEntityLink);
    // A GPX/KML opened while the app was closed sets the notifier during
    // main() before this screen mounts, so drain any already-present value
    // once the first frame is up (the listener only fires on later shares).
    // A notification tap that cold-started the app lands the same way — the
    // push bridge reads the launch message with no Navigator yet in the tree.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshPlanOverview();
      _onIncomingRouteImport();
      _onPendingPushTarget();
      _onPendingSettingsDestination();
      _onPendingHelpDestination();
      _onPendingClubInvite();
      _onPendingEntityLink();
    });
    // Surface the recovery banner from main.dart's in-progress
    // evaluation. Casual #3: this also fires on DISCARD ("Discarded a
    // 38 m partial recording...") — pre-fix that path was silent and
    // a casual user couldn't tell whether the app saw + dropped their
    // tap-Start-then-quit attempt or just lost the run entirely.
    final bannerMessage = widget.recoveryBannerMessage;
    if (bannerMessage != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        showTopBanner(
          context,
          bannerMessage,
          duration: const Duration(seconds: 6),
        );
      });
    }
    // A resumable in-progress partial (process was killed mid-run): jump
    // straight to the keep-alive Run page on first frame so RunScreen builds
    // and prompts Resume / Finish / Discard. The runner reopening the app at
    // the next aid station lands back on the recording surface rather than
    // hunting for it.
    if (widget.resumablePartial != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _goToPage(_pageRun);
      });
    }
    // Post-sign-in gates (mobile twin of web's root-layout consent and
    // `/onboarding` redirects): the GDPR Art 8 consent screen when the
    // profile records no age + terms confirmation, then the setup wizard
    // when `user_profiles.onboarded_at` is still null. Skipped offline /
    // signed out (the profile read fails and nothing is pushed). Fires
    // after the first frame so the dashboard is mounted underneath.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _runSignInGates();
    });
  }

  bool _setupWizardShown = false;
  bool _consentGateOpen = false;

  @override
  ApiClient? get authApi => widget.apiClient;

  /// The post-frame gates in initState only cover a session that
  /// was already signed in at launch. The normal signup flow — launch
  /// signed out, create the account from Settings — and a fresh account
  /// signing in over a previous session both arrive here instead, so the
  /// gate re-arms and re-runs per identity (the server-side onboarded_at
  /// check keeps it from ever showing twice for the same user).
  @override
  void onAuthUserChanged(String? userId) {
    _setupWizardShown = false;
    if (userId != null) _runSignInGates();
  }

  Future<void> _runSignInGates() async {
    final api = widget.apiClient;
    if (api == null || api.userId == null) return;
    if (_setupWizardShown || _consentGateOpen) return;
    // A sign-up that collected the affirmation in-app is still stamping
    // it; reading before that lands would re-ask.
    await api.consentStampSettled;
    if (!mounted) return;
    cm.UserProfileRow? profile;
    try {
      profile = await api.fetchMyProfile();
    } catch (e) {
      debugPrint('sign-in gates: fetchMyProfile failed: $e');
      return;
    }
    if (!mounted) return;
    if (!consentRecordedOn(profile)) {
      _consentGateOpen = true;
      final confirmed = await Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(
          fullscreenDialog: true,
          builder: (_) => ConfirmAgeScreen(apiClient: api),
        ),
      );
      _consentGateOpen = false;
      if (!mounted || confirmed != true) return;
      try {
        profile = await api.fetchMyProfile();
      } catch (e) {
        debugPrint('sign-in gates: fetchMyProfile after consent failed: $e');
        return;
      }
      if (!mounted) return;
    }
    if (await deferredOnboardingStampHandled(api, widget.preferences)) {
      return;
    }
    if (!mounted) return;
    // Only an account with a materialised row but no onboarded_at stamp
    // gets the wizard. A row that still isn't there is left alone —
    // better to skip than to block a signed-in user behind a wizard we
    // can't persist.
    if (profile == null || profile.onboardedAt != null) return;
    _setupWizardShown = true;
    // The wizard pops the chosen `primary_goal` when the runner taps the
    // goal-keyed "create my training plan" CTA (else null). Route straight
    // into the plan wizard preselected so a brand-new runner doesn't have to
    // hunt for /plans/new + the beginner walk-run toggle.
    final goal = await Navigator.of(context).push<String?>(
      MaterialPageRoute<String?>(
        fullscreenDialog: true,
        builder: (_) => SetupWizardScreen(
          apiClient: api,
          preferences: widget.preferences,
          settingsSync: widget.settingsSync,
          initialDisplayName: profile!.displayName,
          // The profile column is 'km'-defaulted at signup
          // (confirm_age_and_terms), so it can't distinguish a user's
          // choice from the default — passing it would clobber the
          // wizard's locale-derived unit seed. The bag key exists only
          // once the user explicitly picked a unit.
          initialPreferredUnit: widget.settingsSync?.service
              ?.effective<String>(SettingsKeys.preferredUnit),
        ),
      ),
    );
    if (!mounted || goal == null) return;
    final preset = planPresetForGoal(goal);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlanNewScreen(
          training: widget.training,
          initialGoal: preset.goalEvent,
          initialBeginnerWalkRun: preset.beginnerWalkRun,
        ),
      ),
    );
  }

  /// Bring the user to the Run tab when something deeper in the nav
  /// stack (e.g. plan_detail's calendar → workout_detail → Start) signals
  /// that a structured workout should start. RunScreen handles the actual
  /// workout-load on its end via the same notifier.
  void _onPendingStartWorkout() {
    if (pendingStartWorkout.value == null) return;
    if (!mounted) return;
    if (_currentIndex.value != _pageRun) {
      _currentIndex.value = _pageRun;
      _pageController.jumpToPage(_pageRun);
    }
  }

  /// The guided-run detail screen armed a script for the recorder. Same
  /// shape as [_onPendingStartWorkout]: bring the Run tab forward and leave
  /// the draining to RunScreen, which owns the arming.
  void _onPendingArmGuidedRun() {
    if (pendingArmGuidedRun.value == null) return;
    if (!mounted) return;
    if (_currentIndex.value != _pageRun) {
      _currentIndex.value = _pageRun;
      _pageController.jumpToPage(_pageRun);
    }
  }

  /// A route surface (route-detail Start FAB, the public / shared-route
  /// screen) asked to start a run following a route. Drain the handoff and
  /// route into the recorder with the route preselected — `_startRunWithRoute`
  /// itself pops back to the shell so any pushed route screen is dismissed.
  void _onPendingStartRunWithRoute() {
    final route = pendingStartRunWithRoute.value;
    if (route == null || !mounted) return;
    pendingStartRunWithRoute.value = null;
    _startRunWithRoute(route);
  }

  /// A push notification was tapped. Drain the parked target and open the
  /// surface it names. Every arm is an L4 auxiliary effect — a failure here
  /// must never take startup or the shell with it, so the whole body is
  /// guarded. A club or event whose slug won't resolve falls back to the clubs
  /// hub rather than opening a screen that can never load; the mapper has
  /// already sent anything it couldn't place to the inbox.
  Future<void> _onPendingPushTarget() async {
    final target = pendingPushTarget.value;
    if (target == null || !mounted) return;
    pendingPushTarget.value = null;
    final api = widget.apiClient;
    if (api == null) return;
    try {
      await _openPushTarget(api, target);
    } catch (e) {
      debugPrint('push target navigation failed: $e');
    }
  }

  Future<void> _openPushTarget(ApiClient api, PushTarget target) async {
    switch (target.kind) {
      case PushTargetKind.notifications:
        final me = api.userId;
        if (me == null) return;
        await _pushScreen(ProfileScreen(
          api: api,
          userId: me,
          initialTab: ProfileTab.notifications,
        ));
      case PushTargetKind.profile:
        await _pushScreen(ProfileScreen(api: api, userId: target.id!));
      case PushTargetKind.run:
        await _openRun(target.id!);
      case PushTargetKind.plans:
        await _pushScreen(PlansScreen(
          training: widget.training,
          apiClient: api,
          runStore: widget.runStore,
        ));
      case PushTargetKind.plan:
      case PushTargetKind.planWorkout:
        await _pushScreen(planTargetScreen(target,
            training: widget.training, runStore: widget.runStore));
      case PushTargetKind.challenges:
        await _pushScreen(ChallengesScreen(social: widget.social));
      case PushTargetKind.clubs:
        await _pushClubsHub(api);
      case PushTargetKind.club:
        final slug = await widget.social.fetchClubSlugById(target.id!);
        if (!mounted) return;
        if (slug == null) return _pushClubsHub(api);
        await _pushScreen(ClubDetailScreen(
          social: widget.social,
          training: widget.training,
          apiClient: api,
          routeStore: widget.routeStore,
          slug: slug,
        ));
      case PushTargetKind.event:
        final slug = await widget.social.fetchClubSlugForEvent(target.id!);
        if (!mounted) return;
        if (slug == null) return _pushClubsHub(api);
        await _pushScreen(EventDetailScreen(
          social: widget.social,
          clubSlug: slug,
          eventId: target.id!,
        ));
      case PushTargetKind.messages:
        final partnerId = target.id;
        await _pushScreen(partnerId == null
            ? MessagesScreen(api: api)
            : MessageThreadScreen(api: api, partnerId: partnerId));
      case PushTargetKind.settingsAccount:
        await _pushScreen(
          _settingsDestinationScreen(SettingsDestination.account),
        );
    }
  }

  /// A surface somewhere in the tree asked to open a Settings sub-screen.
  /// Drain the parked destination and push it.
  ///
  /// The shell is the host because it already holds every dependency the
  /// settings screens take, so a leaf surface needs none of them — see
  /// [SettingsDestination] and decisions § 710. The push lands on top of the
  /// current tab rather than switching to You first: a runner sent to
  /// Preferences from the nearby list wants one Back to return to the list
  /// they were reading, not to be relocated into Settings.
  void _onPendingSettingsDestination() {
    final destination = pendingSettingsDestination.value;
    if (destination == null || !mounted) return;
    pendingSettingsDestination.value = null;
    _pushScreen(_settingsDestinationScreen(destination));
  }

  Widget _settingsDestinationScreen(SettingsDestination destination) =>
      switch (destination) {
        SettingsDestination.preferences => SettingsPreferencesScreen(
            apiClient: widget.apiClient,
            preferences: widget.preferences,
            settingsSync: widget.settingsSync,
            gymStore: widget.gymStore,
            foodStore: widget.foodStore,
          ),
        SettingsDestination.account => SettingsAccountScreen(
            apiClient: widget.apiClient,
            preferences: widget.preferences,
            settingsSync: widget.settingsSync,
            runStore: widget.runStore,
            routeStore: widget.routeStore,
          ),
        SettingsDestination.safety => SettingsSafetyScreen(
            api: widget.apiClient,
            settingsSync: widget.settingsSync,
          ),
        SettingsDestination.integrations => SettingsIntegrationsScreen(
            apiClient: widget.apiClient,
            heartRate: widget.heartRate,
            treadmill: widget.treadmill,
            preferences: widget.preferences,
            settingsSync: widget.settingsSync,
          ),
        SettingsDestination.bodyMetrics => SettingsBodyMetricsScreen(
            api: widget.apiClient,
            settingsSync: widget.settingsSync,
            preferences: widget.preferences,
          ),
        SettingsDestination.about => const SettingsAboutScreen(),
        SettingsDestination.pro =>
            SettingsProScreen(apiClient: widget.apiClient),
      };

  /// A help guide's route link asked for a surface. Drain the parked intent
  /// and open it with the dependencies the shell holds (decisions § 710's
  /// seam). L4: a guide link failing to navigate must not take the shell
  /// with it.
  Future<void> _onPendingHelpDestination() async {
    final destination = pendingHelpDestination.value;
    if (destination == null || !mounted) return;
    pendingHelpDestination.value = null;
    try {
      await _openHelpDestination(destination);
    } catch (e) {
      debugPrint('help destination navigation failed: $e');
    }
  }

  Future<void> _openHelpDestination(HelpDestination destination) async {
    final api = widget.apiClient;
    switch (destination) {
      case HelpDestination.clubs:
        if (api != null) {
          await _openPushTarget(api, const PushTarget(PushTargetKind.clubs));
        }
      case HelpDestination.notifications:
        if (api != null) await _openPushTarget(api, PushTarget.inbox);
      case HelpDestination.runs:
        // The run list is a Fitness hub tab, not a pushable screen: return to
        // the shell and select it, as the Log action does for Gym/Nutrition.
        final shell = ModalRoute.of(context);
        Navigator.of(context).popUntil((route) => route == shell);
        _fitnessTab.value = FitnessTab.runs;
        _goToPage(_pageFitness);
      case HelpDestination.races:
        String? key;
        try {
          final raw = (dotenv.env['MAPTILER_KEY'] ?? '').trim();
          if (raw.isNotEmpty) key = raw;
        } catch (e) {
          debugPrint('home: MAPTILER_KEY unreadable: $e');
        }
        await _pushScreen(
            RacesScreen(service: RaceService(), mapTilerKey: key));
      case HelpDestination.integrations:
        await _pushScreen(
            _settingsDestinationScreen(SettingsDestination.integrations));
      case HelpDestination.preferences:
        await _pushScreen(
            _settingsDestinationScreen(SettingsDestination.preferences));
      case HelpDestination.safety:
        await _pushScreen(
            _settingsDestinationScreen(SettingsDestination.safety));
      case HelpDestination.account:
        await _pushScreen(
            _settingsDestinationScreen(SettingsDestination.account));
      case HelpDestination.pro:
        await _pushScreen(
            _settingsDestinationScreen(SettingsDestination.pro));
    }
  }

  Future<void> _pushClubsHub(ApiClient api) => _pushScreen(ClubsScreen(
        social: widget.social,
        training: widget.training,
        apiClient: api,
        routeStore: widget.routeStore,
      ));

  Future<void> _pushScreen(Widget screen) {
    if (!mounted) return Future<void>.value();
    return Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  /// An invite link the OS opened the app with: hand the token to the invite
  /// screen, which redeems it on mount (and asks for the activity-risk
  /// acknowledgement when the club requires it).
  Future<void> _onPendingClubInvite() async {
    final token = pendingClubInviteToken.value;
    if (token == null || !mounted) return;
    pendingClubInviteToken.value = null;
    await _pushScreen(ClubInviteScreen(
      social: widget.social,
      training: widget.training,
      initialToken: token,
    ));
  }

  /// A run or route link the OS opened the app with, or a run an in-app
  /// surface handed over with `openRunLink`. The runner's own run or
  /// route opens its owner screen from the device; anything else opens the
  /// non-owner view, which reads public first and then what the owner shared
  /// with this viewer (decisions § 1874), with the clipped track only. An L4
  /// effect: a failure is logged, never thrown into the shell.
  Future<void> _onPendingEntityLink() async {
    final link = pendingEntityLink.value;
    if (link == null || !mounted) return;
    pendingEntityLink.value = null;
    try {
      await _openEntityLink(link);
    } catch (e) {
      debugPrint('entity link navigation failed: $e');
    }
  }

  /// The one decision every run link, push and inbox row shares, as web's
  /// `/runs/[id]` makes it: the owner's detail screen when the run is on this
  /// device, else the non-owner view. A run of the runner's own that is not on
  /// the device (an older one the history list has not paged in) takes the
  /// non-owner view too, which reads the owner's unclipped track for them.
  Future<void> _openRun(String runId) async {
    final api = widget.apiClient;
    final own = await widget.runStore.runById(runId);
    if (!mounted) return;
    if (own != null) {
      return _pushScreen(RunDetailScreen(
        run: own,
        runStore: widget.runStore,
        routeStore: widget.routeStore,
        preferences: widget.preferences,
        apiClient: api,
        settingsSync: widget.settingsSync,
      ));
    }
    if (api == null) return;
    await _pushScreen(PublicRunScreen(api: api, runId: runId));
  }

  Future<void> _openEntityLink(EntityLink link) async {
    final api = widget.apiClient;
    switch (link.kind) {
      case EntityLinkKind.run:
        await _openRun(link.id);
      case EntityLinkKind.route:
        final own = widget.routeStore.routes
            .where((r) => r.id == link.id)
            .firstOrNull;
        if (own != null) {
          return _pushScreen(RouteDetailScreen(
            route: own,
            routeStore: widget.routeStore,
            preferences: widget.preferences,
            apiClient: api,
            isOwner: true,
          ));
        }
        if (api == null) return;
        await _pushScreen(PublicRouteScreen(api: api, routeId: link.id));
    }
  }

  /// A GPX/KML handed to the app by another app (WhatsApp "Open with" /
  /// share, iOS document open) was imported into the route library; drain
  /// the handoff, confirm it, and open the freshly-imported route. Every
  /// failure collapses to one generic banner (the service logged the cause).
  void _onIncomingRouteImport() {
    final result = incomingRouteImport.value;
    if (result == null || !mounted) return;
    incomingRouteImport.value = null;
    final l10n = AppLocalizations.of(context);
    if (!result.ok) {
      showTopBanner(context, l10n.routesImportSharedFailed);
      return;
    }
    final route = result.route!;
    showTopBanner(context, l10n.routesImported(route.name));
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RouteDetailScreen(
          route: route,
          routeStore: widget.routeStore,
          preferences: widget.preferences,
          apiClient: widget.apiClient,
          isOwner: true,
        ),
      ),
    );
  }

  void _rebuildPages() {
    // Each page is wrapped in `_LazyKeepAliveTab`, which only constructs
    // its heavy child on the first `build` call. PageView lazily builds
    // its children (only the visible page + cacheExtent neighbours) so
    // tabs the user hasn't touched stay un-initialised — saving their
    // initState `_load()` network calls and listener registrations
    // until the user actually swipes there.
    _pages = [
      _LazyKeepAliveTab(
        builder: () => DashboardScreen(
          key: const PageStorageKey('dashboard'),
          apiClient: widget.apiClient,
          training: widget.training,
          runStore: widget.runStore,
          routeStore: widget.routeStore,
          gymStore: widget.gymStore,
          foodStore: widget.foodStore,
          preferences: widget.preferences,
          settingsSync: widget.settingsSync,
          onStartRun: () => _performLogAction(LogAction.run),
          onLogLift: () => _performLogAction(LogAction.lift),
          onSyncRuns: widget.syncService == null
              ? null
              : () => widget.syncService!.triggerSync('manual'),
        ),
      ),
      _LazyKeepAliveTab(
        builder: () => FitnessHubScreen(
          key: const PageStorageKey('fitness'),
          apiClient: widget.apiClient,
          social: widget.social,
          runStore: widget.runStore,
          routeStore: widget.routeStore,
          gymStore: widget.gymStore,
          foodStore: widget.foodStore,
          preferences: widget.preferences,
          settingsSync: widget.settingsSync,
          training: widget.training,
          selectedTab: _fitnessTab,
        ),
      ),
      _LazyKeepAliveTab(
        // rebuildKey ties the cached child to the preselected
        // route's id — when `_startRunWithRoute` updates
        // `_preselectedRoute`, the id flips, the cache invalidates,
        // and the next build calls the RunScreen builder with the
        // freshly-set `initialRoute`. Without this, a user who
        // tapped "Start Run" from a route detail jumped to the
        // Run page but the route stayed unselected.
        rebuildKey: _preselectedRoute?.id,
        builder: () => RunScreen(
          key: const PageStorageKey('run'),
          apiClient: widget.apiClient,
          runStore: widget.runStore,
          routeStore: widget.routeStore,
          preferences: widget.preferences,
          audioCues: widget.audioCues,
          settingsSync: widget.settingsSync,
          social: widget.social,
          raceController: widget.raceController,
          training: widget.training,
          heartRate: widget.heartRate,
          treadmill: widget.treadmill,
          initialRoute: _preselectedRoute,
          initialResumablePartial: widget.resumablePartial,
        ),
      ),
      _LazyKeepAliveTab(
        builder: () => SocialScreen(
          key: const PageStorageKey('social'),
          api: widget.apiClient,
          social: widget.social,
          training: widget.training,
          routeStore: widget.routeStore,
        ),
      ),
      _LazyKeepAliveTab(
        builder: () => YouScreen(
          key: const PageStorageKey('you'),
          apiClient: widget.apiClient,
          preferences: widget.preferences,
          runStore: widget.runStore,
          routeStore: widget.routeStore,
          gymStore: widget.gymStore,
          foodStore: widget.foodStore,
          gearStore: widget.gearStore,
          heartRate: widget.heartRate,
          treadmill: widget.treadmill,
          settingsSync: widget.settingsSync,
        ),
      ),
    ];
  }

  @override
  void dispose() {
    pendingStartWorkout.removeListener(_onPendingStartWorkout);
    pendingArmGuidedRun.removeListener(_onPendingArmGuidedRun);
    pendingStartRunWithRoute.removeListener(_onPendingStartRunWithRoute);
    widget.training.removeListener(_onTrainingChange);
    _trainingDebounce?.cancel();
    incomingRouteImport.removeListener(_onIncomingRouteImport);
    pendingPushTarget.removeListener(_onPendingPushTarget);
    pendingSettingsDestination
        .removeListener(_onPendingSettingsDestination);
    pendingHelpDestination.removeListener(_onPendingHelpDestination);
    pendingClubInviteToken.removeListener(_onPendingClubInvite);
    pendingEntityLink.removeListener(_onPendingEntityLink);
    _pageController.dispose();
    _currentIndex.dispose();
    _fitnessTab.dispose();
    super.dispose();
  }

  void _startRunWithRoute(cm.Route route) {
    // The Run page takes a preselected route via constructor; changing it
    // means rebuilding that page. Cheap — only reached by draining the
    // pendingStartRunWithRoute handoff, not during a swipe.
    _preselectedRoute = route;
    setState(_rebuildPages);
    _currentIndex.value = _pageRun;
    _pageController.jumpToPage(_pageRun);
    // Dismiss any screens pushed on top of the shell (RoutesScreen /
    // RouteDetailScreen — "Start run" is reached by pushing those). We
    // just jumped the shell PageView to the recorder, but a pushed
    // route screen would keep obscuring it — so tapping "Start run" from
    // the routes page looked like it just reopened the route page. Pop
    // back to the shell so the recorder is actually shown.
    if (mounted) {
      Navigator.of(context).popUntil((r) => r.isFirst);
    }
  }

  void _goToPage(int index) {
    if (index == _currentIndex.value) return;
    _currentIndex.value = index;
    // Jump instead of animate — sweeping across several pages would be slow
    // and distracting. Destinations, not a sequence.
    _pageController.jumpToPage(index);
  }

  void _onPageChanged(int index) {
    _currentIndex.value = index;
  }

  /// Guards against a second confirm stacking on the first — on Android the
  /// back gesture keeps firing while the dialog is up.
  bool _confirmingExit = false;

  /// System back. The shell is `MaterialApp.home`, so an unguarded back pops
  /// the only route and closes the app from whichever destination the user
  /// happened to be on. Back walks toward Home instead, and only Home leaves.
  ///
  /// A live recording never leaves silently: the Run page locks the swipe
  /// mid-run (issue #490), which makes back the one gesture still available
  /// there, and it would have taken the session with it.
  Future<void> _onSystemBack(int index, bool recording) async {
    if (index != _pageHome) {
      _goToPage(_pageHome);
      return;
    }
    if (!recording || _confirmingExit) return;
    _confirmingExit = true;
    final l10n = AppLocalizations.of(context);
    final leave = await confirmDestructive(
      context,
      title: l10n.backExitRecordingTitle,
      body: l10n.backExitRecordingBody,
      confirmLabel: l10n.backExitRecordingLeave,
      cancelLabel: l10n.backExitRecordingStay,
    );
    _confirmingExit = false;
    if (leave && mounted) await SystemNavigator.pop();
  }

  /// Wraps the shell so the system back gesture navigates rather than exits.
  /// Both notifiers feed only the `PopScope`'s `canPop`; the shell itself
  /// rides through as the builders' `child`, so a page change still rebuilds
  /// nothing but the nav bar.
  Widget _backGuard(Widget shell) => ValueListenableBuilder<bool>(
        valueListenable: runRecordingActive,
        builder: (context, recording, child) => ValueListenableBuilder<int>(
          valueListenable: _currentIndex,
          builder: (context, index, inner) => PopScope(
            canPop: index == _pageHome && !recording,
            onPopInvokedWithResult: (didPop, _) {
              if (didPop) return;
              _onSystemBack(index, recording);
            },
            child: inner!,
          ),
          child: child,
        ),
        child: shell,
      );

  // --- Centre Log button (multi_modal.md § Bottom nav) ---

  bool get _gymShown => widget.preferences
      .gymShown(hasData: widget.gymStore.workouts.isNotEmpty);

  bool get _nutritionShown => widget.preferences
      .nutritionShown(hasData: widget.foodStore.rows.isNotEmpty);

  /// Whether a tap on the centre Log button starts a run outright. Read at
  /// gesture time from the live stores rather than cached at build time, so
  /// the day's first logged lift flips it without a rebuild.
  bool get _runIsPrimary => runIsPrimaryLogAction(
        keepRunPrimary: widget.preferences.keepRunPrimary,
        gymShown: _gymShown,
        nutritionShown: _nutritionShown,
      );

  /// Tap on the centre Log button: the primary capture action for this user.
  /// While a run records it is the way back to it instead.
  void _onLogTap({Offset? anchor}) {
    if (runRecordingActive.value || _runIsPrimary) {
      _performLogAction(LogAction.run);
    } else {
      _openLogMenu(anchor: anchor);
    }
  }

  /// Long-press on the centre Log button opens the runner's menu: what the
  /// tap does not already do (decisions § R10MENU-1). One gesture, one
  /// meaning — it used to open the same fan as the tap, and with Gym and
  /// Nutrition hidden that fan had one item, so the long-press was the tap.
  ///
  /// Except mid-run: the button is then "return to your run" for both
  /// gestures, so a press held half a beat too long at a traffic light does
  /// not open a picker over the run.
  void _onLogLongPress() {
    if (runRecordingActive.value) {
      _performLogAction(LogAction.run);
    } else {
      _openRunnerMenu();
    }
  }

  /// The active plan, cached so the menu opens at once rather than after a
  /// plan read; [todaysOpenWorkout] re-derives today from it at menu time.
  /// Null until the first read lands. Offline, the read answers from the copy
  /// the last good one saved (`active_plan_cache.dart`).
  ActivePlanOverview? _planOverview;
  Timer? _trainingDebounce;

  Future<void> _refreshPlanOverview() async {
    final api = widget.apiClient;
    if (api != null) unawaited(refreshHrPrescriptionGate(api.hrPrescriptionEnabled));
    try {
      final p = await widget.training.fetchActiveOverview();
      if (mounted) _planOverview = p;
      // The same read keeps both watches and the home-screen widget holding
      // today's workout; a failed read pushes nothing, so each keeps what it
      // had.
      unawaited(WatchWorkoutBridge().publish(p));
      unawaited(TodayWidgetBridge().publish(p));
    } catch (e) {
      debugPrint('home: plan overview for the runner menu failed: $e');
    }
  }

  void _onTrainingChange() {
    _trainingDebounce?.cancel();
    _trainingDebounce = Timer(const Duration(milliseconds: 500), () {
      if (mounted) _refreshPlanOverview();
    });
  }

  Future<void> _openRunnerMenu() async {
    final workout = todaysOpenWorkout(
      _planOverview?.workouts ?? const [],
      DateTime.now(),
    );
    final routes = widget.routeStore.routes;
    final inline = recentRoutes(routes, widget.runStore.runs);
    final picked = await showRunnerMenu(
      context: context,
      actions: runnerMenuActions(
        tapFans: !_runIsPrimary,
        hasTodaysWorkout: workout != null,
        hasRoutes: routes.isNotEmpty,
        gymShown: _gymShown,
        nutritionShown: _nutritionShown,
      ),
      unit: widget.preferences.unit,
      todaysWorkout: workout,
      routes: inline,
      hasMoreRoutes: routes.length > inline.length,
    );
    if (picked == null || !mounted) return;
    switch (picked) {
      case RunnerMenuRouteChoice(:final route):
        _followRoute(route);
      case RunnerMenuActionChoice(:final action):
        switch (action) {
          case RunnerMenuAction.todaysWorkout:
            _startTodaysWorkout(workout!);
          case RunnerMenuAction.followRoute:
            await _pickRouteToFollow();
          case RunnerMenuAction.pastRun:
            _openAddPastRun();
          case RunnerMenuAction.lift:
            await _performLogAction(LogAction.lift);
          case RunnerMenuAction.food:
            await _performLogAction(LogAction.food);
        }
    }
  }

  /// The recorder loads a workout only from its start screen, so a finished
  /// run's summary is closed first, as a Start run tap closes it.
  void _startTodaysWorkout(cm.PlanWorkoutRow workout) {
    if (runSummaryShowing.value) runSummaryDismissRequests.request();
    // Cleared first: the recorder leaves a handoff it could not honour in
    // place, and writing the same row again would notify nobody.
    pendingStartWorkout.value = null;
    pendingStartWorkout.value = workout;
  }

  Future<void> _pickRouteToFollow() async {
    final picked = await pickRoute(
      context,
      routes: widget.routeStore.routes,
      unit: widget.preferences.unit,
    );
    if (picked == null || !mounted) return;
    _followRoute(picked);
  }

  /// The recorder takes a route only from its start screen, so a finished
  /// run's summary is closed first.
  void _followRoute(cm.Route route) {
    if (runSummaryShowing.value) runSummaryDismissRequests.request();
    _startRunWithRoute(route);
  }

  void _openAddPastRun() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => AddRunScreen(
          runStore: widget.runStore,
          routeStore: widget.routeStore,
          preferences: widget.preferences,
        ),
      ),
    );
  }

  Set<LogAction> get _hiddenLogActions => hiddenLogActions(
        gymShown: _gymShown,
        nutritionShown: _nutritionShown,
      );

  // The centre Log button fans the three capture actions up above itself
  // (speed-dial) rather than opening a bottom sheet; the History Log FAB keeps
  // the sheet.
  Future<void> _openLogMenu({Offset? anchor}) async {
    final picked = await showLogSpeedDial(
      context: context,
      recent: logActionFromWire(widget.preferences.lastLogType),
      hidden: _hiddenLogActions,
      anchor: anchor,
    );
    if (picked != null) _performLogAction(picked);
  }

  Future<void> _performLogAction(LogAction action) async {
    final l10n = AppLocalizations.of(context);
    widget.preferences.setLastLogType(action.wire);
    // Asking to log a lift or a meal is asking for that modality, and a
    // hidden one has no hub tab to land on — the first-run "Lifting instead?"
    // link reaches here for exactly the account whose Gym starts hidden.
    // Awaited so the hub's strip already has the tab when it is selected.
    //
    // It changes what the centre button's tap does from then on, so it is
    // announced, with an Undo: one stray tap on the first-run gym link used
    // to re-modalise the app silently, recoverable only from Settings.
    ({String message, Future<void> Function() undo})? switchedOn;
    if (action == LogAction.lift && !_gymShown) {
      final prior = widget.preferences.showGym;
      await widget.preferences.setShowGym(true);
      _roamModalityVisibility();
      switchedOn = (
        message: l10n.logModalityShownGym,
        undo: () => widget.preferences.setShowGym(prior),
      );
    } else if (action == LogAction.food && !_nutritionShown) {
      final prior = widget.preferences.showNutrition;
      await widget.preferences.setShowNutrition(true);
      _roamModalityVisibility();
      switchedOn = (
        message: l10n.logModalityShownNutrition,
        undo: () => widget.preferences.setShowNutrition(prior),
      );
    }
    if (!mounted) return;
    // Each Log action lands on that modality's dwell-in workspace (decisions
    // §63) — the keep-alive Run page for a recording, the Fitness hub's own Gym
    // and Nutrition tabs for the other two. All three behave identically: you
    // arrive on a surface you can operate in for as long as the session lasts
    // (record the run, build the workout over several sets, log the day's
    // meals) rather than a one-shot modal that closes after a single entry, and
    // each surfaces its composer one tap away.
    //
    // Gym and Nutrition are the hub's tabs rather than pages of their own so
    // that this button and the Fitness tab strip reach the SAME screen, still
    // showing the day, filters and half-typed entry it was left on (§ 1654).
    final tab = switch (action) {
      LogAction.run => null,
      LogAction.lift => FitnessTab.gym,
      LogAction.food => FitnessTab.nutrition,
    };
    final page = tab == null ? _pageRun : _pageFitness;
    // The Run page showing a finished run's summary is not the start screen,
    // wherever the tap came from: asking for a run closes the summary first.
    final leavingSummary =
        action == LogAction.run && runSummaryShowing.value;
    if (leavingSummary) runSummaryDismissRequests.request();
    if (!leavingSummary &&
        page == _currentIndex.value &&
        (tab == null || tab == _fitnessTab.value)) {
      // Picking the page you are already on is a no-op navigation, and the
      // fan closing onto an unchanged screen reads as a dropped tap. Say
      // where the tap went instead.
      showTopBanner(context, l10n.logAlreadyOnPage(_logPageName(l10n, action)));
      return;
    }
    if (tab != null) _fitnessTab.value = tab;
    _goToPage(page);
    if (switchedOn != null) _announceSwitchedOn(switchedOn);
  }

  /// The Undo restores the choice that was there before, which may be no
  /// choice at all: writing false would pin the modality hidden for a runner
  /// who later logs one, which is what the tri-state exists to avoid
  /// (decisions § 1739).
  void _announceSwitchedOn(
      ({String message, Future<void> Function() undo}) switchedOn) {
    showTopBanner(
      context,
      switchedOn.message,
      duration: const Duration(seconds: 6),
      actionLabel: AppLocalizations.of(context).undoAction,
      onAction: () async {
        try {
          await switchedOn.undo();
        } catch (e) {
          debugPrint('home: modality visibility undo failed: $e');
          return;
        }
        await _roamModalityVisibility();
      },
    );
  }

  Future<void> _roamModalityVisibility() async {
    try {
      await widget.settingsSync?.pushModalityVisibility();
    } catch (e) {
      debugPrint('home: modality visibility push failed: $e');
    }
  }

  /// Whether the docked centre button is the recorder's Stop: a run records
  /// (a manual pause included) and the Run page is showing. Phone shell only
  /// — the rail docks nothing, so the recorder panel keeps its own Stop there
  /// ([RunStopDock]). Away from the Run page the button stays the way back to
  /// it, so a tap from Home can never end a run.
  bool get _centreIsStop =>
      runRecordingActive.value && _currentIndex.value == _pageRun;

  /// The centre button's icon, caption and spoken label. When a tap starts a
  /// run it says so: a "+" captioned "Log" reads as "add an entry", and a
  /// first-timer only found out it opened the GPS recorder by pressing it.
  ///
  /// Mid-run the shell looked exactly as it does idle, and the way back to the
  /// recorder was a "+" that reads as "start another". So while a run records
  /// the button turns the error colour and says so, and a tap returns to it —
  /// except on the docked button over the Run page, where it is the Stop.
  ({IconData icon, String label, String semantics, bool recording})
      _centreLook(AppLocalizations l10n, {bool docked = false}) {
    if (docked && _centreIsStop) {
      return (
        icon: Icons.stop_rounded,
        label: l10n.navStop,
        semantics: l10n.runStopA11yLabel,
        recording: true,
      );
    }
    if (runRecordingActive.value) {
      return (
        icon: Icons.fiber_manual_record,
        label: l10n.navRecording,
        semantics: l10n.logReturnToRunA11yLabel,
        recording: true,
      );
    }
    return _runIsPrimary
        ? (
            // Play, not a runner: with Gym and Nutrition hidden the hub
            // beside it wears the runner glyph.
            icon: Icons.play_arrow,
            label: l10n.navStartRun,
            semantics: l10n.logStartRunA11yLabel,
            recording: false,
          )
        : (
            icon: Icons.add,
            label: l10n.navLog,
            semantics: l10n.logA11yLabel,
            recording: false,
          );
  }

  /// The Fitness hub's nav icon and label. "Fitness" under a dumbbell was
  /// chosen because the hub holds gym and nutrition too (decisions § 139);
  /// with both hidden it holds runs, routes, segments, plans and races, and
  /// a runner looking for their runs scanned past a gym icon. "Training"
  /// rather than "Runs" because the hub's own first tab is already "Runs",
  /// and it names the plans and races beside them.
  ({IconData icon, String label}) _hubLook(AppLocalizations l10n) =>
      _gymShown || _nutritionShown
          ? (icon: Icons.fitness_center, label: l10n.navFitness)
          : (icon: Icons.directions_run, label: l10n.navTraining);

  String _logPageName(AppLocalizations l10n, LogAction action) =>
      switch (action) {
        LogAction.run => l10n.navRun,
        LogAction.lift => l10n.gymTitle,
        LogAction.food => l10n.nutritionTitle,
      };

  @override
  Widget build(BuildContext context) {
    // PageView replaces IndexedStack so the user can swipe left/right
    // between tabs. Each child is wrapped in `_KeepAlive` so the state
    // of a tab (scroll position, live run recorder, in-flight fetches)
    // survives being swiped off-screen — the same guarantee IndexedStack
    // gave us for free.
    //
    // BillingIssueBanner sits above the PageView so it surfaces on
    // every authed tab when a Pro user has a failed renewal payment
    // sitting in the store's grace period. Cleared automatically
    // when the revenuecat-webhook fires RENEWAL / EXPIRATION /
    // CANCELLATION. Mirrors web's root-layout banner; renders
    // nothing when the flag is null or the user is on the free
    // tier — zero footprint in the common case.
    final expanded = widthClassOf(context) == WidthClass.expanded;
    final body = Column(
      children: [
        BillingIssueBanner(apiClient: widget.apiClient),
        Expanded(
          // Lock the horizontal swipe while a run is actively recording so a
          // stray swipe can't fling the user off the recording surface
          // mid-run (issue #490). Deliberate bottom-nav taps still navigate —
          // `_goToPage` drives the controller directly, which non-scrollable
          // physics doesn't block. Fail-open: the notifier defaults to false.
          child: RunStopDock(
            docked: !expanded,
            child: ValueListenableBuilder<bool>(
              valueListenable: runRecordingActive,
              builder: (context, recording, _) => PageView(
                controller: _pageController,
                onPageChanged: _onPageChanged,
                physics: recording
                    ? const NeverScrollableScrollPhysics()
                    : const PageScrollPhysics(),
                children: _pages,
              ),
            ),
          ),
        ),
      ],
    );
    if (expanded) {
      return _backGuard(Scaffold(
        body: Row(
          children: [
            ListenableBuilder(
              listenable: _navInputs,
              builder: (context, _) {
                final index = _currentIndex.value;
                final l10n = AppLocalizations.of(context);
                final hub = _hubLook(l10n);
                return NavigationRail(
                  selectedIndex: _railIndexFor(index),
                  onDestinationSelected: (i) => _goToPage(_railPages[i]),
                  labelType: NavigationRailLabelType.all,
                  leading: Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 24),
                    child: _logFab(anchored: true),
                  ),
                  destinations: [
                    NavigationRailDestination(
                      icon: const Icon(Icons.dashboard),
                      label: Text(l10n.navHome),
                    ),
                    NavigationRailDestination(
                      icon: Icon(hub.icon),
                      label: Text(hub.label),
                    ),
                    NavigationRailDestination(
                      icon: const Icon(Icons.public),
                      label: Text(l10n.navSocial),
                    ),
                    NavigationRailDestination(
                      icon: const Icon(Icons.person),
                      label: Text(l10n.navYou),
                    ),
                  ],
                );
              },
            ),
            const VerticalDivider(width: 1),
            // This branch has no `bottomNavigationBar`, so `Scaffold` leaves
            // the whole system bottom inset on the body's `MediaQuery` — where
            // the phone branch below spends it on the `BottomAppBar` and
            // `Scaffold` therefore zeroes it. The pages were written against
            // that zero (`SafeArea(bottom: false)` on dashboard and You), so
            // without this the last card on a tablet sits under the
            // gesture / nav bar. `SafeArea` both pads and removes, so a page
            // sees the same zero either way (decisions § 538); left / right
            // stay for the pages, matching the phone branch.
            Expanded(
              child: SafeArea(
                top: false,
                left: false,
                right: false,
                child: body,
              ),
            ),
          ],
        ),
      ));
    }
    return _backGuard(Scaffold(
      body: DockedFabInset(height: kDockedFabOverhang, child: body),
      floatingActionButton: _logFab(),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: ListenableBuilder(
        listenable: _navInputs,
        builder: (context, _) {
          final index = _currentIndex.value;
          final l10n = AppLocalizations.of(context);
          final hub = _hubLook(l10n);
          final metrics =
              bottomNavMetrics(MediaQuery.textScalerOf(context).scale(1));
          return BottomAppBar(
            height: metrics.height,
            padding: EdgeInsets.zero,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _BottomNavItem(
                  icon: Icons.dashboard,
                  label: l10n.navHome,
                  selected: index == _pageHome,
                  onTap: () => _goToPage(_pageHome),
                ),
                _BottomNavItem(
                  icon: hub.icon,
                  label: hub.label,
                  selected: index == _pageFitness,
                  onTap: () => _goToPage(_pageFitness),
                ),
                // The docked centre Log FAB sits over this slot; the caption
                // gives the centre action a visible text label like every other
                // nav destination, so it isn't the one unlabelled "+" (#256).
                // Wider than the 56 dp button: at 56 "Recording" cut to
                // "Recordi…" at the default text size.
                SizedBox(
                  width: _centreSlotWidth,
                  child: Builder(builder: (context) {
                    final look = _centreLook(l10n, docked: true);
                    return _CentreLogLabel(
                        label: look.label, alert: look.recording);
                  }),
                ),
                _BottomNavItem(
                  icon: Icons.public,
                  label: l10n.navSocial,
                  selected: index == _pageSocial,
                  onTap: () => _goToPage(_pageSocial),
                ),
                _BottomNavItem(
                  icon: Icons.person,
                  label: l10n.navYou,
                  selected: index == _pageYou,
                  onTap: () => _goToPage(_pageYou),
                ),
              ],
            ),
          );
        },
      ),
    ));
  }

  static const _railPages = [_pageHome, _pageFitness, _pageSocial, _pageYou];

  static const double _centreSlotWidth = 72;

  int? _railIndexFor(int pageIndex) {
    final i = _railPages.indexOf(pageIndex);
    return i == -1 ? null : i;
  }

  // The raised "+" is the Log action (multi_modal.md § Bottom nav) — the
  // docked centre FAB on phones, the NavigationRail leading button on
  // expanded layouts. FloatingActionButton has no long-press, so the
  // GestureDetector wrapper claims that gesture while the button keeps the
  // tap; the Semantics label makes the action explicit for screen readers,
  // and the 56 dp FAB clears the >=48 dp target. When [anchored], the
  // speed-dial fans from the button's own position instead of the
  // bottom-centre dock.
  //
  // Docked over the Run page mid-recording it is the recorder's Stop instead
  // (the panel leaves its own out, `RunStopDock`): the same 800 ms
  // `HoldToStopButton`, so one gate guards every way a run ends. It has no
  // long-press wrapper, which would fire at 500 ms into the hold.
  Widget _logFab({bool anchored = false}) {
    return ListenableBuilder(
      listenable: _navInputs,
      builder: (fabContext, _) {
        final l10n = AppLocalizations.of(fabContext);
        if (!anchored && _centreIsStop) {
          return HoldToStopButton(
            size: 56,
            iconSize: 28,
            showHint: false,
            semanticsHint: l10n.runHoldToStopRunA11yHint,
            onHoldComplete: runStopRequests.request,
          );
        }
        Offset? anchorOf() {
          if (!anchored) return null;
          final box = fabContext.findRenderObject() as RenderBox?;
          if (box == null || !box.hasSize) return null;
          return box.localToGlobal(box.size.center(Offset.zero));
        }

        final look = _centreLook(l10n);
        final scheme = Theme.of(fabContext).colorScheme;
        return GestureDetector(
          onLongPress: _onLogLongPress,
          child: Semantics(
            button: true,
            label: look.semantics,
            // The long-press is otherwise found only by holding the button.
            // TalkBack announces the hint ("double-tap and hold to show more
            // options"); VoiceOver has no long-press, so the menu is also a
            // custom action in its actions rotor. Mid-run both gestures
            // return to the run, so there is no menu to announce.
            onLongPress: look.recording ? null : _onLogLongPress,
            onLongPressHint: look.recording ? null : l10n.logMoreLongPressHint,
            customSemanticsActions: look.recording
                ? null
                : {
                    CustomSemanticsAction(label: l10n.logMoreTitle):
                        _onLogLongPress,
                  },
            // The tooltip is OURS and manually triggered, never the
            // FloatingActionButton's own: a `tooltip:` builds a Tooltip
            // INSIDE the button, whose long-press recognizer enters the
            // gesture arena ahead of this GestureDetector's and wins every
            // time — which left the long-press affordance dead on the phone
            // FAB. The visible caption under the button carries the label
            // anyway (#256), so nothing is lost by not showing it on hold.
            child: Tooltip(
              message: look.label,
              triggerMode: TooltipTriggerMode.manual,
              child: FloatingActionButton(
                backgroundColor: look.recording ? scheme.error : null,
                foregroundColor: look.recording ? scheme.onError : null,
                onPressed: () => _onLogTap(anchor: anchorOf()),
                child: Icon(look.icon),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// One destination in the [BottomAppBar] — icon over label, tinted when
/// selected. A real button for accessibility (role + selected state), with
/// a >=48 dp tap target.
/// How tall the bottom nav is, and whether its labels still fit, for a given
/// text scale.
///
/// The bar was a hard 64 dp holding a 24 dp icon, a 2 dp gap and a label, which
/// overflows by 12 px at `accessibility-extra-extra-extra-large` and clips the
/// labels to "Ho / Fit / L / So / You" on the way there. Both are failures of
/// the same assumption: that a fixed box can hold text whose size the runner
/// chooses.
///
/// So the bar grows with the scale, and past the point where a label can no
/// longer be read in the width a fifth of the screen affords, it drops the
/// label rather than showing two of its letters. The icon and the `Semantics`
/// label both stay, so the destination is still announced in full to a screen
/// reader and still recognisable to everyone else — which an ellipsised "Ho"
/// is not.
({double height, bool showLabels}) bottomNavMetrics(double textScale) {
  final scale = textScale.isFinite && textScale > 0 ? textScale : 1.0;
  if (scale > 1.6) return (height: 56.0, showLabels: false);
  return (height: (64.0 * scale).clamp(64.0, 96.0), showLabels: true);
}

class _BottomNavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _BottomNavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color =
        selected ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant;
    final metrics = bottomNavMetrics(MediaQuery.textScalerOf(context).scale(1));
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: metrics.height,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: color, size: 24),
                if (metrics.showLabels) ...[
                  const SizedBox(height: 2),
                  Flexible(
                    child: Text(
                      label,
                      style:
                          theme.textTheme.labelSmall?.copyWith(color: color),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The caption under the docked centre Log FAB. The FAB itself is the tap
/// target and occupies the icon slot; this renders the label at the same
/// baseline as the sibling nav labels so the centre action carries visible
/// text, not just a tooltip (#256). Marked [ExcludeSemantics] so the reader
/// doesn't double-announce over the FAB's own semantics label.
class _CentreLogLabel extends StatelessWidget {
  final String label;

  /// Tints the caption the error colour, matching the button above it while
  /// a run records.
  final bool alert;
  const _CentreLogLabel({required this.label, this.alert = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 64,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Transparent stand-in for the 24 dp icon the sibling nav items
          // render, so this label lines up with theirs while the floating
          // FAB visually fills the space above it.
          const SizedBox(height: 24),
          const SizedBox(height: 2),
          // Shrinks to fit rather than ellipsising: at a large text size a
          // smaller whole word reads, a clipped one does not.
          ExcludeSemantics(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: alert
                      ? theme.colorScheme.error
                      : theme.colorScheme.onSurfaceVariant,
                ),
                maxLines: 1,
                softWrap: false,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Lazy + keep-alive tab wrapper. Combines two roles:
///
///  1. `AutomaticKeepAliveClientMixin` — preserves the child's State once
///     it has been built (the page survives swiping off-screen, which is
///     the contract we used to get from `IndexedStack`).
///  2. Lazy construction — the child widget itself (and its heavy
///     `initState` chain: network loads, listener registrations) is only
///     instantiated on the first `build` call. PageView's lazy delegate
///     means tabs the user hasn't visited stay un-built, which keeps
///     cold-start work scoped to the initial page.
class _LazyKeepAliveTab extends StatefulWidget {
  final Widget Function() builder;

  /// Bump this whenever an upstream input the builder closes over
  /// has meaningfully changed and the tab must re-mount its child.
  /// Without this, the cache below kept the very first build of
  /// the child alive across the lifetime of the tab — which meant
  /// `_startRunWithRoute` could set `_preselectedRoute` + rebuild
  /// the pages list, but RunScreen never saw the new `initialRoute`
  /// (the cached instance from the FIRST build was returned again).
  /// User-visible symptom: tapping "Start run" on a route's detail
  /// FAB jumped to the Run tab but the route wasn't selected.
  final Object? rebuildKey;

  const _LazyKeepAliveTab({required this.builder, this.rebuildKey});

  @override
  State<_LazyKeepAliveTab> createState() => _LazyKeepAliveTabState();
}

class _LazyKeepAliveTabState extends State<_LazyKeepAliveTab>
    with AutomaticKeepAliveClientMixin {
  Widget? _child;

  @override
  bool get wantKeepAlive => true;

  @override
  void didUpdateWidget(covariant _LazyKeepAliveTab old) {
    super.didUpdateWidget(old);
    // Invalidate the cached child when the upstream rebuildKey
    // changes. The next `build` call below re-invokes the builder
    // (with the latest closed-over state). Tabs without a
    // rebuildKey keep the original "build once, keep alive
    // forever" semantics — only the tabs that need to react to
    // external state changes pay the rebuild cost.
    if (old.rebuildKey != widget.rebuildKey) {
      _child = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return _child ??= widget.builder();
  }
}
