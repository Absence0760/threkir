import 'package:api_client/api_client.dart' show GroupMember, GroupPlaceholder;
import 'package:core_models/core_models.dart' show DirectMessageRow;

import 'catalogue_browse.dart' show compareFoldedNames;

/// Group conversations on mobile (issue #1365 slice 3, decisions § 2468): the
/// pure rules the inbox, the create and invite pickers and the group thread
/// share. Dart twin of web `social/group_messages.ts`.
///
/// The server is authoritative on every one of them (migrations
/// 20271216000007 and 20271217000006); these decide only what to offer, so a
/// control the server would refuse is not drawn.

/// `c_group_max_members` in private.group_check_cap: members and live invites.
const int kGroupMaxMembers = 32;

/// A group's title is 1 to 60 characters after trimming
/// (conversations_title_check).
const int kGroupTitleMax = 60;

/// create_group_conversation needs at least two other people.
const int kGroupMinInvitees = 2;

/// A role read at the boundary; anything else is no role.
String? parseGroupRole(Object? raw) =>
    raw == 'owner' || raw == 'admin' || raw == 'member' ? raw as String : null;

// The whitespace JavaScript's String.prototype.trim strips, so a title trims
// the same on both platforms (Dart's own trim also strips U+0085).
final _edgeSpace = RegExp(
    '^[\\t\\n\\v\\f\\r \\u00a0\\u1680\\u2000-\\u200a\\u2028\\u2029\\u202f\\u205f\\u3000\\ufeff]+'
    '|[\\t\\n\\v\\f\\r \\u00a0\\u1680\\u2000-\\u200a\\u2028\\u2029\\u202f\\u205f\\u3000\\ufeff]+\$');

/// The title as the server stores it, or null when it would refuse it.
/// Counted in code points, as Postgres `char_length` counts characters, so
/// an emoji is one of the 60 and not two.
String? normalizeGroupTitle(String raw) {
  final t = raw.replaceAll(_edgeSpace, '');
  final n = t.runes.length;
  return n >= 1 && n <= kGroupTitleMax ? t : null;
}

/// Seats a group has left for new invites: 32 less its members and live
/// invites. The creator takes a seat, so a new group can invite 31.
int groupSeatsLeft(int activeCount, int pendingCount) {
  final left = kGroupMaxMembers -
      (activeCount < 0 ? 0 : activeCount) -
      (pendingCount < 0 ? 0 : pendingCount);
  return left < 0 ? 0 : left;
}

/// private.group_rank: an invite has no role and ranks 0.
int _rank(String? role) => switch (role) {
      'owner' => 3,
      'admin' => 2,
      'member' => 1,
      _ => 0,
    };

/// Owner and admins invite and rename (invite_to_group, rename_group).
bool canManageGroup(String? myRole) => myRole == 'owner' || myRole == 'admin';

/// Only the owner changes roles and hands ownership on.
bool canChangeGroupRoles(String? myRole) => myRole == 'owner';

/// remove_group_member's rule: an admin or the owner removes someone ranked
/// below them (an invite ranks below everyone, so cancelling one is a
/// removal), never themselves, and nobody removes the owner.
bool canRemoveGroupMember(String? myRole, String? me, GroupMember target) {
  if (me == null || target.userId == me || _rank(myRole) < 2) return false;
  return _rank(myRole) > _rank(target.invited ? null : target.role);
}

/// Owner first, then admins, then members, each by folded name with unnamed
/// last; invites after. Folded rather than collated so both platforms order
/// it the same way (decisions § 1956).
List<GroupMember> sortGroupMembers(List<GroupMember> members) =>
    [...members]..sort((a, b) {
        if (a.invited != b.invited) return a.invited ? 1 : -1;
        final r = _rank(b.role) - _rank(a.role);
        if (r != 0) return r;
        final an = a.name;
        final bn = b.name;
        if (an == null || bn == null) {
          if (an != bn) return an == null ? 1 : -1;
          final byId = a.userId.compareTo(b.userId);
          return byId == 0 ? 0 : (byId < 0 ? -1 : 1);
        }
        return compareFoldedNames(an, a.userId, bn, b.userId);
      });

/// One line of a group thread: a message, or the place of one the viewer
/// blocked.
sealed class GroupThreadItem {
  const GroupThreadItem();
  String get id;
  DateTime get createdAt;
}

class GroupMessageItem extends GroupThreadItem {
  const GroupMessageItem(this.message);
  final DirectMessageRow message;
  @override
  String get id => message.id;
  @override
  DateTime get createdAt => message.createdAt;
}

class GroupBlockedItem extends GroupThreadItem {
  const GroupBlockedItem(this.id, this.createdAt);
  @override
  final String id;
  @override
  final DateTime createdAt;
}

/// Messages and "message from someone you blocked" placeholders in thread
/// order, `(created_at, id)` with the microseconds Postgres stamps. A
/// placeholder whose id is also a message on screen is dropped: the viewer
/// unblocked and the message itself came back.
List<GroupThreadItem> mergeGroupThread(
  List<DirectMessageRow> messages,
  List<GroupPlaceholder> placeholders,
) {
  final shown = {for (final m in messages) m.id};
  final items = <GroupThreadItem>[
    for (final m in messages) GroupMessageItem(m),
    for (final p in placeholders)
      if (!shown.contains(p.id)) GroupBlockedItem(p.id, p.createdAt),
  ];
  return items
    ..sort((a, b) {
      final at = a.createdAt.compareTo(b.createdAt);
      if (at != 0) return at;
      final byId = a.id.compareTo(b.id);
      return byId == 0 ? 0 : (byId < 0 ? -1 : 1);
    });
}

/// The lower bound for a placeholder read: the oldest message on screen
/// while older ones exist, so placeholders stay inside the loaded window;
/// null once the whole readable history is loaded.
DateTime? placeholdersSince(List<DirectMessageRow> messages, bool hasMore) =>
    hasMore && messages.isNotEmpty ? messages.first.createdAt : null;
