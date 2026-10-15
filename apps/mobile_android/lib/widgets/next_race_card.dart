import 'package:flutter/material.dart';

import '../l10n/date_format.dart';
import '../l10n/gen/app_localizations.dart';
import '../l10n/locale_support.dart';
import '../plan_week.dart';
import '../training.dart' show toIsoDate;
import '../training_service.dart';

/// The active plan's race day on Home: the plan's name, its race date and how
/// far away that is. Mirrors the countdown in web `/dashboard`'s plan card; the
/// day count is the shared `planRaceCountdown` (plan_week pair), so the two
/// cannot disagree. Races were otherwise reachable only from the Training
/// tab's peer strip, where Races sat last (decisions § 1954).
///
/// Self-hiding once the race is behind the runner: a countdown to a past date
/// says nothing, and the plan itself is still one tap away under Training.
class NextRaceCard extends StatelessWidget {
  final ActivePlanOverview overview;
  final DateTime now;
  final VoidCallback? onTap;

  const NextRaceCard({
    super.key,
    required this.overview,
    required this.now,
    this.onTap,
  });

  static PlanRaceCountdown countdownFor(ActivePlanOverview overview, DateTime now) =>
      planRaceCountdown(
        toIsoDate(overview.plan.startDate),
        toIsoDate(overview.plan.endDate),
        toIsoDate(now),
      );

  /// Whether the card has anything to say for [overview] on [now].
  static bool shows(ActivePlanOverview overview, DateTime now) =>
      countdownFor(overview, now).kind != PlanRaceCountdownKind.racePast;

  static String relation(AppLocalizations l10n, PlanRaceCountdown c) =>
      switch (c.kind) {
        PlanRaceCountdownKind.startsIn => c.days == 1
            ? l10n.homePlanStartsTomorrow
            : l10n.homePlanStartsInDays(c.days),
        PlanRaceCountdownKind.raceIn =>
          c.days == 1 ? l10n.homeRaceTomorrow : l10n.homeRaceInDays(c.days),
        PlanRaceCountdownKind.raceDay => l10n.homeRaceDay,
        PlanRaceCountdownKind.racePast => '',
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final tag = localeToTag(Localizations.localeOf(context));
    final countdown = countdownFor(overview, now);
    final raceDay = countdown.kind == PlanRaceCountdownKind.raceDay;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              Icon(Icons.flag_outlined, color: theme.colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.homeTrainingPlanLabel,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      overview.plan.name,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      formatDateMed(overview.plan.endDate, tag),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  relation(l10n, countdown),
                  key: const Key('nextRaceCountdown'),
                  textAlign: TextAlign.end,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: raceDay
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
