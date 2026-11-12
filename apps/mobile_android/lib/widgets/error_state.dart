import 'package:flutter/material.dart';

import '../l10n/gen/app_localizations.dart';

/// Shared empty-but-errored state for any list/detail screen whose
/// primary data fetch hit a backend failure or timeout. Keeps copy and
/// layout consistent across tabs so users learn one recovery affordance.
///
/// Callers render this instead of the normal list when their `_error`
/// field is non-null, and wire `onRetry` to the same load function.
class ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  final IconData icon;
  final bool compact;

  const ErrorState({
    super.key,
    required this.message,
    required this.onRetry,
    this.icon = Icons.cloud_off,
  }) : compact = false;

  /// The same state as one row, for a section inside a page that otherwise
  /// loaded (a panel, a list section), where the full-height form would
  /// push the rest of the page away.
  const ErrorState.inline({
    super.key,
    required this.message,
    required this.onRetry,
    this.icon = Icons.cloud_off,
  }) : compact = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (compact) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(icon, size: 20, color: theme.colorScheme.outline),
            const SizedBox(width: 12),
            Expanded(child: Text(message, style: theme.textTheme.bodyMedium)),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 18),
              label: Text(AppLocalizations.of(context).errorStateRetry),
            ),
          ],
        ),
      );
    }
    // SingleChildScrollView wrapping the Center so the contents can
    // scroll when the parent's available height shrinks (e.g. the
    // software keyboard sliding up on the Clubs → Browse search
    // field — the user reported "BOTTOM OVERFLOWED BY 54 PIXELS"
    // below the 'Couldn\'t load clubs' message). Without the
    // scroll wrap, the Column's ~152 px intrinsic height crashed
    // into a sub-100 px viewport.
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 48, color: theme.colorScheme.outline),
              const SizedBox(height: 12),
              Text(
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              FilledButton.tonalIcon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: Text(AppLocalizations.of(context).errorStateRetry),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
