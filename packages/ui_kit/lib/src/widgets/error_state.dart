import 'package:flutter/material.dart';

/// The whole-surface state for a read that failed: an icon, the message and a
/// Retry button wired to the same load. The sibling of [EmptyState] (same 48
/// icon and 32 padding), so a failed surface and an empty one read as one
/// family, and a failure is never drawn as "nothing here".
///
/// It has no art slot on purpose: the mascot belongs to "nothing yet"
/// surfaces, never to an error.
///
/// [retryLabel] is required because ui_kit has no catalogue; the app's
/// `AppErrorState` fills it from its own.
class ErrorState extends StatelessWidget {
  final String message;
  final String retryLabel;
  final VoidCallback onRetry;
  final IconData icon;
  final bool compact;

  const ErrorState({
    super.key,
    required this.message,
    required this.retryLabel,
    required this.onRetry,
    this.icon = Icons.cloud_off,
  }) : compact = false;

  /// The same state as one row, for a section inside a page that otherwise
  /// loaded (a panel, a list section), where the full-height form would push
  /// the rest of the page away.
  const ErrorState.inline({
    super.key,
    required this.message,
    required this.retryLabel,
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Icon(icon, size: 20, color: theme.colorScheme.outline),
            ),
            const SizedBox(width: 12),
            // Message and Retry share a line while they fit; a long message
            // or large text puts Retry under it rather than pushing it off a
            // narrow row (issue #1374: 240 dp over in fr at 2x on 320 dp).
            Expanded(
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(message, style: theme.textTheme.bodyMedium),
                  ),
                  TextButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: Text(retryLabel),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    // Scrollable so the column survives a viewport the keyboard has shrunk
    // below its ~152 dp, and so a pull-to-refresh host can still pull.
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
                label: Text(retryLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
