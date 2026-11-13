import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:ui_kit/ui_kit.dart'
    show AppInsets, AppSemanticColors, AppSpace, ChartCardHeader, ListCard, ProgressBar, SectionHeader;

import '../adaptive_width.dart';
import '../age_grade.dart';
import '../current_week.dart' show WeekStart;
import '../dashboard_layout.dart' show parseHiddenCards, withCardHidden;
import '../device_timezone.dart';
import '../disclosure.dart';
import '../disclosure_state.dart';
import '../goals.dart';
import '../health_consent.dart';
import '../hr_prescription_gate.dart';
import '../l10n/date_format.dart' show formatDowDateShort;
import '../l10n/gen/app_localizations.dart';
import '../l10n/locale_support.dart' show activeLocaleTag;
import '../local_gym_store.dart';
import '../local_route_store.dart';
import '../local_run_store.dart';
import '../metrics.dart';
import '../preferences.dart';
import '../run_intensity.dart';
import '../run_stats.dart';
import '../settings_destination.dart';
import '../settings_sync.dart';
import '../streak_card.dart';
import '../streaks.dart';
import '../training.dart' show parseIsoDate, workoutKindFromDb;
import '../training_labels.dart' show workoutKindLabel;
import '../training_load.dart';
import '../training_load_inputs.dart';
import '../plan_ramp.dart' show RunForVolume;
import '../training_service.dart';
import '../week_lead.dart';
import '../widgets/comeback_card.dart';
import '../widgets/disclosure_section.dart';
import '../widgets/finish_plan_card.dart';
import '../widgets/fitness_card.dart';
import '../widgets/goal_editor_sheet.dart';
import '../widgets/intensity_card.dart';
import '../widgets/load_ramp_card.dart';
import '../widgets/metric_label.dart';
import '../widgets/mileage_trend_card.dart';
import '../widgets/race_predictor_card.dart';
import '../widgets/recent_lifts_card.dart';
import '../widgets/top_banner.dart';
import '../widgets/training_load_chart.dart';
import '../workout_summary.dart' show plannedWorkoutSize;
import '../workout_summary_format.dart' show formatPlannedSize;
import '../fitness_surface_requests.dart';
import 'gym_detail_screen.dart';
import 'gym_screen.dart';
import 'period_summary_screen.dart';
import 'recap_screen.dart';
import 'workout_detail_screen.dart';

const _kSectionGap = SizedBox(height: AppInsets.sectionGap);
const _kPagePadding = EdgeInsets.fromLTRB(
    AppInsets.gutter, AppInsets.pageTop, AppInsets.gutter, AppSpace.md);

/// The trend groups on the Progress page: each folds to its one-line heading,
/// remembered per account on this device. Every default is open (decisions
/// § 2080). The scope keeps its `dashboard_trends` name, so a fold a runner
/// made on Home before the groups moved here is still the fold they see. Web
/// twin: `/dashboard`'s `TREND_DEFAULTS`.
const String _kTrendScope = 'dashboard_trends';
const DisclosureState _kTrendDefaults = {
  'volume': true,
  'fitness': true,
  'performance': true,
  'effort': true,
  'recent': true,
};

/// Metres for each best-effort PB label (both the offline track-scan keys and
/// the server `personal_records` labels). Used to age-grade a timed PB via the
/// shared `ageGradeForRun` helper — non-standard distances simply yield no
/// grade (matchStandardDistance returns null).
const _pbLabelMetres = <String, double>{
  'Mile': 1609.344,
  '1 mi': 1609.344,
  '1 km': 1000,
  '5 km': 5000,
  '8 km': 8000,
  '10 km': 10000,
  '12 km': 12000,
  'Half Marathon': 21097,
  'Marathon': 42195,
};

/// Wider than [kContentMaxWidth] because the expanded page is a two-column
/// composition (mirrors web /dashboard), not a reading column.
const double _kExpandedMaxWidth = 1100;

/// Everything about how the runner is doing over time: this week against its
/// yardstick, goals, the month and all-time totals with the recap, the
/// streak, and the trend groups (volume, fitness and form, performance,
/// effort, recent lifts). Pushed one tap from Today's progress summary card
/// (issue #1374): Home used to carry all of it under a Trends divider, up to
/// eighteen blocks, so what to do today sat above a long scroll of stats.
class ProgressScreen extends StatefulWidget {
  final ApiClient? apiClient;
  final TrainingService? training;
  final LocalRunStore runStore;
  final LocalRouteStore routeStore;
  final LocalGymStore gymStore;
  final Preferences preferences;
  final SettingsSyncService? settingsSync;

