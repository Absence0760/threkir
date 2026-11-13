import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:ui_kit/ui_kit.dart'
    show
        AppInsets,
        AppSemanticColors,
        AppSpace,
        ChartCardHeader,
        ListCard,
        PageHeader,
        ProgressBar,
        RootPage,
        SectionHeader,
        SkeletonBlock,
        StatGrid,
        StatTile;

import '../activity_type_labels.dart';
import '../backend_timeout.dart';
import '../social_service.dart';
import '../adaptive_fitness_flag.dart';
import '../adaptive_width.dart';
import '../fitness_surface_requests.dart';
import '../fab_clearance.dart' show DockedFabInset;
import '../ai_disclosure.dart' show AiDisclosureRecord;
import '../ai_disclosure_memo.dart';
import '../auth_change_aware.dart';
import '../current_week.dart' show WeekStart;
import '../device_timezone.dart';
import '../dashboard_layout.dart';
import '../plan_week.dart' show PlanRaceCountdownKind;
import '../goals.dart';
import '../l10n/gen/app_localizations.dart';
import '../local_food_store.dart';
import '../local_gym_store.dart';
import '../local_route_store.dart';
import '../local_run_store.dart';
import '../nutrition_targets.dart' show NutritionTargets;
import '../nutrition_totals.dart' show sumMacros;
import '../preferences.dart';
import '../pro_sellable.dart' show ProPerks, fetchProPerks;
import '../settings_sync.dart';
import '../streak_card.dart';
import '../streaks.dart';
import '../training_load_inputs.dart';
import '../training_service.dart';
import '../week_lead.dart';
import '../widgets/gym_summary_card.dart';
import '../widgets/pending_sync_banner.dart';
import '../widgets/nutrition_rings_card.dart';
import '../widgets/readiness_card.dart';
import '../widgets/rest_day_grisnir.dart';
import '../widgets/run_list_tile.dart';
import '../widgets/goal_editor_sheet.dart';
import '../widgets/todays_workout_card.dart';
import '../widgets/upcoming_event_card.dart';
import '../widgets/runner_menu.dart' show todaysOpenWorkout;
import '../widgets/plan_nudge_card.dart';
import '../plan_nudges.dart' show PlanNudge, PlanNudgeKind, workoutOverrunMetres;
import '../widgets/finish_plan_card.dart';
import '../widgets/plan_break_card.dart';
import '../widgets/missed_workout_prompt_card.dart';
import '../widgets/next_race_card.dart';
import '../widgets/up_next_plan_card.dart';
import '../widgets/plan_discovery_card.dart';
import '../widgets/top_banner.dart';
import '../recent_5k_suggestion.dart';
import 'add_run_screen.dart';
import 'coach_screen.dart';
import 'run_screen.dart' show runRecordingActive;
import 'gym_screen.dart';
import 'import_screen.dart';
import 'nutrition_screen.dart';
import 'plan_detail_screen.dart';
import 'plan_new_screen.dart';
import '../widgets/single_flight.dart';
import 'progress_screen.dart';
import 'run_detail_screen.dart';

const _kSectionGap = SizedBox(height: AppInsets.sectionGap);
/// The page gutter; the bottom adds the shell's docked centre button on top
/// of it (`_pagePadding`), so the last block scrolls clear of the Start.
const _kPagePadding = EdgeInsets.fromLTRB(
    AppInsets.gutter, 0, AppInsets.gutter, AppSpace.md);

/// Home, titled Today (issue #1374): what to do now and what was just done.
/// The Today hero (today's workout, readiness and the one Start), the next
/// race or club event, the last run and today's lift and meals, a goals strip,
/// one progress summary card that opens [ProgressScreen], and the Coach row.
/// Trends, PBs, the streak, the full goals and the recap live on that page.
class TodayScreen extends StatefulWidget {
  final ApiClient? apiClient;
  final TrainingService? training;
  final LocalRunStore runStore;
  final LocalRouteStore routeStore;
  final LocalGymStore gymStore;
  final LocalFoodStore foodStore;
  final Preferences preferences;
  final SettingsSyncService? settingsSync;

  /// Starts a run from the zero-runs welcome empty state, wired by the host
  /// (`home_screen`) to the same page jump the centre Log FAB performs
  /// (`_pageRun`). Null when there's no host able to reach the recorder, in
  /// which case the "Start a run" affordance is hidden rather than dead.
  final VoidCallback? onStartRun;

  /// Lands on the Fitness hub's Gym tab from the same welcome state — the
  /// shell's Log → Lift action. Null hides the hint rather than leaving it
  /// dead, as with [onStartRun].
  final VoidCallback? onLogLift;

  /// Starts the run with today's open plan workout armed, from the Start on
  /// Home's today's-workout card. The host wires it to the same start the
  /// centre button's long-press menu uses (`requestPlannedWorkoutStart`), so
  /// the recorder still runs its permission checks and the cancellable
  /// 3-2-1. Null leaves that card without a Start.
  final ValueChanged<PlanWorkoutRow>? onStartWorkout;

  /// Reads the runner's next club event for the Today block. Null (no social
  /// layer, as in most tests) leaves the card off.
  final SocialService? social;

  /// Pushes the unsynced runs now, from the pending-sync banner's Retry. The
  /// host wires it to `SyncService` — the one run drain — rather than this
  /// screen pushing runs itself. Null leaves runs counted but not retried.
  final Future<void> Function()? onSyncRuns;

  /// Reads whether the Coach is live on this deploy. Defaults to
  /// [fetchProPerks], the manifest the Messages inbox's Coach row reads.
  final Future<ProPerks> Function()? loadPerks;

  const TodayScreen({
    super.key,
    this.apiClient,
    this.training,
    required this.runStore,
    required this.routeStore,
    required this.gymStore,
    required this.foodStore,
    required this.preferences,
    this.settingsSync,
    this.onStartRun,
    this.onLogLift,
    this.onStartWorkout,
    this.social,
    this.onSyncRuns,
    this.loadPerks,
  });

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

enum _HomeMenuAction { addRun, importRuns }

/// What the SERVER says about this account's history — the one thing the
/// runless welcome state is a claim about and local disk cannot answer. A
/// fresh install hydrates an empty store before the first frame, so a
/// disk-only gate told the owner of 500 synced runs they had never run
/// (issue #921).
enum _AccountHistory { unknown, none, some }

class _HomeBreak {
  final List<DateTime>? runStarts;
  final PlanBreakState state;

  const _HomeBreak(this.runStarts, this.state);

