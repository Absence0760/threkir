import 'package:flutter/material.dart';

import '../l10n/gen/app_localizations.dart';

/// The small "(i)" a runner taps to find out what a feature IS and how to use
/// it, without leaving the screen it sits on.
///
/// Mobile twin of web's `InfoTip.svelte`, and deliberately a DIALOG rather than
/// that side's anchored popover: a tooltip on touch needs a long-press nobody
/// discovers, and the sentences here are two or three long — more than fits
/// beside a `ListTile` on a phone.
///
/// Every string arrives translated; the widget takes no l10n keys of its own
/// except the dismiss label, so it can sit on any screen.
class InfoTipButton extends StatelessWidget {
  /// Accessible name for the button. Must name the SUBJECT ("About Strava"),
  /// never just "info" — a screen-reader user meeting several of these on one
  /// screen cannot tell them apart otherwise.
  final String label;
  final String title;
  final String body;

  const InfoTipButton({
    super.key,
    required this.label,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      // The GLYPH shrinks to sit on a ListTile title line; the tap target does
      // not. Shrinking the box instead is what `tap_target_guard_test.dart`
      // exists to stop (issue #664).
      icon: const Icon(Icons.info_outline, size: 18),
      tooltip: label,
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      padding: EdgeInsets.zero,
      onPressed: () => showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(child: Text(body)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(AppLocalizations.of(dialogContext).commonDismiss),
            ),
          ],
        ),
      ),
    );
  }
}

/// A `ListTile` title with an [InfoTipButton] beside it.
///
/// The text is `Expanded` so a long provider name wraps rather than overflowing
/// the row and pushing the button off the tile.
Widget infoTipTitle(String text, InfoTipButton tip) => Row(
      children: [Expanded(child: Text(text)), tip],
    );
