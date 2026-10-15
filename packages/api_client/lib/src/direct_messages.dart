import 'package:core_models/core_models.dart';

/// One conversation in the direct-message inbox: the latest message with one
/// partner plus how many of theirs the viewer has not read. Mirrors web's
/// `DmThread` (`apps/web/src/lib/core/data.ts`), aggregated server-side by the
/// `dm_threads()` RPC (migration 20270117_001).
class DmThread {
  const DmThread({
    required this.partnerId,
    required this.lastBody,
    required this.lastAt,
    required this.lastFromMe,
    required this.unread,
    this.partnerName,
    this.partnerAvatarUrl,
  });

  final String partnerId;
  final String? partnerName;
  final String? partnerAvatarUrl;
  final String lastBody;
  final DateTime lastAt;
  final bool lastFromMe;
  final int unread;

  DmThread copyWith({int? unread}) => DmThread(
        partnerId: partnerId,
        partnerName: partnerName,
        partnerAvatarUrl: partnerAvatarUrl,
        lastBody: lastBody,
        lastAt: lastAt,
        lastFromMe: lastFromMe,
        unread: unread ?? this.unread,
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
