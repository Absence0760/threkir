import 'catalogue_browse.dart' show compareFoldedNames, fold;

/// Who a targeted in-app send may be offered to. Dart twin of web
/// `social/dm_recipients.ts`.
///
/// The `direct_messages` INSERT policy (migration `20261026_001`) admits a
/// send when a follow edge exists in EITHER direction and neither party has
/// blocked the other. The picker is therefore built from the union of the
/// sender's followers and the people they follow: a list built from followers
/// alone hides people the send would in fact accept, and one built from an
/// open people search offers sends RLS is going to refuse.
///
/// The block half of that gate is deliberately not modelled here.
/// `user_blocks` is owner-read only, so a client cannot see a block placed ON
/// it, and marking a row "can't be messaged" would require leaking exactly
/// that. Those sends are refused server-side as `DmSendNotPermitted`.
enum DmRelation { mutual, followsYou, youFollow }

/// The profile shape the follower and following pages carry.
class DmCandidateProfile {
  const DmCandidateProfile({
    required this.id,
    this.displayName,
    this.avatarUrl,
  });

  final String id;
  final String? displayName;
  final String? avatarUrl;
}

class DmRecipient {
  DmRecipient({
    required this.id,
    required this.displayName,
    required this.avatarUrl,
    required this.relation,
  });

  final String id;
  final String? displayName;
  final String? avatarUrl;
  DmRelation relation;
}

/// Merge the two follow directions into one deduped, display-ordered list.
///
/// [selfId] is dropped when present: the `direct_messages` CHECK forbids
/// `sender_id = recipient_id` outright, so a self row reaching the list some
/// other way must not be offered as a send that can only fail.
///
/// Ordering is by folded display name, unnamed last, with the id as a total
/// tiebreak, so two renders of the same follow graph list people in the same
/// order whichever fetch resolved first. Folded rather than collated because
/// this runtime has no collator and the two platforms must agree (decisions
/// § 1337, and the entry that made this list a pair).
List<DmRecipient> dmRecipientCandidates(
  Iterable<DmCandidateProfile> followers,
  Iterable<DmCandidateProfile> following, {
  String? selfId,
}) {
  final byId = <String, DmRecipient>{};
  void add(DmCandidateProfile p, DmRelation relation) {
    if (p.id.isEmpty || p.id == selfId) return;
    final seen = byId[p.id];
    if (seen != null) {
      if (seen.relation != relation) seen.relation = DmRelation.mutual;
      return;
    }
    byId[p.id] = DmRecipient(
      id: p.id,
      displayName: p.displayName,
      avatarUrl: p.avatarUrl,
      relation: relation,
    );
  }

  for (final p in followers) {
    add(p, DmRelation.followsYou);
  }
  for (final p in following) {
    add(p, DmRelation.youFollow);
  }

  return byId.values.toList()..sort(_byName);
}

int _byName(DmRecipient a, DmRecipient b) {
  final an = a.displayName;
  final bn = b.displayName;
  if (an == null || bn == null) {
    if (an != bn) return an == null ? 1 : -1;
    final byId = a.id.compareTo(b.id);
    return byId == 0 ? 0 : (byId < 0 ? -1 : 1);
  }
  return compareFoldedNames(an, a.id, bn, b.id);
}

/// Narrow the candidate list by a typed name query, accent-folded so a
/// diacritic the sender didn't type still matches the name that carries it.
/// A blank query keeps everyone; a recipient with no display name matches no
/// non-blank query, because there is no text on the row to have matched.
List<DmRecipient> filterDmRecipients(
  List<DmRecipient> recipients,
  String query,
) {
  final q = fold(query.trim());
  if (q.isEmpty) return [...recipients];
  return [
    for (final r in recipients)
      if (r.displayName != null && fold(r.displayName!).contains(q)) r,
  ];
}
