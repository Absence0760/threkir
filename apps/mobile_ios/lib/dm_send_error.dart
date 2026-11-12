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
  if (error is DmRequestCapReached) return l10n.messagesRequestCapReached;
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

/// The sentence shown in the edit dialog when an edit did not save: the
/// server refused it (window passed, unsent, a block, not yours — one
/// sentence, so a block is not revealed), the edit throttle, offline, or
/// anything else.
String dmEditErrorMessage(AppLocalizations l10n, Object error) {
  if (error is DmEditClosed) return l10n.messagesEditClosed;
  if (error is PostgrestException) {
    final throttled =
        rateLimitErrorMessage(l10n, code: error.code, message: error.message);
    if (throttled != null) return throttled;
  }
  if (classifyAuthError(error) == AuthErrorKind.offline) {
    return l10n.authErrorOffline;
  }
  return l10n.messagesEditFailed;
}

/// The sentence a sender reads when a message with a photo did not go. The
/// INSERT policy admits a photo under a narrower rule than text (a follow
/// edge or an accepted conversation), so its refusal says that rule, still
/// without saying which part refused. [uploaded] is false when the failure
/// came before the photo reached storage.
String dmPhotoSendErrorMessage(
  AppLocalizations l10n,
  Object error, {
  required bool uploaded,
}) {
  if (error is DmSendNotPermitted) return l10n.messagesPhotoSendNotAllowed;
  if (error is DmImageUnavailable) return l10n.messagesPhotoUnavailable;
  if (error is DmRequestCapReached) return l10n.messagesRequestCapReached;
  if (error is PostgrestException) {
    final throttled =
        rateLimitErrorMessage(l10n, code: error.code, message: error.message);
    if (throttled != null) return throttled;
  }
  if (classifyAuthError(error) == AuthErrorKind.offline) {
    return l10n.authErrorOffline;
  }
  return uploaded ? l10n.messagesSendFailed : l10n.messagesPhotoUploadFailed;
}

/// The sentence shown when a reaction did not save: one refusal for every
/// reason the server gives (so a block is not revealed), the reaction
/// throttle, or offline.
String dmReactionErrorMessage(AppLocalizations l10n, Object error) {
  if (error is PostgrestException) {
    final throttled =
        rateLimitErrorMessage(l10n, code: error.code, message: error.message);
    if (throttled != null) return throttled;
  }
  if (classifyAuthError(error) == AuthErrorKind.offline) {
    return l10n.authErrorOffline;
  }
  return l10n.messagesReactionRefused;
}