  static const none = _HomeBreak(null, PlanBreakState.none);
}

class _TodayScreenState extends State<TodayScreen>
    with AuthChangeAware<TodayScreen>, WidgetsBindingObserver {
  /// Opening the last run reads it first; a second tap in that read would
  /// open a second detail (issue #1374 NS-11).
  final _open = SingleFlight();

  _AccountHistory _history = _AccountHistory.unknown;

  /// This build's break state (`_homeBreak`), read by every plan card.
  _HomeBreak _breakNow = _HomeBreak.none;

  /// Whether the last hydrate reached the server. Feeds the pending-sync
  /// banner's retry affordance, nothing else.
  bool _isOnline = true;

  /// Active training plan + today's workout, used to render the
  /// `TodaysWorkoutCard` at the top of the dashboard. Null when
  /// there's no active plan, no scheduled workout today, or the
  /// service hasn't returned yet. Lazy fetch on mount; refetched
  /// when the TrainingService notifies (e.g. user marks a workout
  /// done, switches plans).
  ActivePlanOverview? _planOverview;

  /// The runner's paused plan, read only when there is no active one.
  TrainingPlanRow? _pausedPlan;

  /// Set once the plan reads have answered "no active plan and no paused
  /// one". A failed read leaves it false, so Home never offers to start a
  /// plan the runner may already have.
  bool _noPlan = false;

  /// This visit's "Not now" on the recent-5K suggestion, ahead of the
  /// settings bag catching up.
  String? _recent5kDismissedLocal;

  /// Daily nutrition targets, resolved once on mount, so the Home nutrition
  /// rings can show fill vs target. Null until resolved / when body metrics
  /// are absent (the rings then render unfilled — anti-clutter).
  NutritionTargets? _nutritionTargets;

  /// The next club event the runner is going to, inside [kHomeEventWindow].
  EventView? _upcomingEvent;

  /// Whether the Coach is live on this deploy. False until the manifest says
  /// so, so an unknown or unreachable manifest hides the coach card, as it
  /// hides the Messages inbox's Coach row (decisions § 2227).
  bool _coachLive = false;

  /// All-time streaks from the `run_streaks_for_user` aggregate — the same
  /// server row web's card reads, so a fresh install of a deep-history
  /// account doesn't present the store's resident sliver as the all-time
  /// truth (decisions § 471 / § 475). Null until resolved / offline /
  /// signed out; the card then suppresses its all-time claim rather than
  /// dressing the local figure up as one (`streak_card.dart`).
  RunStreaks? _allTimeStreaks;

  @override
  void initState() {
    super.initState();
    widget.runStore.addListener(_onRunStoreChanged);
    widget.preferences.addListener(_onChange);
    widget.gymStore.addListener(_onChange);
    widget.foodStore.addListener(_onChange);
    // The bag drives the disclosure level, so a change made in Settings must
    // reach this keep-alive page without a remount.
    widget.settingsSync?.addListener(_onSettingsChange);
    widget.training?.addListener(_refreshPlanOverview);
    runRecordingActive.addListener(_onChange);
    WidgetsBinding.instance.addObserver(this);
    _refreshPlanOverview();
    _hydrateModalities();
    _loadUpcomingEvent();
    _loadViewerProfile();
    _loadRunStreaks();
    _loadCoachLive();
  }

  Future<void> _loadCoachLive() async {
    var live = false;
    try {
      live = (await (widget.loadPerks ?? fetchProPerks)()).coach;
    } catch (e) {
      debugPrint('dashboard: capability lookup failed: $e');
    }
    if (mounted && live != _coachLive) setState(() => _coachLive = live);
  }

  /// Grisnir on a rest day: the universal `show_mascot`, on unless it is
  /// literally `false`, as web reads it.
  bool get _showMascot =>
      widget.settingsSync?.service?.effective<Object>(SettingsKeys.showMascot) !=
      false;

  @override
  ApiClient? get authApi => widget.apiClient;

  /// Every loader this screen owns, in parallel. Home is page 0 of a
  /// never-torn-down keep-alive `PageView`, so before this its five loaders
  /// ran once at mount and never again: `SyncService` kept the runs list
  /// moving on resume while the PBs, the streak, the plan and the meals sat
  /// at whatever they were when the app first opened (issue #921).
  Future<void> _refreshAll() async {
    try {
      await Future.wait([
        _refreshPlanOverview(),
        _hydrateModalities(),
        _loadUpcomingEvent(),
        _loadViewerProfile(),
        _loadRunStreaks(),
      ]);
    } catch (e) {
      // Each loader already degrades on its own; this only stops one of them
      // failing the pull-to-refresh gesture for the other four.
      debugPrint('dashboard refresh failed: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshAll();
  }

  /// The dashboard is page 0 of the never-torn-down keep-alive PageView,
  /// so its initState-fetched per-user caches outlive the session that
  /// fetched them. Drop them the moment the user changes (sign-out clears,
  /// account switch clears + refetches as the new user — the loaders
  /// no-op / come back empty while signed out).
  @override
  void onAuthUserChanged(String? userId) {
    setState(() {
      _planOverview = null;
      _nutritionTargets = null;
      _upcomingEvent = null;
      _allTimeStreaks = null;
      _history = _AccountHistory.unknown;
    });
    _refreshPlanOverview();
    _hydrateModalities();
    _loadUpcomingEvent();
    _loadViewerProfile();
    _loadRunStreaks();
  }

  /// The runner's next `going` club event within [kHomeEventWindow], for the
  /// Today block (decisions § 2285). L4: a failed read leaves the card off and
  /// the rest of Home as it was.
  Future<void> _loadUpcomingEvent() async {
    final social = widget.social;
    if (social == null) return;
    try {
      final evt = await social
          .fetchNextRsvpedEvent(window: kHomeEventWindow)
          .timeout(kBackendLoadTimeout);
      if (mounted) setState(() => _upcomingEvent = evt);
    } catch (e) {
      debugPrint('dashboard: upcoming event fetch failed: $e');
    }
  }

  /// Best-effort read of the viewer's profile for its AI-consent record, so
  /// "Ask your coach" opens straight into the chat (L4 — a failure just
  /// leaves the consent step in front of it). The PB age grades that also
  /// read this row moved to the Progress page with the PBs.
  Future<void> _loadViewerProfile() async {
    final api = widget.apiClient;
    if (api == null) return;
    try {
      final p = await api.fetchMyProfile();
      // The same row carries the AI-consent record, so remembering it here
      // lets "Ask your coach" open straight into the chat.
      final uid = api.userId;
      if (p != null && uid != null) {
        AiDisclosureMemo.remember(
          uid,
          AiDisclosureRecord(
            version: p.aiDisclosureVersion,
            acceptedAt: p.coachConsentAt?.toUtc().toIso8601String(),
          ),
        );
      }
    } catch (e) {
      debugPrint('dashboard: profile fetch failed: $e');
    }
  }

  /// Best-effort load of the server all-time streak aggregate (L4 — a
  /// failure just leaves the claim-suppressed local fallback in place,
  /// never a resident-window number dressed up as all-time). Signed-out
  /// must not call the SECURITY INVOKER RPC at all. The device's IANA
  /// zone rides along so the server buckets days exactly like the local
  /// `computeRunStreaks` (`fetchRunStreaks` never throws; null keeps the
  /// previous answer, which at mount is the suppressing null).
  Future<void> _loadRunStreaks() async {
    final api = widget.apiClient;
    if (api == null || api.userId == null) return;
    final tz = await deviceIanaTimeZone();
    final row = await api.fetchRunStreaks(tz: tz);
    if (row == null || !mounted) return;
    setState(() =>
        _allTimeStreaks = RunStreaks(current: row.current, best: row.best));
  }

  @override
  void dispose() {
    widget.runStore.removeListener(_onRunStoreChanged);
    widget.preferences.removeListener(_onChange);
    widget.gymStore.removeListener(_onChange);
    widget.foodStore.removeListener(_onChange);
    widget.settingsSync?.removeListener(_onSettingsChange);
    widget.training?.removeListener(_refreshPlanOverview);
    runRecordingActive.removeListener(_onChange);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _onRunStoreChanged() {
    if (mounted) setState(() {});
  }

  /// Best-effort hydrate of the gym + food caches (so today's logged
  /// modalities surface on Home even on a fresh launch, before the user
  /// visits the Gym / Nutrition screens) plus the nutrition target. Each
  /// hop is wrapped independently (layered resilience): a gym fetch failure
  /// must not block the food fetch, and neither can break the dashboard.
  Future<void> _hydrateModalities() async {
    final api = widget.apiClient;
    if (api == null || api.userId == null) {
      // Signed out, the local disk IS the whole truth about this device.
      if (mounted) setState(() => _history = _AccountHistory.none);
      return;
    }
    var hasHistory = false;
    var online = true;
    try {
      final fresh = await api.fetchGymWorkoutsWithSets(limit: 100);
      await widget.gymStore.replaceFromServer(fresh, fetchLimit: 100);
      hasHistory = hasHistory || fresh.isNotEmpty;
    } catch (e) {
      debugPrint('dashboard gym hydrate failed: $e');
      online = false;
    }
    try {
      // One row is the whole question: has this account ever recorded a run?
      // The runs themselves are SyncService's job, not this screen's.
      hasHistory = hasHistory || (await api.getRuns(limit: 1)).isNotEmpty;
    } catch (e) {
      debugPrint('dashboard run probe failed: $e');
      online = false;
    }
    // Answered as early as it can be: the two hops above are the whole
    // question, and the food + target hops below would otherwise hold the
    // welcome state behind two calls that cannot change the answer.
    if (mounted) {
      setState(() {
        _isOnline = online;
        // Offline with an empty disk resolves to `none` rather than staying
        // unknown: there is nothing to show either way, and the welcome
        // state's own actions (record, import) are the only useful thing
        // left — a permanent loader would not be more honest, just less
        // usable.
        _history = hasHistory ? _AccountHistory.some : _AccountHistory.none;
      });
    }
    try {
      final now = DateTime.now();
      final weekStart = DateTime(now.year, now.month, now.day - 6);
      final tomorrow = DateTime(now.year, now.month, now.day + 1);
      final fresh = await api.fetchFoodLog(from: weekStart, to: tomorrow);
      await widget.foodStore.replaceFromServer(
        [for (final r in fresh) r.toJson()],
        windowStart: weekStart,
        windowEnd: tomorrow,
      );
    } catch (e) {
      debugPrint('dashboard food hydrate failed: $e');
    }
    try {
      final t = await loadNutritionTargets(api, widget.settingsSync?.service);
      if (mounted) setState(() => _nutritionTargets = t);
    } catch (e) {
      debugPrint('dashboard nutrition targets failed: $e');
    }
  }

  bool get _gymShown => widget.preferences
      .gymShown(hasData: widget.gymStore.workouts.isNotEmpty);

  bool get _nutritionShown => widget.preferences
      .nutritionShown(hasData: widget.foodStore.rows.isNotEmpty);

  /// Today's most-recent gym workout, or null when none was logged today.
  StoredGymWorkout? get _todaysLift {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    for (final w in widget.gymStore.workouts) {
      final at = w.startedAt?.toLocal();
      if (at != null && !at.isBefore(start)) return w;
    }
    return null;
  }

  /// Today's logged food entries (for the nutrition rings), oldest first.
  List<FoodEntry> get _todaysFood {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final end = DateTime(now.year, now.month, now.day + 1);
    return [
      for (final r in widget.foodStore.entriesForRange(start, end))
        FoodEntry.fromRow(r),
    ];
  }

  /// The Fitness hub's own Gym tab, not a second copy pushed over Home
  /// (decisions § 1654, § 2437, issue #1374): a diary day or a half-typed
  /// entry left in the hub is still there.
  Future<void> _openGym() => openFitnessSurface(
        context,
        FitnessTab.gym,
        fallback: () =>
            GymScreen(api: widget.apiClient, store: widget.gymStore),
      );

  /// The newest run on this device, or null when there is none.
  static Run? _latestRun(List<Run> runs) {
    Run? latest;
    for (final r in runs) {
      if (latest == null || r.startedAt.isAfter(latest.startedAt)) latest = r;
    }
    return latest;
  }

  /// "How did that go, and did it save?" is the first question after a run,
  /// and answering it took Fitness, then Runs, then the row. The row here is
  /// the Runs list's own, unsynced and parked markers included.
  Widget _latestRunSection(Run run, DistanceUnit unit) {
    final l10n = AppLocalizations.of(context);
    return Column(
      key: const Key('dashboardLatestRun'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // One row, so it names itself; _SectionHeader is kept for groups.
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
          child: ChartCardHeader(title: l10n.runLastRun),
        ),
        RunListTile.owned(
          run: run,
          unit: unit,
          api: widget.apiClient,
          isUnsynced: widget.runStore.unsyncedRuns.any((r) => r.id == run.id),
          isBlocked: widget.runStore.blockedRuns.containsKey(run.id),
          onTap: () => _openRun(run),
        ),
      ],
    );
  }

  Future<void> _openRun(Run run) =>
      _open.openOnce(() async {
        // The dashboard reads track-less summaries; detail needs the full run.
        final full = await widget.runStore.runById(run.id) ?? run;
        if (!mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) => RunDetailScreen(
              run: full,
              runStore: widget.runStore,
              routeStore: widget.routeStore,
              preferences: widget.preferences,
              apiClient: widget.apiClient,
              settingsSync: widget.settingsSync,
            ),
          ),
        );
      });

  /// The hub's Nutrition tab, for the same reason as [_openGym].
  Future<void> _openNutrition() => openFitnessSurface(
        context,
        FitnessTab.nutrition,
        fallback: () => NutritionScreen(
          api: widget.apiClient,
          store: widget.foodStore,
          settingsSync: widget.settingsSync,
        ),
      );

  void _onChange() {
    if (mounted) setState(() {});
  }

  /// The bag moved (Settings, another device), so the cards that read it
  /// (the mascot, HR prefs, week start) redraw.
  void _onSettingsChange() => _onChange();

  Future<void> _refreshPlanOverview() async {
    final svc = widget.training;
    if (svc == null) return;
    try {
      final overview = await svc.fetchActiveOverview();
      if (mounted) {
        setState(() {
          _planOverview = overview;
          if (overview != null) _noPlan = false;
        });
      }
      if (overview != null) {
        if (mounted && _pausedPlan != null) setState(() => _pausedPlan = null);
        return;
      }
      // Its own catch: a failed paused-plan read costs the card and nothing
      // else, and must not read as a failed overview.
      try {
        final paused = await svc.fetchPausedPlan();
        if (mounted) {
          setState(() {
            _pausedPlan = paused;
            _noPlan = paused == null;
          });
        }
      } catch (e) {
        if (mounted) setState(() => _noPlan = false);
        debugPrint('dashboard paused-plan fetch failed: $e');
      }
    } catch (e) {
      if (mounted) setState(() => _noPlan = false);
      // Non-critical — same logging stance as run_screen's overview
      // fetch. The card simply doesn't render; the rest of the
      // dashboard keeps working.
      debugPrint('dashboard plan-overview fetch failed: $e');
    }
  }

  void _openImport() {
    // From the welcome empty state and Home's overflow. Routes into the existing
    // ImportScreen which handles Strava ZIP / Health Connect /
    // GPX-folder paths. The user might not be signed in (apiClient
    // null) — ImportScreen handles that internally by greying out
    // the cloud-push tile and still allowing local import.
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ImportScreen(
          apiClient: widget.apiClient,
          runStore: widget.runStore,
          routeStore: widget.routeStore,
          preferences: widget.preferences,
          settingsSync: widget.settingsSync,
        ),
      ),
    );
  }

  void _openAddRun() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => AddRunScreen(
          runStore: widget.runStore,
          routeStore: widget.routeStore,
          preferences: widget.preferences,
          apiClient: widget.apiClient,
          social: widget.social,
        ),
      ),
    );
  }

  /// The shown plan's dates have run out but the runner has not filed it.
  bool _planFinished(DateTime now) {
    final p = _planOverview;
    return p != null &&
        FinishPlanCard.shows(
            status: p.plan.status, endDate: p.plan.endDate, now: now);
  }

  /// The shown plan's race-day countdown (or "starts in" before it begins),
  /// or the Finish plan card once its dates have run out, with the plan
  /// queued after it beneath. Null with neither: no active plan, or a race
  /// day passed with nothing queued.
  /// A paused plan stays on Home with a way back to it: the card opens the
  /// plan with the resume confirm up, where the paused weeks move back.
  Widget? _pausedPlanCard() {
    final paused = _pausedPlan;
    final svc = widget.training;
    if (paused == null || svc == null) return null;
    final l10n = AppLocalizations.of(context);
    Future<void> open() async {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PlanDetailScreen(
            training: svc,
            planId: paused.id,
            openResume: true,
          ),
        ),
      );
      _refreshPlanOverview();
    }

    final theme = Theme.of(context);
    // The action is a button under the text, not plain text in a ListTile's
    // trailing slot: "Reprendre le plan" at 2x took about 200 dp of the row
    // there and squeezed the plan's name to a word per line, and as plain
    // text it did not read as something to tap (#1374 TO-11).
    return ListCard(
      key: const Key('dashboardPausedPlan'),
      dense: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.pause_circle_outline,
                  color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(paused.name, style: theme.textTheme.titleMedium),
                    Text(
                      l10n.dashboardPlanPausedBody,
                      style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton(
              key: const Key('dashboardPausedPlanResume'),
              onPressed: open,
              child: Text(l10n.planDetailResumePlan),
            ),
          ),
        ],
      ),
    );
  }

  /// Whether Home may offer to start a plan: signed in, with the plan reads
  /// answered "none".
  bool get _offersPlanEntry =>
      _noPlan &&
      _planOverview == null &&
      _pausedPlan == null &&
      widget.training != null &&
      widget.apiClient?.userId != null;

  Future<void> _openPlanNew({int? recent5kSec}) async {
    final svc = widget.training;
    if (svc == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            PlanNewScreen(training: svc, initialRecent5kSec: recent5kSec),
      ),
    );
    _refreshPlanOverview();
  }

  /// The recent measured 5K to seed a plan from, or null. Null too while the
  /// settings bag is unread: an unknown answer must not re-show a suggestion
  /// the runner dismissed on another device. Reads the resident runs, not the
  /// summaries Home charts from: a summary carries no `fastest_5k_s`, and the
  /// newest 200 runs reach back past the eight-week window for anyone running
  /// fewer than three times a day.
  Recent5kSuggestion? _recent5kSuggestion(DateTime now) {
    final runs = widget.runStore.runs;
    final service = widget.settingsSync?.service;
    if (service == null) return null;
    try {
      final stored =
          service.effective<Object>(SettingsKeys.planSuggestionDismissedAt);
      return pickRecent5k(
        [
          for (final r in runs)
            Recent5kCandidate(
              id: r.id,
              startedAt: r.startedAt.toUtc().toIso8601String(),
              fastest5kS: switch (r.metadata?[MetadataKeys.fastest5kS]) {
                final num s => s,
                _ => null,
              },
              activityType: switch (r.metadata?[MetadataKeys.activityType]) {
                final String a => a,
                _ => null,
              },
              isDnf: switch (r.metadata?[MetadataKeys.isDnf]) {
                final bool d => d,
                _ => null,
              },
            ),
        ],
        now.millisecondsSinceEpoch,
        _recent5kDismissedLocal ?? (stored is String ? stored : null),
      );
    } catch (e) {
      debugPrint('dashboard recent-5K suggestion failed: $e');
      return null;
    }
  }

  Future<void> _dismissRecent5k() async {
    final stamp = DateTime.now().toUtc().toIso8601String();
    setState(() => _recent5kDismissedLocal = stamp);
    try {
      await widget.settingsSync?.updateUniversal(
          {SettingsKeys.planSuggestionDismissedAt: stamp});
    } catch (e) {
      debugPrint('dashboard recent-5K dismissal not saved: $e');
      if (!mounted) return;
      showTopBanner(
          context, AppLocalizations.of(context).dashboardRecent5kDismissFailed);
    }
  }

  /// The plan slot for a runner with no plan: the recent-5K suggestion when
  /// there is one, else "Train for something".
  Widget? _planDiscoveryCard(DateTime now) {
    if (!_offersPlanEntry) return null;
    final suggestion = _recent5kSuggestion(now);
    if (suggestion != null) {
      return Recent5kPlanCard(
        key: const Key('dashboardRecent5k'),
        suggestion: suggestion,
        onBuild: () => _openPlanNew(recent5kSec: suggestion.seconds),
        onDismiss: _dismissRecent5k,
      );
    }
    return TrainForSomethingCard(
      key: const Key('dashboardTrainForSomething'),
      onTap: _openPlanNew,
    );
  }

  Widget? _nextRaceCard(DateTime now) {
    final p = _planOverview;
    if (p == null) return _pausedPlanCard();
    final training = widget.training;
    final Widget? race;
    if (_planFinished(now) && training != null) {
      race = FinishPlanCard(
        key: const Key('dashboardFinishPlan'),
        training: training,
        planId: p.plan.id,
        planName: p.plan.name,
        endDate: p.plan.endDate,
        onFinished: _refreshPlanOverview,
      );
    } else if (NextRaceCard.shows(p, now)) {
      race = NextRaceCard(
        key: const Key('dashboardNextRace'),
        overview: p,
        now: now,
        onTap: _openTodayWorkout,
      );
    } else {
      race = null;
    }
    final upNext = UpNextPlanCard.shows(p)
        ? UpNextPlanCard(
            key: const Key('dashboardUpNextPlan'),
            overview: p,
            now: now,
            onTap: () => _openPlan(p.upcomingPlan!.id),
          )
        : null;
    final brk = _planBreakCard(p, now, _breakNow);
    final parts = [?brk, ?race, ?upNext];
    if (parts.length < 2) return parts.firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < parts.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          parts[i],
        ],
      ],
    );
  }

  /// A break of a week or more in the shown plan (decisions § 2128). The
  /// card hides itself when there is none; the local store holds every run,
  /// unsynced ones included, so a run recorded offline still ends a break.
  Widget? _planBreakCard(
      ActivePlanOverview p, DateTime now, _HomeBreak home) {
    final training = widget.training;
    if (training == null || !home.state.showing) return null;
    return PlanBreakCard(
      key: const Key('dashboardPlanBreak'),
      training: training,
      plan: p.plan,
      weeks: p.weeks,
      workouts: p.workouts,
      runStarts: home.runStarts,
      now: now,
      onApplied: _refreshPlanOverview,
      onAnswered: () {
        if (mounted) setState(() {});
      },
    );
  }

  /// The break state for Home's plan, worked out once per build: the offer
  /// outranks the missed-workout prompt and the plan nudge. The runs are
  /// known once the store holds one, or the account has none at all; a cold
  /// store on an account that has run shows no offer rather than call that
  /// runner on a break.
  _HomeBreak _homeBreak(List<Run> runs, DateTime now) {
    final p = _planOverview;
    if (p == null || p.plan.status != 'active') return _HomeBreak.none;
    final runStarts = runs.isNotEmpty || _history == _AccountHistory.none
        ? [for (final r in runs) r.startedAt]
        : null;
    return _HomeBreak(
      runStarts,
      PlanBreakCard.stateFor(
        plan: p.plan,
        weeks: p.weeks,
        workouts: p.workouts,
        runStarts: runStarts,
        now: now,
      ),
    );
  }

  /// The Coach row that closes Home's Today block, shown whenever there is a
  /// training service to open the Coach screen with (issue #1374): that
  /// screen also holds Guided runs and Athletes & coaches, which have no
  /// other entry point. Only a live AI coach, for a signed-in runner, is
  /// offered as "Ask your coach"; otherwise the row names what the screen
  /// still holds, so it never promises a chat this deploy does not run
  /// (decisions § 2227).
  Widget? _coachEntry() {
    final api = widget.apiClient;
    final training = widget.training;
    if (api == null || training == null) return null;
    final l10n = AppLocalizations.of(context);
    final asks = _coachLive && api.userId != null;
    return _CoachEntryCard(
      title: asks ? l10n.homeAskCoach : l10n.homeCoachTitle,
      // Its placement is the Coach-prominence decision; its copy is not. A
      // runner with Gym and Nutrition hidden was promised advice on two
      // things they had just been told are hidden.
      subtitle: !asks
          ? l10n.homeCoachSubtitleTools
          : _gymShown || _nutritionShown
              ? l10n.homeAskCoachSubtitle
              : l10n.homeAskCoachSubtitleRunOnly,
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => CoachScreen(api: api, training: training),
        ),
      ),
    );
  }

  void _openPlan(String planId) {
    final svc = widget.training;
    if (svc == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlanDetailScreen(training: svc, planId: planId),
      ),
    );
  }

  /// Asks once about the plan's most recent missed workout (decisions
  /// § 2122). Only for an active plan that has not run out of dates; the
  /// overview is always the runner's own.
  Widget? _missedPromptCard(DateTime now) {
    final p = _planOverview;
    final svc = widget.training;
    if (p == null || svc == null || _breakNow.state.showing) return null;
    if (p.plan.status != 'active' || p.plan.isTemplate || _planFinished(now)) {
      return null;
    }
    final prompt = MissedWorkoutPromptCard.promptFor(
        weeks: p.weeks, workouts: p.workouts, now: now);
    if (prompt == null) return null;
    return MissedWorkoutPromptCard(
      key: ValueKey('dashboardMissedPrompt-${prompt.workoutId}'),
      training: svc,
      planId: p.plan.id,
      prompt: prompt,
      onMakeUp: () async {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => PlanDetailScreen(
              training: svc,
              planId: p.plan.id,
              openMakeUp: true,
            ),
          ),
        );
        _refreshPlanOverview();
      },
      onAnswered: _refreshPlanOverview,
    );
  }

  /// How far today's done workout ran past its target, when the linked run
  /// is on this device (`workoutOverrunMetres`).
  double? _todayOverrun(List<Run> runs) {
    final t = _planOverview?.todayWorkout;
    final runId = t?.completedRunId;
    if (t == null || runId == null) return null;
    for (final r in runs) {
      if (r.id == runId) {
        return workoutOverrunMetres(t.targetDistanceM, r.distanceMetres, t.kind);
      }
    }
    return null;
  }

  /// Home's plan card (`planNudge`): null when there is nothing to say, the
  /// plan's dates have run out, or there is no service to open the plan with.
  ///
  /// [hidden] is the one switch a card that outranks this one flips.
  Widget? _planNudgeCard(List<Run> runs, DateTime now, {bool hidden = false}) {
    final p = _planOverview;
    final svc = widget.training;
    if (hidden || p == null || svc == null || _planFinished(now)) return null;
    if (_breakNow.state.showing) return null;
    final window = _breakNow.state.window;
    final anchorVolume = adaptiveFitnessGate;
    final nudge = PlanNudgeCard.nudgeFor(
      overview: p,
      runs: runs,
      dismissed: PlanNudgeCard.dismissedIn(widget.settingsSync),
      now: now,
      breakWindow: window,
      anchorVolume: anchorVolume,
    );
    if (nudge == null) return null;
    return PlanNudgeCard(
      key: ValueKey('planNudge:${nudge.key}'),
      overview: p,
      runs: runs,
      settingsSync: widget.settingsSync,
      now: now,
      breakWindow: window,
      anchorVolume: anchorVolume,
      onReview: (n) => _reviewPlanNudge(svc, p.plan.id, n),
    );
  }

  Future<void> _reviewPlanNudge(
      TrainingService svc, String planId, PlanNudge n) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlanDetailScreen(
          training: svc,
          planId: planId,
          runStore: widget.runStore,
          openReview: n.kind == PlanNudgeKind.adaptiveUnder
              ? PlanReview.adaptive
              : PlanReview.replan,
        ),
      ),
    );
    _refreshPlanOverview();
  }

  void _openTodayWorkout() {
    final svc = widget.training;
    final p = _planOverview;
    if (svc == null || p == null) return;
    // The card's body is the overview: a tap routes into plan_detail so the
    // runner can see the full week + drill into the workout. Starting it is
    // the card's own Start button (decisions § 2282).
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlanDetailScreen(
          training: svc,
          planId: p.plan.id,
        ),
      ),
    );
  }

  /// audit/accessibility — WCAG 4.1.3 (Status Messages). The goal grid
  /// updates via `setState` without moving focus, so a TalkBack user
  /// gets no feedback that a goal was created / removed.
  /// `SemanticsService.announce` pushes a one-shot live-region message
  /// (mirrors `run_screen._announceA11yState`). Best-effort.
  void _announceA11yState(String message) {
    try {
      SemanticsService.announce(message, TextDirection.ltr);
    } catch (e) {
      debugPrint('SemanticsService.announce failed: $e');
    }
  }

  Future<void> _newGoal() async {
    final msg = await showGoalEditorSheet(
      context,
      preferences: widget.preferences,
      settingsSync: widget.settingsSync,
    );
    if (msg != null) _announceA11yState(msg);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final unit = widget.preferences.unit;
    // Stats + cards read the full-history index (track-less). Only the offline
    // PB fallback below needs GPS tracks, and it scans the resident window
    // (runStore.runs) directly.
    final runs = widget.runStore.summaryRuns;
    final goals = widget.preferences.goals;

    final now = DateTime.now();
    _breakNow = _homeBreak(runs, now);
    // The readiness line in the hero reads the same series the Progress
    // page's load card does (`training_load_inputs.dart`, decisions § 109).
    final loadSeries = trainingLoadSeriesFor(runs, now,
        gymStore: widget.gymStore, settingsSync: widget.settingsSync);
    final hrPrefs = hrPrefsOf(widget.settingsSync);
    final pagePadding = _kPagePadding.copyWith(
        bottom: _kPagePadding.bottom + DockedFabInset.of(context));

    final api = widget.apiClient;

    // The root page's actions: the overflow only (issue #1374). The Feed,
    // bell and Profile glyphs duplicated the Social and You tabs a thumb
    // away, and the notifications and messages they reached live in Social's
    // top bar now. They sit in the RootPage bar, so they stay reachable once
    // the title has scrolled away.
    final actions = <Widget>[
      // Logging a run after the fact and importing history are occasional
      // jobs, so they sit in the overflow rather than on the week lead, where
      // they took the lead's whole bottom row on every visit (decisions
      // § 2281). Neither needs a session: both work offline and signed out.
      PopupMenuButton<_HomeMenuAction>(
        key: const Key('dashboardMoreMenu'),
        tooltip: l10n.commonMore,
        icon: const Icon(Icons.more_vert),
        onSelected: (a) => switch (a) {
          _HomeMenuAction.addRun => _openAddRun(),
          _HomeMenuAction.importRuns => _openImport(),
        },
        itemBuilder: (_) => [
          PopupMenuItem(
            key: const Key('dashboardMenuAddRun'),
            value: _HomeMenuAction.addRun,
            child: Text(l10n.dashboardLeadAddRun),
          ),
          PopupMenuItem(
            key: const Key('dashboardMenuImport'),
            value: _HomeMenuAction.importRuns,
            child: Text(l10n.dashboardImportRuns),
          ),
        ],
      ),
    ];
    // Home opened on four glyphs and no title at all — nothing on the screen
    // said which surface it was, and the bottom-nav label is 700 dp away at
    // the other end of the phone. The heading sits inside the page's own
    // gutter, so the title starts where the cards do (it used to add 16 of
    // its own and start at 32).
    final actionToolbar = PageHeader(
      title: l10n.todayTitle,
      padding: const EdgeInsets.only(top: AppSpace.sm),
    );

    // Active-plan hero + the goals block: both outlive the welcome state,
    // because onboarding can mint a plan and a goal before the first run
    // exists and neither is a derived metric.
    // Home's primary action (decisions § 2282, § 2385): one Start, on today's
    // workout when there is an open one to follow, else on the Today hero.
    // None while a run records, since the centre button is then the way back
    // to it and a second "Start" would misstate what a tap does.
    final recording = runRecordingActive.value;
    final openWorkout = recording || widget.onStartWorkout == null
        ? null
        : todaysOpenWorkout(_planOverview?.workouts ?? const [], now);
    final todayWorkout = _planOverview?.todayWorkout;
    final startsTodayWorkout =
        openWorkout != null && openWorkout.id == todayWorkout?.id;
    final todayCard = todayWorkout != null
        ? TodaysWorkoutCard(
            workout: todayWorkout,
            onTap: _openTodayWorkout,
            onStart: startsTodayWorkout
                ? () => widget.onStartWorkout!(openWorkout)
                : null,
            overrunMetres: _todayOverrun(runs),
          )
        : null;
    final heroStart =
        recording || startsTodayWorkout ? null : widget.onStartRun;
    final missedPrompt = _missedPromptCard(now);
    final nudgeCard = _planNudgeCard(runs, now);
    final heroCards = [
      if (missedPrompt != null) missedPrompt,
      if (todayCard != null) todayCard,
      if (nudgeCard != null) nudgeCard,
    ];
    final Widget? heroWorkoutCard = heroCards.isEmpty
        ? null
        : heroCards.length == 1
            ? heroCards.single
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < heroCards.length; i++) ...[
                    if (i > 0) const SizedBox(height: 8),
                    heroCards[i],
                  ],
                ],
              );
    final pendingBanner = PendingSyncBanner(
      api: api,
      isOnline: _isOnline,
      stores: [widget.gymStore, widget.foodStore],
      runStore: widget.runStore,
      onRetryRuns: widget.onSyncRuns,
    );

    // Web's `isNewAccount`: no runs all-time AND no gym sessions. A goal is
    // deliberately not in it — the welcome copy offers "set a goal" as one of
    // its own three actions, and the old `runs.isEmpty && goals.isEmpty` gate
    // had accepting that offer replace the welcome with three zeroed period
    // cards, a 0-day streak and an empty load chart.
    // A lifter with 50 sessions and no runs got the same screen telling them
    // to record a run (issue #921).
    final hasLocalHistory =
        runs.isNotEmpty || widget.gymStore.workouts.isNotEmpty;

    final Widget content;
    if (!hasLocalHistory && _history != _AccountHistory.none) {
      // Either the server has not answered yet or it says there IS history
      // that this device's disk has not received. Neither is a runless
      // account, so neither may be told it has never run.
      content = ListView(
        // Shorter than the viewport, so without this the pull-to-refresh
        // gesture has no overscroll to report and silently does nothing.
        physics: const AlwaysScrollableScrollPhysics(),
        padding: pagePadding,
        children: [
          actionToolbar,
          pendingBanner,
          const SizedBox(height: 8),
          SkeletonBlock(height: 120, label: l10n.commonLoading),
          const SizedBox(height: 12),
          const SkeletonBlock(height: 96),
          const SizedBox(height: 12),
          const SkeletonBlock(height: 180),
        ],
      );
    } else if (!hasLocalHistory) {
      // A plan that has not started yet has no workout today, but its
      // "Starts in N days" card still sits above the welcome block.
      final raceCard = _nextRaceCard(now);
      content = CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppInsets.gutter),
                  child: Column(children: [actionToolbar, pendingBanner]),
                ),
                // #272: no "Ask your coach" card on the brand-new zero-runs
                // welcome screen — it used to dominate above the onboarding
                // buttons. It returns once the runner has data (the
                // non-empty branch, gated on runs.isNotEmpty below).
                if (heroWorkoutCard != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: heroWorkoutCard,
                  ),
                // Onboarding can mint a plan before the first run, so its
                // race day shows here too, not only once there is history.
                if (raceCard != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: raceCard,
                  ),
                if (goals.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: _goalsStrip(runs, goals, now, unit),
                  ),
              ],
            ),
          ),
          // Fills the rest of the viewport so the welcome block stays
          // centred when nothing sits above it, and scrolls once a plan or
          // a goal does.
          SliverFillRemaining(
            hasScrollBody: false,
            child: _WelcomeEmpty(
              theme: theme,
              planAbove: heroWorkoutCard != null || raceCard != null,
              onStartRun: widget.onStartRun,
              startActivity:
                  ActivityType.fromName(widget.preferences.defaultActivityType),
              // Hidden only from the account that said it does not lift (the
              // setup wizard's track step, or Settings); that is the one answer
              // the link would contradict. An account that said it lifts and
              // has logged nothing is who the hint is for, and an unanswered
              // one may lift too. Same rule as web's DashboardFirstRun
              // (decisions § 2041).
              onLogLift: widget.preferences.showGym == false
                  ? null
                  : widget.onLogLift,
              onAddGoal: _newGoal,
              onImport: _openImport,
              onTrainForSomething: _offersPlanEntry ? _openPlanNew : null,
            ),
          ),
        ],
      );
    } else {
      // Today (issue #1374): about six blocks, what to do now and what was
      // just done. Trends, PBs, the streak, the full goals and the recap are
      // the Progress page's, one tap from the summary card at the end.
      //
      // The coach entry — the Coach stays one persistent tap from Home (it
      // has no bottom-nav slot), closing the Today block (decisions § 139,
      // amended by § 2280 and § 2387). Gated on api + training only
      // (`_coachEntry`); the runless welcome state, a different branch, still
      // carries none (#272).
      final coach = _coachEntry();
      final raceCard = _nextRaceCard(now) ?? _planDiscoveryCard(now);
      final social = widget.social;
      final eventCard = _upcomingEvent == null || social == null
          ? null
          : UpcomingEventCard(
              key: const Key('dashboardUpcomingEvent'),
              event: _upcomingEvent!,
              onTap: () async {
                await openUpcomingEvent(context, social, _upcomingEvent!);
                _loadUpcomingEvent();
              },
            );
      // Today's plan cards (the missed prompt, the workout with its Start,
      // the nudge) belong to the Today hero.
      final workoutCard = heroWorkoutCard;
      final latestRun = _latestRun(runs);
      final latestRunSection =
          latestRun == null ? null : _latestRunSection(latestRun, unit);
      final dayStart = DateTime(now.year, now.month, now.day);
      final plan = _planOverview;
      final heroState = todayHeroState(
        hasPlan: plan != null,
        raceToday: plan != null &&
            NextRaceCard.countdownFor(plan, now).kind ==
                PlanRaceCountdownKind.raceDay,
        todayWorkoutKind: plan?.todayWorkout?.kind,
        isNewAccount: false,
        ranToday: latestRun != null &&
            !latestRun.startedAt.toLocal().isBefore(dayStart),
      );
      final runInHero = heroState == TodayHeroState.ranToday;
      final raceInHero = heroState == TodayHeroState.raceDay;
      final todayBlocks = _orderTodayBlocks(
        latestRun: latestRun,
        latestRunSection: runInHero ? null : latestRunSection,
        modalityBody: _todayModalityBody(),
        now: now,
      );
      final startActivity =
          ActivityType.fromName(widget.preferences.defaultActivityType);
      final startButton = heroStart == null
          ? null
          : FilledButton.icon(
              key: const Key('dashboardHeroStart'),
              onPressed: heroStart,
              icon: Icon(startActivity.icon),
              label: Text(startActivityCaption(l10n, startActivity)),
            );
      final readinessLine = ReadinessCard(
        key: const Key('dashboardHeroReadiness'),
        runs: runs,
        now: now,
        hrPrefs: hrPrefs,
        loadSeries: loadSeries,
        compact: true,
      );
      // The adaptive Today hero leads Home (#1187, decisions § 2385); the
      // state comes from the `dashboard_layout` parity pair, the cards from
      // what Home already had.
      final hero = TodayHero(
        key: const Key('dashboardTodayHero'),
        state: heroState,
        children: switch (heroState) {
          TodayHeroState.raceDay => [
              ?raceCard,
              ?workoutCard,
              readinessLine,
              ?startButton,
            ],
          TodayHeroState.planToday => [?workoutCard, readinessLine, ?startButton],
          TodayHeroState.restDay => [
              workoutCard ?? const _RestDayCard(),
              if (_showMascot) const RestDayGrisnir(),
              readinessLine,
              ?startButton,
            ],
          TodayHeroState.ranToday => [
              ?latestRunSection,
              readinessLine,
              ?startButton,
            ],
          TodayHeroState.newAccount || TodayHeroState.noPlan => [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
                child: Text(
                  l10n.dashboardHeroNothingPlanned,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              ReadinessCard(
                key: const Key('dashboardHeroReadinessCard'),
                runs: runs,
                now: now,
                hrPrefs: hrPrefs,
                loadSeries: loadSeries,
              ),
              ?startButton,
            ],
        },
      );
      final goalsStrip = goals.isEmpty ? null : _goalsStrip(runs, goals, now, unit);
      final summary = _progressSummary(runs, now, unit);

      // One column on every width: Today is a short reading list, and the
      // Progress page is where the wide two-column grid earns its keep.
      content = contentColumn(
        context,
        ListView(
          padding: pagePadding,
          children: [
            actionToolbar,
            pendingBanner,
            hero,
            _kSectionGap,
            if (raceCard != null && !raceInHero) ...[raceCard, _kSectionGap],
            if (eventCard != null) ...[eventCard, _kSectionGap],
            for (final block in todayBlocks) ...[block, _kSectionGap],
            if (goalsStrip != null) ...[goalsStrip, _kSectionGap],
            summary,
            if (coach != null) ...[_kSectionGap, coach],
          ],
        ),
      );
    }

    // A root page (ui_kit RootPage): the large title is the body's first
    // row, and the slim bar above it holds the overflow and says the title
    // once the heading has scrolled under it.
    return RootPage(
      title: l10n.todayTitle,
      actions: actions,
      body: RefreshIndicator(onRefresh: _refreshAll, child: content),
    );
  }

  /// The "today's logged modalities" block — gym + nutrition cards, each
  /// self-hiding when that modality has no data today or is switched off in
  /// Settings. Renders the two 2-up on phones wide enough (multi_modal.md §
  /// Home density rules) when both are present, full-width otherwise. Null
  /// when neither has a card.
  Widget? _todayModalityBody() {
    final lift = _gymShown ? _todaysLift : null;
    final food = _nutritionShown ? _todaysFood : const <FoodEntry>[];
    final hasFood = food.isNotEmpty;
    if (lift == null && !hasFood) return null;

    final gymCard = lift == null
        ? null
        : GymSummaryCard(workout: lift, onTap: _openGym);
    final nutritionCard = !hasFood
        ? null
        : NutritionRingsCard(
            consumed: sumMacros(food),
            targets: _nutritionTargets,
            onTap: _openNutrition,
          );

    final wideEnough = MediaQuery.of(context).size.width >= 360;
    final Widget body;
    if (gymCard != null && nutritionCard != null && wideEnough) {
      body = IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: nutritionCard),
            const SizedBox(width: 8),
            Expanded(child: gymCard),
          ],
        ),
      );
    } else {
      body = Column(
        children: [
          if (nutritionCard != null) nutritionCard,
          if (nutritionCard != null && gymCard != null)
            const SizedBox(height: 8),
          if (gymCard != null) gymCard,
        ],
      );
    }
    return body;
  }

  /// The Today block under the plan cards, in multi_modal.md § Home rule 2's
  /// order: what was logged today, most recently started first, then the last
  /// run when it is from an earlier day, so a run from last week never sits
  /// above the lift and the meals logged this morning.
  List<Widget> _orderTodayBlocks({
    required Run? latestRun,
    required Widget? latestRunSection,
    required Widget? modalityBody,
    required DateTime now,
  }) {
    final dayStart = DateTime(now.year, now.month, now.day);
    final runAt = latestRun?.startedAt.toLocal();
    final runIsToday = runAt != null && !runAt.isBefore(dayStart);
    if (latestRunSection == null || modalityBody == null) {
      return [?latestRunSection, ?modalityBody];
    }
    if (!runIsToday) return [modalityBody, latestRunSection];
    final modalityAt = _todayModalityStartedAt();
    final runFirst = modalityAt == null || !runAt.isBefore(modalityAt);
    return runFirst
        ? [latestRunSection, modalityBody]
        : [modalityBody, latestRunSection];
  }

  /// When the newest shown lift or meal of today started; null when none
  /// carries a time.
  DateTime? _todayModalityStartedAt() {
    DateTime? latest;
    void consider(DateTime? at) {
      final local = at?.toLocal();
      if (local != null && (latest == null || local.isAfter(latest!))) {
        latest = local;
      }
    }

    if (_gymShown) consider(_todaysLift?.startedAt);
    if (_nutritionShown) {
      for (final f in _todaysFood) {
        consider(f.startedAt);
      }
    }
    return latest;
  }

  /// The Progress page: trends, PBs, streak, goals and recap, one tap from
  /// Today rather than under it (issue #1374). A pushed page, not a tab.
  void _openProgress() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProgressScreen(
          apiClient: widget.apiClient,
          training: widget.training,
          runStore: widget.runStore,
          routeStore: widget.routeStore,
          gymStore: widget.gymStore,
          preferences: widget.preferences,
          settingsSync: widget.settingsSync,
        ),
      ),
    );
  }

  /// One line per goal (up to [_kGoalsStripMax]) with its progress; a tap
  /// opens the Progress page, where each goal is edited.
  Widget _goalsStrip(
      List<Run> runs, List<RunGoal> goals, DateTime now, DistanceUnit unit) {
    final planWorkouts =
        leadPlanWorkoutsOf(_planOverview) ?? const <LeadPlanWorkout>[];
    return _TodayGoalsStrip(
      key: const Key('todayGoalsStrip'),
      goals: [
        for (final goal in goals.take(_kGoalsStripMax))
          (
            goal: goal,
            progress: evaluateGoal(goal, runs, now,
                weekStartDay: weekStartDayOf(widget.settingsSync),
                planWorkouts: planWorkouts),
          ),
      ],
      more: goals.length > _kGoalsStripMax,
      onOpen: _openProgress,
    );
  }

  /// The one progress summary card that closes Today's numbers: this week,
  /// this month and the current streak, opening the Progress page. The week
  /// is `weekLead`'s own figure, so it matches the Progress page's first
  /// card to the metre.
  Widget _progressSummary(List<Run> runs, DateTime now, DistanceUnit unit) {
    final monthStart = DateTime(now.year, now.month, 1);
    var monthDistance = 0.0;
    for (final r in runs) {
      if (!r.startedAt.isBefore(monthStart)) monthDistance += r.distanceMetres;
    }
    final week = weekLead(
      activities: [
        for (final r in runs)
          LeadActivity(
            startedAt: r.startedAt.toIso8601String(),
            distanceM: r.distanceMetres,
          ),
      ],
      planWorkouts: null,
      weeklyGoal: null,
      weekStart: weekStartDayOf(widget.settingsSync) == 'sunday'
          ? WeekStart.sunday
          : WeekStart.monday,
      now: now,
    );
    final windowed = computeRunStreaks(
        [for (final r in runs) r.startedAt], now);
    final allTime = _allTimeStreaks;
    final streak = streakCardState(
      allTime == null ? null : mergeAllTimeStreaks(allTime, windowed),
      windowed,
    ).current;
    return _ProgressSummaryCard(
      key: const Key('todayProgressSummary'),
      weekMetres: week.distanceM,
      monthMetres: monthDistance,
      streakDays: streak,
      unit: unit,
      onOpen: _openProgress,
    );
  }
}

