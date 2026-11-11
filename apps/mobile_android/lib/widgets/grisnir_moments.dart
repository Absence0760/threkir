import 'package:flutter/material.dart';

import '../l10n/gen/app_localizations.dart';
import '../mascot.dart';

/// Grisnir's hop beside a run's one milestone line (first run, first 5K, a
/// badge, a new best, the longest yet). A still, so there is no motion for the
/// OS's reduce-motion setting to stop; the art is decorative and the line
/// carries the moment for a screen reader. Never on a failed sync, an unsaved
/// run or any error. Web twin: `GrisnirMilestone.svelte`.
class GrisnirMilestone extends StatelessWidget {
  const GrisnirMilestone({super.key, required this.kind});

  final MilestoneKind kind;

  /// The art's drawn height; its width follows the render's aspect.
  static const double artHeight = 56;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Container(
      key: const Key('run-milestone-grisnir'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Image.asset(
            kGrisnirProudAsset,
            height: artHeight,
            excludeFromSemantics: true,
            filterQuality: FilterQuality.medium,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              milestoneLine(l10n, kind),
              style: theme.textTheme.titleSmall,
            ),
          ),
        ],
      ),
    );
  }
}

/// Grisnir waiting by a trail sign, for the "nothing yet" states that name him
/// (no runs, no routes, an empty feed) and onboarding. Decorative. Never in
/// [ErrorState], which takes no art at all, nor any failure state. Web twin:
/// the `mascot` prop on `EmptyState.svelte`.
class GrisnirWaiting extends StatelessWidget {
  const GrisnirWaiting({super.key, this.width = 136});

  final double width;

  @override
  Widget build(BuildContext context) => Image.asset(
        kGrisnirWaitAsset,
        key: const Key('empty-state-grisnir'),
        width: width,
        excludeFromSemantics: true,
        filterQuality: FilterQuality.medium,
      );
}

/// [GrisnirWaiting] when the runner shows him, otherwise null so an
/// `EmptyState` falls back to its icon.
Widget? grisnirWaitingOrNull({double width = 136}) =>
    mascotShown() ? GrisnirWaiting(width: width) : null;
