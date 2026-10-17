import 'dart:async';

import 'package:core_models/core_models.dart' hide Route;
import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart';

import '../l10n/gen/app_localizations.dart';
import '../l10n/date_format.dart';
import '../l10n/locale_support.dart';
import '../plan_races.dart';
import '../relink_candidates.dart';
import '../training.dart';
import '../training_labels.dart';
import '../training_service.dart';
import '../backend_timeout.dart';
import '../hr_prescription_flag.dart';
import '../widgets/error_state.dart';
import '../widgets/top_banner.dart';
import '../workout_kind_color.dart';
import '../workout_summary.dart';
import '../workout_summary_format.dart';
import '../workout_prescription.dart';
import '../workout_target_label.dart';

class WorkoutDetailScreen extends StatefulWidget {
  final TrainingService training;
  final String planId;
  final String workoutId;

  /// The heart-rate prescription gate (decisions § 2092); null reads the
  /// deploy flag. A test passes it directly.
  final bool? hrPrescription;
  const WorkoutDetailScreen({
    super.key,
    required this.training,
    required this.planId,
    required this.workoutId,
    this.hrPrescription,
  });

  @override
  State<WorkoutDetailScreen> createState() => _WorkoutDetailScreenState();
}

class _WorkoutDetailScreenState extends State<WorkoutDetailScreen> {
  PlanWorkoutRow? _workout;
  late final bool _hrPrescription = widget.hrPrescription ?? hrPrescriptionGate;

