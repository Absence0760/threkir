import 'dart:async';

import 'package:core_models/core_models.dart' hide Route;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:ui_kit/ui_kit.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../adaptive_fitness_flag.dart';
import '../adaptive_width.dart';
import '../auth_error.dart';
import '../widgets/confirm_destructive.dart';
import '../widgets/plan_details_sheet.dart';
import '../plan_repace.dart';
import '../plan_bulk_ops.dart' show shiftIsoDate;
import '../plan_race_date.dart';
import '../plan_resume.dart';
import '../plan_restart.dart';
import '../rate_limit_message.dart' show rateLimitErrorMessage;
import '../cycle_plan.dart' show CyclePlanConfig, CyclePlanMode;
import '../cycle_plan_config.dart';
import '../share_sheet.dart';
import '../plan_serialize.dart';
import '../l10n/date_format.dart';
import '../l10n/gen/app_localizations.dart';
import '../l10n/locale_support.dart';
import '../l10n/number_format.dart';
import '../local_run_store.dart';
import '../main.dart' show pendingStartWorkout;
import '../plan_adherence.dart';
import '../plan_current.dart';
import '../plan_progress.dart';
import '../plan_replan.dart';
import '../plan_adaptive_replan.dart';
import '../plan_move.dart';
import '../plan_races.dart';
import '../plan_week.dart';
import '../race_taper.dart';
import '../social_service.dart' show ClubView, RecentRunRow, SocialService;
import '../metrics.dart';
import '../goal_time.dart' show formatGoalTimeS, formatRaceGoalTimeS;
import '../training.dart';
import '../training_labels.dart';
import '../training_load.dart';
import '../training_service.dart';
import '../settings_sync.dart' show activeWeekStartDay;
import '../preferences.dart' show activePreferences;
import 'package:api_client/api_client.dart' show ApiClient;
import 'coaching_screen.dart';
import 'profile_screen.dart';
import '../backend_timeout.dart';
import '../disclosure_state.dart';
import '../widgets/finish_plan_card.dart';
import '../widgets/plan_break_card.dart';
import '../widgets/error_state.dart';
import '../widgets/current_week_strip.dart';
import '../widgets/next_race_card.dart';
import '../widgets/plan_card.dart';
import '../widgets/plan_workout_status_style.dart';
import '../widgets/disclosure_section.dart';
import '../widgets/plan_calendar.dart';
import '../widgets/plan_races_list.dart';
import '../widgets/todays_workout_card.dart';
import '../widgets/top_banner.dart';
import '../widgets/workout_edit_sheet.dart';
import 'workout_detail_screen.dart';

/// Wider than kContentMaxWidth — the week grid and calendar read better with
/// more room than a prose column.
const double _kExpandedBodyMaxWidth = 900;

/// The whole-plan changes the Adjust plan dialog offers. Web twin: the option
/// list in `apps/web/src/routes/plans/[id]/+page.svelte` (decisions § 1635).
enum _PlanAdjustment { replan, adaptiveReplan, raceTaper, cycle, pause, resume }

/// Today's session and this week lead the screen; everything else sits behind
/// a named expander whose open/closed state is remembered per account. Every
/// default is open: a runner who uses one of these sections today must not
/// find it gone on the first visit after this shipped. Web twin: the
/// `DISCLOSURE_*` constants on `/plans/[id]` (decisions § 1660).
const String _kDisclosureScope = 'plan_detail';
const DisclosureState _kDisclosureDefaults = {
  'progress': true,
  'rules': true,
  'calendar': true,
  'weeks': true,
  'share': true,
};

/// Web `isWorkoutSkipped` twin — deliberately dropped, off the books.
bool _isWorkoutSkipped(PlanWorkoutRow wo) => isWorkoutSkipped(wo.skippedAt);

/// Filter the viewer's club memberships to ones they can publish a
/// plan-template into — owner or admin. Pure so it's directly
/// unit-tested in `plan_detail_screen_test.dart`.
@visibleForTesting
List<ClubView> adminClubsForPublish(Iterable<ClubView> clubs) {
  return clubs.where((c) => c.isAdmin).toList();
}

class PlanDetailScreen extends StatefulWidget {
  final TrainingService training;
  final String planId;

  /// Optional SocialService injection so tests can drive the publish
  /// flow with a fake. Production callsites pass `null` and the screen
  /// constructs its own SocialService against the global Supabase
  /// client.
  final SocialService? social;

  /// Test-only override for the signed-in user id. Production passes null and
  /// the screen reads it from the global Supabase auth session; widget tests
  /// inject it so the owner-gated adherence / re-plan / duplicate surfaces are
  /// reachable without a live auth session.
  @visibleForTesting
  final String? viewerIdOverride;

  /// Source of full `Run`s (with `metadata.avg_bpm`) for the P2 adaptive-replan
  /// fitness gate. Only consumed when `ADAPTIVE_FITNESS_GATE` is on (gated OFF
  /// by default, pending P2 CISO sign-off); null leaves the P1 behaviour intact.
  /// Threaded from the Fitness hub via PlansScreen; other call sites pass null.
  final LocalRunStore? runStore;

  /// Clock for every "today" this screen derives. The adherence surfaces are
  /// windowed on the days of the current week that have already ended, so on
  /// a Monday nothing has and the banner correctly does not render -- which
  /// made a fixture built from `_mondayThisWeek()` a test that passed six days
  /// in seven. Production leaves the default.
  final DateTime Function() now;

  /// The runner's cycle / pregnancy adjustment config, read under the
  /// cycle-plans gate (`readCyclePlanConfig`). A test passes its own.
  final CyclePlanConfig? Function() cyclePlanConfig;

  /// Open with the resume confirm up, when the plan is paused and the viewer
  /// owns it: Home's paused-plan card lands here. Web twin: `?resume=1`.
  final bool openResume;

  /// Opens a user's profile. Production leaves it null and pushes
  /// [ProfileScreen]; a test passes its own to see where the coach entry goes.
  @visibleForTesting
  final void Function(BuildContext context, String userId)? openProfileOverride;

  const PlanDetailScreen({
    super.key,
    required this.training,
    required this.planId,
    this.social,
    this.viewerIdOverride,
    this.runStore,
    this.now = DateTime.now,
    this.cyclePlanConfig = readCyclePlanConfig,
    this.openResume = false,
    this.openProfileOverride,
  });

  @override
  State<PlanDetailScreen> createState() => _PlanDetailScreenState();
}