  const ProgressScreen({
    super.key,
    this.apiClient,
    this.training,
    required this.runStore,
    required this.routeStore,
    required this.gymStore,
    required this.preferences,
    this.settingsSync,
  });

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> {
  /// Memoised fastest-5k window per run id; rescanning every resident track
  /// on each rebuild is the app's hottest loop. Cleared when the store moves.
  final Map<String, Map<double, Duration?>> _bestEffortCache = {};

  /// The active plan, for the week lead's yardstick and next session and for
  /// the goals that count plan sessions. Null without one or until read.
  ActivePlanOverview? _planOverview;

  /// Authoritative all-history personal records from the server cache; empty
  /// offline or signed out, when the track scan over resident runs stands in.
  List<PersonalRecordRow> _serverPbs = const [];

  /// DOB + sex for the PB rows' age grade. Null until read; the grade then
  /// simply doesn't render.
  UserProfileRow? _viewerProfile;

  /// The `run_streaks_for_user` row (decisions § 471 / § 475). Null until
  /// read, offline or signed out; the card then suppresses its all-time
  /// claim rather than dressing the local figure up as one.
  RunStreaks? _allTimeStreaks;

  DisclosureState _trendOpen = Map.of(_kTrendDefaults);

  /// This visit's hide, ahead of the settings bag catching up.
  List<String>? _hiddenCardsLocal;

  /// Set once the reader toggles a group, so a slow first read can't undo it.
  bool _trendTouched = false;

  /// This visit's toggle of the "Training load" expander, ahead of the
  /// settings bag catching up, and in place of it when the write is refused.
  bool? _trainingLoadExpandedLocal;

  @override
  void initState() {
    super.initState();
    widget.runStore.addListener(_onRunStoreChanged);
    widget.preferences.addListener(_onChange);
    widget.gymStore.addListener(_onChange);
    widget.settingsSync?.addListener(_onSettingsChange);
    widget.training?.addListener(_refreshPlanOverview);
    _refreshAll();
    _loadTrendOpen();
  }

  @override
  void dispose() {
    widget.runStore.removeListener(_onRunStoreChanged);
    widget.preferences.removeListener(_onChange);
    widget.gymStore.removeListener(_onChange);
    widget.settingsSync?.removeListener(_onSettingsChange);
    widget.training?.removeListener(_refreshPlanOverview);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  void _onRunStoreChanged() {
    _bestEffortCache.clear();
    _onChange();
  }

  /// The bag moved (Settings restored a group, another device synced), so it
  /// is the truth again rather than this visit's copy.
  void _onSettingsChange() {
    if (!mounted) return;
    setState(() => _hiddenCardsLocal = null);
  }

  /// Every loader, in parallel. Each degrades on its own (L4): a failed read
  /// leaves its card on the fallback it already had.
  Future<void> _refreshAll() async {
    try {
      await Future.wait([
        _refreshPlanOverview(),
        _loadPersonalRecords(),
        _loadViewerProfile(),
        _loadRunStreaks(),
      ]);
    } catch (e) {
      debugPrint('progress refresh failed: $e');
    }
  }

  Future<void> _refreshPlanOverview() async {
    final svc = widget.training;
    if (svc == null) return;
    try {
      final overview = await svc.fetchActiveOverview();
      if (mounted) setState(() => _planOverview = overview);
    } catch (e) {
      debugPrint('progress: plan-overview fetch failed: $e');
    }
  }

  Future<void> _loadPersonalRecords() async {
    final api = widget.apiClient;
    if (api == null) return;
    try {
      final pbs = await api.fetchPersonalRecords();
      if (mounted) setState(() => _serverPbs = pbs);
    } catch (e) {
      debugPrint('progress: personal_records fetch failed: $e');
    }
  }

  Future<void> _loadViewerProfile() async {
    final api = widget.apiClient;
    if (api == null) return;
    try {
      final p = await api.fetchMyProfile();
      if (mounted) setState(() => _viewerProfile = p);
    } catch (e) {
      debugPrint('progress: profile fetch failed: $e');
    }
  }

  /// Signed out must not call the SECURITY INVOKER RPC at all; the device's
  /// IANA zone rides along so the server buckets days like the local compute.
  Future<void> _loadRunStreaks() async {
    final api = widget.apiClient;
    if (api == null || api.userId == null) return;
    final tz = await deviceIanaTimeZone();
    final row = await api.fetchRunStreaks(tz: tz);
    if (row == null || !mounted) return;
    setState(() =>
        _allTimeStreaks = RunStreaks(current: row.current, best: row.best));
  }

  Future<void> _loadTrendOpen() async {
    final stored = await readDisclosureState(
        _kTrendScope, widget.apiClient?.userId, _kTrendDefaults);
    if (!mounted || _trendTouched) return;
    setState(() => _trendOpen = stored);
  }

  /// Trend groups the runner hid (`dashboard_hidden_cards`, universal,
  /// decisions § 2386). An unreadable bag hides nothing.
  List<String> get _hiddenCards {
    final local = _hiddenCardsLocal;
    if (local != null) return local;
    try {
      return parseHiddenCards(widget.settingsSync?.service
          ?.effective<Object>(SettingsKeys.dashboardHiddenCards));
    } catch (e) {
      debugPrint('progress: hidden cards read failed: $e');
      return const [];
    }
  }

  /// Hiding is honestly reversible (Progress cards on the Units & display
  /// page brings a group back), so there is no confirm; the banner's action
  /// opens that page. A refused write
  /// puts the group back rather than leaving the page and the bag disagreeing.
  Future<void> _hideTrendGroup(String id, String title) async {
    final l10n = AppLocalizations.of(context);
    final previous = _hiddenCards;
    final next = withCardHidden(previous, id, true);
    setState(() => _hiddenCardsLocal = next);
    try {
      await widget.settingsSync
          ?.updateUniversal({SettingsKeys.dashboardHiddenCards: next});
      if (!mounted) return;
      showTopBanner(
        context,
        l10n.dashboardCardHidden(title),
        actionLabel: l10n.dashboardCardHiddenAction,
        onAction: () => openSettings(SettingsDestination.display),
      );
    } catch (e) {
      debugPrint('progress: hiding $id not saved: $e');
      if (!mounted) return;
      setState(() => _hiddenCardsLocal = previous);
      showTopBanner(context, l10n.dashboardHideCardFailed);
    }
  }

  void _setTrendOpen(String key, bool open) {
    if (_trendOpen[key] == open) return;
    _trendTouched = true;
    setState(() => _trendOpen = {..._trendOpen, key: open});
    unawaited(writeDisclosureState(
        _kTrendScope, widget.apiClient?.userId, _trendOpen));
  }

  /// How much of the trend section opens up before the runner asks for more
  /// (web `/dashboard`'s `disclosure`). An unreadable bag falls to the
  /// derivation from history alone rather than to a guess.
  String _disclosureLevel(int runCount) {
    Object? stored;
    String? goal;
    try {
      final service = widget.settingsSync?.service;
      stored = service?.effective<Object>(disclosureLevelKey);
      final g = service?.effective<Object>(SettingsKeys.primaryGoal);
      goal = g is String ? g : null;
    } catch (e) {
      debugPrint('progress: disclosure level read failed: $e');
    }
    return resolveDisclosureLevel(stored, goal, runCount);
  }

  /// Absent or non-bool reads as closed: the fold is what `simple` asked for,
  /// so an unreadable bag must not silently re-open it.
  bool get _trainingLoadExpanded {
    final local = _trainingLoadExpandedLocal;
    if (local != null) return local;
    try {
      return widget.settingsSync?.service
              ?.effective<Object>(SettingsKeys.dashboardTrainingLoadExpanded) ==
          true;
    } catch (e) {
      debugPrint('progress: training-load expander read failed: $e');
      return false;
    }
  }

  /// Remembering the expander is auxiliary (L4): the section is open for this
  /// visit either way, so a refused write is logged rather than bannered.
  Future<void> _setTrainingLoadExpanded(bool open) async {
    if (_trainingLoadExpanded == open) return;
    setState(() => _trainingLoadExpandedLocal = open);
    try {
      await widget.settingsSync?.updateUniversal(
          {SettingsKeys.dashboardTrainingLoadExpanded: open});
    } catch (e) {
      debugPrint('progress: training-load expander state not saved: $e');
    }
  }

  /// Age grade (e.g. `72.4%`) for a timed best-effort PB, or null when the
  /// distance isn't a graded standard or the viewer's DOB/sex is unknown.
  String? _pbAgeGrade(String label, Duration time, DateTime now,
      {DateTime? achievedAt}) {
    final metres = _pbLabelMetres[label];
    if (metres == null) return null;
    final p = _viewerProfile;
    final result = ageGradeForRun(
      distanceM: metres,
      durationSec: time.inSeconds.toDouble(),
      // Age grading is an Art 9 use of the age record, which carries no
      // consent term of its own (§ 718 / § 722).
      dobIso: healthUseDob(p),
      runStartIso: (achievedAt ?? now).toIso8601String(),
      sex: p?.gender,
    );
    return result != null ? formatAgeGradePercent(result.percent) : null;
  }

  String get _weekStartDay => weekStartDayOf(widget.settingsSync);

  bool get _gymShown => widget.preferences
      .gymShown(hasData: widget.gymStore.workouts.isNotEmpty);

  /// The shown plan's dates have run out but the runner has not filed it.
  bool _planFinished(DateTime now) {
    final p = _planOverview;
    return p != null &&
        FinishPlanCard.shows(
            status: p.plan.status, endDate: p.plan.endDate, now: now);
  }

  void _openPeriodSummary(PeriodType period, [DateTime? anchor]) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PeriodSummaryScreen(
          initialPeriod: period,
          initialAnchor: anchor ?? DateTime.now(),
          runStore: widget.runStore,
          routeStore: widget.routeStore,
          preferences: widget.preferences,
          settingsSync: widget.settingsSync,
        ),
      ),
    );
  }

  void _openPlanSession(LeadPlanWorkout w) {
    final svc = widget.training;
    final p = _planOverview;
    final id = w.id;
    if (svc == null || p == null || id == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => WorkoutDetailScreen(
          training: svc,
          planId: p.plan.id,
          workoutId: id,
          initial: p.workouts.where((wo) => wo.id == id).firstOrNull,
        ),
      ),
    );
  }

  /// The Fitness hub's own Gym tab, not a second copy pushed over this page
  /// (decisions § 1654, § 2437): the hub is the one Gym screen.
  Future<void> _openGym() => openFitnessSurface(
        context,
        FitnessTab.gym,
        fallback: () =>
            GymScreen(api: widget.apiClient, store: widget.gymStore),
      );

  void _openGymWorkout(String workoutId) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => GymDetailScreen(
        api: widget.apiClient,
        store: widget.gymStore,
        workoutId: workoutId,
      ),
    ));
  }

  /// audit/accessibility — WCAG 4.1.3 (Status Messages): the goal list
  /// updates without moving focus, so the change is announced.
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

  Future<void> _editGoal(RunGoal goal) async {
    final msg = await showGoalEditorSheet(
      context,
      preferences: widget.preferences,
      settingsSync: widget.settingsSync,
      existing: goal,
    );
    if (msg != null) _announceA11yState(msg);
  }

  Widget _weekLeadCard(
      List<Run> runs, List<RunGoal> goals, DistanceUnit unit, DateTime now) {
    // A finished plan has no sessions left to offer; Today asks to file it
    // instead (FinishPlanCard), so the lead says nothing about the plan.
    final planWorkouts =
        _planFinished(now) ? null : leadPlanWorkoutsOf(_planOverview);
    final lead = weekLead(
      activities: [
        for (final r in runs)
          LeadActivity(
            startedAt: r.startedAt.toIso8601String(),
            distanceM: r.distanceMetres,
          ),
      ],
      planWorkouts: planWorkouts,
      weeklyGoal: weeklyGoalTarget(goals),
      weekStart:
          _weekStartDay == 'sunday' ? WeekStart.sunday : WeekStart.monday,
      now: now,
    );
    return _DashboardWeekLead(
      key: const Key('dashboardWeekLead'),
      onOpenWeek: () => _openPeriodSummary(PeriodType.week),
      lead: lead,
      hasPlan: planWorkouts != null,
      unit: unit,
      onOpenSession: _openPlanSession,
    );
  }

  Widget _buildTrainingLoadChart(
      List<Run> runs, List<TrainingLoadPoint> series) {
    final prefs = hrPrefsOf(widget.settingsSync);
    final hasHr = hasTrimpSignal(runs, prefs);
    final medicationAffected = widget.settingsSync?.service
            ?.effective<bool>(SettingsKeys.hrMedicationAffected) ==
        true;
    return TrainingLoadChart(
      points: series,
      hasHr: hasHr,
      includesLifts: series.any((p) => p.liftStress > 0),
      lowConfidence:
          hrPrescriptionGate && isTrimpLowConfidence(hasHr, medicationAffected),
    );
  }

  /// True when a logged lift lands inside the ~fatigue-relevant window, so the
  /// "factored in" / "excluded" note only shows when gym is actually relevant.
  bool _hasRecentLift(DateTime now) {
    final cutoff = now.toUtc().subtract(const Duration(days: 14));
    for (final w in widget.gymStore.workouts) {
      if (w.isTombstone) continue;
      final at = w.startedAt;
      if (at != null && !at.toUtc().isBefore(cutoff)) return true;
    }
    return false;
  }

  Widget _gymReadinessNote(ThemeData theme, AppLocalizations l10n) {
    final excluded = excludesGymFromReadiness(widget.settingsSync);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.sm),
      child: Row(
        children: [
          Icon(Icons.fitness_center,
              size: 16, color: theme.colorScheme.outline),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              excluded
                  ? l10n.dashGymReadinessExcluded
                  : l10n.dashGymReadinessIncluded,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }

  Widget _goalsSection(
    DistanceUnit unit,
    List<Run> runs,
    List<RunGoal> goals,
    DateTime now,
  ) {
    final l10n = AppLocalizations.of(context);
    final planWorkouts =
        leadPlanWorkoutsOf(_planOverview) ?? const <LeadPlanWorkout>[];
    return Column(
      key: const Key('progressGoals'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          label: l10n.dashboardGoals,
          trailing: goals.isNotEmpty
              ? TextButton.icon(
                  key: const Key('progressAddGoal'),
                  onPressed: _newGoal,
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(l10n.dashboardAdd),
                )
              : null,
        ),
        const SizedBox(height: AppSpace.xs),
        if (goals.isEmpty)
          _EmptyGoalsCta(onAdd: _newGoal)
        else
          for (final goal in goals)
            _GoalCard(
              goal: goal,
              progress: evaluateGoal(goal, runs, now,
                  weekStartDay: _weekStartDay, planWorkouts: planWorkouts),
              unit: unit,
              onTap: () => _editGoal(goal),
            ),
      ],
    );
  }

  /// Personal-best cards are running-only. Cycles, walks, and hikes have
  /// their own pace/distance scales and would otherwise starve the run PBs.
  /// Legacy runs with no `activity_type` in metadata default to run.
  static bool _isRunActivity(Run r) {
    final raw = r.metadata?['activity_type'] as String?;
    return raw == null || raw == 'run';
  }

  static String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final unit = widget.preferences.unit;
    // Stats + cards read the full-history index (track-less). Only the offline
    // PB fallback below needs GPS tracks, and it scans the resident window.
    final runs = widget.runStore.summaryRuns;
    final goals = widget.preferences.goals;
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);
    final loadSeries = trainingLoadSeriesFor(runs, now,
        gymStore: widget.gymStore, settingsSync: widget.settingsSync);
    final hrPrefs = hrPrefsOf(widget.settingsSync);

    // One pass over the runs collects the month and all-time totals and the
    // longest run. Matters at 10k+ runs.
    var monthRunCount = 0;
    var monthDistance = 0.0;
    var monthVert = 0.0;
    var allDistance = 0.0;
    var allVert = 0.0;
    Run? longest;
    const pbDistances = <String, double>{
      '5 km': 5000,
      '10 km': 10000,
      'Half Marathon': 21097,
      'Marathon': 42195,
    };
    final bestEfforts = <String, Duration>{};
    for (final r in runs) {
      allDistance += r.distanceMetres;
      final vert = runVertMetres(r);
      allVert += vert;
      if (!r.startedAt.isBefore(monthStart)) {
        monthRunCount++;
        monthDistance += r.distanceMetres;
        monthVert += vert;
      }
      if (!_isRunActivity(r)) continue;
      if (longest == null || r.distanceMetres > longest.distanceMetres) {
        longest = r;
      }
    }
    // Offline / signed-out best-effort fallback: scan the resident runs' GPS
    // tracks. Skipped when the authoritative server PB cache is present.
    if (_serverPbs.isEmpty) {
      for (final r in widget.runStore.runs) {
        if (!_isRunActivity(r)) continue;
        final runCache = _bestEffortCache.putIfAbsent(r.id, () => {});
        for (final e in pbDistances.entries) {
          if (r.distanceMetres < e.value) continue;
          final cached = runCache.putIfAbsent(
              e.value, () => fastestWindowOf(trackLine(r.track), e.value));
          if (cached != null &&
              (!bestEfforts.containsKey(e.key) ||
                  cached < bestEfforts[e.key]!)) {
            bestEfforts[e.key] = cached;
          }
        }
      }
    }
    final displayEfforts = _serverPbs.isNotEmpty
        ? bestEffortsFromPersonalRecords(_serverPbs)
        : bestEfforts;
    final pbDates = _serverPbs.isNotEmpty
        ? pbAchievedAtByLabel(_serverPbs)
        : const <String, DateTime>{};
    final hasAnyPb = longest != null || displayEfforts.isNotEmpty;
    final api = widget.apiClient;

    final weekLeadCard =
        runs.isNotEmpty ? _weekLeadCard(runs, goals, unit, now) : null;
    // An empty-goals card earns its slot on a new account, not on visit 200:
    // once there is a run it shrinks to a one-line link under the totals.
    final goalsSection = goals.isEmpty && runs.isNotEmpty
        ? null
        : _goalsSection(unit, runs, goals, now);
    // Month and all-time. The week is the week lead's alone (decisions
    // § 2283); its chevron opens the weekly summary.
    final periodRow = Row(
      children: [
        Expanded(
          child: _PeriodStatCard(
            label: l10n.dashboardPeriodMonth,
            distanceMetres: monthDistance,
            runCount: monthRunCount,
            vertMetres: monthVert,
            unit: unit,
            onTap: () => _openPeriodSummary(PeriodType.month),
          ),
        ),
        const SizedBox(width: AppSpace.sm),
        Expanded(
          child: _PeriodStatCard(
            label: l10n.dashboardPeriodAllTime,
            distanceMetres: allDistance,
            runCount: runs.length,
            vertMetres: allVert,
            unit: unit,
            onTap: () => _openPeriodSummary(PeriodType.all),
          ),
        ),
      ],
    );
    // A labelled link under the period cards it summarises (#666 I8).
    final recapButton = api == null
        ? null
        : TextButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => RecapScreen(
                  runStore: widget.runStore,
                  preferences: widget.preferences,
                  api: api,
                ),
              ),
            ),
            icon: const Icon(Icons.auto_awesome, size: 18),
            label: Text(l10n.dashboardRecapTooltip),
          );
    final addGoalButton = goalsSection != null
        ? null
        : TextButton.icon(
            key: const Key('dashboardAddGoalLink'),
            onPressed: _newGoal,
            icon: const Icon(Icons.flag_outlined, size: 18),
            label: Text(l10n.dashboardSetGoal),
          );
    // A Wrap rather than a Row, so the two labels take a line each in a
    // locale too long to fit both rather than overflowing.
    final periodLinks = addGoalButton != null || recapButton != null
        ? Wrap(
            alignment: addGoalButton != null && recapButton != null
                ? WrapAlignment.spaceBetween
                : addGoalButton != null
                    ? WrapAlignment.start
                    : WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [?addGoalButton, ?recapButton],
          )
        : null;
    final streakCard = ListCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ChartCardHeader(title: l10n.dashboardSectionStreak),
          const SizedBox(height: 10),
          _StreakRow(
            key: const Key('dashboardStreakRow'),
            runs: runs,
            allTime: _allTimeStreaks,
          ),
        ],
      ),
    );
    final mileageCard = MileageTrendCard(
      runs: runs,
      unit: unit,
      weekStartDay: _weekStartDay,
      now: now,
    );
    final pbCard = hasAnyPb
        ? ListCard(
          child: Column(
            children: [
              ChartCardHeader(
                title: l10n.dashboardSectionPersonalBests,
                action: const MetricInfoButton(metric: Metric.ageGrade),
              ),
              const SizedBox(height: 10),
              if (longest != null)
                _PbRow(
                  icon: Icons.straighten,
                  label: l10n.dashboardLongestRun,
                  value: UnitFormat.distance(longest.distanceMetres, unit),
                ),
              for (final e in displayEfforts.entries) ...[
                const SizedBox(height: AppSpace.smPlus),
                _PbRow(
                  icon: Icons.emoji_events,
                  label: l10n.dashboardFastestDistance(
                      bestEffortDistanceLabel(l10n, e.key)),
                  value: _formatDuration(e.value),
                  subValue: switch (_pbAgeGrade(e.key, e.value, now,
                      achievedAt: pbDates[e.key])) {
                    final ag? => metricText(l10n, Metric.ageGrade,
                        variant: 'pb', args: {'percent': ag}),
                    _ => null,
                  },
                ),
              ],
            ],
          ),
        )
        : null;
    final fitnessCard = FitnessCard(
        runs: runs, now: now, hrPrefs: hrPrefs, loadSeries: loadSeries);
    final predictorCard = RacePredictorCard(runs: runs, now: now);
    final intensityCard = IntensityCard(
      runs: runs,
      hrZones: parseHrZones(
          widget.settingsSync?.service?.effective<Map>(SettingsKeys.hrZones)),
      now: now,
      settingsSync: widget.settingsSync,
    );
    // The runner's own load ramp, and the comeback signal for the runner whose
    // recent history cannot carry a ratio: fed the SAME inputs and mutually
    // exclusive by construction (decisions § 609 + § 612).
    final volumeRuns = _runVolumeInputs(runs);
    final loadRampCard = LoadRampCard(runs: volumeRuns, now: now);
    final comebackCard = ComebackCard(runs: volumeRuns, now: now);
    final loadChart = _buildTrainingLoadChart(runs, loadSeries);
    final gymNote = _hasRecentLift(now) ? _gymReadinessNote(theme, l10n) : null;
    final liftsCard = _gymShown && widget.gymStore.workouts.isNotEmpty
        ? RecentLiftsCard(
            workouts: widget.gymStore.workouts,
            onOpenWorkout: _openGymWorkout,
            onViewAll: _openGym,
          )
        : null;

    // The trend groups, in web's order. A group mounts only when a card in it
    // is sure to draw, so a fold never opens on nothing; a group the runner
    // hid is not built at all (decisions § 2386).
    final hidden = _hiddenCards;
    Widget? group(String key, String title, String hint, List<Widget> cards) =>
        hidden.contains(key)
            ? null
            : Padding(
                padding: const EdgeInsets.only(top: AppSpace.sm),
                child: DisclosureSection(
                  key: ValueKey('dashboard-trend-$key'),
                  title: title,
                  hint: hint,
                  open: _trendOpen[key] ?? true,
                  onToggle: (open) => _setTrendOpen(key, open),
                  hideLabel: l10n.progressHideGroup,
                  onHide: () => _hideTrendGroup(key, title),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: cards,
                  ),
                ),
              );
    final loadBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [loadChart, ?gymNote],
    );
    // Progressive disclosure: at `simple` the fitness snapshot and the load
    // curve fold into one named expander, never dropped, remembered per
    // account. Web twin: the `training-load-disclosure` <details>.
    final isSimple = _disclosureLevel(runs.length) == 'simple';
    final loadRows = isSimple
        ? <Widget>[
            Padding(
              padding: const EdgeInsets.only(top: AppSpace.sm),
              child: DisclosureSection(
                key: const Key('dashboardTrainingLoadDisclosure'),
                title: l10n.dashboardTrainingLoadSection,
                hint: l10n.dashboardTrainingLoadSectionHint,
                open: _trainingLoadExpanded,
                onToggle: _setTrainingLoadExpanded,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [fitnessCard, loadBlock],
                ),
              ),
            ),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                key: const Key('dashboardDisclosureLevelLink'),
                onPressed: () => openSettings(SettingsDestination.display),
                child: Text(l10n.dashboardTrainingLoadSectionAction),
              ),
            ),
            loadRampCard,
            comebackCard,
          ]
        : <Widget>[fitnessCard, loadRampCard, comebackCard, loadBlock];
    // One card for the load views (decisions § 2385): they read one series
    // (§ 109), so they are rows of one card rather than four cards.
    final fitnessCards = <Widget>[
      _TrainingLoadCard(
        key: const Key('dashboardTrainingLoadCard'),
        title: isSimple ? null : l10n.dashboardTrainingLoadSection,
        children: loadRows,
      ),
    ];
    final trendGroups = <Widget>[
      ?group('volume', l10n.dashboardTrendGroupVolume,
          l10n.dashboardTrendGroupVolumeHint, [mileageCard]),
      // The load chart always draws (it has its own empty state), so this
      // group always mounts.
      ?group('fitness', l10n.dashboardTrendGroupFitness,
          l10n.dashboardTrendGroupFitnessHint, fitnessCards),
      if (pbCard != null)
        ?group('performance', l10n.dashboardTrendGroupPerformance,
            l10n.dashboardTrendGroupPerformanceHint, [pbCard, predictorCard])
      else if (!hidden.contains('performance'))
        predictorCard,
      if (intensityCard.hasContent)
        ?group('effort', l10n.dashboardTrendGroupEffort,
            l10n.dashboardTrendGroupEffortHint, [intensityCard]),
      if (liftsCard != null)
        ?group('recent', l10n.dashboardTrendGroupRecent,
            l10n.dashboardTrendGroupRecentHint, [liftsCard]),
    ];

    final lead = <Widget>[
      if (weekLeadCard != null) ...[weekLeadCard, _kSectionGap],
      if (goalsSection != null) ...[goalsSection, _kSectionGap],
      periodRow,
      ?periodLinks,
      _kSectionGap,
    ];

    final Widget content;
    if (widthClassOf(context) == WidthClass.expanded) {
      // Tablet-landscape: the trend cards flow into two columns, blocks
      // alternating, as web /dashboard's card grid does.
      final left = <Widget>[];
      final right = <Widget>[];
      for (final (i, block) in [streakCard, ...trendGroups].indexed) {
        (i.isEven ? left : right).add(block);
      }
      content = contentColumn(
        context,
        maxWidth: _kExpandedMaxWidth,
        ListView(
          padding: _kPagePadding,
          children: [
            ...lead,
            Row(
              key: const Key('dashboardExpandedChartColumns'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: left,
                  ),
                ),
                const SizedBox(width: AppSpace.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: right,
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    } else {
      content = ListView(
        padding: _kPagePadding,
        children: [...lead, streakCard, ...trendGroups],
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(l10n.progressTitle)),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(onRefresh: _refreshAll, child: content),
      ),
    );
  }
}

/// The Progress page's opening card: this calendar week against its
/// yardstick and the next plan session. Mirrors web
/// `DashboardWeekLead.svelte`; the numbers come from the `week_lead.dart`
/// parity pair.
class _DashboardWeekLead extends StatelessWidget {
  final WeekLead lead;
  final bool hasPlan;
  final DistanceUnit unit;
  final ValueChanged<LeadPlanWorkout> onOpenSession;

  /// Opens this week's summary, the day-by-day detail the lead stands for.
  final VoidCallback onOpenWeek;

  const _DashboardWeekLead({
    super.key,
    required this.onOpenWeek,
    required this.lead,
    required this.hasPlan,
    required this.unit,
    required this.onOpenSession,
  });

  String _whenLabel(AppLocalizations l10n, String iso, int? inDays) {
    if (inDays == 0) return l10n.dashboardLeadToday;
    if (inDays == 1) return l10n.dashboardLeadTomorrow;
    return formatDowDateShort(parseIsoDate(iso), activeLocaleTag);
  }

  String? _vsText(AppLocalizations l10n) {
    final c = lead.comparison;
    if (c == null) return null;
    final done = UnitFormat.distance(lead.distanceM, unit);
    return switch (c.kind) {
      WeekComparisonKind.plan => l10n.dashboardLeadVsPlan(
          done, UnitFormat.distance(c.targetM!, unit)),
      WeekComparisonKind.goal => l10n.dashboardLeadVsGoal(
          done, UnitFormat.distance(c.targetM!, unit)),
      WeekComparisonKind.goalRuns =>
        l10n.dashboardLeadVsGoalRuns(lead.count, c.targetCount!.round()),
      WeekComparisonKind.average => l10n.dashboardLeadVsAverage(
          c.weeks!, UnitFormat.distance(c.averageM!, unit)),
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final c = lead.comparison;
    final ratio = c == null || c.kind == WeekComparisonKind.average
        ? null
        : c.kind == WeekComparisonKind.goalRuns
            ? lead.count / c.targetCount!
            : lead.distanceM / c.targetM!;
    final vs = _vsText(l10n);
    final next = lead.next;
    final nextSize = next == null
        ? null
        : plannedWorkoutSize(
            kind: next.kind,
            targetDistanceM: next.targetDistanceM,
            targetDurationS: next.targetDurationSeconds,
            structure: next.structure,
          );

    return ListCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ChartCardHeader(
            title: l10n.dashboardLeadTitle,
            action: IconButton(
              key: const Key('dashboardWeekLeadOpenWeek'),
              tooltip: l10n.periodWeeklySummary,
              icon: const Icon(Icons.chevron_right),
              onPressed: onOpenWeek,
            ),
          ),
          const SizedBox(height: 8),
          if (lead.count == 0)
            Text(
              l10n.dashboardLeadEmpty,
              key: const Key('dashboardWeekLeadEmpty'),
              style: theme.textTheme.titleMedium?.copyWith(color: muted),
            )
          else
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.end,
              spacing: 8,
              children: [
                Text(
                  UnitFormat.distance(lead.distanceM, unit),
                  key: const Key('dashboardWeekLeadDistance'),
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                Text(
                  l10n.dashboardWeekStripCount(lead.count),
                  style: theme.textTheme.bodyMedium?.copyWith(color: muted),
                ),
              ],
            ),
          if (ratio != null) ...[
            const SizedBox(height: 8),
            ProgressBar(
              key: const Key('dashboardWeekLeadMeter'),
              value: ratio.clamp(0.0, 1.0),
              semanticsLabel: c!.kind == WeekComparisonKind.plan
                  ? l10n.dashboardLeadPlanProgressAria
                  : l10n.dashboardLeadGoalProgressAria,
            ),
          ],
          if (vs != null) ...[
            const SizedBox(height: 6),
            Text(
              vs,
              key: const Key('dashboardWeekLeadVs'),
              style: theme.textTheme.bodyMedium?.copyWith(color: muted),
            ),
          ],
          if (hasPlan) ...[
            const SizedBox(height: 16),
            Text(
              l10n.dashboardLeadNextSession,
              style: theme.textTheme.labelMedium?.copyWith(color: muted),
            ),
            const SizedBox(height: 6),
            if (next != null)
              _WeekLeadSession(
                key: const Key('dashboardWeekLeadNext'),
                when: _whenLabel(l10n, next.scheduledDate, lead.nextInDays),
                detail: [
                  workoutKindLabel(l10n, workoutKindFromDb(next.kind)),
                  if (nextSize != null)
                    formatPlannedSize(l10n, nextSize,
                        (m) => UnitFormat.distance(m.toDouble(), unit)),
                ].join(' · '),
                onTap: () => onOpenSession(next),
              )
            else
              Text(
                l10n.dashboardLeadNoNextSession,
                key: const Key('dashboardWeekLeadNoNext'),
                style: theme.textTheme.bodyMedium?.copyWith(color: muted),
              ),
          ],
        ],
      ),
    );
  }
}