  /// Whether the athlete's coach made the last edit. Auxiliary: a failed
  /// owner read leaves the line hidden and never touches the workout.
  bool _editedByCoach = false;
  bool _loading = true;
  bool _unlinking = false;
  bool _skipping = false;
  _WorkoutLoadError? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final w = await widget.training
          .fetchWorkout(widget.workoutId)
          .timeout(kBackendLoadTimeout);
      if (!mounted) return;
      setState(() {
        _workout = w;
        _loading = false;
      });
      unawaited(_loadProvenance(w));
    } on TimeoutException catch (e) {
      debugPrint('WorkoutDetailScreen._load timed out: $e');
      if (mounted) {
        setState(() {
          _loading = false;
          _error = _WorkoutLoadError.timeout;
        });
      }
    } catch (e, s) {
      debugPrint('WorkoutDetailScreen._load failed: $e\n$s');
      if (mounted) {
        setState(() {
          _loading = false;
          _error = _WorkoutLoadError.generic;
        });
      }
    }
  }

  Future<void> _openRelinkPicker(PlanWorkoutRow workout) async {
    final l10n = AppLocalizations.of(context);
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => _RelinkPickerDialog(
        training: widget.training,
        workout: workout,
      ),
    );
    if (picked == null || !mounted) return;
    try {
      await widget.training.markCompleted(widget.workoutId, picked);
      await _load();
    } catch (e, s) {
      debugPrint('WorkoutDetailScreen._openRelinkPicker re-link failed: $e\n$s');
      if (mounted) showTopBanner(context, l10n.workoutRelinkError);
    }
  }

  // Unlinking the matched run resets the plan's progress for this workout,
  // so it confirms first (parity with web's ConfirmDialog) and surfaces a
  // failure instead of swallowing it. Guarded against a double-tap.
  //
  // A workout marked done by hand has no run to unlink; the same path clears
  // the mark, under copy that says so. Mobile has no "mark done", so the
  // confirm stays: the runner could not put it back from here.
  Future<void> _confirmUnlink(PlanWorkoutRow w) async {
    if (_unlinking) return;
    final l10n = AppLocalizations.of(context);
    final hasRun = w.completedRunId != null;
    final ok = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: Text(
                hasRun ? l10n.workoutUnlinkTitle : l10n.workoutMarkNotDoneTitle),
            content: Text(
                hasRun ? l10n.workoutUnlinkBody : l10n.workoutMarkNotDoneBody),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(l10n.workoutEditCancel),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error),
                child: Text(
                    hasRun ? l10n.workoutUnlink : l10n.workoutMarkNotDone),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok || !mounted) return;
    setState(() => _unlinking = true);
    try {
      await widget.training.markCompleted(widget.workoutId, null);
      await _load();
    } catch (e, s) {
      debugPrint('WorkoutDetailScreen._confirmUnlink failed: $e\n$s');
      if (mounted) {
        showTopBanner(context,
            hasRun ? l10n.workoutUnlinkError : l10n.workoutMarkNotDoneError);
      }
    } finally {
      if (mounted) setState(() => _unlinking = false);
    }
  }

  Future<void> _toggleSkip(PlanWorkoutRow w) async {
    if (_skipping) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _skipping = true);
    try {
      await widget.training.setSkipped(widget.workoutId, w.skippedAt == null);
      await _load();
    } catch (e, s) {
      debugPrint('WorkoutDetailScreen._toggleSkip failed: $e\n$s');
      if (mounted) showTopBanner(context, l10n.workoutSkipError);
    } finally {
      if (mounted) setState(() => _skipping = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (_loading) {
      return Scaffold(
        appBar: AppBar(),
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
            message: _error == _WorkoutLoadError.timeout
                ? l10n.workoutTimeoutError
                : l10n.workoutLoadError,
            onRetry: _load),
      );
    }
    final w = _workout;
    if (w == null) {
      return Scaffold(
        appBar: AppBar(),
        body: EmptyState(
          icon: Icons.directions_run,
          title: l10n.workoutNotFound,
        ),
      );
    }
    final theme = Theme.of(context);
    final kind = workoutKindFromDb(w.kind);
    final structure = w.structure == null
        ? null
        : WorkoutStructure.fromJson(w.structure!);

    return Scaffold(
      appBar: AppBar(),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          _hero(theme, l10n, w, kind, structure),
          const SizedBox(height: 12),
          _status(theme, l10n, w),
          if (w.notes != null && w.notes!.isNotEmpty)
            _card(theme, l10n.workoutSectionNotes,
                Text(w.notes!, style: theme.textTheme.bodyMedium)),
          if (structure != null)
            _card(theme, l10n.workoutSectionStructure,
                _structureBody(theme, l10n, structure, kind))
          else if (kind != WorkoutKind.rest)
            _card(theme, l10n.workoutSectionStructure,
                _freeForm(theme, l10n)),
          _card(theme, l10n.workoutSectionHowTo,
              Text(_advice(l10n, kind), style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }

  Future<void> _loadProvenance(PlanWorkoutRow? w) async {
    if (w == null || w.updatedBy == null) return;
    try {
      final owner = await widget.training
          .fetchPlanOwnerId(widget.planId)
          .timeout(kBackendLoadTimeout);
      final edited = isEditedByCoach(
        updatedBy: w.updatedBy,
        ownerId: owner,
        viewerId: widget.training.currentUserId,
      );
      if (mounted && edited != _editedByCoach) {
        setState(() => _editedByCoach = edited);
      }
    } catch (e) {
      debugPrint('WorkoutDetailScreen._loadProvenance failed: $e');
    }
  }

  Widget _hero(ThemeData theme, AppLocalizations l10n, PlanWorkoutRow w,
      WorkoutKind kind, WorkoutStructure? structure) {
    final tag = localeToTag(Localizations.localeOf(context));
    final isRace = kind == WorkoutKind.race;
    final walkRun = walkRunPattern(structure);
    final hasPace = w.targetPaceSecPerKm != null && walkRun == null;
    final secondary = <Widget>[
      if (walkRun == null && w.targetDistanceM != null)
        _metric(theme, l10n.workoutMetricDistance, fmtKm(w.targetDistanceM, 2)),
      if (walkRun == null && w.targetDurationSeconds != null)
        _metric(
            theme,
            isRace
                ? l10n.workoutEditRaceGoalTimeLabel
                : l10n.workoutMetricDuration,
            fmtHms(w.targetDurationSeconds)),
      if (isRace && racePriorities.contains(w.racePriority))
        _metric(theme, l10n.workoutEditRacePriorityLabel,
            racePriorityOptionLabel(l10n, w.racePriority!)),
      if (rpeTargetLabel(l10n, w.targetRpeMin, w.targetRpeMax) case final rpe?)
        KeyedSubtree(
          key: const Key('workoutDetailRpeTarget'),
          child: _metric(theme, l10n.workoutMetricEffort, rpe),
        ),
      if (_hrPrescription)
        if (hrTargetLabel(l10n, w.targetHrMinBpm, w.targetHrMaxBpm)
            case final hr?)
          KeyedSubtree(
            key: const Key('workoutDetailHrTarget'),
            child: _metric(theme, l10n.workoutMetricHeartRate, hr),
          ),
    ];
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(formatDateMed(w.scheduledDate, tag),
                key: const Key('workoutDetailDate'),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w700,
                )),
            const SizedBox(height: 4),
            Text(
                isRace && w.raceName != null
                    ? w.raceName!
                    : workoutKindLabel(l10n, kind),
                key: const Key('workoutDetailHeading'),
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(_tagline(l10n, kind, structure),
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            if (walkRun != null) ...[
              const SizedBox(height: 12),
              _label(theme, l10n.workoutMetricSession),
              Text(formatWalkRunTotal(l10n, walkRun),
                  key: const Key('walkRunTotal'),
                  style: theme.textTheme.headlineMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              Text(formatWalkRunPattern(l10n, walkRun),
                  key: const Key('walkRunPattern'),
                  style: theme.textTheme.bodyMedium),
            ] else if (hasPace) ...[
              const SizedBox(height: 12),
              _label(theme, l10n.workoutMetricTargetPace),
              Text(
                w.targetPaceEndSecPerKm != null &&
                        w.targetPaceEndSecPerKm != w.targetPaceSecPerKm
                    ? '${fmtPace(w.targetPaceSecPerKm)} → ${fmtPace(w.targetPaceEndSecPerKm)}'
                    : fmtPace(w.targetPaceSecPerKm),
                style: theme.textTheme.headlineMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              if (w.targetPaceToleranceSec != null ||
                  (w.paceZone != null && w.paceZone!.trim().isNotEmpty))
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (w.targetPaceToleranceSec != null)
                        Text(fmtPaceTolerance(w.targetPaceToleranceSec!),
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            )),
                      if (w.paceZone != null && w.paceZone!.trim().isNotEmpty)
                        _zoneChip(theme, l10n, w.paceZone!),
                    ],
                  ),
                ),
            ],
            if (secondary.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(spacing: 24, runSpacing: 10, children: secondary),
            ],
            if (_editedByCoach && w.updatedAt != null) ...[
              const SizedBox(height: 10),
              Row(
                key: const Key('workoutDetailCoachEdited'),
                children: [
                  Icon(Icons.sports,
                      size: 16, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      l10n.workoutUpdatedByCoach(
                          formatDateShort(w.updatedAt!.toLocal(), tag)),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _zoneChip(ThemeData theme, AppLocalizations l10n, String zone) {
    return Container(
      key: const Key('workoutDetailZone'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
      child: Text(
        formatPaceZone(l10n, zone, paceZoneName(zone)),
        style: theme.textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w700,
          color: theme.colorScheme.onPrimaryContainer,
        ),
      ),
    );
  }

  String _tagline(
      AppLocalizations l10n, WorkoutKind kind, WorkoutStructure? structure) {
    if (kind == WorkoutKind.walkRun) return l10n.workoutTaglineWalkRun;
    if (structure != null) return l10n.workoutTaglineStructured;
    return switch (kind) {
      WorkoutKind.easy || WorkoutKind.recovery => l10n.workoutTaglineEasy,
      WorkoutKind.long => l10n.workoutTaglineLong,
      WorkoutKind.rest => l10n.workoutTaglineRest,
      WorkoutKind.race => l10n.workoutTaglineRace,
      _ => l10n.workoutTaglineFreeForm,
    };
  }

  // The status row is a Wrap: German "Erledigt" plus "Neu verknüpfen" and
  // "Verknüpfung lösen" needs ~374 dp in a ~308 dp lane, and a Row(min)
  // overflowed there at 1.0x.
  Widget _status(ThemeData theme, AppLocalizations l10n, PlanWorkoutRow w) {
    Widget panel(
            {required Key key,
            required Color bg,
            required Color fg,
            required IconData icon,
            required String label,
            required List<Widget> actions}) =>
        Container(
          key: key,
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: AppIconSize.standard, color: fg),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(label,
                        style: TextStyle(color: fg, fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
              ...actions,
            ],
          ),
        );

    if (isWorkoutCompleted(w)) {
      return panel(
        key: const Key('workoutDetailCompleted'),
        bg: theme.colorScheme.primaryContainer,
        fg: theme.colorScheme.onPrimaryContainer,
        icon: Icons.check_circle,
        label: l10n.workoutCompleted,
        actions: [
          if (w.completedRunId != null)
            TextButton(
              onPressed: () => _openRelinkPicker(w),
              child: Text(l10n.workoutRelink),
            ),
          TextButton(
            onPressed: _unlinking ? null : () => _confirmUnlink(w),
            child: Text(w.completedRunId != null
                ? l10n.workoutUnlink
                : l10n.workoutMarkNotDone),
          ),
        ],
      );
    }
    if (w.skippedAt != null) {
      return panel(
        key: const Key('workoutDetailSkipped'),
        bg: theme.colorScheme.surfaceContainerHighest,
        fg: theme.colorScheme.onSurfaceVariant,
        icon: Icons.skip_next,
        label: l10n.workoutSkipped,
        actions: [
          TextButton(
            onPressed: _skipping ? null : () => _toggleSkip(w),
            child: Text(l10n.workoutUnskip),
          ),
        ],
      );
    }
    if (w.kind == 'rest') return const SizedBox.shrink();
    // Start pops with the workout row so callers can load it into the
    // WorkoutRunner; plan detail forwards it to RunScreen across a tab switch.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          onPressed: () => Navigator.of(context).pop(w),
          icon: const Icon(Icons.play_arrow),
          label: Text(l10n.workoutStart),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
        const SizedBox(height: 4),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            onPressed: _skipping ? null : () => _toggleSkip(w),
            icon: const Icon(Icons.skip_next, size: AppIconSize.standard),
            label: Text(l10n.workoutSkip),
          ),
        ),
      ],
    );
  }

  Widget _card(ThemeData theme, String title, Widget child) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              child,
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(ThemeData theme, String label) {
    return Text(label.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          letterSpacing: 0.6,
        ));
  }

  Widget _metric(ThemeData theme, String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(theme, label),
        Text(value,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700)),
      ],
    );
  }

  Widget _freeForm(ThemeData theme, AppLocalizations l10n) {
    return Row(
      key: const Key('workoutDetailFreeForm'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.timeline,
            size: AppIconSize.material,
            color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.workoutFreeFormTitle,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              Text(l10n.workoutFreeFormHint,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  )),
            ],
          ),
        ),
      ],
    );
  }

  Color _roleColor(ThemeData theme, WorkoutKind kind, SegmentRole role) {
    final mark = workoutKindMarkColor(theme, kind);
    final muted = theme.colorScheme.onSurfaceVariant;
    return switch (role) {
      SegmentRole.warmup => muted.withValues(alpha: 0.55),
      SegmentRole.cooldown => muted.withValues(alpha: 0.35),
      SegmentRole.work || SegmentRole.steady => mark,
      SegmentRole.recovery => mark.withValues(alpha: 0.3),
    };
  }

  Widget _structureBody(ThemeData theme, AppLocalizations l10n,
      WorkoutStructure s, WorkoutKind kind) {
    final segments = structureSegments(s);
    final total = structureTotal(s);
    final rows = <Widget>[];

    void add(SegmentRole role, String term, String main,
        {String? pace, String? recovery}) {
      rows.add(Padding(
        padding: const EdgeInsets.only(top: 10),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 4,
                decoration: BoxDecoration(
                  color: _roleColor(theme, kind, role),
                  borderRadius: BorderRadius.circular(AppRadius.xs),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 2,
                  children: [
                    TextLane(
                      width: 90,
                      child: Text(term,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                          )),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(main,
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w700)),
                        if (pace != null)
                          Text(pace,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              )),
                        if (recovery != null)
                          Text.rich(
                            key: const Key('workoutStepRecovery'),
                            TextSpan(children: [
                              TextSpan(
                                  text: '${l10n.workoutStructRecovery}  ',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700)),
                              TextSpan(text: recovery),
                            ]),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ));
    }

    if (s.warmup != null) {
      add(SegmentRole.warmup, l10n.workoutStructWarmup,
          _stepAmount(s.warmup!, 1),
          pace: l10n.workoutStructAtEasy);
    }
    if (s.repeats != null) {
      final r = s.repeats!;
      final pace = (r['pace_sec_per_km'] as num?)?.toInt();
      final count = r['count'];
      add(
        SegmentRole.work,
        l10n.workoutStructRepeats,
        l10n.workoutStructRepeatsMain(
            count is num ? count.toInt() : 0, _stepAmount(r, 2)),
        pace: pace == null ? null : l10n.workoutStructAtPace(fmtPace(pace)),
        recovery: _recoveryLabel(l10n, r),
      );
    }
    if (s.steady != null) {
      final st = s.steady!;
      final pace = (st['pace_sec_per_km'] as num?)?.toInt();
      add(SegmentRole.steady, l10n.workoutStructSteady, _stepAmount(st, 1),
          pace: pace == null ? null : l10n.workoutStructAtPace(fmtPace(pace)));
    }
    if (s.cooldown != null) {
      add(SegmentRole.cooldown, l10n.workoutStructCooldown,
          _stepAmount(s.cooldown!, 1),
          pace: l10n.workoutStructAtEasy);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (segments.isNotEmpty)
          Semantics(
            label: l10n.workoutTimelineLabel,
            child: ExcludeSemantics(
              child: ClipRRect(
                key: const Key('workoutDetailTimeline'),
                borderRadius: BorderRadius.circular(AppRadius.xs),
                child: SizedBox(
                  height: 12,
                  child: Row(
                    children: [
                      for (final seg in segments)
                        Expanded(
                          flex: (seg.fraction * 1000).round().clamp(10, 1000),
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 1),
                            color: _roleColor(theme, kind, seg.role),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ...rows,
        if (total != null) ...[
          const Divider(height: 24),
          Text(
            l10n.workoutStructTotal(switch (total) {
              StructureTotalDistance(:final metres) => fmtKm(metres, 2),
              StructureTotalDuration(:final seconds) => fmtHms(seconds.round()),
            }),
            key: const Key('workoutDetailTotal'),
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }

  String? _recoveryLabel(AppLocalizations l10n, Map<String, dynamic> r) {
    if (r['recovery_distance_m'] == null && r['recovery_duration_s'] == null) {
      return null;
    }
    final amount = _stepAmount(r, 2, recovery: true);
    final effort = switch (r['recovery_pace']) {
      'jog' => l10n.workoutEffortJog,
      'easy' => l10n.workoutEffortEasy,
      'walk' => l10n.workoutEffortWalk,
      _ => null,
    };
    return effort == null
        ? amount
        : l10n.workoutStructRecoveryDetail(amount, effort);
  }

  // A step reads as its distance when it has one, else its duration: the
  // walk-run generator writes only `duration_s`, and a hard `as num` cast on
  // the missing `distance_m` threw. Mirrors web's `stepAmount`.
  String _stepAmount(Map<String, dynamic> step, int digits,
      {bool recovery = false}) {
    final distance =
        step[recovery ? 'recovery_distance_m' : 'distance_m'] as num?;
    if (distance != null) return fmtKm(distance, digits);
    final duration =
        step[recovery ? 'recovery_duration_s' : 'duration_s'] as num?;
    if (duration != null) return fmtHms(duration.toInt());
    return '—';
  }

  String _advice(AppLocalizations l10n, WorkoutKind k) => switch (k) {
        WorkoutKind.easy || WorkoutKind.recovery => l10n.workoutAdviceEasy,
        WorkoutKind.long => l10n.workoutAdviceLong,
        WorkoutKind.tempo => l10n.workoutAdviceTempo,
        WorkoutKind.interval => l10n.workoutAdviceInterval,
        WorkoutKind.marathonPace => l10n.workoutAdviceMarathonPace,
        WorkoutKind.walkRun => l10n.workoutAdviceWalkRun,
        WorkoutKind.race => l10n.workoutAdviceRace,
        WorkoutKind.rest => l10n.workoutAdviceRest,
      };
}

enum _WorkoutLoadError { timeout, generic }

class _RelinkPickerDialog extends StatefulWidget {
  final TrainingService training;
  final PlanWorkoutRow workout;
  const _RelinkPickerDialog({required this.training, required this.workout});

  @override
  State<_RelinkPickerDialog> createState() => _RelinkPickerDialogState();
}

class _RelinkPickerDialogState extends State<_RelinkPickerDialog> {
  bool _loading = true;
  bool _error = false;
  List<RelinkCandidateRun> _candidates = const [];

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    try {
      final c = await widget.training
          .fetchRelinkCandidates(widget.workout)
          .timeout(kBackendLoadTimeout);
      if (!mounted) return;
      setState(() {
        _candidates = c;
        _loading = false;
      });
    } catch (e, s) {
      debugPrint('_RelinkPickerDialog._fetch failed: $e\n$s');
      if (mounted) {
        setState(() {
          _loading = false;
          _error = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tag = localeToTag(Localizations.localeOf(context));
    final currentId = widget.workout.completedRunId;

    Widget body;
    if (_loading) {
      body = ListSkeleton.section(
        label: l10n.commonLoading,
        rows: 3,
        rowHeight: 56,
        hasLeading: false,
      );
    } else if (_error) {
      body = Text(l10n.workoutRelinkError);
    } else if (_candidates.isEmpty) {
      body = Text(l10n.workoutRelinkEmpty);
    } else {
      body = ListView.builder(
        shrinkWrap: true,
        itemCount: _candidates.length,
        itemBuilder: (ctx, i) {
          final run = _candidates[i];
          final isCurrent = run.id == currentId;
          return ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(formatDateShort(run.startedAt, tag)),
            subtitle: Text(
              '${fmtKm(run.distanceM, 2)} · ${fmtHms(run.durationS)}',
            ),
            trailing: isCurrent
                ? Text(
                    l10n.workoutRelinkCurrent,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                  )
                : null,
            onTap: () => Navigator.of(context).pop(run.id),
          );
        },
      );
    }

    return AlertDialog(
      title: Text(l10n.workoutRelinkTitle),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.workoutRelinkHint,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Flexible(child: body),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
      ],
    );
  }
}
