import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart' show StatusPill;

import '../l10n/gen/app_localizations.dart';

/// Marks a run or route that reached the viewer through its owner's
/// followers level or a named-person share rather than being public
/// (decisions § 1874). Twin of web's `run-shared-with-you` /
/// `route-shared-with-you` chips.
class SharedWithYouChip extends StatelessWidget {
  const SharedWithYouChip({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Tooltip(
      message: l10n.audienceSharedWithYouHint,
      child: Semantics(
        label: l10n.audienceSharedWithYouHint,
        excludeSemantics: true,
        child: StatusPill(
          key: const Key('shared-with-you'),
          label: l10n.audienceSharedWithYou,
          foreground: theme.colorScheme.onSecondaryContainer,
          fill: theme.colorScheme.secondaryContainer,
          icon: Icons.group,
        ),
      ),
    );
  }
}
