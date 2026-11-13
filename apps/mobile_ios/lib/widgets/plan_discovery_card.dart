import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart' show ListCard, AppSpace;

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
    return ListCard.row(
      leading: Icon(Icons.event_note, color: theme.colorScheme.primary),
      title: l10n.dashboardTrainForSomething,
      subtitle: l10n.dashboardTrainForSomethingBody,
      subtitleMaxLines: 4,
      chevron: true,
      onTap: onTap,
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
    return ListCard(
      actions: [
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.dashboardRecent5kTitle(fmtHms(suggestion.seconds), date),
            key: const Key('dashboardRecent5kTitle'),
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpace.xs),
          Text(
            l10n.dashboardRecent5kBody,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
