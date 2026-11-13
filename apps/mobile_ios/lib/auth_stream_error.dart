import 'package:api_client/api_client.dart' show safeErrorLabel;
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthRetryableFetchException;

import 'auth_error.dart';
import 'l10n/gen/app_localizations.dart';
import 'widgets/top_banner.dart';

/// The app's root navigator, so a failure that arrives outside any
/// screen can still be shown.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

/// Shows an error delivered on `onAuthStateChange`. supabase_flutter
/// reports a refused auth deep link (an emailed sign-in, confirmation or
/// reset link that expired or was already used) by adding the
/// `AuthException` to that stream instead of throwing, so a listener
/// without `onError` turns it into an unhandled fatal error and the
/// person is told nothing.
///
/// The same stream carries a token refresh that could not reach the server
/// ([AuthRetryableFetchException], Sentry THREKIR-CLIENT-2): offline, every
/// auto-refresh tick near expiry adds one. That is an L4 failure with
/// nothing for the person to do — the SDK retries on its next tick and on
/// every resume, and the session stays until the server refuses it — so it
/// is logged, never shown.
void showAuthStreamError(
  Object error, {
  GlobalKey<NavigatorState>? navigatorKey,
}) {
  if (error is AuthRetryableFetchException) {
    debugPrint('auth: token refresh deferred: ${safeErrorLabel(error)}');
    return;
  }
  final context = (navigatorKey ?? appNavigatorKey).currentContext;
  if (context == null) return;
  showTopBanner(
    context,
    friendlyAuthError(AppLocalizations.of(context), error),
    duration: kTopBannerMaxDuration,
  );
}
