import 'package:flutter/material.dart';

import '../l10n/date_format.dart';
import '../l10n/gen/app_localizations.dart';
import '../l10n/locale_support.dart';
import '../plan_races.dart';
import '../plan_week.dart';
import '../training.dart' show parseIsoDate, toIsoDate;
import '../training_service.dart';

/// The active plan's next race on Home: the race's name (the plan's for the
/// plan's own end-date race), its date and how far away that is. A plan can
/// hold several races (`plan_races.dart`), so a B race mid-block gets its
/// own countdown before the A race at the end. Mirrors the countdown in web `/dashboard`'s plan card; the
/// day count is the shared `planRaceCountdown` (plan_week pair), so the two
/// cannot disagree. Races were otherwise reachable only from the Training
/// tab's peer strip, where Races sat last (decisions § 1954).
///
/// Self-hiding once the plan's last race is behind the runner: a countdown to a past date
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

  /// The first race of [overview]'s plan on or after [now]'s day, or null
  /// once the last one has passed.
  static PlanRace? nextRaceFor(ActivePlanOverview overview, DateTime now) {
    final plan = overview.plan;
    return nextRace(
      planRaces(
        endDate: toIsoDate(plan.endDate),
        goalDistanceM: plan.goalDistanceM,
        goalTimeSec: plan.goalTimeSeconds,
        workouts: [
          for (final w in overview.workouts) PlanRaceWorkout.fromRow(w),
        ],
      ),
      toIsoDate(now),
    );
  }

  static PlanRaceCountdown countdownFor(ActivePlanOverview overview, DateTime now) =>
      planRaceCountdown(
        toIsoDate(overview.plan.startDate),
        nextRaceFor(overview, now)?.date ?? toIsoDate(overview.plan.endDate),
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
    final race = nextRaceFor(overview, now);
    final raceDate =
        race == null ? overview.plan.endDate : parseIsoDate(race.date);
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
                      race?.name ?? overview.plan.name,
                      key: const Key('nextRaceName'),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      formatDateMed(raceDate, tag),
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
