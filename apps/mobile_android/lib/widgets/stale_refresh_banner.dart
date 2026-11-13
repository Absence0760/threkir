import 'dart:async';

import 'package:flutter/material.dart';

import '../auth_error.dart';
import '../l10n/gen/app_localizations.dart';
import 'top_banner.dart';

/// The banner for a refresh that failed over rows already on screen: the rows
/// stay, and the banner says they are what was last loaded, naming being
/// offline (a timeout counts) apart from any other failure. The other half of
/// `AsyncView`'s rule that a failed read is never drawn as empty.
///
/// [onRetry] adds a Retry action, for screens with no pull-to-refresh.
void showStaleRefreshBanner(
  BuildContext context,
  Object error, {
  VoidCallback? onRetry,
}) {
  final l10n = AppLocalizations.of(context);
  showTopBanner(
    context,
    error is TimeoutException ||
            classifyAuthError(error) == AuthErrorKind.offline
        ? l10n.commonStaleOffline
        : l10n.commonStaleRefreshFailed,
    actionLabel: onRetry == null ? null : l10n.errorStateRetry,
    onAction: onRetry,
  );
}
