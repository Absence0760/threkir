import 'package:core_models/core_models.dart';

/// Which conversation a thread is: the partner, or — once the partner deleted
/// their account — the random per-partner key the server stamped on the
/// viewer's remaining messages (migration 20271021000003). Mirrors web's
/// `DmThreadTarget` (`apps/web/src/lib/social/dm_thread.ts`).
sealed class DmThreadTarget {
  const DmThreadTarget();
}

class DmPartnerThread extends DmThreadTarget {
  const DmPartnerThread(this.partnerId);
  final String partnerId;
}

/// A conversation whose partner deleted their account. It holds only the
/// viewer's own messages: the leaver's were erased with their account.
class DmDeletedPartnerThread extends DmThreadTarget {
  const DmDeletedPartnerThread(this.deletedPartnerKey);
  final String deletedPartnerKey;
}

/// One conversation in the direct-message inbox: the latest message with one
/// partner plus how many of theirs the viewer has not read. Mirrors web's
/// `DmThread` (`apps/web/src/lib/core/data.ts`), aggregated server-side by the
/// `dm_threads()` RPC (migrations 20270117_001, 20271021000003,
/// 20271105000010).
class DmThread {
  const DmThread({
    required this.conversationId,
    required this.partnerId,
    required this.lastBody,
    required this.lastAt,
    required this.lastFromMe,
    required this.unread,
    this.deletedPartnerKey,
    this.lastUnsent = false,
    this.partnerName,
    this.partnerAvatarUrl,
    this.muted = false,
    this.archived = false,
    this.markedUnread = false,
  }) : assert(partnerId != null || deletedPartnerKey != null);

  /// The conversation the mute, archive and delete-for-me actions act on.
  final String conversationId;

  /// Null when the partner deleted their account; [deletedPartnerKey] then
  /// names the conversation.
  final String? partnerId;
  final String? deletedPartnerKey;
  final String? partnerName;
  final String? partnerAvatarUrl;

  /// Null when the latest message was unsent ([lastUnsent]).
  final String? lastBody;
  final bool lastUnsent;
  final DateTime lastAt;
  final bool lastFromMe;
  final int unread;

  /// The viewer muted it: no notification, and left out of the badge.
  final bool muted;

  /// The viewer archived it and nothing newer has arrived since.
  final bool archived;

  /// The viewer marked it unread (migration 20271109000020). [unread] already
  /// counts it as at least one; opening the conversation clears it.
  final bool markedUnread;

  /// Unique per conversation, for keys and the opened-at map.
  String get threadKey => partnerId ?? deletedPartnerKey!;

  DmThreadTarget get target => partnerId != null
      ? DmPartnerThread(partnerId!)
      : DmDeletedPartnerThread(deletedPartnerKey!);

  DmThread copyWith({
    int? unread,
    bool? muted,
    bool? archived,
    bool? markedUnread,
  }) =>
      DmThread(
    conversationId: conversationId,
    partnerId: partnerId,
    deletedPartnerKey: deletedPartnerKey,
    partnerName: partnerName,
    partnerAvatarUrl: partnerAvatarUrl,
    lastBody: lastBody,
    lastUnsent: lastUnsent,
    lastAt: lastAt,
    lastFromMe: lastFromMe,
    unread: unread ?? this.unread,
    muted: muted ?? this.muted,
    archived: archived ?? this.archived,
    markedUnread: markedUnread ?? this.markedUnread,
  );
}

/// One page of a conversation, oldest message first so it renders top to
/// bottom. [hasMore] is true when older messages exist before the first one.
class DmThreadPage {
  const DmThreadPage({required this.messages, required this.hasMore});

  final List<DirectMessageRow> messages;
  final bool hasMore;
}

/// The `direct_messages` INSERT policy refused the send (SQLSTATE 42501): no
/// follow edge in either direction, or a block in either direction. The two
/// are one policy and deliberately indistinguishable — `user_blocks` is
/// owner-read only, so telling a sender "they blocked you" would leak exactly
/// what the block exists to hide.
class DmSendNotPermitted implements Exception {
  const DmSendNotPermitted();

  @override
  String toString() => 'DmSendNotPermitted';
}