class _WeekLeadSession extends StatelessWidget {
  final String when;
  final String detail;
  final VoidCallback onTap;

  const _WeekLeadSession({
    super.key,
    required this.when,
    required this.detail,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Icon(Icons.directions_run, color: scheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(when,
                          style: theme.textTheme.bodyLarge
                              ?.copyWith(fontWeight: FontWeight.w600)),
                      Text(detail,
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One card holding the load views as rows. Each row is a card in its own
/// right elsewhere, so the cards inside drop their chrome here rather than
/// nesting a card in a card.
class _TrainingLoadCard extends StatelessWidget {
  final String? title;
  final List<Widget> children;
  const _TrainingLoadCard({super.key, this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Flush: the rows are cards with their own insets, drawn chromeless by
    // the theme below.
    return ListCard.flush(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
        child: Theme(
          data: theme.copyWith(
            cardTheme: theme.cardTheme.copyWith(
              elevation: 0,
              margin: EdgeInsets.zero,
              color: Colors.transparent,
              surfaceTintColor: Colors.transparent,
              shadowColor: Colors.transparent,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (title != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: ChartCardHeader(title: title!),
                ),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyGoalsCta extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyGoalsCta({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    // audit/accessibility (2026-05-25) High — WCAG 4.1.2. Tappable
    // `InkWell` carries no role for TalkBack; without Semantics it
    // reads as a generic tappable region. The label summarises the
    // CTA so a screen-reader user understands what activates.
    return ListCard(
      onTap: onAdd,
      child: Semantics(
        label: l10n.dashboardSetWeeklyGoalA11y,
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.colorScheme.primaryContainer,
              ),
              child: Icon(Icons.flag_outlined,
                  color: theme.colorScheme.primary),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.dashboardSetFirstGoal,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(
                    l10n.dashboardSetFirstGoalBody,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: theme.colorScheme.outline),
          ],
        ),
      ),
    );
  }
}

class _GoalCard extends StatelessWidget {
  final RunGoal goal;
  final GoalProgress progress;
  final DistanceUnit unit;
  final VoidCallback onTap;
  const _GoalCard({
    required this.goal,
    required this.progress,
    required this.unit,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final completeColor = AppSemanticColors.of(context).success;
    final accent =
        progress.complete ? completeColor : theme.colorScheme.primary;
    final periodLabel = goal.period == GoalPeriod.week
        ? l10n.dashboardGoalWeekly
        : l10n.dashboardGoalMonthly;
    final customTitle = goal.title;

    // Look up per-kind progress so the card can render every kind in order,
    // with unset targets shown as muted "-" rows. Keeps the layout stable
    // regardless of which targets the user has configured.
    final byKind = <GoalTargetKind, TargetProgress>{
      for (final t in progress.targets) t.kind: t,
    };

    final a11yLabel = l10n.dashboardGoalA11y(
      periodLabel,
      customTitle ?? l10n.dashboardGoalTapToEdit,
      progress.complete
          ? l10n.dashboardGoalComplete
          : l10n.dashboardGoalInProgress,
    );

    return ListCard(
      onTap: onTap,
      child: Semantics(
        label: a11yLabel,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        customTitle ??
                            l10n.dashboardGoalTitleFallback(periodLabel),
                        style: (customTitle != null
                                ? theme.textTheme.titleMedium
                                : theme.textTheme.labelMedium)
                            ?.copyWith(
                          color: customTitle != null
                              ? null
                              : theme.colorScheme.onSurfaceVariant,
                          letterSpacing: customTitle != null ? 0 : 1.1,
                          fontWeight: customTitle != null
                              ? FontWeight.w700
                              : FontWeight.normal,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (customTitle != null)
                        Text(
                          periodLabel,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            letterSpacing: 1.1,
                          ),
                        ),
                    ],
                  ),
                ),
                Text(
                  '${(progress.overallPercent * 100).round()}%',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.edit_outlined,
                    size: 14, color: theme.colorScheme.outline),
              ],
            ),
            const SizedBox(height: 14),
            for (int i = 0; i < GoalTargetKind.values.length; i++) ...[
              if (i > 0) const SizedBox(height: 12),
              _TargetRow(
                kind: GoalTargetKind.values[i],
                target: byKind[GoalTargetKind.values[i]],
                unit: unit,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TargetRow extends StatelessWidget {
  final GoalTargetKind kind;
  final TargetProgress? target;
  final DistanceUnit unit;
  const _TargetRow({
    required this.kind,
    required this.target,
    required this.unit,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = target;

    if (t == null) {
      // Unset target — single muted line, no bar, no feedback.
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Expanded(
              child: Text(
                goalKindLabel(kind),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Text(
              '—',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
    }

    final completeColor = AppSemanticColors.ofTheme(theme).success;
    final accent = t.complete ? completeColor : theme.colorScheme.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(
              child: Text(
                goalKindLabel(kind),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(width: AppSpace.sm),
            // Flexible: "12.3 / 30.0 km" at 2x on a 320 dp phone ran 234 dp
            // past the goal card, so it wraps under its own baseline now.
            Flexible(
              child: Text(
                _valueText(t, unit),
                textAlign: TextAlign.end,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ProgressBar(value: t.percent, fill: accent),
        const SizedBox(height: 5),
        Row(
          children: [
            Icon(
              t.complete ? Icons.check_circle : Icons.trending_up,
              size: 14,
              color: accent,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                t.feedback,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  static String _valueText(TargetProgress t, DistanceUnit unit) {
    switch (t.kind) {
      case GoalTargetKind.distance:
        final c = UnitFormat.distanceValue(t.current, unit);
        final tgt = UnitFormat.distanceValue(t.target, unit);
        return '$c / $tgt ${UnitFormat.distanceLabel(unit)}';
      case GoalTargetKind.time:
        return '${_coarseDuration(t.current)} / ${_coarseDuration(t.target)}';
      case GoalTargetKind.avgPace:
        final c =
            t.current > 0 ? UnitFormat.pace(t.current, unit) : '--:--';
        final tgt = UnitFormat.pace(t.target, unit);
        return '$c / $tgt ${UnitFormat.paceLabel(unit)}';
      case GoalTargetKind.runCount:
        return '${t.current.toInt()} / ${t.target.toInt()}';
    }
  }

  static String _coarseDuration(double seconds) {
    final totalMin = (seconds / 60).round();
    if (totalMin >= 60) {
      final h = totalMin ~/ 60;
      final m = totalMin % 60;
      return m > 0 ? '${h}h ${m}m' : '${h}h';
    }
    return '${totalMin}m';
  }
}

class _PbRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  /// Optional muted second line under the value — the age grade for a timed
  /// PB (#269). Null for rows with no graded standard (e.g. longest run) or
  /// when the viewer's DOB/sex is unknown.
  final String? subValue;
  const _PbRow({
    required this.icon,
    required this.label,
    required this.value,
    this.subValue,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, color: theme.colorScheme.primary, size: 20),
        const SizedBox(width: 12),
        Expanded(child: Text(label, style: theme.textTheme.bodyLarge)),
        const SizedBox(width: AppSpace.sm),
        // Flexible, so at 2x on a 320 dp phone the time and its age grade
        // wrap rather than push the row past the card.
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value,
                textAlign: TextAlign.end,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (subValue != null)
                Text(
                  subValue!,
                  textAlign: TextAlign.end,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Compact 3-column stat card used in the dashboard's activity
/// summary strip. Replaces the stacked "This Week" / "This Month" /
/// "All Time" surfaces — same data, tighter footprint. Tappable
/// when [onTap] is set (week + month tap into PeriodSummary; all
/// time has no period detail surface, so the card stays inert).
class _PeriodStatCard extends StatelessWidget {
  final String label;
  final double distanceMetres;
  final int runCount;
  final double vertMetres;
  final DistanceUnit unit;
  final VoidCallback? onTap;

  const _PeriodStatCard({
    required this.label,
    required this.distanceMetres,
    required this.runCount,
    required this.vertMetres,
    required this.unit,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final value = UnitFormat.distanceValue(distanceMetres, unit);
    final unitLabel = UnitFormat.distanceLabel(unit);
    final inner = Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: 0.06,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(
                  value,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                  softWrap: false,
                ),
              ),
              const SizedBox(width: 3),
              Text(
                unitLabel,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            l10n.dashboardRunCount(runCount),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (vertMetres > 0) ...[
            const SizedBox(height: 2),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.terrain,
                  size: 14,
                  color: theme.colorScheme.outline,
                ),
                const SizedBox(width: 3),
                Flexible(
                  child: Text(
                    metricText(l10n, Metric.vert, variant: 'total', args: {
                      'value': UnitFormat.elevation(vertMetres, unit)
                    }),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.fade,
                    softWrap: false,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
    final isTappable = onTap != null;
    final theme0 = Theme.of(context);
    // Subtle differentiation so users can tell which tiles drill in.
    // - Tappable: outlined border in the primary tint + trailing
    //   chevron in the value row + standard Card elevation.
    // - Non-tappable: zero elevation + no chevron + no outline — sits
    //   visually flatter so it reads as a read-only stat.
    // Was previously visually identical regardless of onTap — field
    // report: "clickable sections should be distinguishable from non-
    // clickable fields … Week / Month / All Time look the same but
    // only Week and Month are clickable."
    final body = Stack(
      children: [
        inner,
        if (isTappable)
          Positioned(
            right: 8,
            top: 8,
            child: Icon(
              Icons.chevron_right,
              size: 16,
              color: theme0.colorScheme.outline,
            ),
          ),
      ],
    );
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: isTappable
          ? RoundedRectangleBorder(
              side: BorderSide(
                color: theme0.colorScheme.primary,
                width: 1,
              ),
              borderRadius: BorderRadius.circular(12),
            )
          : RoundedRectangleBorder(
              side: BorderSide(
                color: theme0.dividerColor,
                width: 1,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
      // audit/accessibility (2026-05-25) High — WCAG 4.1.2. The
      // tappable InkWell was bare; without Semantics TalkBack
      // announced only the raw stat numbers in reading order.
      // Wrapping with a button-roled label restores the semantics
      // for the period summary drill-in.
      child: isTappable
          ? Semantics(
              button: true,
              label: l10n.dashboardPeriodSummaryA11y(
                label,
                '${UnitFormat.distanceValue(distanceMetres, unit)} '
                    '${UnitFormat.distanceLabel(unit)}',
                l10n.dashboardRunCount(runCount),
                vertMetres > 0
                    ? l10n.dashboardElevationGainSuffix(
                        UnitFormat.elevation(vertMetres, unit))
                    : '',
              ),
              child: InkWell(onTap: onTap, child: body),
            )
          : body,
    );
  }
}

/// Current + best run-streak card. Strava-style daily grace — a
/// missing today doesn't break the streak if yesterday is intact.
/// Pure compute via `lib/streaks.dart`; the claim discipline lives in
/// `lib/streak_card.dart` (decisions § 471 / § 475): [allTime] is the
/// `run_streaks_for_user` row and drives both figures when present
/// (folded with the local compute so an unsynced run is never walked
/// back), while a null — loading, offline, signed out — suppresses the
/// best/all-time sub-label entirely rather than presenting the store's
/// resident sliver as the all-time truth.
class _StreakRow extends StatelessWidget {
  final List<Run> runs;
  final RunStreaks? allTime;
  const _StreakRow({super.key, required this.runs, required this.allTime});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final windowed = computeRunStreaks(
      runs.map((r) => r.startedAt).toList(),
      DateTime.now(),
    );
    final at = allTime;
    final state = streakCardState(
      at == null ? null : mergeAllTimeStreaks(at, windowed),
      windowed,
    );
    final crown = state.current > 0;
    final color = crown
        ? AppSemanticColors.of(context).crown
        : theme.colorScheme.onSurfaceVariant;
    final bestText = switch (state.sub) {
      StreakSubKind.best => l10n.dashboardStreakBest(state.bestN!),
      StreakSubKind.allTimeBest => l10n.dashboardStreakAllTimeBest,
      // Encourage rather than guilt a beginner with no current streak
      // (new persona #26).
      StreakSubKind.restart => l10n.dashboardStreakRestart,
      StreakSubKind.start => l10n.dashboardStreakStart,
      StreakSubKind.none => null,
    };
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        Flexible(
          child: Column(
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Icon(Icons.local_fire_department, color: color, size: 24),
                  const SizedBox(width: 6),
                  Text(
                    '${state.current}',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      state.current == 1
                          ? l10n.dashboardStreakDayUnit
                          : l10n.dashboardStreakDaysUnit,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                l10n.dashboardStreakCurrent,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        if (bestText != null)
          Flexible(
            child: Column(
              children: [
                Text(
                  bestText,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.dashboardStreakHistory,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// The runner's own runs reduced to what the load helpers grade on. One
/// mapping for both cards: `selfLoad` and `comebackLoad` compare their windows
/// against each other, and two conversions would let the two windows come from
/// different run sets — the one way that comparison can silently lie.
List<RunForVolume> _runVolumeInputs(List<Run> runs) => [
      for (final r in runs)
        RunForVolume(
          startedAt: r.startedAt.toIso8601String(),
          distanceM: r.distanceMetres,
          activityType: r.metadata?['activity_type'] as String?,
        ),
    ];