class _PlanDetailScreenState extends State<PlanDetailScreen>
    with WidgetsBindingObserver {
  TrainingPlanRow? _plan;
  List<PlanWeekRow> _weeks = const [];
  Map<String, List<PlanWorkoutRow>> _byWeek = const {};
  bool _loading = true;

  /// [PlanDetailScreen.openResume] fires once, not on every reload.
  bool _resumeOffered = false;
  bool _coachesOwner = false;
  _PlanDetailLoadError? _error;
  bool _publishing = false;
  bool _bulkBusy = false;
  bool _libraryBusy = false;
  String? _publishedTemplateId;
  List<RecentRunRow> _recentRuns = const [];
  bool _recentRunsLoaded = false;
  List<ReplanChange>? _replanPreview;
  // The B/C race taper's proposals (decisions § 2051), previewed like a
  // re-plan and applied only on the runner's say-so.
  List<RaceTaperChange>? _taperPreview;
  // Set only when the current preview came from the adaptive (trend-based)
  // path, so its header can explain the multi-week reason + confidence.
  ({AdaptiveReason reason, AdaptiveConfidence confidence})? _adaptiveInfo;
  DisclosureState _disclosure = Map.of(_kDisclosureDefaults);
  // A toggle made before the stored state arrives wins over it.
  bool _disclosureTouched = false;
  // Finished weeks fold into one summary row until the runner opens them.
  bool _showEarlierWeeks = false;
  String? _assigningCoachName;
  // "Today" is derived on every build from widget.now(); these rebuild the
  // screen when the day turns over while it is open, or when it resumes.
  Timer? _midnight;
  // A proposal renders below the Adjust button, often under the fold; it is
  // scrolled into view when it appears, as web moves focus to its heading.
  final GlobalKey _taperPreviewKey = GlobalKey();
  final GlobalKey _replanPreviewKey = GlobalKey();

  void _reveal(GlobalKey key) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = key.currentContext;
      if (ctx != null && mounted) {
        Scrollable.ensureVisible(ctx, alignment: 0.1);
      }
    });
  }

  // Lazily construct a SocialService against the global Supabase client
  // when none was injected. Tests pass a fake via the constructor.
  late final SocialService _social = widget.social ?? SocialService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scheduleMidnight();
    _load();
    _loadDisclosure();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _midnight?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      setState(() {});
      _scheduleMidnight();
    }
  }

  void _scheduleMidnight() {
    _midnight?.cancel();
    final now = widget.now();
    final next = DateTime(now.year, now.month, now.day + 1);
    _midnight = Timer(next.difference(now) + const Duration(seconds: 1), () {
      if (!mounted) return;
      setState(() {});
      _scheduleMidnight();
    });
  }

  bool _notStarted(TrainingPlanRow p) =>
      toIsoDate(widget.now()).compareTo(toIsoDate(p.startDate)) < 0;

  /// Who assigned this plan, when a coach did and it is not the viewer.
  Future<void> _loadAssigningCoach() async {
    final coachId = _plan?.assignedByCoachId;
    if (coachId == null || coachId == _viewerId()) return;
    try {
      final name = await widget.training
          .fetchDisplayName(coachId)
          .timeout(kBackendLoadTimeout);
      if (mounted && _plan?.assignedByCoachId == coachId) {
        setState(() => _assigningCoachName = name);
      }
    } catch (e) {
      debugPrint('PlanDetailScreen._loadAssigningCoach failed: $e');
    }
  }

  void _openCoachProfile(String coachId) {
    final override = widget.openProfileOverride;
    if (override != null) {
      override(context, coachId);
      return;
    }
    if (!ApiClient.isInitialized) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ProfileScreen(api: ApiClient(), userId: coachId),
    ));
  }

  void _openCoaching() {
    final prefs = activePreferences;
    if (prefs == null || !ApiClient.isInitialized) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => CoachingScreen(api: ApiClient(), preferences: prefs),
    ));
  }

  Future<void> _loadDisclosure() async {
    final stored = await readDisclosureState(
        _kDisclosureScope, _viewerId(), _kDisclosureDefaults);
    if (!mounted || _disclosureTouched) return;
    setState(() => _disclosure = stored);
  }

  void _setDisclosure(String key, bool open) {
    if (_disclosure[key] == open) return;
    _disclosureTouched = true;
    setState(() => _disclosure = {..._disclosure, key: open});
    unawaited(
        writeDisclosureState(_kDisclosureScope, _viewerId(), _disclosure));
  }

  Future<void> _load() async {
    // A plan already on screen stays there while it refreshes: no full-body
    // loader, no scroll reset, and a failed refresh is a banner over the
    // stale plan rather than an error page in its place.
    final refreshing = _plan != null;
    setState(() {
      if (!refreshing) _loading = true;
      _error = null;
    });
    try {
      final res = await widget.training
          .fetchPlan(widget.planId)
          .timeout(kBackendLoadTimeout);
      if (!mounted) return;
      final byWeek = <String, List<PlanWorkoutRow>>{};
      for (final w in res.workouts) {
        byWeek.putIfAbsent(w.weekId, () => []).add(w);
      }
      setState(() {
        _plan = res.plan;
        _weeks = res.weeks;
        _byWeek = byWeek;
        _loading = false;
      });
      _loadRecentRuns();
      _loadPublishedState();
      _loadCoachesOwner();
      _loadAssigningCoach();
      final loaded = _plan;
      if (widget.openResume &&
          !_resumeOffered &&
          loaded != null &&
          loaded.status == 'paused' &&
          _isOwner(loaded)) {
        _resumeOffered = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _setPlanPaused(loaded, paused: false);
        });
      }
    } catch (e, s) {
      debugPrint('PlanDetailScreen._load failed: $e\n$s');
      if (!mounted) return;
      final kind = e is TimeoutException
          ? _PlanDetailLoadError.timeout
          : classifyAuthError(e) == AuthErrorKind.offline
              ? _PlanDetailLoadError.offline
              : _PlanDetailLoadError.generic;
      if (refreshing) {
        final l10n = AppLocalizations.of(context);
        showTopBanner(
          context,
          kind == _PlanDetailLoadError.generic
              ? l10n.commonStaleRefreshFailed
              : l10n.commonStaleOffline,
        );
        return;
      }
      setState(() {
        _loading = false;
        _error = kind;
      });
    }
  }

  /// Best-effort fetch of the viewer's recent runs so the adherence banner
  /// + re-plan flow can compare actual weekly mileage to the plan. A failure
  /// leaves the adherence surfaces hidden — the rest of the plan still loads.
  Future<void> _loadRecentRuns() async {
    final plan = _plan;
    if (plan == null || !_isOwner(plan)) return;
    try {
      final runs =
          await _social.fetchRecentRuns(limit: 50).timeout(kBackendLoadTimeout);
      if (!mounted) return;
      setState(() {
        _recentRuns = runs;
        _recentRunsLoaded = true;
      });
    } catch (_) {
      /* L4 best-effort — leave the adherence surfaces hidden. */
    }
  }

  /// When the runner's runs started, for the break card: the local store
  /// when the host passed one (it holds unsynced runs too), else the recent
  /// runs once they loaded; null until then, which keeps the card hidden.
  List<DateTime>? get _breakRunStarts {
    final store = widget.runStore;
    if (store != null) return [for (final r in store.summaryRuns) r.startedAt];
    if (!_recentRunsLoaded) return null;
    return [for (final r in _recentRuns) r.startedAt];
  }

  /// Coach RLS lets an athlete's active coach edit the workouts of a
  /// non-template plan. Fails closed: without the link the editor stays shut.
  Future<void> _loadCoachesOwner() async {
    final plan = _plan;
    if (plan == null || plan.isTemplate || _isOwner(plan)) return;
    try {
      final coaches = await widget.training
          .isActiveCoachOf(plan.userId)
          .timeout(kBackendLoadTimeout);
      if (mounted && coaches != _coachesOwner) {
        setState(() => _coachesOwner = coaches);
      }
    } catch (e) {
      debugPrint('PlanDetailScreen._loadCoachesOwner failed: $e');
    }
  }

  bool _canEditWorkouts(TrainingPlanRow plan) =>
      _isOwner(plan) || (_coachesOwner && !plan.isTemplate);

  String? _viewerId() {
    final override = widget.viewerIdOverride;
    if (override != null) return override;
    try {
      return Supabase.instance.client.auth.currentUser?.id;
    } catch (e) {
      debugPrint('PlanDetailScreen: no auth session to read: $e');
      return null;
    }
  }

  bool _isOwner(TrainingPlanRow plan) {
    final uid = _viewerId();
    return uid != null && plan.userId == uid;
  }

  int _currentWeekIndex(TrainingPlanRow plan) {
    // A plan whose weeks failed to load (or never landed) has no valid index:
    // the shared helper would return -1 here, as the web twin's Math.min does,
    // and the screen renders empty rather than indexing off the end.
    if (_weeks.isEmpty) return 0;
    return currentPlanWeekIndex(
      toIsoDate(plan.startDate),
      toIsoDate(widget.now()),
      _weeks.length,
    );
  }

  /// Actual runs dated inside `[weekIndex]`'s 7-day window, on their local
  /// calendar day.
  List<DriftRun> _runsForWeek(TrainingPlanRow plan, int weekIndex) {
    // Calendar days, not 24-hour spans: a plan whose weeks cross a DST
    // transition would otherwise shift every later boundary by an hour, and
    // a run logged in that hour lands in the wrong week.
    final weekStart = addDays(plan.startDate, weekIndex * 7);
    final weekEnd = addDays(weekStart, 7);
    final runs = <DriftRun>[];
    for (final r in _recentRuns) {
      final t = r.startedAt.toLocal();
      if (!t.isBefore(weekStart) && t.isBefore(weekEnd)) {
        runs.add(DriftRun(date: toIsoDate(t), distanceM: r.distanceM));
      }
    }
    return runs;
  }

  /// Summed actual run mileage dated inside `[weekIndex]`'s 7-day window.
  double _actualMetresForWeek(TrainingPlanRow plan, int weekIndex) =>
      _runsForWeek(plan, weekIndex).fold(0.0, (s, r) => s + r.distanceM);

  double _plannedMetresForWeek(PlanWeekRow week) {
    var planned = week.targetVolumeM ?? 0;
    if (!(planned > 0)) {
      planned = 0;
      for (final wo in _byWeek[week.id] ?? const <PlanWorkoutRow>[]) {
        if (wo.kind != 'rest') planned += wo.targetDistanceM ?? 0;
      }
    }
    return planned;
  }

  /// Current-week mileage drift vs the plan TO DATE, or null when on-track /
  /// not the owner. Both sides are windowed to the week's days that have
  /// already ended, so a part-elapsed week is not judged against its full
  /// seven-day target.
  WeeklyDrift? _currentWeekDrift(TrainingPlanRow plan) {
    if (!_isOwner(plan) || _weeks.isEmpty) return null;
    final idx = _currentWeekIndex(plan);
    if (idx >= _weeks.length) return null;
    final week = _weeks[idx];
    final d = weeklyDriftToDate(
      workouts: (_byWeek[week.id] ?? const <PlanWorkoutRow>[])
          .map((w) => DriftWorkout(
                scheduledDate: toIsoDate(w.scheduledDate),
                kind: w.kind,
                targetDistanceM: w.targetDistanceM,
              ))
          .toList(),
      runs: _runsForWeek(plan, idx),
      today: toIsoDate(widget.now()),
      weekTargetVolumeM: week.targetVolumeM,
    );
    return d.flagged ? d : null;
  }

  /// A long run in the current week that's past + uncompleted → make-up/skip
  /// advice driven by phase + whether a step-back week is imminent.
  MissedWorkoutAdvice? _missedLongRun(TrainingPlanRow plan) {
    if (!_isOwner(plan) || _weeks.isEmpty) return null;
    final idx = _currentWeekIndex(plan);
    if (idx >= _weeks.length) return null;
    final week = _weeks[idx];
    final today = toIsoDate(widget.now());
    final missed = (_byWeek[week.id] ?? const <PlanWorkoutRow>[]).where((w) =>
        w.kind == 'long' &&
        toIsoDate(w.scheduledDate).compareTo(today) < 0 &&
        !isWorkoutCompleted(w) &&
        !_isWorkoutSkipped(w));
    if (missed.isEmpty) return null;
    final next = idx + 1 < _weeks.length ? _weeks[idx + 1] : null;
    final nextVol = next?.targetVolumeM ?? 0;
    final curVol = week.targetVolumeM ?? 0;
    final recoveryImminent =
        next != null && nextVol > 0 && curVol > 0 && nextVol < curVol * 0.85;
    return missedWorkoutAdvice(MissedWorkoutInput(
      kind: 'long',
      isTaper: week.phase == 'taper' || week.phase == 'race',
      recoveryWeekImminent: recoveryImminent,
    ));
  }

  List<String> _orderedPhases() =>
      orderedPlanPhases(_weeks.map((w) => PlanProgressWeek(w.phase)).toList());

  double? _longestLongRunMetres() {
    final actualById = <String, double>{};
    for (final r in _recentRuns) {
      actualById[r.id] = r.distanceM;
    }
    final workouts = _byWeek.values
        .expand((x) => x)
        .map((w) => LongRunWorkout(
              kind: w.kind,
              targetDistanceM: w.targetDistanceM,
              completedRunId: w.completedRunId,
              manuallyCompleted: w.manuallyCompleted,
            ))
        .toList();
    return longestCompletedLongRunMetres(workouts, actualById);
  }

  List<ReplanWeek> _buildReplanInput(TrainingPlanRow plan) {
    final today = toIsoDate(widget.now());
    final todayD = widget.now();
    return _weeks.map((w) {
      final weekStart = addDays(plan.startDate, w.weekIndex * 7);
      final weekEnd = addDays(weekStart, 7);
      return ReplanWeek(
        weekIndex: w.weekIndex,
        phase: w.phase,
        plannedMetres: _plannedMetresForWeek(w),
        actualMetres: _actualMetresForWeek(plan, w.weekIndex),
        isComplete: !weekEnd.isAfter(todayD),
        workouts: (_byWeek[w.id] ?? const <PlanWorkoutRow>[])
            .map((x) => ReplanWorkout(
                  id: x.id,
                  scheduledDate: toIsoDate(x.scheduledDate),
                  kind: x.kind,
                  targetDistanceM: x.targetDistanceM,
                  completed: isWorkoutCompleted(x),
                  skipped: _isWorkoutSkipped(x),
                  isPast: toIsoDate(x.scheduledDate).compareTo(today) < 0,
                ))
            .toList(),
      );
    }).toList();
  }

  /// Every race the plan builds toward (plan_races.dart, decisions § 2009).
  List<PlanRace> _planRacesFor(TrainingPlanRow p) => planRaces(
        endDate: toIsoDate(p.endDate),
        goalDistanceM: p.goalDistanceM,
        goalTimeSec: p.goalTimeSeconds,
        trimmedAt: p.trimmedAt,
        workouts: [
          for (final w in _byWeek.values.expand((x) => x))
            PlanRaceWorkout.fromRow(w),
        ],
      );

  /// The race the hero's distance / goal / date follow: the next race once it
  /// is not the plan's own A race on the end date. Null keeps the plan goal,
  /// which the races list carries either way. Web twin: `heroRace`.
  PlanRace? _heroRace(TrainingPlanRow p, List<PlanRace> races) {
    final next = nextRace(races, toIsoDate(widget.now()));
    if (next == null) return null;
    if (next.priority == 'A' && next.date == toIsoDate(p.endDate)) return null;
    return next;
  }

  bool _hasFutureBcRace(TrainingPlanRow p) {
    final today = toIsoDate(widget.now());
    return _planRacesFor(p)
        .any((r) => r.priority != 'A' && r.date.compareTo(today) > 0);
  }

  void _proposeRaceTaper(TrainingPlanRow plan) {
    if (!_isOwner(plan) || _bulkBusy) return;
    final l10n = AppLocalizations.of(context);
    final changes = raceTaperProposals(
      workouts: [
        for (final w in _weeks)
          for (final x in _byWeek[w.id] ?? const <PlanWorkoutRow>[])
            RaceTaperWorkout(
              id: x.id,
              scheduledDate: toIsoDate(x.scheduledDate),
              kind: x.kind,
              targetDistanceM: x.targetDistanceM,
              targetDurationSeconds: x.targetDurationSeconds,
              structure: x.structure,
              notes: x.notes,
              phase: w.phase,
              completed: isWorkoutCompleted(x),
              skipped: _isWorkoutSkipped(x),
              taperApplied: x.raceTaperAppliedAt != null,
            ),
      ],
      races: _planRacesFor(plan),
      today: toIsoDate(widget.now()),
    );
    setState(() {
      _replanPreview = null;
      _adaptiveInfo = null;
      _taperPreview = changes.isEmpty ? null : changes;
    });
    if (changes.isEmpty) {
      showTopBanner(context, l10n.planDetailRaceTaperNone);
    } else {
      _reveal(_taperPreviewKey);
    }
  }

  /// Writes every proposed patch in one transaction; the server restates
  /// each touched week's volume. A failure re-fetches the plan so nothing
  /// stale stays on screen. Web twin: `applyRaceTaper`.
  Future<void> _applyRaceTaper(TrainingPlanRow plan) async {
    final changes = _taperPreview;
    if (changes == null || _bulkBusy) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _bulkBusy = true);
    try {
      await widget.training
          .applyRaceTaper(
            planId: plan.id,
            patches: {for (final c in changes) c.workoutId: raceTaperPatch(c)},
          )
          .timeout(kBackendLoadTimeout);
      if (!mounted) return;
      setState(() {
        _taperPreview = null;
        _bulkBusy = false;
      });
      showTopBanner(context, l10n.planDetailReplanApplied(changes.length));
      await _load();
    } catch (e) {
      debugPrint('plan detail race taper failed: $e');
      if (!mounted) return;
      setState(() {
        _taperPreview = null;
        _bulkBusy = false;
      });
      showTopBanner(context, l10n.planDetailBulkFailed(friendlyError(l10n, e)));
      await _load();
    }
  }

  String _taperChangeLabel(AppLocalizations l10n, RaceTaperChange c) {
    String side(String kind, double? metres, int? seconds) => [
          workoutKindLabel(l10n, workoutKindFromDb(kind)),
          if (metres != null) fmtKm(metres),
          if (seconds != null) formatGoalTimeS(seconds),
        ].join(' ');

    final change = '${side(c.fromKind, c.fromMetres, c.fromDurationS)} → '
        '${side(c.toKind, c.toMetres, c.toDurationS)}';
    final race = c.raceName ?? c.raceDate;
    return switch (c.reason) {
      RaceTaperReason.shakeout => l10n.planDetailRaceTaperShakeout(change, race),
      RaceTaperReason.preRace => l10n.planDetailRaceTaperPre(change, race),
      RaceTaperReason.postRace => l10n.planDetailRaceTaperPost(change, race),
    };
  }

  void _proposeReplan(TrainingPlanRow plan) {
    if (!_isOwner(plan) || _bulkBusy) return;
    final l10n = AppLocalizations.of(context);
    final res = replanRemaining(
        weeks: _buildReplanInput(plan), today: toIsoDate(widget.now()));
    if (res.onTrack || res.changes.isEmpty) {
      setState(() => _replanPreview = null);
      showTopBanner(context, l10n.planDetailReplanOnTrack);
      return;
    }
    setState(() {
      _adaptiveInfo = null;
      _replanPreview = res.changes;
    });
    _reveal(_replanPreviewKey);
  }

  /// P2 (gated): the runner's latest training-load point as the fitness input.
  /// Null unless `ADAPTIVE_FITNESS_GATE` is on, so the health-derived-load path
  /// is dormant by default. Mirrors web's `adaptiveFitnessInput`: feed FULL
  /// `Run`s (with `metadata.avg_bpm`) from `LocalRunStore` — NOT `_recentRuns`
  /// (`RecentRunRow`, no HR) — to `computeTrainingLoadSeries`, default HR prefs.
  AdaptiveFitness? _adaptiveFitnessInput() {
    if (!adaptiveFitnessGate) return null;
    final runs = widget.runStore?.runs;
    if (runs == null || runs.isEmpty) return null;
    final series = computeTrainingLoadSeries(runs, endDate: widget.now());
    if (series.isEmpty) return null;
    final last = series.last;
    return AdaptiveFitness(tsb: last.tsb, atl: last.atl, ctl: last.ctl);
  }

  /// Adaptive (trend-based) re-plan: only proposes when the last few completed
  /// weeks show a sustained drift, suppressing single-week noise.
  void _proposeAdaptiveReplan(TrainingPlanRow plan) {
    if (!_isOwner(plan) || _bulkBusy) return;
    final l10n = AppLocalizations.of(context);
    final res = adaptiveReplanRemaining(
      weeks: _buildReplanInput(plan),
      today: toIsoDate(widget.now()),
      fitness: _adaptiveFitnessInput(),
    );
    if (res.reason == AdaptiveReason.deloadFatigue) {
      // P2 arm 2: the load signal overrode the direction. Volume is never added
      // on top of deep fatigue; the deload is proposed instead (or nothing at
      // all, when there's no future week left to ease).
      setState(() {
        _adaptiveInfo = null;
        _replanPreview = res.changes.isEmpty ? null : res.changes;
      });
      if (res.changes.isNotEmpty) _reveal(_replanPreviewKey);
      showTopBanner(context, l10n.planDetailAdaptiveFitnessHeld);
      return;
    }
    if (res.fitnessGated) {
      // P2 arms 1 + 3: an add-volume trend was withheld because the runner is
      // carrying fatigue (TSB < 0) — the adherence and fitness signals disagree.
      setState(() {
        _replanPreview = null;
        _adaptiveInfo = null;
      });
      showTopBanner(context, l10n.planDetailAdaptiveFitnessHeld);
      return;
    }
    if (res.reason == AdaptiveReason.onTrack) {
      setState(() {
        _replanPreview = null;
        _adaptiveInfo = null;
      });
      showTopBanner(context, l10n.planDetailAdaptiveOnTrack);
      return;
    }
    if (res.changes.isEmpty) {
      setState(() {
        _replanPreview = null;
        _adaptiveInfo = null;
      });
      showTopBanner(context, l10n.planDetailAdaptiveNoSafeChange);
      return;
    }
    setState(() {
      _adaptiveInfo = (reason: res.reason, confidence: res.confidence);
      _replanPreview = res.changes;
    });
    _reveal(_replanPreviewKey);
  }

  String _adaptiveBadgeText(AppLocalizations l10n) {
    final info = _adaptiveInfo!;
    final reason = info.reason == AdaptiveReason.trendUnderfitness
        ? l10n.planDetailAdaptiveReasonUnder
        : l10n.planDetailAdaptiveReasonOver;
    final confidence = info.confidence == AdaptiveConfidence.high
        ? l10n.planDetailAdaptiveConfidenceHigh
        : l10n.planDetailAdaptiveConfidenceMedium;
    return l10n.planDetailAdaptiveBadge(reason, confidence);
  }

  /// One entry point for every whole-plan change, each named with a sentence
  /// on what it does and when to use it. Web twin: the Adjust plan Modal.
  Future<void> _openAdjustPlan(TrainingPlanRow p) async {
    if (!_isOwner(p) || p.isTemplate) return;
    final l10n = AppLocalizations.of(context);
    // Art 9: the cycle and pregnancy settings are read only under the gate.
    final cycleConfig = widget.cyclePlanConfig();
    final choice = await showDialog<_PlanAdjustment>(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return AlertDialog(
          title: Text(l10n.planDetailAdjustPlan),
          contentPadding: const EdgeInsets.only(top: 12, bottom: 8),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                  child: Text(
                    l10n.planDetailAdjustPlanIntro,
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
                _adjustOption(
                  ctx,
                  icon: Icons.auto_fix_high,
                  title: l10n.planDetailReplan,
                  description: l10n.planDetailAdjustReplanDesc,
                  value: _PlanAdjustment.replan,
                ),
                _adjustOption(
                  ctx,
                  icon: Icons.trending_up,
                  title: l10n.planDetailAdaptiveReplan,
                  description: l10n.planDetailAdjustAdaptiveDesc,
                  value: _PlanAdjustment.adaptiveReplan,
                ),
                if (_hasFutureBcRace(p))
                  _adjustOption(
                    ctx,
                    icon: Icons.flag_outlined,
                    title: l10n.planDetailRaceTaper,
                    description: l10n.planDetailAdjustRaceTaperDesc,
                    value: _PlanAdjustment.raceTaper,
                  ),
                if (cycleConfig != null)
                  _adjustOption(
                    ctx,
                    icon: Icons.favorite_border,
                    title: cycleConfig.mode == CyclePlanMode.cycle
                        ? l10n.planDetailCycleAdjustCycle
                        : l10n.planDetailCycleAdjustPregnancy,
                    description: cycleConfig.mode == CyclePlanMode.cycle
                        ? l10n.planDetailAdjustCycleDesc
                        : l10n.planDetailAdjustPregnancyDesc,
                    value: _PlanAdjustment.cycle,
                  ),
                if (p.status == 'paused')
                  _adjustOption(
                    ctx,
                    icon: Icons.play_arrow,
                    title: l10n.planDetailResumePlan,
                    description: l10n.planDetailAdjustResumeDesc,
                    value: _PlanAdjustment.resume,
                  )
                else if (p.status == 'active')
                  _adjustOption(
                    ctx,
                    icon: Icons.pause,
                    title: l10n.planDetailPausePlan,
                    description: l10n.planDetailAdjustPauseDesc,
                    value: _PlanAdjustment.pause,
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l10n.commonCancel),
            ),
          ],
        );
      },
    );
    if (choice == null || !mounted) return;
    if (choice != _PlanAdjustment.raceTaper && _taperPreview != null) {
      setState(() => _taperPreview = null);
    }
    switch (choice) {
      case _PlanAdjustment.replan:
        _proposeReplan(p);
      case _PlanAdjustment.adaptiveReplan:
        _proposeAdaptiveReplan(p);
      case _PlanAdjustment.raceTaper:
        _proposeRaceTaper(p);
      case _PlanAdjustment.pause:
        await _setPlanPaused(p, paused: true);
      case _PlanAdjustment.resume:
        await _setPlanPaused(p, paused: false);
      case _PlanAdjustment.cycle:
        await _applyCycleAdjustment(p, cycleConfig!);
    }
  }

  /// Eases the upcoming workouts for the runner's cycle or pregnancy after
  /// a confirm that says what changes. Web twin: `applyCycleAdjustment`.
  Future<void> _applyCycleAdjustment(
      TrainingPlanRow p, CyclePlanConfig cfg) async {
    if (_bulkBusy) return;
    final l10n = AppLocalizations.of(context);
    final ok = await confirmDestructive(
      context,
      title: l10n.planDetailCycleAdjustConfirmTitle,
      body: cfg.mode == CyclePlanMode.cycle
          ? l10n.planDetailCycleAdjustConfirmCycle
          : l10n.planDetailCycleAdjustConfirmPregnancy,
      confirmLabel: cfg.mode == CyclePlanMode.cycle
          ? l10n.planDetailCycleAdjustCycle
          : l10n.planDetailCycleAdjustPregnancy,
      cancelLabel: l10n.plansCancel,
    );
    if (!ok || !mounted) return;
    setState(() => _bulkBusy = true);
    try {
      final changed = await widget.training
          .applyCycleAdjustment(p.id, _byWeek.values.expand((x) => x).toList(),
              cfg, toIsoDate(widget.now()))
          .timeout(kBackendLoadTimeout);
      if (!mounted) return;
      showTopBanner(
          context,
          changed > 0
              ? l10n.planDetailCycleAdjustDone
              : l10n.planDetailCycleAdjustNone);
      if (changed > 0) await _load();
    } catch (e) {
      debugPrint('plan cycle adjustment failed: $e');
      if (mounted) {
        showTopBanner(context, l10n.planDetailBulkFailed(friendlyError(l10n, e)));
      }
    } finally {
      if (mounted) setState(() => _bulkBusy = false);
    }
  }

  Widget _adjustOption(
    BuildContext ctx, {
    required IconData icon,
    required String title,
    required String description,
    required _PlanAdjustment value,
  }) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(description),
      isThreeLine: true,
      enabled: !_bulkBusy,
      onTap: () => Navigator.pop(ctx, value),
    );
  }

  /// Pause and resume apply straight from the chooser. The plan is put back
  /// with Resume in the same dialog, so a confirm here would guard a
  /// reversible action — the shape `confirmDestructive` documents itself as
  /// not being for.
  Future<void> _setPlanPaused(TrainingPlanRow p,
      {required bool paused}) async {
    if (!_isOwner(p) || _bulkBusy) return;
    final l10n = AppLocalizations.of(context);
    // The weeks the runner had not started move back by the whole weeks the
    // plan sat paused, so they come back as upcoming rather than missed.
    final shift = paused
        ? null
        : resumeShift(
            startIso: toIsoDate(p.startDate),
            pausedOnIso:
                p.pausedAt == null ? null : toIsoDate(p.pausedAt!.toLocal()),
            todayIso: toIsoDate(widget.now()),
            weekCount: _weeks.length,
          );
    if (shift != null) {
      final ok = await confirmDestructive(
        context,
        title: l10n.planDetailResumeShiftTitle,
        body: l10n.planDetailResumeShiftMessage(
          shift.weeks,
          formatDateShort(
              parseIsoDate(shiftIsoDate(toIsoDate(p.endDate), 7 * shift.weeks)),
              localeToTag(Localizations.localeOf(context))),
        ),
        confirmLabel: l10n.planDetailResumePlan,
        cancelLabel: l10n.plansCancel,
      );
      if (!ok || !mounted) return;
    }
    setState(() => _bulkBusy = true);
    try {
      if (paused) {
        await widget.training.pausePlan(p.id);
      } else {
        await widget.training.resumePlan(p.id, shift: shift);
      }
      if (!mounted) return;
      setState(() => _bulkBusy = false);
      showTopBanner(
          context,
          paused
              ? l10n.planDetailPauseDone
              : shift != null
                  ? l10n.planDetailResumeShiftedDone(shift.weeks)
                  : l10n.planDetailResumeDone);
      await _load();
    } on ActivePlanExistsError {
      if (!mounted) return;
      setState(() => _bulkBusy = false);
      showTopBanner(context, l10n.planDetailResumeOverlap);
    } catch (e, s) {
      debugPrint('pause/resume plan failed: $e\n$s');
      if (!mounted) return;
      setState(() => _bulkBusy = false);
      showTopBanner(context, l10n.planDetailBulkFailed(friendlyError(l10n, e)));
    }
  }

  /// Writes every proposed distance in one transaction; a failure re-fetches
  /// the plan so nothing stale stays on screen, like the taper path.
  Future<void> _applyReplan(TrainingPlanRow plan) async {
    final changes = _replanPreview;
    if (changes == null || _bulkBusy) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _bulkBusy = true);
    try {
      await widget.training
          .applyReplan(
            planId: plan.id,
            distances: {for (final c in changes) c.workoutId: c.toMetres},
          )
          .timeout(kBackendLoadTimeout);
      if (!mounted) return;
      setState(() {
        _replanPreview = null;
        _adaptiveInfo = null;
        _bulkBusy = false;
      });
      showTopBanner(context, l10n.planDetailReplanApplied(changes.length));
      await _load();
    } catch (e) {
      debugPrint('plan detail bulk failed: $e');
      if (!mounted) return;
      setState(() {
        _replanPreview = null;
        _adaptiveInfo = null;
        _bulkBusy = false;
      });
      showTopBanner(context, l10n.planDetailBulkFailed(friendlyError(l10n, e)));
      await _load();
    }
  }

  void _onPlanMenu(_PlanMenu action, TrainingPlanRow p) {
    switch (action) {
      case _PlanMenu.adjust:
        _openAdjustPlan(p);
      case _PlanMenu.editDetails:
        _editPlanDetails(p);
      case _PlanMenu.shift:
        _shiftPlan(p);
      case _PlanMenu.raceDate:
        _changeRaceDate(p);
      case _PlanMenu.exportMarkdown:
        _exportPlan(p, json: false);
      case _PlanMenu.exportJson:
        _exportPlan(p, json: true);
      case _PlanMenu.abandon:
        _abandonPlan(p);
      case _PlanMenu.coach:
        final coachId = p.assignedByCoachId;
        if (coachId != null) _openCoachProfile(coachId);
      case _PlanMenu.restart:
        _restartPlan(p);
      case _PlanMenu.delete:
        _deletePlan(p);
    }
  }

  /// Restarts the plan as a fresh active copy on a date the runner picks
  /// (`restart_training_plan`), then opens the copy in this screen's place.
  /// The plans it replaces are retired as abandoned by the same RPC; this one
  /// keeps its history.
  Future<void> _restartPlan(TrainingPlanRow p) async {
    if (!_isOwner(p) || _bulkBusy) return;
    final l10n = AppLocalizations.of(context);
    final workouts = [
      for (final w in _byWeek.values.expand((x) => x))
        RestartWorkout(kind: w.kind, scheduledDate: toIsoDate(w.scheduledDate)),
    ];
    final startIso = await showDialog<String>(
      context: context,
      builder: (_) => _RestartPlanDialog(
        plan: p,
        workouts: workouts,
        todayIso: toIsoDate(widget.now()),
      ),
    );
    if (startIso == null || !mounted) return;
    setState(() => _bulkBusy = true);
    final String newId;
    try {
      newId = await widget.training
          .restartPlan(p.id, startIso)
          .timeout(kBackendLoadTimeout);
    } on PlanRestartRaceAheadError {
      if (!mounted) return;
      setState(() => _bulkBusy = false);
      showTopBanner(context, l10n.planDetailRestartRaceAheadError);
      return;
    } on PlanRestartBeforeTodayError {
      if (!mounted) return;
      setState(() => _bulkBusy = false);
      showTopBanner(context, l10n.planDetailRestartBeforeTodayError);
      return;
    } catch (e, s) {
      debugPrint('restart plan failed: $e\n$s');
      if (!mounted) return;
      setState(() => _bulkBusy = false);
      final friendly = e is PostgrestException
          ? rateLimitErrorMessage(l10n, code: e.code, message: e.message)
          : null;
      showTopBanner(
          context, friendly ?? l10n.planDetailBulkFailed(friendlyError(l10n, e)));
      return;
    }
    if (!mounted) return;
    showTopBanner(context, l10n.planDetailRestartDone);
    unawaited(Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
      builder: (_) => PlanDetailScreen(
        training: widget.training,
        planId: newId,
        social: widget.social,
        viewerIdOverride: widget.viewerIdOverride,
        runStore: widget.runStore,
        now: widget.now,
        cyclePlanConfig: widget.cyclePlanConfig,
      ),
    )));
  }

  /// Edits the plan's name, days per week, goal time, notes and rules. A new
  /// goal time re-derives the paces still ahead (`plan_repace`) and is written
  /// with them in one transaction; the other fields are a plain update. Web
  /// twin: `PlanMetaEditor.svelte`.
  Future<void> _editPlanDetails(TrainingPlanRow p) async {
    if (_bulkBusy) return;
    final edit = await showPlanDetailsSheet(context, p);
    if (edit == null || !mounted) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _bulkBusy = true);
    try {
      var repaced = 0;
      if (edit.goalTimeSec != p.goalTimeSeconds) {
        final changes = goalTimeRepacePatches(
          goalDistanceM: p.goalDistanceM,
          oldGoalTimeSec: p.goalTimeSeconds,
          newGoalTimeSec: edit.goalTimeSec,
          recent5kSec: p.current5kSeconds,
          todayIso: toIsoDate(widget.now()),
          workouts: _byWeek.values.expand((x) => x).toList(),
        );
        final goal = edit.goalTimeSec;
        final vdot = goal != null && p.current5kSeconds == null
            ? (vdotFromRace(p.goalDistanceM, goal) * 100).round() / 100
            : null;
        await widget.training
            .setPlanGoalTime(p.id, goal, vdot, changes)
            .timeout(kBackendLoadTimeout);
        repaced = changes.length;
      }
      await widget.training
          .updatePlanMeta(p.id,
              name: edit.name,
              notes: edit.notes,
              daysPerWeek: edit.daysPerWeek,
              rules: edit.rules)
          .timeout(kBackendLoadTimeout);
      if (!mounted) return;
      showTopBanner(
        context,
        repaced > 0
            ? l10n.planDetailDetailsSavedRepaced(repaced)
            : l10n.planDetailDetailsSaved,
      );
      await _load();
    } catch (e) {
      debugPrint('plan details save failed: $e');
      if (mounted) {
        showTopBanner(context, l10n.planDetailBulkFailed(friendlyError(l10n, e)));
        await _load();
      }
    } finally {
      if (mounted) setState(() => _bulkBusy = false);
    }
  }

  /// Moves the whole plan by a number of days the runner types (the race
  /// moved, they started late). A forward shift that runs into the plans
  /// queued after this one offers to move them by the same amount; a shift
  /// into an earlier plan is refused with what to do instead. Web twin:
  /// `shiftPlan` on the plan page.
  Future<void> _shiftPlan(TrainingPlanRow plan) async {
    if (_bulkBusy) return;
    final l10n = AppLocalizations.of(context);
    final days = await showDialog<int>(
      context: context,
      builder: (_) => const _ShiftDatesDialog(),
    );
    if (days == null || !mounted) return;
    setState(() => _bulkBusy = true);
    var shiftFollowing = false;
    try {
      while (true) {
        try {
          await widget.training
              .shiftTrainingPlan(plan.id, days, shiftFollowing: shiftFollowing)
              .timeout(kBackendLoadTimeout);
          break;
        } on ActivePlanExistsError {
          if (!mounted) return;
          if (days < 0 || shiftFollowing) {
            showTopBanner(context, l10n.planDetailShiftBlocked);
            return;
          }
          final moveThem = await confirmDestructive(
            context,
            title: l10n.planDetailShiftFollowingTitle,
            body: l10n.planDetailShiftFollowingMessage(days.abs()),
            confirmLabel: l10n.planDetailShiftFollowingApply,
            cancelLabel: l10n.plansCancel,
          );
          if (!moveThem || !mounted) return;
          shiftFollowing = true;
        }
      }
      if (!mounted) return;
      showTopBanner(context, l10n.planDetailShiftDone(days.abs()));
      await _load();
    } catch (e) {
      debugPrint('plan shift failed: $e');
      if (mounted) {
        showTopBanner(context, l10n.planDetailBulkFailed(friendlyError(l10n, e)));
      }
    } finally {
      if (mounted) setState(() => _bulkBusy = false);
    }
  }

  RaceDatePlan _raceDatePlan(TrainingPlanRow p) => RaceDatePlan(
        startDate: toIsoDate(p.startDate),
        endDate: toIsoDate(p.endDate),
        trimmedAt: p.trimmedAt?.toIso8601String(),
        status: p.status,
        isTemplate: p.isTemplate,
      );

  List<RaceDateWeek> get _raceDateWeeks => [
        for (final w in _weeks)
          RaceDateWeek(id: w.id, weekIndex: w.weekIndex, phase: w.phase)
      ];

  /// The race day the owner can move, or null for a plan with no race still
  /// ahead (a walk-run plan, one ended early, one whose race has passed).
  String? _raceDateOffer(TrainingPlanRow p) {
    final d = planRaceDate(_raceDatePlan(p), _raceDateWeeks);
    return d != null && d.compareTo(toIsoDate(widget.now())) >= 0 ? d : null;
  }

  String _raceDateRefusal(AppLocalizations l10n, RaceDateResult r, String date,
      String locale) {
    switch (r.reason!) {
      case RaceDateRefusal.tooSoon:
        return l10n.planDetailRaceDateTooSoon(
            formatDateShort(parseIsoDate(date), locale),
            r.earliestIso == null
                ? ''
                : formatDateShort(parseIsoDate(r.earliestIso!), locale));
      case RaceDateRefusal.past:
        return l10n.planDetailRaceDatePast;
      case RaceDateRefusal.invalid:
        return l10n.planDetailRaceDateInvalid;
      case RaceDateRefusal.unchanged:
        return l10n.planDetailRaceDateUnchanged;
      case RaceDateRefusal.noRace:
        return l10n.planDetailRaceDateNoRace;
      case RaceDateRefusal.raceWeekStarted:
        return l10n.planDetailRaceDateWeekStarted;
      case RaceDateRefusal.tooFar:
        return l10n.planDetailRaceDateTooFar;
      case RaceDateRefusal.noBuildWeek:
        return l10n.planDetailRaceDateNoBuild;
      case RaceDateRefusal.inTheWay:
        return l10n.planDetailRaceDateInTheWay;
    }
  }

  /// Moves the plan's race to a day the runner picks: the weeks still ahead
  /// are re-anchored so the plan ends on it, build weeks added or cut and the
  /// taper kept (`raceDateChange`). A day the plan cannot reach with its
  /// taper, or a later end that runs into another active plan, is refused
  /// before anything is asked.
  Future<void> _changeRaceDate(TrainingPlanRow p) async {
    if (_bulkBusy) return;
    final current = _raceDateOffer(p);
    if (current == null) return;
    final l10n = AppLocalizations.of(context);
    final locale = localeToTag(Localizations.localeOf(context));
    final todayIso = toIsoDate(widget.now());
    final tomorrow = parseIsoDate(shiftIsoDate(todayIso, 1));
    final initial = parseIsoDate(current);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(tomorrow) ? tomorrow : initial,
      firstDate: tomorrow,
      lastDate: parseIsoDate(shiftIsoDate(todayIso, 3 * 366)),
      helpText: l10n.planDetailRaceDatePickerHelp,
    );
    if (picked == null || !mounted) return;
    final date = toIsoDate(picked);
    final result = raceDateChange(
      plan: _raceDatePlan(p),
      weeks: _raceDateWeeks,
      workouts: [
        for (final w in _byWeek.values.expand((x) => x))
          RaceDateWorkout(
            id: w.id,
            weekId: w.weekId,
            scheduledDate: toIsoDate(w.scheduledDate),
            kind: w.kind,
            racePriority: w.racePriority,
            completedRunId: w.completedRunId,
            manuallyCompleted: w.manuallyCompleted,
          )
      ],
      raceDateIso: date,
      todayIso: todayIso,
    );
    if (!result.ok) {
      showTopBanner(context, _raceDateRefusal(l10n, result, date, locale));
      return;
    }
    if (p.status == 'active' && date.compareTo(toIsoDate(p.endDate)) > 0) {
      final List<TrainingPlanRow> others;
      try {
        others = [
          for (final o in await widget.training
              .fetchActivePlans()
              .timeout(kBackendLoadTimeout))
            if (o.id != p.id) o
        ];
      } catch (e) {
        debugPrint('plan race date overlap check failed: $e');
        if (mounted) {
          showTopBanner(
              context, l10n.planDetailBulkFailed(friendlyError(l10n, e)));
        }
        return;
      }
      if (!mounted) return;
      if (overlappingActivePlans(others, toIsoDate(p.startDate), date)
          .isNotEmpty) {
        showTopBanner(context, l10n.planDetailRaceDateOverlap);
        return;
      }
    }
    final change = result.change!;
    final shown = formatDateShort(parseIsoDate(date), locale);
    final ok = await confirmDestructive(
      context,
      title: l10n.planDetailRaceDateConfirmTitle,
      body: change.weekDelta > 0
          ? l10n.planDetailRaceDateConfirmLater(change.weekDelta, shown)
          : change.weekDelta < 0
              ? l10n.planDetailRaceDateConfirmEarlier(-change.weekDelta, shown)
              : l10n.planDetailRaceDateConfirmSameWeek(shown),
      confirmLabel: l10n.planDetailRaceDateApply,
      cancelLabel: l10n.plansCancel,
    );
    if (!ok || !mounted) return;
    setState(() => _bulkBusy = true);
    try {
      await widget.training
          .changePlanRaceDate(p.id, change, todayIso)
          .timeout(kBackendLoadTimeout);
      if (!mounted) return;
      showTopBanner(context, l10n.planDetailRaceDateDone(shown));
      await _load();
    } on ActivePlanExistsError {
      if (mounted) showTopBanner(context, l10n.planDetailRaceDateOverlap);
    } catch (e) {
      debugPrint('plan race date change failed: $e');
      if (mounted) {
        showTopBanner(context, l10n.planDetailBulkFailed(friendlyError(l10n, e)));
      }
    } finally {
      if (mounted) setState(() => _bulkBusy = false);
    }
  }

  /// Eases one week to a recovery week: about 60% volume, quality sessions
  /// turned into easy runs. Not reversible, so it confirms first. Web twin:
  /// `markWeekRecovery` on the plan page.
  Future<void> _markWeekRecovery(TrainingPlanRow plan, PlanWeekRow week) async {
    if (_bulkBusy) return;
    final l10n = AppLocalizations.of(context);
    final ok = await confirmDestructive(
      context,
      title: l10n.planDetailRecoveryConfirmTitle,
      body: l10n.planDetailRecoveryConfirmMessage(week.weekIndex + 1),
      confirmLabel: l10n.planDetailMarkRecovery,
      cancelLabel: l10n.plansCancel,
    );
    if (!ok || !mounted) return;
    setState(() => _bulkBusy = true);
    try {
      await widget.training
          .markWeekRecovery(plan.id, _byWeek[week.id] ?? const [])
          .timeout(kBackendLoadTimeout);
      if (!mounted) return;
      showTopBanner(context, l10n.planDetailRecoveryDone);
      await _load();
    } catch (e) {
      debugPrint('plan recovery week failed: $e');
      if (mounted) {
        showTopBanner(context, l10n.planDetailBulkFailed(friendlyError(l10n, e)));
      }
    } finally {
      if (mounted) setState(() => _bulkBusy = false);
    }
  }

  /// The plan in web's export shape (`plan_serialize`'s `ExportPlan`).
  Map<String, dynamic> _exportShape(TrainingPlanRow p) {
    final weekIndexById = {for (final w in _weeks) w.id: w.weekIndex};
    return {
      'name': p.name,
      'goalEvent': p.goalEvent,
      'goalDistanceM': p.goalDistanceM,
      'goalTimeSec': p.goalTimeSeconds,
      'startDate': toIsoDate(p.startDate),
      'workouts': [
        for (final w in _byWeek.values.expand((x) => x))
          {
            'week_index': weekIndexById[w.weekId] ?? 0,
            'scheduled_date': toIsoDate(w.scheduledDate),
            'kind': w.kind,
            'target_distance_m': w.targetDistanceM,
            'target_pace_sec_per_km': w.targetPaceSecPerKm,
            'notes': w.notes,
            'target_duration_seconds': w.targetDurationSeconds,
            'race_name': w.raceName,
            'race_priority': w.racePriority,
            'race_taper_applied_at': w.raceTaperAppliedAt?.toUtc().toIso8601String(),
          },
      ],
    };
  }

  /// Hands the plan to the share sheet as the Markdown table or the JSON
  /// file web exports, so it can be saved, sent, or pasted into the plan
  /// import on either app.
  Future<void> _exportPlan(TrainingPlanRow p, {required bool json}) async {
    final shape = _exportShape(p);
    try {
      await shareTextFrom(
        context,
        text: json ? planToJson(shape) : planToMarkdown(shape),
        subject: p.name,
      );
    } catch (e) {
      debugPrint('plan export share failed: $e');
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        showTopBanner(context, l10n.planDetailBulkFailed(friendlyError(l10n, e)));
      }
    }
  }

  /// Abandon an active or paused plan. Not reversible from the UI, so it
  /// confirms first; the reload then drops every active/paused-only action.
  /// Web twin: the Abandon option in `/plans/[id]`'s Adjust plan dialog.
  Future<void> _abandonPlan(TrainingPlanRow p) async {
    if (_bulkBusy || (p.status != 'active' && p.status != 'paused')) return;
    final l10n = AppLocalizations.of(context);
    final ok = await confirmDestructive(
      context,
      title: l10n.plansAbandonTitle(p.name),
      body: l10n.plansAbandonBody,
      confirmLabel: l10n.plansAbandon,
      cancelLabel: l10n.plansCancel,
    );
    if (!ok || !mounted) return;
    setState(() => _bulkBusy = true);
    try {
      await widget.training
          .updateStatus(p.id, 'abandoned')
          .timeout(kBackendLoadTimeout);
    } catch (e) {
      debugPrint('plan abandon failed: $e');
      if (!mounted) return;
      setState(() => _bulkBusy = false);
      showTopBanner(context, l10n.planDetailBulkFailed(friendlyError(l10n, e)));
      return;
    }
    if (!mounted) return;
    setState(() => _bulkBusy = false);
    await _load();
  }

  Future<void> _deletePlan(TrainingPlanRow p) async {
    final l10n = AppLocalizations.of(context);
    final ok = await confirmDestructive(
      context,
      title: l10n.plansDeleteTitle(p.name),
      body: l10n.plansDeleteBody,
      confirmLabel: l10n.plansDelete,
      cancelLabel: l10n.plansCancel,
    );
    if (!ok || !mounted) return;
    setState(() => _bulkBusy = true);
    try {
      await widget.training.deletePlan(p.id).timeout(kBackendLoadTimeout);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      debugPrint('plan delete failed: $e');
      if (!mounted) return;
      setState(() => _bulkBusy = false);
      showTopBanner(context, l10n.planDetailBulkFailed(friendlyError(l10n, e)));
    }
  }

  Future<void> _duplicateWeek(TrainingPlanRow plan, PlanWeekRow week) async {
    if (_bulkBusy) return;
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final dl10n = AppLocalizations.of(ctx);
        return AlertDialog(
          title: Text(dl10n.planDetailDuplicateConfirmTitle),
          content: Text(
              dl10n.planDetailDuplicateConfirmMessage(week.weekIndex + 1)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(dl10n.plansCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(dl10n.planDetailDuplicateConfirm),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;
    setState(() => _bulkBusy = true);
    try {
      await widget.training
          .duplicatePlanWeek(plan.id, week.weekIndex)
          .timeout(kBackendLoadTimeout);
      if (!mounted) return;
      setState(() => _bulkBusy = false);
      showTopBanner(
          context, l10n.planDetailDuplicateWeekDone(week.weekIndex + 1));
      await _load();
    } on ActivePlanExistsError {
      if (!mounted) return;
      setState(() => _bulkBusy = false);
      showTopBanner(context, l10n.planDetailDuplicateWeekOverlap);
    } catch (e) {
      debugPrint('plan detail bulk failed: $e');
      if (!mounted) return;
      setState(() => _bulkBusy = false);
      showTopBanner(context, l10n.planDetailBulkFailed(friendlyError(l10n, e)));
    }
  }

  Future<void> _publishToClub(TrainingPlanRow plan) async {
    if (_publishing) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _publishing = true);

    List<ClubView> myClubs;
    try {
      myClubs = await _social.fetchMyClubs().timeout(kBackendLoadTimeout);
    } on TimeoutException {
      if (mounted) {
        setState(() => _publishing = false);
        showTopBanner(context, l10n.planDetailPublishLoadClubsTimeout);
      }
      return;
    } catch (e, s) {
      debugPrint('publish: fetchMyClubs failed: $e\n$s');
      if (mounted) {
        setState(() => _publishing = false);
        showTopBanner(context, l10n.planDetailPublishLoadClubsFailed);
      }
      return;
    }
    if (!mounted) return;

    final eligible = adminClubsForPublish(myClubs);
    if (eligible.isEmpty) {
      setState(() => _publishing = false);
      showTopBanner(
        context,
        l10n.planDetailPublishNoClubs,
      );
      return;
    }

    final clubId = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => PublishClubPicker(clubs: eligible),
    );
    if (clubId == null) {
      if (mounted) setState(() => _publishing = false);
      return;
    }

    try {
      await widget.training
          .publishPlanAsTemplate(planId: plan.id, clubId: clubId)
          .timeout(kBackendLoadTimeout);
      if (!mounted) return;
      setState(() => _publishing = false);
      showTopBanner(context, l10n.planDetailPublishSuccess(plan.name));
    } catch (e, s) {
      debugPrint('publishPlanAsTemplate failed: $e\n$s');
      if (!mounted) return;
      setState(() => _publishing = false);
      showTopBanner(context, l10n.planDetailPublishFailed(friendlyError(l10n, e)));
    }
  }

  Future<void> _loadPublishedState() async {
    final plan = _plan;
    if (plan == null || !_isOwner(plan) || plan.isTemplate) return;
    try {
      final published = await widget.training
          .fetchMyPublishedPlans()
          .timeout(kBackendLoadTimeout);
      if (!mounted) return;
      setState(() {
        _publishedTemplateId =
            published.where((t) => t.name == plan.name).map((t) => t.id).firstOrNull;
      });
    } catch (_) {
      /* L4 best-effort — leave the toggle in publish state. */
    }
  }

  Future<void> _publishToLibrary(TrainingPlanRow plan) async {
    if (_libraryBusy) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _libraryBusy = true);
    try {
      final newId = await widget.training
          .publishPlanToLibrary(planId: plan.id)
          .timeout(kBackendLoadTimeout);
      if (!mounted) return;
      setState(() {
        _libraryBusy = false;
        _publishedTemplateId = newId;
      });
      showTopBanner(context, l10n.planDetailPublishLibrarySuccess);
    } catch (e, s) {
      debugPrint('publishPlanToLibrary failed: $e\n$s');
      if (!mounted) return;
      setState(() => _libraryBusy = false);
      showTopBanner(context, l10n.planDetailPublishLibraryFailed(friendlyError(l10n, e)));
    }
  }

  Future<void> _unpublishFromLibrary() async {
    final templateId = _publishedTemplateId;
    if (templateId == null || _libraryBusy) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _libraryBusy = true);
    try {
      await widget.training
          .unpublishFromLibrary(templateId)
          .timeout(kBackendLoadTimeout);
      if (!mounted) return;
      setState(() {
        _libraryBusy = false;
        _publishedTemplateId = null;
      });
      showTopBanner(context, l10n.planDetailUnpublishSuccess);
    } catch (e, s) {
      debugPrint('unpublishFromLibrary failed: $e\n$s');
      if (!mounted) return;
      setState(() => _libraryBusy = false);
      showTopBanner(context, l10n.planDetailUnpublishFailed(friendlyError(l10n, e)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (_loading) {
      return Scaffold(
        body: FullBodyLoader(
          kind: ActivityLoaderKind.run,
          label: l10n.commonLoading,
        ),
      );
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(),
        body: ErrorState(
            message: switch (_error!) {
              _PlanDetailLoadError.timeout => l10n.planDetailTimeoutError,
              _PlanDetailLoadError.offline => l10n.authErrorOffline,
              _PlanDetailLoadError.generic => l10n.planDetailLoadError,
            },
            onRetry: _load),
      );
    }
    final p = _plan;
    if (p == null) {
      return Scaffold(
        appBar: AppBar(),
        body: EmptyState(
          icon: Icons.calendar_month,
          title: l10n.planDetailNotFound,
        ),
      );
    }
    final theme = Theme.of(context);
    final today = toIsoDate(widget.now());
    final currentWeek = _currentWeekIndex(p);
    final todayWorkout = _byWeek.values
        .expand((x) => x)
        .where((w) => toIsoDate(w.scheduledDate) == today && w.kind != 'rest')
        .cast<PlanWorkoutRow?>()
        .firstOrNull;
    final allActive = _byWeek.values
        .expand((x) => x)
        .where((w) => w.kind != 'rest' && !_isWorkoutSkipped(w))
        .toList();
    final done = allActive.where(isWorkoutCompleted).length;
    final pct =
        allActive.isEmpty ? 0 : (100 * done / allActive.length).round();
    final body = _bodyList(
        theme, l10n, p, pct, done, allActive.length, currentWeek, todayWorkout);

    return Scaffold(
      appBar: AppBar(
        title: Text(p.name),
        actions: [
          if (_isOwner(p) && !p.isTemplate)
            PopupMenuButton<_PlanMenu>(
              key: const Key('planDetailMenu'),
              tooltip: l10n.planDetailMoreActions,
              enabled: !_bulkBusy,
              onSelected: (a) => _onPlanMenu(a, p),
              itemBuilder: (_) => [
                PopupMenuItem(
                    value: _PlanMenu.adjust,
                    child: Text(l10n.planDetailAdjustPlan)),
                PopupMenuItem(
                    value: _PlanMenu.editDetails,
                    child: Text(l10n.planDetailEditDetails)),
                PopupMenuItem(
                    value: _PlanMenu.shift,
                    child: Text(l10n.planDetailShiftDates)),
                if (_raceDateOffer(p) != null)
                  PopupMenuItem(
                      key: const Key('planDetailChangeRaceDate'),
                      value: _PlanMenu.raceDate,
                      child: Text(l10n.planDetailChangeRaceDate)),
                PopupMenuItem(
                    value: _PlanMenu.exportMarkdown,
                    child: Text(l10n.planDetailExportMarkdown)),
                PopupMenuItem(
                    value: _PlanMenu.exportJson,
                    child: Text(l10n.planDetailExportJson)),
                PopupMenuItem(
                    value: _PlanMenu.restart,
                    child: Text(l10n.planDetailRestartPlan)),
                if (p.assignedByCoachId != null &&
                    p.assignedByCoachId != _viewerId() &&
                    _assigningCoachName != null)
                  PopupMenuItem(
                      key: const Key('planDetailMenuCoach'),
                      value: _PlanMenu.coach,
                      child: Text(
                          l10n.planDetailAssignedBy(_assigningCoachName!))),
                const PopupMenuDivider(),
                if (p.status == 'active' || p.status == 'paused')
                  PopupMenuItem(
                      key: const Key('planDetailMenuAbandon'),
                      value: _PlanMenu.abandon,
                      child: Text(l10n.planDetailAbandonPlan)),
                PopupMenuItem(
                    value: _PlanMenu.delete,
                    child: Text(l10n.planDetailDeletePlan)),
              ],
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: contentColumn(context, body, maxWidth: _kExpandedBodyMaxWidth),
      ),
    );
  }

  Widget _bodyList(ThemeData theme, AppLocalizations l10n, TrainingPlanRow p,
      int pct, int done, int total, int currentWeek,
      PlanWorkoutRow? todayWorkout) {
    final allWorkouts = _byWeek.values.expand((x) => x).toList();
    final races = _planRacesFor(p);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        _heroCard(theme, l10n, p, pct, done, total,
            heroRace: _heroRace(p, races)),
        if (_isOwner(p) &&
            !p.isTemplate &&
            FinishPlanCard.shows(
                status: p.status, endDate: p.endDate, now: widget.now())) ...[
          const SizedBox(height: 12),
          FinishPlanCard(
            key: const Key('planDetailFinishPlan'),
            training: widget.training,
            planId: p.id,
            planName: p.name,
            endDate: p.endDate,
            onFinished: _load,
          ),
        ],
        if (_isOwner(p) &&
            PlanBreakCard.shows(
                plan: p,
                weeks: _weeks,
                workouts: allWorkouts,
                runStarts: _breakRunStarts,
                now: widget.now())) ...[
          const SizedBox(height: 12),
          PlanBreakCard(
            key: const Key('planDetailPlanBreak'),
            training: widget.training,
            plan: p,
            weeks: _weeks,
            workouts: allWorkouts,
            runStarts: _breakRunStarts,
            now: widget.now(),
            onApplied: _load,
          ),
        ],
        if (PlanRacesList.shows(races)) ...[
          const SizedBox(height: 12),
          PlanRacesList(
            key: const Key('planDetailRaces'),
            planName: p.name,
            planStartIso: toIsoDate(p.startDate),
            races: races,
            todayIso: toIsoDate(widget.now()),
            onSelectWorkout: (id) {
              final wo = allWorkouts.where((w) => w.id == id).firstOrNull;
              if (wo != null) _openWorkout(wo);
            },
          ),
        ],
        const SizedBox(height: 12),
        if (todayWorkout != null)
          TodaysWorkoutCard(
            workout: todayWorkout,
            onTap: () => _openWorkout(todayWorkout),
            // Only the plan's runner starts its workout: a coach or a
            // template viewer reading the plan has nothing to record.
            onStart: _isOwner(p) && !p.isTemplate
                ? () => _startWorkout(todayWorkout)
                : null,
          )
        else
          _todayFallback(theme, l10n, p, allWorkouts),
        if (_weeks.isNotEmpty) ...[
          const SizedBox(height: 16),
          CurrentWeekStrip(
            startDate: p.startDate,
            weekIndex: _weeks[currentWeek].weekIndex,
            weekWorkouts: _byWeek[_weeks[currentWeek].id] ?? const [],
            today: widget.now(),
            title: _notStarted(p) ? l10n.planDetailFirstWeek : null,
            onSelect: _openWorkout,
          ),
        ],
        // Adherence flags and the re-plan preview stay uncollapsed: a warning
        // that only renders when something is wrong is signal, and the
        // preview exists only after an explicit tap.
        ..._adherenceSection(theme, l10n, p),
        ..._replanSection(theme, l10n, p),
        ..._disclosures(theme, l10n, p, currentWeek),
      ],
    );
  }

  /// What the Today slot says when today has no session: the next one, race
  /// day, or a rest day, so the slot never silently vanishes. Web twin: the
  /// next up / race day / rest day branches on `/plans/[id]`.
  Widget _todayFallback(ThemeData theme, AppLocalizations l10n,
      TrainingPlanRow p, List<PlanWorkoutRow> all) {
    final today = toIsoDate(widget.now());
    final tag = localeToTag(Localizations.localeOf(context));
    final next = (all
            .where((w) =>
                toIsoDate(w.scheduledDate).compareTo(today) > 0 &&
                w.kind != 'rest')
            .toList()
          ..sort((a, b) => a.scheduledDate.compareTo(b.scheduledDate)))
        .firstOrNull;
    final raceToday = planRaceCountdown(
                toIsoDate(p.startDate), toIsoDate(p.endDate), today)
            .kind ==
        PlanRaceCountdownKind.raceDay;

    Widget card({
      required Key key,
      required IconData icon,
      required String label,
      required String title,
      String? meta,
      VoidCallback? onTap,
    }) =>
        Card(
          key: key,
          margin: EdgeInsets.zero,
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.md),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(icon,
                      size: AppIconSize.material,
                      color: theme.colorScheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(label,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            )),
                        Text(title,
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700)),
                        if (meta != null)
                          Text(meta,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              )),
                      ],
                    ),
                  ),
                  if (onTap != null)
                    Icon(Icons.chevron_right,
                        color: theme.colorScheme.onSurfaceVariant),
                ],
              ),
            ),
          ),
        );

    if (raceToday) {
      return card(
        key: const Key('planDetailTodayRaceDay'),
        icon: Icons.emoji_events_outlined,
        label: l10n.planDetailRaceDayTitle,
        title: l10n.planDetailGoAndRunIt,
      );
    }
    final restToday = all.any(
        (w) => w.kind == 'rest' && toIsoDate(w.scheduledDate) == today);
    if (next != null && !restToday) {
      final parts = [
        formatDowDateShort(next.scheduledDate, tag),
        if (next.targetDistanceM != null) fmtKm(next.targetDistanceM),
        if (next.targetPaceSecPerKm != null)
          l10n.todaysWorkoutAtPace(fmtPace(next.targetPaceSecPerKm)),
      ];
      return card(
        key: const Key('planDetailTodayNextUp'),
        icon: Icons.event_available,
        label: l10n.planDetailNextUp,
        title: workoutKindLabel(l10n, workoutKindFromDb(next.kind)),
        meta: parts.join(' · '),
        onTap: () => _openWorkout(next),
      );
    }
    return card(
      key: const Key('planDetailTodayRest'),
      icon: Icons.self_improvement,
      label: l10n.planDetailTodayLabel,
      title: l10n.planDetailRestDayTitle,
      meta: l10n.planDetailRestDayHint,
    );
  }

  List<Widget> _disclosures(ThemeData theme, AppLocalizations l10n,
      TrainingPlanRow p, int currentWeek) {
    final progress = _progressCard(
        theme, l10n, _weeks.isNotEmpty ? _weeks[currentWeek].phase : null);
    final rules = _planRules(p);
    DisclosureSection section(String key, String title, String hint,
            Widget child) =>
        DisclosureSection(
          key: ValueKey('plan-disclosure-$key'),
          title: title,
          hint: hint,
          open: _disclosure[key] ?? true,
          onToggle: (open) => _setDisclosure(key, open),
          child: child,
        );
    return [
      if (progress != null) ...[
        const SizedBox(height: 16),
        section('progress', l10n.planDetailSectionProgressTitle,
            l10n.planDetailSectionProgressHint, progress),
      ],
      if (rules.isNotEmpty) ...[
        const SizedBox(height: 16),
        section('rules', l10n.planDetailSectionRulesTitle,
            l10n.planDetailSectionRulesHint, _rulesCard(theme, rules)),
      ],
      const SizedBox(height: 16),
      section(
        'calendar',
        l10n.planDetailSectionCalendarTitle,
        l10n.planDetailSectionCalendarHint,
        PlanCalendar(
          startDate: p.startDate,
          endDate: p.endDate,
          workouts: _byWeek.values.expand((x) => x).toList(),
          today: widget.now(),
          weekStartDay: activeWeekStartDay(),
          onSelect: _openWorkout,
        ),
      ),
      const SizedBox(height: 16),
      section(
        'weeks',
        l10n.planDetailSectionWeeksTitle,
        l10n.planDetailSectionWeeksHint(_weeks.length),
        _weeksList(theme, l10n, p, currentWeek),
      ),
      if (_isOwner(p) && !p.isTemplate) ...[
        const SizedBox(height: 16),
        section('share', l10n.planDetailSectionShareTitle,
            l10n.planDetailSectionShareHint, _shareCard(theme, l10n, p)),
      ],
    ];
  }

  /// Finished weeks fold into one summary row, so the current week leads the
  /// section instead of sitting eighteen cards down.
  Widget _weeksList(ThemeData theme, AppLocalizations l10n, TrainingPlanRow p,
      int currentWeek) {
    final started = !_notStarted(p);
    final earlier =
        started ? _weeks.where((w) => w.weekIndex < currentWeek).toList() : const <PlanWeekRow>[];
    final rest = _weeks.where((w) => !earlier.contains(w)).toList();
    final earlierWorkouts = [
      for (final w in earlier) ...(_byWeek[w.id] ?? const <PlanWorkoutRow>[]),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (earlier.isNotEmpty) ...[
          Material(
            type: MaterialType.transparency,
            child: InkWell(
              key: const Key('planDetailEarlierWeeks'),
              borderRadius: BorderRadius.circular(AppRadius.md),
              onTap: () =>
                  setState(() => _showEarlierWeeks = !_showEarlierWeeks),
              child: Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                decoration: planCardDecoration(theme),
                child: Row(
                  children: [
                    Expanded(
                      child: Wrap(
                        spacing: 8,
                        children: [
                          Text(l10n.planDetailEarlierWeeks(earlier.length),
                              style: theme.textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w700)),
                          Text(
                              l10n.planDetailWeekDoneCount(
                                  earlierWorkouts
                                      .where(isWorkoutCompleted)
                                      .length,
                                  _activeCount(earlierWorkouts)),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              )),
                        ],
                      ),
                    ),
                    Icon(
                      _showEarlierWeeks ? Icons.expand_less : Icons.expand_more,
                      semanticLabel: _showEarlierWeeks
                          ? l10n.planDetailHideEarlierWeeks
                          : l10n.planDetailShowEarlierWeeks,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                  ],
                ),
              ),
            ),
          ),
          if (_showEarlierWeeks)
            for (final w in earlier) _weekCard(theme, l10n, p, w, currentWeek),
        ],
        for (final w in rest) _weekCard(theme, l10n, p, w, currentWeek),
      ],
    );
  }

  int _activeCount(List<PlanWorkoutRow> workouts) => workouts
      .where((w) => w.kind != 'rest' && !_isWorkoutSkipped(w))
      .length;

  /// `training_plans.rules` is an untyped jsonb column; web renders it as a
  /// list of strings, so anything else is treated as no rules.
  List<String> _planRules(TrainingPlanRow p) {
    final raw = p.rules;
    if (raw is! List) return const [];
    return [
      for (final r in raw)
        if (r is String && r.trim().isNotEmpty) r,
    ];
  }

  Widget _rulesCard(ThemeData theme, List<String> rules) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: planCardDecoration(theme),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < rules.length; i++) ...[
            if (i > 0) const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.check, size: 16, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(rules[i], style: theme.textTheme.bodySmall)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _shareCard(
      ThemeData theme, AppLocalizations l10n, TrainingPlanRow p) {
    final published = _publishedTemplateId != null;
    Widget spinner() => const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: planCardDecoration(theme),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          OutlinedButton.icon(
            onPressed: _publishing ? null : () => _publishToClub(p),
            icon: _publishing ? spinner() : const Icon(Icons.publish, size: 18),
            label: Text(l10n.planDetailPublishTooltip),
          ),
          const SizedBox(height: 12),
          Text(l10n.planDetailPublishLibraryLabel,
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(
            published
                ? l10n.planDetailAlreadyPublished
                : l10n.planDetailPublishLibraryHint,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _libraryBusy
                ? null
                : (published ? _unpublishFromLibrary : () => _publishToLibrary(p)),
            icon: _libraryBusy
                ? spinner()
                : Icon(published ? Icons.public_off : Icons.public, size: 18),
            label: Text(published
                ? l10n.planDetailUnpublishLibrary
                : l10n.planDetailPublishLibrary),
          ),
        ],
      ),
    );
  }

  List<Widget> _adherenceSection(
      ThemeData theme, AppLocalizations l10n, TrainingPlanRow p) {
    final drift = _currentWeekDrift(p);
    final missed = _missedLongRun(p);
    if (drift == null && missed == null) return const [];
    final flags = <Widget>[];
    if (drift != null) {
      final pctOff = (drift.driftFraction.abs() * 100).round();
      flags.add(_adherenceFlag(
        theme,
        Icons.insights,
        drift.direction == DriftDirection.over
            ? l10n.planDetailDriftOverFlag(pctOff)
            : l10n.planDetailDriftUnderFlag(
                fmtKm(drift.actualMetres), fmtKm(drift.plannedMetres)),
      ));
    }
    if (missed != null) {
      final text = missed.reason == MissedWorkoutReason.taper
          ? l10n.planDetailMissedLongTaper
          : missed.reason == MissedWorkoutReason.recoverySoon
              ? l10n.planDetailMissedLongRecovery
              : l10n.planDetailMissedLongMakeUp;
      flags.add(_adherenceFlag(theme, Icons.event_busy, text));
    }
    final warning = (theme.extension<AppSemanticColors>() ??
            (theme.brightness == Brightness.dark
                ? AppSemanticColors.dark
                : AppSemanticColors.light))
        .warning;
    return [
      const SizedBox(height: 12),
      Container(
        key: const Key('planDetailAdherence'),
        padding: const EdgeInsets.all(12),
        decoration: planCardDecoration(theme).copyWith(
          border: Border.all(color: warning),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < flags.length; i++) ...[
              if (i > 0) const SizedBox(height: 8),
              flags[i],
            ],
            if (_isOwner(p) && !p.isTemplate)
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton(
                  key: const Key('planDetailAdherenceAdjust'),
                  onPressed: _bulkBusy ? null : () => _openAdjustPlan(p),
                  child: Text(l10n.planDetailAdjustPlan),
                ),
              ),
          ],
        ),
      ),
    ];
  }

  Widget? _progressCard(
      ThemeData theme, AppLocalizations l10n, String? currentPhase) {
    final phases = _orderedPhases();
    final longest = _longestLongRunMetres();
    if (phases.length <= 1 && longest == null) return null;
    return Container(
        padding: const EdgeInsets.all(12),
        decoration: planCardDecoration(theme),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (phases.length > 1)
              Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (var i = 0; i < phases.length; i++) ...[
                    if (i > 0)
                      Icon(Icons.chevron_right,
                          size: 14, color: theme.colorScheme.outline),
                    Text(
                      planPhaseLabel(l10n, planPhaseFromDb(phases[i]))
                          .toUpperCase(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: phases[i] == currentPhase
                            ? FontWeight.w700
                            : FontWeight.w400,
                        color: phases[i] == currentPhase
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            if (longest != null) ...[
              if (phases.length > 1) const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.trending_up,
                      size: 18, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text('${l10n.planDetailLongestLongRun}: ',
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        )),
                  ),
                  Text(fmtKm(longest),
                      style: theme.textTheme.bodySmall
                          ?.copyWith(fontWeight: FontWeight.w600)),
                ],
              ),
            ],
          ],
        ),
    );
  }

  Widget _adherenceFlag(ThemeData theme, IconData icon, String text) {
    final warning = (theme.extension<AppSemanticColors>() ??
            (theme.brightness == Brightness.dark
                ? AppSemanticColors.dark
                : AppSemanticColors.light))
        .warning;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: AppIconSize.standard, color: warning),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, style: theme.textTheme.bodySmall),
        ),
      ],
    );
  }

  List<Widget> _replanSection(
      ThemeData theme, AppLocalizations l10n, TrainingPlanRow p) {
    if (!_isOwner(p) || p.isTemplate) return const [];
    final preview = _replanPreview;
    final taper = _taperPreview;
    return [
      const SizedBox(height: 12),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: _bulkBusy ? null : () => _openAdjustPlan(p),
          icon: const Icon(Icons.tune, size: 18),
          label: Text(l10n.planDetailAdjustPlan),
        ),
      ),
      if (taper != null) ...[
        SizedBox(key: _taperPreviewKey, height: 10),
        Container(
          key: const Key('planDetailRaceTaperPreview'),
          padding: const EdgeInsets.all(12),
          decoration: planCardDecoration(theme),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.planDetailRaceTaperPreviewTitle,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              for (final c in taper)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextLane(
                        width: 92,
                        child: Text(
                            formatDowDateShort(parseIsoDate(c.scheduledDate),
                                localeToTag(Localizations.localeOf(context))),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            )),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_taperChangeLabel(l10n, c),
                                style: theme.textTheme.bodySmall),
                            if (c.clearsNotes)
                              Text(l10n.planDetailRaceTaperNotesCleared,
                                  key: Key('planDetailRaceTaperNotesCleared-${c.workoutId}'),
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  )),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _bulkBusy
                        ? null
                        : () => setState(() => _taperPreview = null),
                    child: Text(l10n.planDetailReplanCancel),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _bulkBusy ? null : () => _applyRaceTaper(p),
                    child: Text(l10n.planDetailReplanApply),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
      if (preview != null) ...[
        SizedBox(key: _replanPreviewKey, height: 10),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: planCardDecoration(theme),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.planDetailReplanPreviewTitle,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
              if (_adaptiveInfo != null) ...[
                const SizedBox(height: 4),
                Text(_adaptiveBadgeText(l10n),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    )),
              ],
              const SizedBox(height: 8),
              for (final c in preview)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextLane(
                        width: 92,
                        child: Text(
                            formatDowDateShort(parseIsoDate(c.scheduledDate),
                                localeToTag(Localizations.localeOf(context))),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            )),
                      ),
                      Expanded(
                        child: Text(
                          c.reason == ReplanReason.makeUpLong
                              ? l10n.planDetailReplanMakeUp(
                                  fmtKm(c.fromMetres), fmtKm(c.toMetres))
                              : l10n.planDetailReplanEase(
                                  fmtKm(c.fromMetres), fmtKm(c.toMetres)),
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _bulkBusy
                        ? null
                        : () => setState(() {
                              _replanPreview = null;
                              _adaptiveInfo = null;
                            }),
                    child: Text(l10n.planDetailReplanCancel),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _bulkBusy ? null : () => _applyReplan(p),
                    child: Text(l10n.planDetailReplanApply),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    ];
  }

  Widget _heroCard(ThemeData theme, AppLocalizations l10n, TrainingPlanRow p,
      int pct, int done, int total, {PlanRace? heroRace}) {
    final tag = localeToTag(Localizations.localeOf(context));
    final today = toIsoDate(widget.now());
    final goalDistanceM = heroRace != null ? heroRace.distanceM : p.goalDistanceM;
    final goalTimeSec = heroRace != null ? heroRace.goalTimeSec : p.goalTimeSeconds;
    final raceIso = heroRace?.date ?? toIsoDate(p.endDate);
    final countdown =
        planRaceCountdown(toIsoDate(p.startDate), raceIso, today);
    final relation = NextRaceCard.relation(l10n, countdown);
    final notStarted = _notStarted(p);
    final coachId = p.assignedByCoachId;
    final assigned = coachId != null && coachId != _viewerId();
    final pills = <Widget>[
      if (!notStarted && _weeks.isNotEmpty)
        _pill(theme,
            l10n.planDetailWeekOfN(_currentWeekIndex(p) + 1, _weeks.length),
            key: const Key('planDetailWeekOfN')),
      if (relation.isNotEmpty)
        _pill(theme, relation,
            key: const Key('planDetailCountdown'),
            emphasised: countdown.kind == PlanRaceCountdownKind.raceDay),
      if (p.status == 'paused')
        _pill(theme, l10n.planDetailPausedChip,
            key: const Key('planDetailPaused'), icon: Icons.pause),
    ];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: planCardDecoration(theme),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (heroRace != null) ...[
                      Text(
                        l10n.planDetailHeroNextRace(heroRace.name ?? p.name),
                        key: const Key('planDetailHeroNextRace'),
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                    ],
                    Wrap(
                      spacing: 10,
                      runSpacing: 4,
                      children: [
                        if (goalDistanceM != null)
                          _chip(theme, Icons.flag_outlined,
                              fmtKm(goalDistanceM, 1)),
                        if (goalTimeSec != null)
                          _chip(
                              theme,
                              Icons.timer,
                              heroRace != null && goalTimeSec > 0
                                  ? formatRaceGoalTimeS(goalTimeSec)
                                  : fmtHms(goalTimeSec)),
                        if (p.vdot != null)
                          _chip(
                              theme,
                              Icons.trending_up,
                              metricText(l10n, Metric.vdot,
                                  variant: 'value',
                                  args: {
                                    'value': formatFixed(
                                        p.vdot!, 1, activeLocaleTag)
                                  })),
                        _chip(theme, Icons.event,
                            formatDateMed(parseIsoDate(raceIso), tag),
                            key: const Key('planDetailRaceDate')),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${formatDateShort(p.startDate, tag)} → '
                      '${formatDateMed(p.endDate, tag)} · '
                      '${l10n.planDetailDaysPerWeek(p.daysPerWeek)}',
                      key: const Key('planDetailDateRange'),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _progressRing(theme, l10n, pct, done, total),
            ],
          ),
          if (pills.isNotEmpty || assigned) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                ...pills,
                if (assigned)
                  ActionChip(
                    key: const Key('planDetailAssignedBy'),
                    avatar: const Icon(Icons.sports, size: AppIconSize.inline),
                    label: Text(_assigningCoachName != null
                        ? l10n.planDetailAssignedBy(_assigningCoachName!)
                        : l10n.planDetailAssignedByCoach),
                    onPressed: _openCoaching,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _pill(ThemeData theme, String text,
      {Key? key, IconData? icon, bool emphasised = false}) {
    final fg = emphasised
        ? theme.colorScheme.onPrimaryContainer
        : theme.colorScheme.onSurface;
    return Container(
      key: key,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: emphasised
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: AppIconSize.dense, color: fg),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(text,
                style: theme.textTheme.labelMedium
                    ?.copyWith(color: fg, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _chip(ThemeData theme, IconData icon, String text, {Key? key}) {
    return Row(
      key: key,
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: AppIconSize.dense, color: theme.colorScheme.outline),
        const SizedBox(width: 3),
        Text(text, style: theme.textTheme.bodySmall),
      ],
    );
  }

  Widget _progressRing(
      ThemeData theme, AppLocalizations l10n, int pct, int done, int total) {
    final tag = localeToTag(Localizations.localeOf(context));
    return Semantics(
      label: l10n.planDetailWorkoutCompletion,
      value: '${formatPercent(pct / 100, tag)}, $done / $total',
      excludeSemantics: true,
      child: SizedBox(
      width: AppIconSize.hero,
      height: AppIconSize.hero,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: AppIconSize.hero,
            height: AppIconSize.hero,
            child: CircularProgressIndicator(
              value: pct / 100,
              strokeWidth: 5,
              color: theme.colorScheme.primary,
              // `outline` clears 3:1 against the card in both themes, where
              // the divider colour read at about 2.5:1 in dark mode.
              backgroundColor: theme.colorScheme.outline,
            ),
          ),
          // The ring's diameter is fixed by the header layout, so its caption
          // is bounded by the graphic: at 2x OS text scale "100%" over "12/12"
          // needs 144 px and overflowed the 64 px ring by 112. Scaling down
          // keeps both numbers whole and legible where clipping did not.
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(formatPercent(pct / 100, tag),
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
                Text('$done/$total',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    )),
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }

  Widget _weekCard(ThemeData theme, AppLocalizations l10n, TrainingPlanRow p,
      PlanWeekRow w, int currentWeek) {
    final phase = planPhaseFromDb(w.phase);
    final today = toIsoDate(widget.now());
    final workouts = _byWeek[w.id] ?? const <PlanWorkoutRow>[];
    final isCurrent = w.weekIndex == currentWeek && !_notStarted(p);
    return Container(
      key: ValueKey('planDetailWeek-${w.weekIndex}'),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: planCardDecoration(theme, emphasised: isCurrent),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(l10n.planDetailWeek(w.weekIndex + 1),
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(planPhaseLabel(l10n, phase).toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.primary,
                      letterSpacing: 0.6,
                      fontWeight: FontWeight.w700,
                    )),
              ),
              Text(fmtKm(w.targetVolumeM, 0),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  )),
              if (_isOwner(p) && !p.isTemplate)
                PopupMenuButton<_WeekMenu>(
                  key: ValueKey('planDetailWeekMenu-${w.weekIndex}'),
                  tooltip: l10n.planDetailWeekActions(w.weekIndex + 1),
                  enabled: !_bulkBusy,
                  icon: Icon(Icons.more_vert,
                      size: 18, color: theme.colorScheme.outline),
                  onSelected: (a) => switch (a) {
                    _WeekMenu.duplicate => _duplicateWeek(p, w),
                    _WeekMenu.recovery => _markWeekRecovery(p, w),
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                        value: _WeekMenu.duplicate,
                        child: Text(l10n.planDetailDuplicateWeek)),
                    PopupMenuItem(
                        value: _WeekMenu.recovery,
                        child: Text(l10n.planDetailMarkRecovery)),
                  ],
                ),
            ],
          ),
          Text(
              l10n.planDetailWeekDoneCount(
                  workouts.where(isWorkoutCompleted).length,
                  _activeCount(workouts)),
              key: ValueKey('planDetailWeekCount-${w.weekIndex}'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              )),
          if (w.notes != null && w.notes!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(w.notes!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  )),
            ),
          const SizedBox(height: 8),
          for (final wo in workouts)
            _workoutRow(theme, l10n, p, wo, today),
        ],
      ),
    );
  }

  Widget _workoutRow(ThemeData theme, AppLocalizations l10n, TrainingPlanRow p,
      PlanWorkoutRow wo, String today) {
    final kind = workoutKindFromDb(wo.kind);
    final isRest = kind == WorkoutKind.rest;
    final status = planWorkoutStatusOf(wo, today);
    final look = planWorkoutStatusLook(theme, status);
    final isSkipped = status == PlanWorkoutStatus.skipped;
    final isToday = toIsoDate(wo.scheduledDate) == today;
    final tag = localeToTag(Localizations.localeOf(context));
    final dow = formatDow(wo.scheduledDate, tag);
    final radius = BorderRadius.circular(AppRadius.sm);
    Widget row = Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      decoration: BoxDecoration(
        color: look.fill,
        borderRadius: radius,
        border: Border.all(
          color: isToday
              ? theme.colorScheme.primary
              // An upcoming row draws no box of its own inside the week card;
              // only a state (done, missed) earns an outline.
              : look.dashed
                  ? Colors.transparent
                  : (look.outline ?? Colors.transparent),
          width: isToday ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          // The today row's outline is what says "today"; the dot and the
          // weight repeat it for a reader who cannot tell the outline apart.
          SizedBox(
            width: 12,
            child: isToday
                ? Icon(Icons.circle, size: 6, color: theme.colorScheme.primary)
                : null,
          ),
          TextLane(
              width: 34,
              child: Text(dow,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: isToday ? FontWeight.w700 : null,
                  ))),
          Expanded(
            child: Text(
              workoutKindLabel(l10n, kind),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: (isRest || isSkipped)
                    ? theme.colorScheme.onSurfaceVariant
                    : null,
                fontWeight: isRest ? FontWeight.w400 : FontWeight.w600,
                decoration: isSkipped ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
          if (wo.targetDistanceM != null && !isRest) ...[
            Text(fmtKm(wo.targetDistanceM, 1),
                style: theme.textTheme.bodySmall),
            const SizedBox(width: 6),
          ],
          if (look.glyph != null)
            Icon(look.glyph, color: look.glyphColor, size: AppIconSize.inline),
        ],
      ),
    );
    if (look.dashed && !isToday) {
      row = CustomPaint(
        foregroundPainter: _TopInsetDashedOutline(look.outline!),
        child: row,
      );
    }
    final label = planWorkoutSemanticsLabel(
      l10n,
      wo,
      today,
      day: formatDowDateShort(wo.scheduledDate, tag),
      kind: workoutKindLabel(l10n, kind),
      distance:
          wo.targetDistanceM != null && !isRest ? fmtKm(wo.targetDistanceM, 1) : null,
    );
    return Row(
      key: ValueKey('planDetailWorkoutRow-${wo.id}'),
      children: [
        Expanded(
          child: Semantics(
            button: !isRest,
            label: label,
            excludeSemantics: true,
            child: InkWell(
              onTap: isRest ? null : () => _openWorkout(wo),
              onLongPress: _canEditWorkouts(p) ? () => _editWorkout(wo) : null,
              borderRadius: radius,
              child: row,
            ),
          ),
        ),
        // Inline edit affordance — discoverable button alongside the
        // long-press gesture. Hidden on rest days; nothing to edit.
        if (!isRest && _canEditWorkouts(p))
          IconButton(
            iconSize: AppIconSize.inline,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            tooltip: l10n.planDetailEditTooltip,
            icon: Icon(Icons.edit_outlined, color: theme.colorScheme.outline),
            onPressed: () => _editWorkout(wo),
          ),
      ],
    );
  }

  /// The days [wo] may move to (decisions § 2073); only the owner moves.
  List<WorkoutMoveDay> _moveDaysFor(PlanWorkoutRow wo) {
    final plan = _plan;
    if (plan == null || !_isOwner(plan)) return const [];
    final week = _weeks.where((w) => w.id == wo.weekId).firstOrNull;
    if (week == null) return const [];
    return workoutMoveDays(
      planStartIso: toIsoDate(plan.startDate),
      planEndIso: toIsoDate(plan.endDate),
      weekIndex: week.weekIndex,
      workout: wo,
      workouts: _byWeek[wo.weekId] ?? const [],
      todayIso: toIsoDate(widget.now()),
    );
  }

  Future<void> _editWorkout(PlanWorkoutRow wo) async {
    final ok = await showWorkoutEditSheet(
      context,
      workout: wo,
      training: widget.training,
      moveDays: _moveDaysFor(wo),
    );
    if (ok) await _load();
  }

  /// Push WorkoutDetailScreen, then either kick the structured runner
  /// (when the user tapped Start) or just refresh the plan. The runner
  /// lives on the Run tab — popping back to root and signalling
  /// `pendingStartWorkout` lets HomeScreen switch tabs and RunScreen
  /// load the workout.
  Future<void> _openWorkout(PlanWorkoutRow wo) async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute<PlanWorkoutRow?>(
        builder: (_) => WorkoutDetailScreen(
          training: widget.training,
          planId: widget.planId,
          workoutId: wo.id,
          initial: wo,
        ),
      ),
    );
    if (!mounted) return;
    if (result != null) {
      _startWorkout(result);
      return;
    }
    _load();
  }

  void _startWorkout(PlanWorkoutRow wo) {
    pendingStartWorkout.value = wo;
    Navigator.of(context).popUntil((r) => r.isFirst);
  }
}

