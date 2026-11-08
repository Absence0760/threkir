/// Read receipts in one direct-message conversation (issue #1216, migration
/// 20271113000001). The server decides whether a read is shared: `seen_at` is
/// set only while both participants have receipts on, and the recipient's own
/// `read_at` is never granted to a client. These helpers only place what the
/// server returned. Web twin: `apps/web/src/lib/social/dm_read_receipt.ts`.
library;

import 'package:core_models/core_models.dart';

/// The viewer's newest message the partner has seen, the one "Seen" sits
/// under, or null. [messages] is oldest first, the order the thread renders in.
DirectMessageRow? seenReceipt(List<DirectMessageRow> messages, String? viewerId) {
  if (viewerId == null) return null;
  for (var i = messages.length - 1; i >= 0; i--) {
    final m = messages[i];
    if (m.senderId == viewerId && m.seenAt != null) return m;
  }
  return null;
}

/// The partner message to mark the conversation read through: the newest one
/// on screen, unless it is the one already marked. Null when there is nothing
/// new from the partner. A client cannot see which messages it has read
/// (`read_at` is withheld), so it remembers how far it marked instead.
DirectMessageRow? dmMarkReadThrough(
  List<DirectMessageRow> messages,
  String partnerId,
  String? markedThroughId,
) {
  for (var i = messages.length - 1; i >= 0; i--) {
    final m = messages[i];
    if (m.senderId == partnerId) return m.id == markedThroughId ? null : m;
  }
  return null;
}
