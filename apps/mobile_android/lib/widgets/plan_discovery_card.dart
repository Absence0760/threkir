import 'package:flutter/material.dart';

import '../l10n/date_format.dart';
import '../l10n/gen/app_localizations.dart';
import '../l10n/locale_support.dart';
import '../recent_5k_suggestion.dart';
import '../training.dart' show fmtHms;

/// Home's plan entry for a runner with no plan: "Train for something", which
/// opens the plan wizard. Web's twin is the dashboard's plan promo.
class TrainForSomethingCard extends StatelessWidget {
  final VoidCallback onTap;

  const TrainForSomethingCard({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading: Icon(Icons.event_note, color: theme.colorScheme.primary),
        title: Text(l10n.dashboardTrainForSomething),
        subtitle: Text(l10n.dashboardTrainForSomethingBody),
        trailing: Icon(Icons.chevron_right, color: theme.colorScheme.outline),
        onTap: onTap,
      ),
    );
  }
}

/// "Your 5K of 24:10 on 3 Oct — build a plan from it." Takes the place of
/// [TrainForSomethingCard] while there is a suggestion. Building opens the
/// wizard with the time filled in and unconfirmed; "Not now" hands the
/// dismissal to the host, which stores it. Web twin: `Recent5kPlanCard.svelte`.
class Recent5kPlanCard extends StatelessWidget {
  final Recent5kSuggestion suggestion;
  final VoidCallback onBuild;
  final VoidCallback onDismiss;

  const Recent5kPlanCard({
    super.key,
    required this.suggestion,
    required this.onBuild,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final tag = localeToTag(Localizations.localeOf(context));
    final date = formatDateShort(DateTime.parse(suggestion.startedAt), tag);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.dashboardRecent5kTitle(fmtHms(suggestion.seconds), date),
              key: const Key('dashboardRecent5kTitle'),
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              l10n.dashboardRecent5kBody,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              children: [
                TextButton(
                  key: const Key('dashboardRecent5kDismiss'),
                  onPressed: onDismiss,
                  child: Text(l10n.dashboardRecent5kDismiss),
                ),
                FilledButton(
                  key: const Key('dashboardRecent5kBuild'),
                  onPressed: onBuild,
                  child: Text(l10n.dashboardRecent5kCta),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
