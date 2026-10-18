import '../activity_type_labels.dart';
import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart' hide Route;
import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart'
    show
        IdentityAvatar,
        ListSkeleton,
        ProgressBar,
        StatusPill,
        StatusPillSize,
        TextLane;

import '../auth_error.dart';
import '../l10n/gen/app_localizations.dart';
import '../l10n/date_format.dart';
import '../l10n/locale_support.dart';
import '../plan_assign.dart';
import '../preferences.dart';
import '../training.dart';
import '../training_labels.dart';
import '../hr_prescription_gate.dart';
import '../training_service.dart' show TrainingService, currentOrUpcomingPlan;
import '../widgets/run_track_preview.dart';
import '../widgets/top_banner.dart';
import '../widgets/workout_edit_sheet.dart';
import '../workout_target_label.dart';

/// Coach run-review surface — mobile mirror of web
/// `/coaching/athletes/[id]` (`.../athletes/[id]/+page.svelte`): a linked
/// athlete's recent runs (public + private, gated by the active-coach RLS
/// policy) + active-plan compliance + the assign-a-plan control. Reached from
/// `coaching_screen.dart`. Reads/writes through [ApiClient]'s coaching methods.
class CoachingAthleteScreen extends StatefulWidget {
  final ApiClient api;
  final Preferences preferences;
  final String athleteId;
  final String? displayName;
  final DateTime? acceptedAt;

  /// Writes the coach's edit to one of the athlete's workouts. The
  /// active-coach RLS policy on plan_workouts (20261116_001) is what admits
  /// it; null builds the app's own service on first use.
  final TrainingService? training;

  /// The heart-rate prescription gate (decisions § 2092); null reads the
  /// deploy flag. A test passes it directly.
  final bool? hrPrescription;

  const CoachingAthleteScreen({
    super.key,
    required this.api,
    required this.preferences,
    required this.athleteId,
    this.displayName,
    this.acceptedAt,
    this.training,
    this.hrPrescription,
  });

  @override
  State<CoachingAthleteScreen> createState() => _CoachingAthleteScreenState();
}

class _CoachingAthleteScreenState extends State<CoachingAthleteScreen> {
  late final TrainingService _training = widget.training ?? TrainingService();
  late final bool _hrPrescription = widget.hrPrescription ?? hrPrescriptionGate;
  bool _loading = true;
  List<AthleteRunSummary> _runs = const [];

  /// The athlete's map, clipped against their privacy zones by
  /// clip-public-track (decisions § 1968). Off until the server gate says so.
  bool _showMaps = false;
  AthletePlanOverview? _overview;
  List<TrainingPlanRow> _myPlans = const [];

