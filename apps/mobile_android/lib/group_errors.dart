import 'package:api_client/api_client.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import 'auth_error.dart';
import 'l10n/gen/app_localizations.dart';
import 'rate_limit_message.dart';

/// The sentence for a refused or failed group action (issue #1365), as web's
/// `groupAppError` reads it. A refused invitee, one that does not exist and a
/// block either way are one 42501 on the server and one sentence here, so a
/// picker cannot be used to learn which it was. [refused] is that sentence
/// for the action at hand (an invite says "can't be invited"); [fallback]
/// is everything the server did not name.
String groupErrorMessage(
  AppLocalizations l10n,
  Object error, {
  String? refused,
  required String fallback,
}) {
  if (error is GroupActionRefused) {
    return switch (error.reason) {
      GroupRefusal.unavailable => l10n.groupsUnavailable,
      GroupRefusal.notFound => l10n.groupsNotFound,
      GroupRefusal.refused => refused ?? l10n.groupsActionRefused,
      GroupRefusal.capReached => l10n.groupsCapReached,
      GroupRefusal.titleInvalid => l10n.groupsTitleInvalid,
    };
  }
  if (error is PostgrestException) {
    final throttled =
        rateLimitErrorMessage(l10n, code: error.code, message: error.message);
    if (throttled != null) return throttled;
  }
  if (classifyAuthError(error) == AuthErrorKind.offline) {
    return l10n.authErrorOffline;
  }
  return fallback;
}

/// The sentence a sender reads when a group message did not go: the send
/// gate (most often a removal the poll has not shown yet, or the flag), the
/// photo rule, the throttle, offline, or anything else.
String groupSendErrorMessage(
  AppLocalizations l10n,
  Object error, {
  required bool withPhoto,
  required bool uploaded,
}) {
  if (error is GroupActionRefused && error.reason == GroupRefusal.refused) {
    return withPhoto
        ? l10n.messagesPhotoSendNotAllowed
        : l10n.groupsSendNotAllowed;
  }
  if (error is DmImageUnavailable) return l10n.messagesPhotoUnavailable;
  return groupErrorMessage(
    l10n,
    error,
    refused: l10n.groupsSendNotAllowed,
    fallback: withPhoto && !uploaded
        ? l10n.messagesPhotoUploadFailed
        : l10n.messagesSendFailed,
  );
}
