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
    this.lastKind = 'text',
    this.partnerName,
    this.partnerAvatarUrl,
    this.muted = false,
    this.archived = false,
    this.markedUnread = false,
    this.request = false,
    this.lastImage = false,
    this.kind = 'direct',
    this.title,
    this.memberCount,
    this.membershipState,
  }) : assert(partnerId != null ||
            deletedPartnerKey != null ||
            kind == 'group');

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

  /// The latest message's `direct_messages.kind`: `coach_share` for an AI
  /// Coach answer the athlete shared (issue #1215 Phase 3), else `text`.
  final String lastKind;
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

  /// A message request to the viewer they have not accepted yet (migration
  /// 20271115002384): listed under Requests, left out of the badge, and the
  /// requester learns nothing until it is accepted.
  final bool request;

  /// The latest message carries a photo (migration 20271213121604), so a
  /// preview with no caption can say so.
  final bool lastImage;

  /// `group` for a group conversation (migration 20271216000007): no partner,
  /// a [title], and the viewer's own [membershipState]. Else `direct`.
  final String kind;

  /// A group's name; null for a direct conversation.
  final String? title;

  /// A group's active members, given only while the viewer is one of them.
  final int? memberCount;

  /// The viewer's membership of a group: `left` rows hold only their own
  /// messages ("You left"). Null for a direct conversation.
  final String? membershipState;

  bool get isGroup => kind == 'group';

  /// Unique per conversation, for keys and the opened-at map.
  String get threadKey => isGroup
      ? 'group/$conversationId'
      : partnerId ?? deletedPartnerKey!;

  /// The 1:1 thread to read. A group is read by its conversation id
  /// (`ApiClient.fetchGroupThread`), so it has none.
  DmThreadTarget get target => partnerId != null
      ? DmPartnerThread(partnerId!)
      : DmDeletedPartnerThread(deletedPartnerKey!);

  DmThread copyWith({
    int? unread,
    bool? muted,
    bool? archived,
    bool? markedUnread,
    bool? request,
  }) =>
      DmThread(
    conversationId: conversationId,
    partnerId: partnerId,
    deletedPartnerKey: deletedPartnerKey,
    partnerName: partnerName,
    partnerAvatarUrl: partnerAvatarUrl,
    lastBody: lastBody,
    lastUnsent: lastUnsent,
    lastKind: lastKind,
    lastAt: lastAt,
    lastFromMe: lastFromMe,
    unread: unread ?? this.unread,
    muted: muted ?? this.muted,
    archived: archived ?? this.archived,
    markedUnread: markedUnread ?? this.markedUnread,
    request: request ?? this.request,
    lastImage: lastImage,
    kind: kind,
    title: title,
    memberCount: memberCount,
    membershipState: membershipState,
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
/// follow edge in either direction and no shared club or event, a declined
/// request, or a block in either direction. They are one policy and
/// deliberately indistinguishable — `user_blocks` is
/// owner-read only, so telling a sender "they blocked you" would leak exactly
/// what the block exists to hide.
class DmSendNotPermitted implements Exception {
  const DmSendNotPermitted();

  @override
  String toString() => 'DmSendNotPermitted';
}

/// A fourth message into a message request the recipient has not accepted
/// (SQLSTATE 54000, migration 20271115002384): a requester may send three
/// until it is accepted. It says nothing about the recipient.
class DmRequestCapReached implements Exception {
  const DmRequestCapReached();

  @override
  String toString() => 'DmRequestCapReached';
}

/// `edit_direct_message` refused the edit (migration 20271114000210): the
/// message is unsent, past the 15-minute window, between a blocked pair
/// (SQLSTATE 55000 for all three, so a block is not revealed), or not the
/// viewer's own (P0002). Clients say one sentence for all of them.
class DmEditClosed implements Exception {
  const DmEditClosed();

  @override
  String toString() => 'DmEditClosed';
}

/// `share_coach_message` refused because sharing an AI Coach answer with a
/// coach is not switched on (SQLSTATE 0A000, the server's `coach_share` gate,
/// migration 20271210001215).
class CoachShareUnavailable implements Exception {
  const CoachShareUnavailable();

  @override
  String toString() => 'CoachShareUnavailable';
}

/// `set_direct_message_reaction` refused (migration 20271213121602): an
/// unsent or hidden message, a block either way, an unaccepted request
/// (55000), or a message outside the viewer's conversations (P0002). One
/// sentence for all of them, so a block is never told apart.
class DmReactionRefused implements Exception {
  const DmReactionRefused();

  @override
  String toString() => 'DmReactionRefused';
}

/// `create_dm_image_upload` refused because photos in messages are not
/// switched on (SQLSTATE 0A000, the server's `dm_images` gate, migration
/// 20271213121604).
class DmImageUnavailable implements Exception {
  const DmImageUnavailable();

  @override
  String toString() => 'DmImageUnavailable';
}

/// One reaction on a direct message, as the SELECT policy hands it out.
typedef DmReactionRecord = ({String messageId, String userId, String reaction});

/// One message that matched a search of the viewer's own conversations
/// (migration 20271213121603). Mirrors web's `DmSearchHit`.
class DmSearchHit {
  const DmSearchHit({
    required this.id,
    required this.conversationId,
    required this.partnerId,
    required this.deletedPartnerKey,
    required this.body,
    required this.createdAt,
    required this.fromMe,
    this.partnerName,
    this.isGroup = false,
    this.groupTitle,
  });

  final String id;
  final String conversationId;

  /// A hit in a group conversation (no recipient and no deleted-partner key):
  /// it opens the group, named by [groupTitle].
  final bool isGroup;

  /// Null for a direct conversation, and for a group the viewer has left
  /// (its title is readable to active members only).
  final String? groupTitle;

  /// Null when the partner deleted their account; [deletedPartnerKey] names
  /// the conversation then.
  final String? partnerId;
  final String? deletedPartnerKey;
  final String? partnerName;
  final String body;
  final DateTime createdAt;
  final bool fromMe;

  DmThreadTarget get target => partnerId != null
      ? DmPartnerThread(partnerId!)
      : DmDeletedPartnerThread(deletedPartnerKey!);
}

/// One message photo: its processing state and, once the server has
/// re-encoded it, a short-lived signed URL. Mirrors web's `DmImageView`.
class DmImageView {
  const DmImageView({
    required this.status,
    this.width,
    this.height,
    this.url,
  });

  /// `pending`, `ready` or `rejected`; anything else reads as `pending`.
  final String status;
  final int? width;
  final int? height;
  final String? url;
}

/// Why a group RPC refused (issue #1365, migrations 20271216000007 and
/// 20271217000006). A refused invitee, one that does not exist and a block
/// either way are one 42501 on the server, so they are one [refused] here:
/// the picker cannot be used to learn which it was. A group the viewer is not
/// in, one that does not exist and one they left are one [notFound].
enum GroupRefusal {
  /// 0A000: the `group_messages` flag is off.
  unavailable,

  /// P0002.
  notFound,

  /// 42501.
  refused,

  /// 54000: the 32-seat cap, invitations included.
  capReached,

  /// 22023: a title outside 1 to 60 characters.
  titleInvalid,
}

class GroupActionRefused implements Exception {
  const GroupActionRefused(this.reason);
  final GroupRefusal reason;

  @override
  String toString() => 'GroupActionRefused(${reason.name})';
}

/// One of the viewer's live group invitations: the title, who invited them
/// and the size only. An invitee never sees who the members are (memo C5).
/// Mirrors web `GroupInvite`.
class GroupInvite {
  const GroupInvite({
    required this.conversationId,
    required this.title,
    required this.invitedAt,
    required this.memberCount,
    this.invitedBy,
    this.inviterName,
  });

  final String conversationId;
  final String title;
  final String? invitedBy;
  final String? inviterName;
  final DateTime invitedAt;
  final int memberCount;
}

/// One row of `group_members()`: an active member, or a live invitation (seen
/// by the owner and admins only), with `role` null for an invitation.
/// Mirrors web `GroupMember`.
class GroupMember {
  const GroupMember({
    required this.userId,
    required this.role,
    required this.state,
    this.name,
    this.avatarUrl,
  });

  final String userId;

  /// `owner`, `admin` or `member`; null for an invitation.
  final String? role;

  /// `active` or `invited`.
  final String state;
  final String? name;
  final String? avatarUrl;

  bool get invited => state == 'invited';
}

/// A blocked sender's message's place in a group thread: its id and time
/// only, never a body or a sender (migration 20271217000006).
typedef GroupPlaceholder = ({String id, DateTime createdAt});
