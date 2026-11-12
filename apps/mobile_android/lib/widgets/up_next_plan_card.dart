import 'package:flutter/material.dart';

import '../l10n/date_format.dart';
import '../l10n/gen/app_localizations.dart';
import '../l10n/locale_support.dart';
import '../plan_week.dart';
import '../training.dart';
import '../training_service.dart';
import 'next_race_card.dart';

/// The active plan queued after the one Home shows — a marathon block's
/// ultra follow-on — with its start date and a countdown to it. Hidden when
/// nothing is queued.
class UpNextPlanCard extends StatelessWidget {
  final ActivePlanOverview overview;
  final DateTime now;
  final VoidCallback? onTap;

  const UpNextPlanCard({
    super.key,
    required this.overview,
    required this.now,
    this.onTap,
  });

  static bool shows(ActivePlanOverview overview) =>
      overview.upcomingPlan != null;

  @override
  Widget build(BuildContext context) {
    final next = overview.upcomingPlan!;
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final tag = localeToTag(Localizations.localeOf(context));
    final countdown = planRaceCountdown(
      toIsoDate(next.startDate),
      toIsoDate(next.endDate),
      toIsoDate(now),
    );
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              Icon(Icons.queue_play_next, color: theme.colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  l10n.homePlanUpNext(
                      next.name, formatDateMed(next.startDate, tag)),
                  key: const Key('upNextPlanLabel'),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (countdown.kind == PlanRaceCountdownKind.startsIn) ...[
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    NextRaceCard.relation(l10n, countdown),
                    textAlign: TextAlign.end,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
