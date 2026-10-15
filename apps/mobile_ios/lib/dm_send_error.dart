import 'package:api_client/api_client.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import 'auth_error.dart';
import 'l10n/gen/app_localizations.dart';
import 'rate_limit_message.dart';

/// The sentence a sender reads when a direct message did not go.
///
/// Four answers, each one the sender can act on differently, so none of them
/// collapses into another: the follow / block gate (nothing to retry — and
/// deliberately silent on which of the two refused, decisions § 734), the
/// rail's send throttle (wait the stated time, § 737), being offline, and
/// everything else. The throttle is matched before the offline check because
/// a P0001 carrying "rate limit" would otherwise read as a network fault.
String dmSendErrorMessage(AppLocalizations l10n, Object error) {
  if (error is DmSendNotPermitted) return l10n.messagesSendNotAllowed;
  if (error is PostgrestException) {
    final throttled =
        rateLimitErrorMessage(l10n, code: error.code, message: error.message);
    if (throttled != null) return throttled;
  }
  if (classifyAuthError(error) == AuthErrorKind.offline) {
    return l10n.authErrorOffline;
  }
  return l10n.messagesSendFailed;
}
