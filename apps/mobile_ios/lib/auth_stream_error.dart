import 'package:flutter/widgets.dart';

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
void showAuthStreamError(
  Object error, {
  GlobalKey<NavigatorState>? navigatorKey,
}) {
  final context = (navigatorKey ?? appNavigatorKey).currentContext;
  if (context == null) return;
  showTopBanner(
    context,
    friendlyAuthError(AppLocalizations.of(context), error),
    duration: kTopBannerMaxDuration,
  );
}
