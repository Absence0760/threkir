import 'package:flutter/material.dart';

import '../l10n/gen/app_localizations.dart';
import '../settings_destination.dart';

/// Every upsell in the app: the reason Pro would help, and a link that opens
/// the Pro screen.
///
/// The prompts it replaces said "upgrade in Settings" and stopped there, so a
/// runner who wanted to pay was told to go and find the page themselves
/// (issue #1374 finding 11). The link goes through the shell's settings seam
/// ([openSettings], decisions § 710), so a prompt anywhere in the tree opens
/// Pro on top of the current screen without holding the Pro screen's
/// dependencies. `upsell_link_guard_test.dart` fails an upsell message drawn
/// anywhere else, and an English string that sends the reader to Settings.
class ProUpsellLink extends StatelessWidget {
  const ProUpsellLink({
    super.key,
    required this.message,
    this.color,
    this.style,
    this.onOpen,
  });

  /// Why Pro would help here, without directions to it: the link is the
  /// directions.
  final String message;

  /// The text and link colour, for a prompt drawn on its own surface (the
  /// Coach's warning banner); the theme's otherwise.
  final Color? color;

  final TextStyle? style;

  /// Replaces the shell hand-off; a test seam.
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final textStyle =
        (style ?? theme.textTheme.bodySmall)?.copyWith(color: color);
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 4,
      children: [
        Text(message, style: textStyle),
        TextButton(
          key: const ValueKey('pro-upsell-link'),
          style: TextButton.styleFrom(
            foregroundColor: color,
            minimumSize: const Size(48, 48),
            tapTargetSize: MaterialTapTargetSize.padded,
            textStyle: textStyle?.copyWith(
              fontWeight: FontWeight.w700,
              decoration: TextDecoration.underline,
            ),
          ),
          onPressed: onOpen ?? () => openSettings(SettingsDestination.pro),
          child: Text(l10n.proUpsellAction),
        ),
      ],
    );
  }
}