enum _PlanDetailLoadError { timeout, offline, generic }

// A workout row carries a 4 dp top margin, so the dash is drawn below it.
class _TopInsetDashedOutline extends CustomPainter {
  final Color color;
  const _TopInsetDashedOutline(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(0, 4);
    DashedOutlinePainter(color: color)
        .paint(canvas, Size(size.width, size.height - 4));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_TopInsetDashedOutline old) => old.color != color;
}

/// Modal that lists the viewer's admin-able clubs and pops the picked
/// club id (or `null` on cancel). Pure presentation — the parent does
/// the fetch + commit so cancel doesn't leave a half-state.
class PublishClubPicker extends StatelessWidget {
  final List<ClubView> clubs;
  const PublishClubPicker({super.key, required this.clubs});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.planDetailPublishPickerTitle,
                style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              l10n.planDetailPublishPickerBody,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: clubs.length,
                itemBuilder: (_, i) {
                  final c = clubs[i];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.group),
                    title: Text(c.row.name),
                    subtitle: Text(
                      '${c.row.locationLabel ?? c.row.slug} · '
                      '${l10n.planDetailPublishPickerMembers(c.memberCount)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.pop(context, c.row.id),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(l10n.planDetailPublishCancel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _PlanMenu {
  adjust,
  editDetails,
  shift,
  raceDate,
  exportMarkdown,
  exportJson,
  restart,
  coach,
  abandon,
  delete,
}

/// Picks the restarted copy's start date and confirms the restart. Pops the
/// start date, or nothing on cancel. A plan with a race still ahead gets the
/// refusal and no confirm (`upcomingRaceIso`).
class _RestartPlanDialog extends StatefulWidget {
  final TrainingPlanRow plan;
  final List<RestartWorkout> workouts;
  final String todayIso;