/// How many goals Today lists before leaving the rest to the Progress page.
const _kGoalsStripMax = 3;

/// Today's goals: each goal's name and how far along it is, read-only. The
/// full cards, with every target and the editor, are on the Progress page.
class _TodayGoalsStrip extends StatelessWidget {
  final List<({RunGoal goal, GoalProgress progress})> goals;
  final bool more;
  final VoidCallback onOpen;

  const _TodayGoalsStrip({
    super.key,
    required this.goals,
    required this.more,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final complete = AppSemanticColors.of(context).success;
    return ListCard(
      onTap: onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            label: l10n.dashboardGoals,
            trailing: Icon(Icons.chevron_right,
                color: theme.colorScheme.onSurfaceVariant),
          ),
          for (final g in goals) ...[
            const SizedBox(height: AppSpace.smPlus),
            Builder(builder: (context) {
              final period = g.goal.period == GoalPeriod.week
                  ? l10n.dashboardGoalWeekly
                  : l10n.dashboardGoalMonthly;
              final title =
                  g.goal.title ?? l10n.dashboardGoalTitleFallback(period);
              final percent = (g.progress.overallPercent * 100).round();
              return MergeSemantics(
                child: Semantics(
                  excludeSemantics: true,
                  label: l10n.dashboardGoalA11y(
                    period,
                    g.goal.title ?? l10n.dashboardGoalTapToEdit,
                    g.progress.complete
                        ? l10n.dashboardGoalComplete
                        : l10n.dashboardGoalInProgress,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: ExcludeSemantics(
                              child: Text(
                                title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w600),
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpace.sm),
                          Text(
                            '$percent%',
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: g.progress.complete
                                  ? complete
                                  : theme.colorScheme.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpace.xs),
                      ProgressBar(
                        value: g.progress.overallPercent.clamp(0.0, 1.0),
                        fill: g.progress.complete ? complete : null,
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
          if (more) ...[
            const SizedBox(height: AppSpace.sm),
            Text(
              l10n.todayGoalsMore,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}

/// Today's one progress summary: this week, this month and the current
/// streak, as one card that opens the Progress page (issue #1374).
class _ProgressSummaryCard extends StatelessWidget {
  final double weekMetres;
  final double monthMetres;
  final int streakDays;
  final DistanceUnit unit;
  final VoidCallback onOpen;

  const _ProgressSummaryCard({
    super.key,
    required this.weekMetres,
    required this.monthMetres,
    required this.streakDays,
    required this.unit,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final distanceUnit = UnitFormat.distanceLabel(unit);
    return ListCard(
      onTap: onOpen,
      semanticHint: l10n.progressSummaryOpenHint,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ChartCardHeader(
            title: l10n.progressSummaryTitle,
            action: Icon(Icons.chevron_right,
                color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpace.smPlus),
          StatGrid(
            cells: [
              StatTile.medium(
                label: l10n.progressSummaryWeek,
                value: UnitFormat.distanceValue(weekMetres, unit),
                unit: distanceUnit,
              ),
              StatTile.medium(
                label: l10n.progressSummaryMonth,
                value: UnitFormat.distanceValue(monthMetres, unit),
                unit: distanceUnit,
              ),
              StatTile.medium(
                label: l10n.dashboardSectionStreak,
                value: '$streakDays',
                unit: l10n.dashboardStreakDayUnit(streakDays),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The "Ask your coach" row that closes Home's Today block: one tap to the
/// AI coach, which has no bottom-nav slot. A compact row rather than a card
/// (decisions § 2387): it is a reminder of where the coach is, not a pitch.
class _CoachEntryCard extends StatelessWidget {
  final String subtitle;
  final VoidCallback onTap;
  final String title;
  const _CoachEntryCard(
      {required this.title, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      excludeSemantics: true,
      onTap: onTap,
      button: true,
      label: title,
      child: Material(
        key: const Key('dashboardCoachRow'),
        color: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.psychology_outlined, color: scheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The adaptive Today hero that leads Home (#1187, decisions § 2385). [state]
/// is what `todayHeroState` picked; [children] are the cards that state
/// shows, in order.
class TodayHero extends StatelessWidget {
  final TodayHeroState state;
  final List<Widget> children;
  const TodayHero(
      {super.key, required this.state, required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, child) in children.indexed) ...[
          if (i > 0) const SizedBox(height: 8),
          child,
        ],
      ],
    );
  }
}

/// The hero on a plan day with nothing scheduled.
class _RestDayCard extends StatelessWidget {
  const _RestDayCard();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListCard.row(
      key: const Key('dashboardHeroRestDay'),
      leading: const Icon(Icons.self_improvement),
      title: l10n.dashboardHeroRestDay,
      subtitle: l10n.dashboardHeroRestDayBody,
      subtitleMaxLines: 4,
    );
  }
}

class _WelcomeEmpty extends StatelessWidget {
  final ThemeData theme;
  final bool planAbove;
  final VoidCallback? onStartRun;

  /// What [onStartRun] records: the runner's default activity.
  final ActivityType startActivity;
  final VoidCallback? onLogLift;
  final VoidCallback onAddGoal;
  final VoidCallback onImport;

  /// Opens the plan wizard. Null while the runner has a plan, or the plan
  /// reads have not answered, so the entry is never offered to someone who
  /// may already have one.
  final VoidCallback? onTrainForSomething;
  const _WelcomeEmpty({
    required this.theme,
    required this.planAbove,
    required this.onStartRun,
    required this.startActivity,
    required this.onLogLift,
    required this.onAddGoal,
    required this.onImport,
    this.onTrainForSomething,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.directions_run,
                size: 64, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text(l10n.dashboardWelcomeTitle,
                style: theme.textTheme.headlineSmall),
            const SizedBox(height: 8),
            // Onboarding can create a plan before the first run exists, and
            // its workout card then renders directly above this block.
            Text(
              planAbove
                  ? l10n.dashboardFirstRunBodyWithPlan
                  : l10n.dashboardWelcomeBody,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            // Primary CTA: start recording. The welcome copy promises
            // "record a run" as the first path, so the empty state leads
            // with it (the goal / import handles used to be the only
            // actions, leaving the promised recording path with no
            // affordance). Hidden when the host can't reach the recorder
            // (onStartRun null) rather than shown as a dead button.
            if (onStartRun != null) ...[
              FilledButton.icon(
                key: const Key('dashboardWelcomeStart'),
                onPressed: onStartRun,
                icon: Icon(startActivity.icon),
                label: Text(startActivityAction(l10n, startActivity)),
              ),
              const SizedBox(height: 12),
            ],
            // Two side-by-side secondary actions — "Set a goal" + the
            // discoverability handle to bulk-import a Strava / Garmin /
            // Health Connect history (the empty-state used to leave
            // import buried under Settings).
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                if (onTrainForSomething != null)
                  FilledButton.tonalIcon(
                    key: const Key('dashboardWelcomeTrainForSomething'),
                    onPressed: onTrainForSomething,
                    icon: const Icon(Icons.event_note),
                    label: Text(l10n.dashboardTrainForSomething),
                  ),
                FilledButton.tonalIcon(
                  onPressed: onAddGoal,
                  icon: const Icon(Icons.flag_outlined),
                  label: Text(l10n.dashboardSetGoal),
                ),
                OutlinedButton.icon(
                  onPressed: onImport,
                  icon: const Icon(Icons.upload_file),
                  label: Text(l10n.dashboardImportRuns),
                ),
              ],
            ),
            // A new account that lifts rather than runs was only ever offered
            // a run; web's first-run card carries the same way out (#905).
            if (onLogLift != null) ...[
              const SizedBox(height: 16),
              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    l10n.dashboardFirstRunGymHint,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: onLogLift,
                    icon: const Icon(Icons.fitness_center),
                    label: Text(l10n.dashboardFirstRunGymAction),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
