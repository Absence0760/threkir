import 'package:core_models/core_models.dart' hide Route;
import 'package:flutter/material.dart';

import '../auth_error.dart';
import '../l10n/date_format.dart';
import '../l10n/gen/app_localizations.dart';
import '../l10n/locale_support.dart';
import '../plan_break.dart';
import '../plan_race_date.dart';
import '../settings_sync.dart';
import '../training.dart' show parseIsoDate, toIsoDate;
import '../training_service.dart';
import 'confirm_destructive.dart';
import 'top_banner.dart';

const String kPlanBreakDismissedKey = 'plan_break_dismissed';

/// What the settings bag says about the last answered break: [loaded] false
/// until the bag has loaded, when the card stays hidden rather than offer a
/// break the runner may already have answered on another device.
typedef PlanBreakDismissal = ({bool loaded, Object? value});

PlanBreakDismissal _activeDismissal() {
  final s = activeSettingsService();
  return (
    loaded: s != null,
    value: s?.effective<Object>(kPlanBreakDismissedKey),
  );
}

Future<void> _writeActiveDismissal(Map<String, dynamic> value) async {
  final s = activeSettingsService();
  if (s == null) throw StateError('settings not loaded');
  await s.updateUniversal({kPlanBreakDismissedKey: value});
}

/// Where the card reads and writes the dismissal: the app's settings bag.
/// A widget test points these at its own.
@visibleForTesting
PlanBreakDismissal Function() planBreakDismissalReader = _activeDismissal;
@visibleForTesting
Future<void> Function(Map<String, dynamic>) planBreakDismissalWriter =
    _writeActiveDismissal;

/// A break of a week or more in the runner's own active plan (decisions
/// § 2128): one calm offer to run the missed weeks again, previewed and
/// applied in one transaction, or to keep the plan as it is. The host shows
/// it only for the plan's owner. Web twin: `PlanBreakCard.svelte`.
class PlanBreakCard extends StatefulWidget {
  final TrainingService training;
  final TrainingPlanRow plan;
  final List<PlanWeekRow> weeks;
  final List<PlanWorkoutRow> workouts;

  /// When the runner's runs started; null while unknown, which hides the
  /// card rather than call a runner whose runs did not load on a break.
  final List<DateTime>? runStarts;
  final DateTime now;

  /// Runs after a change applied, so the host can re-read the plan.
  final Future<void> Function() onApplied;

  const PlanBreakCard({
    super.key,
    required this.training,
    required this.plan,
    required this.weeks,
    required this.workouts,
    required this.runStarts,
    required this.now,
    required this.onApplied,
  });

  /// Whether a card built from these would show: a break to offer that the
  /// runner has not already answered. Hosts check it so an absent card leaves
  /// no gap.
  static bool shows({
    required TrainingPlanRow plan,
    required List<PlanWeekRow> weeks,
    required List<PlanWorkoutRow> workouts,
    required List<DateTime>? runStarts,
    required DateTime now,
  }) {
    final found = _detectFor(plan, weeks, workouts, runStarts, now);
    if (found == null) return false;
    final d = planBreakDismissalReader();
    return d.loaded && !isBreakDismissed(d.value, plan.id, found.fromIso);
  }

  @override
  State<PlanBreakCard> createState() => _PlanBreakCardState();
}

RaceDatePlan _planOf(TrainingPlanRow p) => RaceDatePlan(
  startDate: toIsoDate(p.startDate),
  endDate: toIsoDate(p.endDate),
  trimmedAt: p.trimmedAt?.toIso8601String(),
  status: p.status,
  isTemplate: p.isTemplate,
);

List<RaceDateWeek> _weeksOf(List<PlanWeekRow> weeks) => [
  for (final w in weeks)
    RaceDateWeek(id: w.id, weekIndex: w.weekIndex, phase: w.phase),
];

List<RaceDateWorkout> _workoutsOf(List<PlanWorkoutRow> workouts) => [
  for (final w in workouts)
    RaceDateWorkout(
      id: w.id,
      weekId: w.weekId,
      scheduledDate: toIsoDate(w.scheduledDate),
      kind: w.kind,
      completedRunId: w.completedRunId,
      manuallyCompleted: w.manuallyCompleted,
    ),
];

List<String> _datesOf(List<DateTime>? runStarts) => [
  for (final d in runStarts ?? const <DateTime>[]) toIsoDate(d.toLocal()),
];

PlanBreak? _detectFor(
  TrainingPlanRow plan,
  List<PlanWeekRow> weeks,
  List<PlanWorkoutRow> workouts,
  List<DateTime>? runStarts,
  DateTime now,
) {
  if (runStarts == null) return null;
  return detectPlanBreak(
    plan: _planOf(plan),
    weeks: _weeksOf(weeks),
    workouts: _workoutsOf(workouts),
    runDatesIso: _datesOf(runStarts),
    todayIso: toIsoDate(now),
  );
}

class _PlanBreakCardState extends State<PlanBreakCard> {
  bool _hidden = false;
  bool _busy = false;
  int? _weeksChoice;

  String get _todayIso => toIsoDate(widget.now);