  const _RestartPlanDialog({
    required this.plan,
    required this.workouts,
    required this.todayIso,
  });

  @override
  State<_RestartPlanDialog> createState() => _RestartPlanDialogState();
}

class _RestartPlanDialogState extends State<_RestartPlanDialog> {
  late final String _sourceStart = toIsoDate(widget.plan.startDate);
  late final bool _walkRun = isWalkRunPlan(widget.workouts);
  late String _start =
      defaultRestartStartIso(_sourceStart, widget.todayIso, _walkRun);

  Future<void> _pickDate() async {
    final today = parseIsoDate(widget.todayIso);
    final picked = await showDatePicker(
      context: context,
      initialDate: parseIsoDate(_start),
      firstDate: today,
      lastDate: DateTime(today.year + 2, today.month, today.day),
      selectableDayPredicate: (d) => restartStartAllowed(
          toIsoDate(d), _sourceStart, widget.todayIso, _walkRun),
    );
    if (picked == null || !mounted) return;
    setState(() => _start =
        alignRestartStartIso(toIsoDate(picked), _sourceStart, _walkRun));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tag = localeToTag(Localizations.localeOf(context));
    String fmt(String iso) => formatDateShort(parseIsoDate(iso), tag);
    final raceAhead = upcomingRaceIso(widget.workouts, widget.todayIso);
    if (raceAhead != null) {
      return AlertDialog(
        title: Text(l10n.planDetailRestartTitle),
        content: Text(l10n.planDetailRestartRaceAhead(fmt(raceAhead))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.plansCancel),
          ),
        ],
      );
    }
    final end = restartedDateIso(
        toIsoDate(widget.plan.endDate), _sourceStart, _start);
    final races = [
      for (final w in widget.workouts)
        if (w.kind == 'race') w.scheduledDate
    ]..sort();
    final live =
        widget.plan.status == 'active' || widget.plan.status == 'paused';
    final message = live
        ? l10n.planDetailRestartConfirmLive(fmt(_start), fmt(end))
        : l10n.planDetailRestartConfirmOver(fmt(_start), fmt(end));
    final raceLine = races.isEmpty
        ? ''
        : ' ${l10n.planDetailRestartRaceMoves(fmt(restartedDateIso(races.last, _sourceStart, _start)))}';
    return AlertDialog(
      title: Text(l10n.planDetailRestartTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$message$raceLine', key: const Key('planDetailRestartMessage')),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            key: const Key('planDetailRestartPickDate'),
            onPressed: _pickDate,
            icon: const Icon(Icons.event),
            label: Text(l10n.planDetailRestartChangeDate),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.plansCancel),
        ),
        FilledButton(
          key: const Key('planDetailRestartConfirm'),
          onPressed: () => Navigator.pop(context, _start),
          child: Text(l10n.planDetailRestartConfirm),
        ),
      ],
    );
  }
}