  String? _selectedPlanId;
  DateTime _startDate = DateTime.now();
  bool _assigning = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        widget.api.fetchAthleteRuns(widget.athleteId, limit: 20),
        widget.api.fetchAthletePlanOverview(widget.athleteId, pick: _pickPlan),
        widget.api.fetchMyPlans(),
        widget.api.coachRunMapEnabled(),
      ]);
      if (!mounted) return;
      setState(() {
        _runs = results[0] as List<AthleteRunSummary>;
        _overview = results[1] as AthletePlanOverview?;
        _myPlans = results[2] as List<TrainingPlanRow>;
        _showMaps = results[3] as bool;
        _loading = false;
        // Start the picker clear of the plans the athlete already holds, so
        // the default is a date the server will accept.
        _startDate = _firstFreeStart();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showTopBanner(
          context,
          AppLocalizations.of(context).coachingAthleteLoadError(
              friendlyError(AppLocalizations.of(context), e)));
    }
  }

  /// The athlete's current plan, or the queued one before any has started —
  /// the same rule as the athlete's own dashboard.
  static TrainingPlanRow? _pickPlan(List<TrainingPlanRow> active) =>
      currentOrUpcomingPlan(active, toIsoDate(DateTime.now()));

  static String _startIso(TrainingPlanRow p) => toIsoDate(p.startDate);
  static String _endIso(TrainingPlanRow p) => toIsoDate(p.endDate);

  /// The athlete's plans an assignment must not overlap: every active plan
  /// they hold that still holds dates, not only the one shown. Web twin: the
  /// `blockers` derived on `/coaching/athletes/[id]`.
  List<TrainingPlanRow> get _blockers {
    final o = _overview;
    if (o == null) return const [];
    // An overview built before activePlans existed still names its own plan.
    final active = o.activePlans.isEmpty ? [o.plan] : o.activePlans;
    return assignBlockers(active, _todayISO(), start: _startIso, end: _endIso);
  }

  DateTime _firstFreeStart() =>
      parseIsoDate(firstStartAfter(_blockers, _todayISO(), end: _endIso));

  bool get _assignedByMe {
    final o = _overview;
    return o != null &&
        o.plan.assignedByCoachId != null &&
        o.plan.assignedByCoachId == widget.api.userId;
  }

  Future<void> _assignPlan() async {
    final l10n = AppLocalizations.of(context);
    final planId = _selectedPlanId;
    if (planId == null || _assigning) return;
    setState(() => _assigning = true);
    try {
      await widget.api.assignPlanToAthlete(
        sourcePlanId: planId,
        athleteId: widget.athleteId,
        startDate: _startDate,
      );
      final overview = await widget.api
          .fetchAthletePlanOverview(widget.athleteId, pick: _pickPlan);
      if (!mounted) return;
      setState(() {
        _overview = overview;
        _selectedPlanId = null;
        _startDate = _firstFreeStart();
      });
      showTopBanner(
        context,
        l10n.coachingAthleteAssignSuccess(
            widget.displayName ?? l10n.coachingAthleteRunnerFallback),
      );
    } on PlanAssignOverlapException {
      // The athlete holds a plan on those dates (23P01). Re-read their plans —
      // the one in the way may have appeared since the screen loaded — and say
      // which, so the coach knows what date to pick.
      AthletePlanOverview? fresh;
      try {
        fresh = await widget.api
            .fetchAthletePlanOverview(widget.athleteId, pick: _pickPlan);
      } catch (e) {
        debugPrint('[CoachingAthleteScreen] plan re-read failed: $e');
      }
      if (!mounted) return;
      if (fresh != null) setState(() => _overview = fresh);
      final name = widget.displayName ?? l10n.coachingAthleteRunnerFallback;
      final source = _myPlans.where((p) => p.id == planId).firstOrNull;
      final hit = source == null
          ? null
          : assignCollision(_blockers, source, toIsoDate(_startDate),
              start: _startIso,
              end: _endIso,
              sourceStart: _startIso,
              sourceEnd: _endIso);
      showTopBanner(
        context,
        hit == null
            ? l10n.coachingAthleteAssignOverlap(name)
            : l10n.coachingAthleteAssignOverlapNamed(
                name,
                hit.name,
                formatDateMed(hit.startDate, activeLocaleTag),
                formatDateMed(hit.endDate, activeLocaleTag),
              ),
      );
    } catch (e) {
      // Any other refusal: assignPlanToAthlete rethrows the RPC's RAISE text
      // as an Exception. Surface it rather than swallow — strip the leading
      // "Exception: " the toString() adds.
      if (!mounted) return;
      showTopBanner(context, _cleanMessage(e));
    } finally {
      if (mounted) setState(() => _assigning = false);
    }
  }

  static String _cleanMessage(Object e) {
    final s = '$e';
    return s.startsWith('Exception: ') ? s.substring('Exception: '.length) : s;
  }

  Future<void> _pickStartDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2),
    );
    if (!mounted) return;
    if (picked != null) setState(() => _startDate = picked);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.displayName ?? l10n.coachingAthleteAthleteFallback),
      ),
      body: _loading
          ? ListSkeleton(
              label: l10n.commonLoading,
              rows: 3,
              rowHeight: 120,
              hasLeading: false,
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _header(l10n),
                  const SizedBox(height: 16),
                  _planCard(l10n),
                  const SizedBox(height: 16),
                  _runsCard(l10n),
                ],
              ),
            ),
    );
  }

  Widget _header(AppLocalizations l10n) {
    final theme = Theme.of(context);
    final since = widget.acceptedAt != null
        ? formatDateMed(widget.acceptedAt!, activeLocaleTag)
        : '—';
    return Row(
      children: [
        IdentityAvatar(
            seed: widget.athleteId, name: widget.displayName, size: 48),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.displayName ?? l10n.coachingAthleteRunnerFallback,
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(l10n.coachingAthleteCoachingSince(since),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  )),
            ],
          ),
        ),
      ],
    );
  }

  Widget _planCard(AppLocalizations l10n) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.coachingAthletePlanCompliance,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            if (_overview == null)
              Text(l10n.coachingAthleteNoActivePlan,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ))
            else
              _activePlanBody(_overview!, l10n),
            _assignSection(l10n),
          ],
        ),
      ),
    );
  }

  /// The assign control, offered whenever the coach has a plan to assign: the
  /// athlete's own plans only constrain the dates, which the server checks.
  Widget _assignSection(AppLocalizations l10n) {
    final theme = Theme.of(context);
    final name = widget.displayName ?? l10n.coachingAthleteRunnerFallback;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    if (_myPlans.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Text(l10n.coachingAthleteAssignNoPlans, style: muted),
      );
    }
    final blockers = _blockers;
    String date(DateTime d) => formatDateMed(d, activeLocaleTag);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 24),
        Text(l10n.coachingAthleteAssignTitle,
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(l10n.coachingAthleteAssignHint(name), style: muted),
        if (blockers.length == 1) ...[
          const SizedBox(height: 4),
          Text(
            l10n.coachingAthleteAssignAfterOne(
                name, blockers[0].name, date(blockers[0].endDate)),
            key: const ValueKey('assign-blockers'),
            style: muted,
          ),
        ] else if (blockers.length == 2) ...[
          const SizedBox(height: 4),
          Text(
            l10n.coachingAthleteAssignAfterTwo(
              name,
              blockers[0].name,
              date(blockers[0].endDate),
              blockers[1].name,
              date(blockers[1].startDate),
              date(blockers[1].endDate),
            ),
            key: const ValueKey('assign-blockers'),
            style: muted,
          ),
        ] else if (blockers.length > 2) ...[
          const SizedBox(height: 4),
          Text(
            l10n.coachingAthleteAssignAfterMany(
              name,
              blockers.length,
              blockers.map((p) => p.name).join(', '),
              date(blockers.last.endDate),
            ),
            key: const ValueKey('assign-blockers'),
            style: muted,
          ),
        ],
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _selectedPlanId,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: l10n.coachingAthleteAssignSelectLabel,
          ),
          hint: Text(l10n.coachingAthleteAssignSelectPlaceholder),
          items: [
            for (final p in _myPlans)
              DropdownMenuItem(value: p.id, child: Text(p.name)),
          ],
          onChanged: _assigning
              ? null
              : (v) => setState(() => _selectedPlanId = v),
        ),
        const SizedBox(height: 12),
        InkWell(
          onTap: _assigning ? null : _pickStartDate,
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: l10n.coachingAthleteAssignStartLabel,
            ),
            child: Text(formatDateMed(_startDate, activeLocaleTag)),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: (_selectedPlanId == null || _assigning) ? null : _assignPlan,
          child: Text(_assigning
              ? l10n.coachingAthleteAssigning
              : l10n.coachingAthleteAssignButton),
        ),
      ],
    );
  }

  Widget _activePlanBody(AthletePlanOverview o, AppLocalizations l10n) {
    final theme = Theme.of(context);
    final todayISO = _todayISO();
    // Skipped workouts are off the books, as completionPct already treats
    // them: never in the total, never a miss. Web twin: `compliance`.
    final real = o.workouts
        .where((w) => w.kind != 'rest' && !isWorkoutSkipped(w.skippedAt))
        .toList();
    final done = real
        .where(isWorkoutCompleted)
        .length;
    final missed = real
        .where((w) =>
            !isWorkoutCompleted(w) &&
            _isoOf(w.scheduledDate).compareTo(todayISO) < 0)
        .length;
    final pct = o.completionPct;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(o.plan.name,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
            ),
            if (_assignedByMe) ...[
              const SizedBox(width: 8),
              StatusPill(
                label: l10n.coachingAthleteAssignedByYou,
                foreground: theme.colorScheme.onPrimaryContainer,
                fill: theme.colorScheme.primaryContainer,
                size: StatusPillSize.compact,
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        ProgressBar(value: (pct / 100).clamp(0.0, 1.0)),
        const SizedBox(height: 6),
        Text.rich(
          TextSpan(children: [
            TextSpan(
                text: '$pct% ',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            TextSpan(text: l10n.coachingAthleteComplete),
            TextSpan(
                text:
                    ' · ${l10n.coachingAthleteDoneCount(done, real.length)}'),
            if (missed > 0)
              TextSpan(
                text: ' · ${l10n.coachingAthleteMissedCount(missed)}',
                style: TextStyle(color: theme.colorScheme.error),
              ),
          ]),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        for (final w in _focusWorkouts(o)) _workoutRow(w, l10n),
      ],
    );
  }

  /// A window around today: recent misses + what's coming up, rather than the
  /// whole plan. Mirrors web's focusWorkouts (4 before the pivot, 6 after).
  List<PlanWorkoutRow> _focusWorkouts(AthletePlanOverview o) {
    final sorted = o.workouts.where((w) => w.kind != 'rest').toList()
      ..sort((a, b) => _isoOf(a.scheduledDate).compareTo(_isoOf(b.scheduledDate)));
    final todayISO = _todayISO();
    var idx = sorted.indexWhere((w) => _isoOf(w.scheduledDate).compareTo(todayISO) >= 0);
    final pivot = idx == -1 ? sorted.length : idx;
    final from = (pivot - 4) < 0 ? 0 : pivot - 4;
    final to = (pivot + 6) > sorted.length ? sorted.length : pivot + 6;
    return sorted.sublist(from, to);
  }

  Widget _workoutRow(PlanWorkoutRow w, AppLocalizations l10n) {
    final theme = Theme.of(context);
    final status = _workoutStatus(w);
    final (label, color) = switch (status) {
      'done' => (l10n.coachingAthleteStatusDone, theme.colorScheme.primary),
      'missed' => (l10n.coachingAthleteStatusMissed, theme.colorScheme.error),
      'skipped' => (
          l10n.coachingAthleteStatusSkipped,
          theme.colorScheme.onSurfaceVariant
        ),
      _ => (
          l10n.coachingAthleteStatusUpcoming,
          theme.colorScheme.onSurfaceVariant
        ),
    };
    final unit = widget.preferences.unit;
    final target = <String>[];
    if (w.targetDistanceM != null && w.targetDistanceM! > 0) {
      target.add(UnitFormat.distance(w.targetDistanceM!, unit));
    }
    if (w.targetPaceSecPerKm != null && w.targetPaceSecPerKm! > 0) {
      target.add(
          '${UnitFormat.pace(w.targetPaceSecPerKm!.toDouble(), unit)} ${UnitFormat.paceLabel(unit)}');
    }
    final rpe = rpeTargetLabel(l10n, w.targetRpeMin, w.targetRpeMax);
    if (rpe != null) target.add(rpe);
    final hr = _hrPrescription
        ? hrTargetLabel(l10n, w.targetHrMinBpm, w.targetHrMaxBpm)
        : null;
    if (hr != null) target.add(hr);
    return InkWell(
      key: Key('coachWorkoutRow-${w.id}'),
      onTap: () => _editWorkout(w),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            TextLane(
              width: 84,
              child: Text(formatDateShort(w.scheduledDate, activeLocaleTag),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  )),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(workoutKindLabel(l10n, workoutKindFromDb(w.kind)),
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  if (target.isNotEmpty)
                    Text(target.join(' · '),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        )),
                ],
              ),
            ),
            StatusPill(
              label: label,
              foreground: color,
              fill: color.withValues(alpha: 0.16),
              size: StatusPillSize.compact,
            ),
          ],
        ),
      ),
    );
  }

  /// The coach edits one of the athlete's workouts in the same sheet the
  /// athlete uses (web reaches it through the plan link). A save reloads the
  /// overview so the row shows what the athlete will now see.
  Future<void> _editWorkout(PlanWorkoutRow w) async {
    final ok = await showWorkoutEditSheet(
      context,
      workout: w,
      training: _training,
      hrPrescription: _hrPrescription,
    );
    if (ok && mounted) await _load();
  }

  Widget _runsCard(AppLocalizations l10n) {
    final theme = Theme.of(context);
    final unit = widget.preferences.unit;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.coachingAthleteRecentRuns,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            if (_showMaps && _runs.any((r) => r.hasTrack)) ...[
              Text(l10n.coachingAthleteMapsClippedNote,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  )),
              const SizedBox(height: 8),
            ],
            if (_runs.isEmpty)
              Text(l10n.coachingAthleteNoRunsYet,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ))
            else
              for (final r in _runs) _runRow(r, unit, l10n),
          ],
        ),
      ),
    );
  }

  Widget _runRow(AthleteRunSummary r, DistanceUnit unit, AppLocalizations l10n) {
    final theme = Theme.of(context);
    final paceSecPerKm = (r.distanceM > 0 && r.durationS > 0)
        ? r.durationS / (r.distanceM / 1000)
        : null;
    final pace = paceSecPerKm == null
        ? '—'
        : '${UnitFormat.pace(paceSecPerKm, unit)} ${UnitFormat.paceLabel(unit)}';
    final row = Row(
        children: [
          TextLane(
            width: 84,
            child: Text(formatDateShort(r.startedAt, activeLocaleTag),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                )),
          ),
          TextLane(
            width: 64,
            child: Text(activityTypeLabelFor(l10n, r.activityType),
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: Text(
                '${UnitFormat.distance(r.distanceM, unit)} · ${_formatDuration(r.durationS)} · $pace',
                style: theme.textTheme.bodySmall),
          ),
          if (!r.isPublic)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: StatusPill(
                label: l10n.coachingAthletePrivate,
                foreground: theme.colorScheme.onSurfaceVariant,
                outline: theme.colorScheme.outlineVariant,
                size: StatusPillSize.compact,
              ),
            ),
        ],
      );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: _showMaps && r.hasTrack
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                row,
                const SizedBox(height: 6),
                Semantics(
                  key: ValueKey('coach-run-map-${r.id}'),
                  image: true,
                  label: l10n.coachingAthleteRunMapLabel(
                      formatDateShort(r.startedAt, activeLocaleTag)),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    // The preview paints to whatever box it is given, and a
                    // list row's height is unbounded; the feed post's map
                    // height keeps the two run maps one size.
                    child: SizedBox(
                      height: 120,
                      child: RunTrackPreview(
                        runId: r.id,
                        trackUrl: r.trackUrl,
                        api: widget.api,
                        ownerUserId: widget.athleteId,
                      ),
                    ),
                  ),
                ),
              ],
            )
          : row,
    );
  }

  String _workoutStatus(PlanWorkoutRow w) {
    if (w.kind == 'rest') return 'rest';
    if (isWorkoutSkipped(w.skippedAt)) return 'skipped';
    if (isWorkoutCompleted(w)) return 'done';
    return _isoOf(w.scheduledDate).compareTo(_todayISO()) < 0
        ? 'missed'
        : 'upcoming';
  }

  static String _formatDuration(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  /// Local-tz today as a YYYY-MM-DD string, matching web's date comparison.
  static String _todayISO() => _isoOf(DateTime.now());

  static String _isoOf(DateTime dt) {
    final d = dt.isUtc ? dt.toLocal() : dt;
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }
}
