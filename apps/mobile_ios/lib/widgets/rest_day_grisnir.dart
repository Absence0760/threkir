import 'package:flutter/material.dart';

import '../l10n/gen/app_localizations.dart';
import '../mascot.dart';

/// Grisnir lying down on a plan rest day, with his one dry line (Thor's goats
/// are back by morning). A still, so there is no motion for the OS's
/// reduce-motion setting to stop; the art is decorative and the line carries
/// the moment for a screen reader. Never used in an error, sync, payment or
/// lost-GPS state. Web twin: `RestDayGrisnir.svelte` on `/dashboard`.
class RestDayGrisnir extends StatelessWidget {
  const RestDayGrisnir({super.key});

  /// The art's drawn width; its height follows the render's aspect.
  static const double artWidth = 120;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Padding(
      key: const Key('dashboardHeroRestGrisnir'),
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
      child: Row(
        children: [
          Image.asset(
            kGrisnirRestAsset,
            width: artWidth,
            excludeFromSemantics: true,
            filterQuality: FilterQuality.medium,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              l10n.dashboardHeroRestDayGrisnir,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontStyle: FontStyle.italic,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