  PlanBreak? _detect() => _detectFor(
    widget.plan,
    widget.weeks,
    widget.workouts,
    widget.runStarts,
    widget.now,
  );

  Future<void> _propose(PlanBreak found, int k) async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    final tag = localeToTag(Localizations.localeOf(context));
    final change = planBreakChange(
      plan: _planOf(widget.plan),
      weeks: _weeksOf(widget.weeks),
      workouts: _workoutsOf(widget.workouts),
      runDatesIso: _datesOf(widget.runStarts),
      todayIso: _todayIso,
      weeksToRepeat: k,
    );
    if (change == null) {
      showTopBanner(context, l10n.planBreakUnavailable);
      return;
    }
    final end = formatDateMed(parseIsoDate(change.endIso), tag);
    final lines = [
      l10n.planBreakPreviewRepeat(change.weeks),
      if (change.dropWeekIds.isNotEmpty) ...[
        l10n.planBreakPreviewDropped(change.dropWeekIds.length),
        l10n.planBreakPreviewRaceDay(end),
      ] else
        l10n.planBreakPreviewEnd(end),
      l10n.planBreakPreviewPast,
    ];
    final ok = await confirmDestructive(
      context,
      title: l10n.planBreakConfirmTitle,
      body: lines.join(' '),
      confirmLabel: l10n.planBreakConfirmApply,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.training.reschedulePlanAfterBreak(
        widget.plan.id,
        change,
        found.fromIso,
        _todayIso,
      );
    } on ActivePlanExistsError {
      if (mounted) {
        setState(() => _busy = false);
        showTopBanner(context, l10n.planOverlapConflict);
      }
      return;
    } catch (e) {
      debugPrint('plan break reschedule failed: $e');
      if (mounted) {
        setState(() => _busy = false);
        showTopBanner(context, l10n.planBreakFailed(friendlyError(l10n, e)));
      }
      return;
    }
    try {
      await planBreakDismissalWriter({
        'plan_id': widget.plan.id,
        'from': found.fromIso,
      });
    } catch (e) {
      debugPrint('plan break: local dismissal write failed: $e');
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _hidden = true;
    });
    showTopBanner(context, l10n.planBreakApplied(end));
    await widget.onApplied();
  }

  Future<void> _dismiss(PlanBreak found) async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      await planBreakDismissalWriter({
        'plan_id': widget.plan.id,
        'from': found.fromIso,
      });
    } catch (e) {
      debugPrint('plan break dismiss failed: $e');
      if (mounted) {
        setState(() => _busy = false);
        showTopBanner(
          context,
          l10n.planBreakDismissFailed(friendlyError(l10n, e)),
        );
      }
      return;
    }
    if (mounted) {
      setState(() {
        _busy = false;
        _hidden = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_hidden) return const SizedBox.shrink();
    final found = _detect();
    if (found == null) return const SizedBox.shrink();
    final dismissal = planBreakDismissalReader();
    if (!dismissal.loaded ||
        isBreakDismissed(dismissal.value, widget.plan.id, found.fromIso)) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final tag = localeToTag(Localizations.localeOf(context));
    final weeks = (_weeksChoice ?? found.maxWeeks).clamp(1, found.maxWeeks);
    final race = found.raceDateIso;
    return Card(
      key: const Key('planBreakCard'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.history, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.planBreakTitle,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        l10n.planBreakBody(
                          found.days,
                          formatDateMed(parseIsoDate(found.fromIso), tag),
                        ),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        race != null
                            ? l10n.planBreakHintRace(
                                formatDateMed(parseIsoDate(race), tag),
                              )
                            : l10n.planBreakHintNoRace,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton(
                  key: const Key('planBreakRepeat'),
                  onPressed: _busy ? null : () => _propose(found, 1),
                  child: Text(l10n.planBreakRepeat),
                ),
                if (found.maxWeeks >= 2) ...[
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(l10n.planBreakWeeksLabel),
                      IconButton(
                        key: const Key('planBreakWeeksMinus'),
                        tooltip: l10n.planBreakWeeksFewer,
                        icon: const Icon(Icons.remove),
                        onPressed: _busy || weeks <= 1
                            ? null
                            : () => setState(() => _weeksChoice = weeks - 1),
                      ),
                      Text('$weeks', key: const Key('planBreakWeeks')),
                      IconButton(
                        key: const Key('planBreakWeeksPlus'),
                        tooltip: l10n.planBreakWeeksMore,
                        icon: const Icon(Icons.add),
                        onPressed: _busy || weeks >= found.maxWeeks
                            ? null
                            : () => setState(() => _weeksChoice = weeks + 1),
                      ),
                    ],
                  ),
                  OutlinedButton(
                    key: const Key('planBreakMore'),
                    onPressed: _busy ? null : () => _propose(found, weeks),
                    child: Text(
                      race != null
                          ? l10n.planBreakShortenBuild
                          : l10n.planBreakPushBack,
                    ),
                  ),
                ],
                TextButton(
                  key: const Key('planBreakDismiss'),
                  onPressed: _busy ? null : () => _dismiss(found),
                  child: Text(l10n.planBreakDismiss),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
