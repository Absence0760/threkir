import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart' show ErrorState;

import '../l10n/gen/app_localizations.dart';

export 'package:ui_kit/ui_kit.dart' show ErrorState;

/// ui_kit's [ErrorState] with the app's localised Retry label filled in, so a
/// screen passes only the message and the retry.
///
/// Callers render this instead of the normal list when their read failed with
/// nothing to show, and wire `onRetry` to the same load function.
class AppErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  final IconData icon;
  final bool compact;

  const AppErrorState({
    super.key,
    required this.message,
    required this.onRetry,
    this.icon = Icons.cloud_off,
  }) : compact = false;

  /// One row, for a section inside a page that otherwise loaded.
  const AppErrorState.inline({
    super.key,
    required this.message,
    required this.onRetry,
    this.icon = Icons.cloud_off,
  }) : compact = true;

  @override
  Widget build(BuildContext context) {
    final retry = AppLocalizations.of(context).errorStateRetry;
    return compact
        ? ErrorState.inline(
            message: message, retryLabel: retry, onRetry: onRetry, icon: icon)
        : ErrorState(
            message: message, retryLabel: retry, onRetry: onRetry, icon: icon);
  }
}
