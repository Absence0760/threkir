import 'package:core_models/core_models.dart' hide Route;
import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart'
    show AppSemanticColors, ListCard, ProgressBar, StatusPill, StatusPillSize;

import '../l10n/date_format.dart';
import '../l10n/gen/app_localizations.dart';
import '../l10n/locale_support.dart';
import '../l10n/number_format.dart';
import '../metrics.dart';
import '../plan_labels.dart';
import '../plan_week.dart';
import '../training.dart';
import 'next_race_card.dart';
import 'plan_meta_item.dart';

/// One plan on the list: name and status, the goal / target / VDOT it was
/// built for, its dates and length, and — while it is active — where today
/// sits in it. Mirrors web `plans/+page.svelte`'s card. Exactly one action:
/// Abandon while the plan is still live (active or paused), Delete once it is
/// over.
class PlanListCard extends StatelessWidget {
  final TrainingPlanRow plan;
  final DateTime now;
  final VoidCallback onTap;
  final VoidCallback? onAbandon;
  final VoidCallback? onDelete;

  /// This card's own Abandon / Delete is being written.
  final bool actionBusy;

  /// Some card's action is being written, so this one waits.
  final bool actionsLocked;

  const PlanListCard({
    super.key,
    required this.plan,
    required this.now,
    required this.onTap,
    this.onAbandon,
    this.onDelete,
    this.actionBusy = false,
    this.actionsLocked = false,
  }) : assert(
         (onAbandon == null) != (onDelete == null),
         'a plan card carries exactly one action',
       );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final tag = localeToTag(Localizations.localeOf(context));
    final semantic = AppSemanticColors.ofTheme(theme);
    final todayIso = toIsoDate(now);
    final startIso = toIsoDate(plan.startDate);
    final endIso = toIsoDate(plan.endDate);
    final active = plan.status == 'active';
    // An active plan that hasn't started is queued behind the current one.
    final upcoming = active && startIso.compareTo(todayIso) > 0;
    final weeks = planWeekCount(plan.startDate, plan.endDate);

    final statusLabel = upcoming
        ? l10n.plansStatusUpcoming
        : planStatusLabel(l10n, plan.status);
    final pill = _pill(theme, semantic, statusLabel, upcoming);
    final goal = planGoalLabel(l10n, plan.goalEvent, plan.goalDistanceM);
    final target = plan.goalTimeSeconds != null && plan.goalTimeSeconds! > 0
        ? fmtHms(plan.goalTimeSeconds)
        : l10n.plansGoalFinish;
    final vdot = plan.vdot == null
        ? null
        : formatFixed(plan.vdot!.toDouble(), 1, activeLocaleTag);
    final dates =
        '${formatDateShort(plan.startDate, tag)} → ${formatDateShort(plan.endDate, tag)}';
    final length = planLengthLabel(l10n, weeks, plan.daysPerWeek);

    String? weekLine;
    String? when;
    double? progress;
    if (active) {
      final week = currentPlanWeekIndex(startIso, todayIso, weeks) + 1;
      weekLine = l10n.plansWeekOf(week, weeks);
      final countdown = planRaceCountdown(startIso, endIso, todayIso);
      when = countdown.kind == PlanRaceCountdownKind.racePast
          ? l10n.plansEnded
          : NextRaceCard.relation(l10n, countdown);
      progress = _calendarProgress(startIso, endIso, todayIso);
    }

    final label = [
      plan.name,
      statusLabel,
      '${l10n.plansHeroGoal}: $goal',
      '${l10n.plansHeroTarget}: $target',
      if (vdot != null) '${metricText(l10n, Metric.vdot)}: $vdot',
      dates,
      length,
      ?weekLine,
      if (when != null && when.isNotEmpty) when,
    ].join(', ');

    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                plan.name,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Flexible(child: pill),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 20,
          runSpacing: 8,
          children: [
            _Hero(label: l10n.plansHeroGoal, value: goal, accent: true),
            _Hero(label: l10n.plansHeroTarget, value: target),
            if (vdot != null)
              _Hero(label: metricText(l10n, Metric.vdot), value: vdot),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: [
            PlanMetaItem(icon: Icons.date_range, text: dates),
            PlanMetaItem(icon: Icons.view_week_outlined, text: length),
          ],
        ),
        if (weekLine != null && progress != null) ...[
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  weekLine,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (when != null && when.isNotEmpty) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    when,
                    textAlign: TextAlign.end,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          ProgressBar(value: progress),
        ],
      ],
    );

    return ListCard(
      dense: true,
      onTap: onTap,
      semanticLabel: label,
      actions: [
        if (onAbandon != null)
          TextButton.icon(
            key: const Key('planCardAbandon'),
            onPressed: actionsLocked ? null : onAbandon,
            icon: _busyIcon(),
            label: Text(l10n.plansAbandon),
          )
        else
          TextButton.icon(
            key: const Key('planCardDelete'),
            onPressed: actionsLocked ? null : onDelete,
            style: TextButton.styleFrom(foregroundColor: semantic.danger),
            icon: _busyIcon(),
            label: Text(l10n.plansDelete),
          ),
      ],
      child: info,
    );
  }

  /// A spinner on the button whose write is out, nothing otherwise.
  Widget? _busyIcon() => actionBusy
      ? const SizedBox.square(
          dimension: 14,
          child: CircularProgressIndicator(strokeWidth: 2),
        )
      : null;

  Widget _pill(
    ThemeData theme,
    AppSemanticColors semantic,
    String label,
    bool upcoming,
  ) {
    final scheme = theme.colorScheme;
    final (IconData icon, Color fg, Color bg) = upcoming
        ? (
            Icons.schedule,
            scheme.onSecondaryContainer,
            scheme.secondaryContainer,
          )
        : switch (plan.status) {
            'active' => (
              Icons.play_circle,
              scheme.onPrimaryContainer,
              scheme.primaryContainer,
            ),
            'paused' => (
              Icons.pause_circle,
              scheme.onTertiaryContainer,
              scheme.tertiaryContainer,
            ),
            'completed' => (
              Icons.check_circle,
              semantic.onSuccess,
              semantic.success,
            ),
            _ => (
              Icons.cancel_outlined,
              scheme.onSurfaceVariant,
              scheme.surfaceContainerHigh,
            ),
          };
    return StatusPill(
      key: upcoming ? const Key('planTileUpcoming') : null,
      label: label,
      icon: icon,
      foreground: fg,
      fill: bg,
      size: StatusPillSize.compact,
    );
  }
}

/// Calendar position (0..1) between a plan's start and end, counted in whole
/// days. Calendar-based, not workout-based, like web's `calendarPct`: cheap to
/// compute without a per-plan workouts fetch, and it answers "where am I in
/// the plan", which is all the list card asks.
double _calendarProgress(String startIso, String endIso, String todayIso) {
  int day(String iso) {
    final p = iso.split('-').map(int.parse).toList();
    return DateTime.utc(p[0], p[1], p[2]).millisecondsSinceEpoch ~/ 86400000;
  }

  final start = day(startIso), end = day(endIso), today = day(todayIso);
  if (today <= start) return 0;
  if (today >= end) return 1;
  return (today - start) / (end - start);
}

class _Hero extends StatelessWidget {
  final String label;
  final String value;
  final bool accent;

  const _Hero({required this.label, required this.value, this.accent = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: accent ? theme.colorScheme.primary : null,
          ),
        ),
      ],
    );
  }
}
