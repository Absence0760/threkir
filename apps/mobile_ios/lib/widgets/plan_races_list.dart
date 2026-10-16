import 'package:flutter/material.dart';

import '../l10n/date_format.dart';
import '../l10n/gen/app_localizations.dart';
import '../l10n/locale_support.dart';
import '../plan_races.dart';
import '../plan_week.dart';
import '../goal_time.dart' show formatRaceGoalTimeS;
import '../training.dart' show fmtKm, parseIsoDate;
import 'next_race_card.dart';

/// The races a plan builds toward, on plan detail: priority, name (the plan's
/// own for its end-date race), date, distance and goal time, with the next
/// one's countdown. Only worth a card when the plan has more than one race;
/// a single race is already the plan's goal in the header.
class PlanRacesList extends StatelessWidget {
  final String planName;
  final String planStartIso;
  final List<PlanRace> races;
  final String todayIso;

  /// Opens the race workout with this id. The plan's synthetic end-date race
  /// has no workout and is not tappable.
  final ValueChanged<String>? onSelectWorkout;

  const PlanRacesList({
    super.key,
    required this.planName,
    required this.planStartIso,
    required this.races,
    required this.todayIso,
    this.onSelectWorkout,
  });

  static bool shows(List<PlanRace> races) => races.length > 1;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final tag = localeToTag(Localizations.localeOf(context));
    final next = nextRace(races, todayIso);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.planDetailRacesTitle,
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          for (final r in races)
            _row(context, theme, l10n, tag, r, identical(r, next)),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, ThemeData theme, AppLocalizations l10n,
      String tag, PlanRace r, bool isNext) {
    final details = [
      formatDateMed(parseIsoDate(r.date), tag),
      if (r.distanceM != null) fmtKm(r.distanceM, 1),
      if (r.goalTimeSec != null && r.goalTimeSec! > 0)
        formatRaceGoalTimeS(r.goalTimeSec!),
    ].join(' · ');
    final past = r.date.compareTo(todayIso) < 0;
    final workoutId = r.workoutId;
    final onTap = workoutId == null || onSelectWorkout == null
        ? null
        : () => onSelectWorkout!(workoutId);
    return InkWell(
      key: ValueKey('planRace-${r.workoutId ?? 'plan'}-${r.date}'),
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Semantics(
              label: l10n.planDetailRacePriority(r.priority),
              excludeSemantics: true,
              child: Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: r.priority == 'A'
                      ? theme.colorScheme.primary
                      : theme.colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  r.priority,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: r.priority == 'A'
                        ? theme.colorScheme.onPrimary
                        : theme.colorScheme.onSecondaryContainer,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    r.name ?? planName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: past ? theme.colorScheme.onSurfaceVariant : null,
                    ),
                  ),
                  Text(
                    details,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (isNext) ...[
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  NextRaceCard.relation(
                    l10n,
                    planRaceCountdown(planStartIso, r.date, todayIso),
                  ),
                  key: const Key('planRacesNextCountdown'),
                  textAlign: TextAlign.end,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
