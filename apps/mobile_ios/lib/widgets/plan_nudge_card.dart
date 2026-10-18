import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';

import '../l10n/gen/app_localizations.dart';
import '../plan_nudges.dart';
import '../settings_sync.dart';
import '../training.dart' show isWorkoutCompleted, toIsoDate;
import '../training_service.dart' show ActivePlanOverview;
import 'top_banner.dart';

/// The one plan card Home shows unprompted ([planNudge]): an existing re-plan
/// proposal worth a look, or the rest-day-runs note. Review hands the plan's
/// own preview the job ([onReview]); nothing here proposes or writes a change.
/// Both Review and Dismiss file the occurrence in `plan_nudges_dismissed`, so
/// it is not offered again on any device until a new week brings one. Web
/// twin: `PlanNudgeCard.svelte`.
class PlanNudgeCard extends StatefulWidget {
  final ActivePlanOverview overview;
  final List<Run> runs;
  final SettingsSyncService? settingsSync;
  final DateTime now;
  final void Function(PlanNudge nudge) onReview;

  /// The days a break covered (`breakWindow`): no nudge judges them.
  final ({String fromIso, String untilIso})? breakWindow;

  const PlanNudgeCard({
    super.key,
    required this.overview,
    required this.runs,
    required this.settingsSync,
    required this.now,
    required this.onReview,
    this.breakWindow,
  });

  /// The dismissed occurrences in the prefs bag.
  static List<String> dismissedIn(SettingsSyncService? sync) =>
      parseDismissedNudges(sync?.service?.effective<Object>(dismissedNudgesKey));

  /// The card's occurrence, or null when there is nothing to say. Auxiliary
  /// (L4): a malformed row must cost the card, never Home.
  static PlanNudge? nudgeFor({
    required ActivePlanOverview overview,
    required List<Run> runs,
    required List<String> dismissed,
    required DateTime now,
    ({String fromIso, String untilIso})? breakWindow,
  }) {
    try {
      final o = overview;
      final today = toIsoDate(now);
      final byWeek = <String, List<PlanWorkoutRow>>{};
      for (final w in o.workouts) {
        (byWeek[w.weekId] ??= []).add(w);
      }
      final runRows = [
        for (final r in runs)
          NudgeInputRun(
            date: toIsoDate(r.startedAt.toLocal()),
            distanceM: r.distanceMetres,
          ),
      ];
      final weeks = buildReplanWeeks(
        startDate: toIsoDate(o.plan.startDate),
        today: today,
        runs: runRows,
        weeks: [
          for (final w in o.weeks)
            NudgeInputWeek(
              weekIndex: w.weekIndex,
              phase: w.phase,
              targetVolumeM: w.targetVolumeM,
              workouts: [
                for (final x in byWeek[w.id] ?? const <PlanWorkoutRow>[])
                  NudgeInputWorkout(
                    id: x.id,
                    scheduledDate: toIsoDate(x.scheduledDate),
                    kind: x.kind,
                    targetDistanceM: x.targetDistanceM,
                    completed: isWorkoutCompleted(x),
                    skipped: x.skippedAt != null,
                  ),
              ],
            ),
        ],
      );
      return planNudge(
        planId: o.plan.id,
        status: o.plan.status,
        isTemplate: o.plan.isTemplate,
        startDate: toIsoDate(o.plan.startDate),
        endDate: toIsoDate(o.plan.endDate),
        today: today,
        weeks: weeks,
        runDates: [for (final r in runRows) r.date],
        dismissed: dismissed,
        breakFromIso: breakWindow?.fromIso,
        breakUntilIso: breakWindow?.untilIso,
      );
    } catch (e) {
      debugPrint('PlanNudgeCard: working out the card failed: $e');
      return null;
    }
  }

  @override
  State<PlanNudgeCard> createState() => _PlanNudgeCardState();
}

class _PlanNudgeCardState extends State<PlanNudgeCard> {
  List<String>? _filed;

  List<String> get _dismissed =>
      _filed ?? PlanNudgeCard.dismissedIn(widget.settingsSync);

  PlanNudge? _nudge() => PlanNudgeCard.nudgeFor(
        overview: widget.overview,
        runs: widget.runs,
        dismissed: _dismissed,
        now: widget.now,
        breakWindow: widget.breakWindow,
      );

  Future<bool> _file(String key) async {
    final sync = widget.settingsSync;
    final previous = _dismissed;
    final next = withDismissedNudge(previous, key);
    setState(() => _filed = next);
    try {
      if (sync == null) throw StateError('no settings sync');
      await sync.updateUniversal(<String, dynamic>{dismissedNudgesKey: next});
      return true;
    } catch (e) {
      debugPrint('PlanNudgeCard: saving the dismissal failed: $e');
      if (mounted) setState(() => _filed = previous);
      return false;
    }
  }

  Future<void> _dismiss(PlanNudge n) async {
    final message = AppLocalizations.of(context).planNudgeDismissFailed;
    if (!await _file(n.key) && mounted) showTopBanner(context, message);
  }

  void _review(PlanNudge n) {
    _file(n.key);
    widget.onReview(n);
  }

  @override
  Widget build(BuildContext context) {
    final n = _nudge();
    if (n == null) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final (title, body) = switch (n.kind) {
      PlanNudgeKind.adaptiveUnder => (
          l10n.planNudgeUnderTitle,
          l10n.planNudgeUnderBody(n.weeks, n.ofWeeks)
        ),
      PlanNudgeKind.easeOver => (l10n.planNudgeEaseTitle, l10n.planNudgeEaseBody),
      PlanNudgeKind.restDayRuns => (
          l10n.planNudgeRestTitle,
          l10n.planNudgeRestBody(n.weeks, n.ofWeeks)
        ),
    };
    return Card(
      key: const Key('planNudgeCard'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2, right: 12),
                  child: Icon(
                    n.kind == PlanNudgeKind.restDayRuns
                        ? Icons.self_improvement
                        : Icons.tune,
                    color: theme.colorScheme.primary,
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Semantics(
                        header: true,
                        child: Text(title, style: theme.textTheme.titleSmall),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        body,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Wrap(
              alignment: WrapAlignment.end,
              children: [
                Semantics(
                  label: l10n.planNudgeDismissA11y,
                  button: true,
                  excludeSemantics: true,
                  onTap: () => _dismiss(n),
                  child: TextButton(
                    key: const Key('planNudgeDismiss'),
                    onPressed: () => _dismiss(n),
                    child: Text(l10n.planNudgeDismiss),
                  ),
                ),
                if (n.kind != PlanNudgeKind.restDayRuns)
                  TextButton(
                    key: const Key('planNudgeReview'),
                    onPressed: () => _review(n),
                    child: Text(l10n.planNudgeReview),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
