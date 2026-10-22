import 'package:flutter/material.dart';

import '../l10n/gen/app_localizations.dart';
import 'verified_badge.dart';

/// "Official" mark on content published by a verified organiser: a route,
/// plan, gym routine, challenge or session plan whose club is verified and
/// whose author is an owner/admin of it. The flag is derived server-side
/// (`is_official`, migration 20271021000030) and never stored per row.
///
/// Reuses the verified-club rosette so a runner learns one mark, with a
/// visible word beside it: on content the icon alone reads as "verified
/// account", and the word says what it is. Twin of the Svelte
/// `OfficialBadge` component.
class OfficialBadge extends StatelessWidget {
  final double size;

  const OfficialBadge({super.key, this.size = 14});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Semantics(
      label: l10n.officialBadgeTooltip,
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          VerifiedBadge(size: size, tooltip: l10n.officialBadgeTooltip),
          const SizedBox(width: 2),
          Text(
            l10n.officialBadgeLabel,
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