enum _WeekMenu { duplicate, recovery }

/// Asks how many days to move the plan by. Pops the signed day count, or
/// nothing on cancel. The RPC's own bound is ±366 and zero is a no-op.
class _ShiftDatesDialog extends StatefulWidget {
  const _ShiftDatesDialog();

  @override
  State<_ShiftDatesDialog> createState() => _ShiftDatesDialogState();
}

class _ShiftDatesDialogState extends State<_ShiftDatesDialog> {
  final _ctrl = TextEditingController(text: '7');
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final n = int.tryParse(_ctrl.text.trim());
    if (n == null || n == 0 || n.abs() > 366) {
      setState(() => _error = AppLocalizations.of(context).planDetailShiftDaysInvalid);
      return;
    }
    Navigator.pop(context, n);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.planDetailShiftTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.planDetailShiftMessage),
          const SizedBox(height: 12),
          TextField(
            key: const Key('planDetailShiftDays'),
            controller: _ctrl,
            autofocus: true,
            keyboardType:
                const TextInputType.numberWithOptions(signed: true),
            decoration: InputDecoration(
              labelText: l10n.planDetailShiftDaysLabel,
              errorText: _error,
              errorMaxLines: 3,
            ),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.plansCancel),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(l10n.planDetailShiftApply),
        ),
      ],
    );
  }
}
