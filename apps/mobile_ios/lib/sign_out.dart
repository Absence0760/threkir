import 'dart:async';

import 'package:api_client/api_client.dart' show safeErrorLabel;
import 'package:flutter/foundation.dart';

/// How long ending the session waits for a pending delete to settle before
/// it goes ahead anyway. The commit is a single request; one that has not
/// answered in this long is a stalled network, and a Sign out that never
/// finishes leaves the session open on the very device the user is leaving.
/// Web's `SIGN_OUT_SETTLE_TIMEOUT_MS`.
const Duration kSignOutSettleTimeout = Duration(seconds: 5);

/// Runs [settlePending] (the undo queue's `flush`) before the session ends,
/// so a delete still inside its undo window commits as the account that
/// made it rather than firing later with no session, or under whoever signs
/// in next. Settling is auxiliary to ending the session: a failure is logged
/// and so is a settle still running after [kSignOutSettleTimeout], and
/// neither stops the caller. The request already in flight keeps the token
/// it was sent with and may still land. Never throws.
Future<void> settleBeforeSessionEnds(
  Future<void> Function() settlePending,
) async {
  try {
    await settlePending().timeout(kSignOutSettleTimeout);
  } on TimeoutException {
    debugPrint(
      'sign-out: a pending delete had not settled after '
      '${kSignOutSettleTimeout.inSeconds} s; signing out anyway',
    );
  } catch (e) {
    debugPrint(
      'sign-out: settling a pending delete failed: ${safeErrorLabel(e)}',
    );
  }
}

/// Settles a pending delete, then calls [signOut]. [signOut]'s own failure
/// still reaches the caller, which decides how to say so.
Future<void> signOutAfterSettling({
  required Future<void> Function() settlePending,
  required Future<void> Function() signOut,
}) async {
  await settleBeforeSessionEnds(settlePending);
  await signOut();
}
