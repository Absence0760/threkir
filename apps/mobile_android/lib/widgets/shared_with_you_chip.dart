import 'package:flutter/material.dart';

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
    final colour = theme.colorScheme.onSecondaryContainer;
    return Tooltip(
      message: l10n.audienceSharedWithYouHint,
      child: Semantics(
        label: l10n.audienceSharedWithYouHint,
        excludeSemantics: true,
        child: Container(
          key: const Key('shared-with-you'),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: theme.colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.group_outlined, size: 16, color: colour),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  l10n.audienceSharedWithYou,
                  style: theme.textTheme.labelMedium?.copyWith(color: colour),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
