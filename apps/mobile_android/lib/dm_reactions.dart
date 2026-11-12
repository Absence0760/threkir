/// Reactions on a direct message (issue #1216, migration 20271213121602).
///
/// The server stores a key from a fixed set, CHECKed on
/// `direct_message_reactions.reaction`; `set_direct_message_reaction` decides
/// who may react. A glyph is built from its Unicode codepoints here, so no
/// source file carries an emoji literal and the stored value is never a
/// glyph. Web twin: `apps/web/src/lib/social/dm_reactions.ts`.
library;

/// Every key the CHECK admits, in the order the picker and the summary use.
const List<String> kDmReactions = [
  'thumbs_up',
  'heart',
  'laugh',
  'surprised',
  'sad',
  'fire',
];

/// The codepoints each key draws as.
const Map<String, List<int>> kDmReactionCodepoints = {
  'thumbs_up': [0x1f44d],
  'heart': [0x2764, 0xfe0f],
  'laugh': [0x1f602],
  'surprised': [0x1f62e],
  'sad': [0x1f622],
  'fire': [0x1f525],
};

String? parseDmReaction(Object? raw) =>
    raw is String && kDmReactions.contains(raw) ? raw : null;

String dmReactionGlyph(String reaction) =>
    String.fromCharCodes(kDmReactionCodepoints[reaction] ?? const []);

class DmReactionRow {
  const DmReactionRow({
    required this.messageId,
    required this.userId,
    required this.reaction,
  });

  final String messageId;
  final String userId;
  final String reaction;
}

class DmReactionSummary {
  const DmReactionSummary({
    required this.reaction,
    required this.count,
    required this.mine,
  });

  final String reaction;
  final int count;
  final bool mine;

  @override
  bool operator ==(Object other) =>
      other is DmReactionSummary &&
      other.reaction == reaction &&
      other.count == count &&
      other.mine == mine;

  @override
  int get hashCode => Object.hash(reaction, count, mine);

  @override
  String toString() => 'DmReactionSummary($reaction, $count, mine: $mine)';
}

/// The chips under one message: one per key that anyone used, in
/// [kDmReactions] order, with whether the viewer's own reaction is that key.
/// Rows for other messages and unknown keys are ignored.
List<DmReactionSummary> summarizeDmReactions(
  List<DmReactionRow> rows,
  String messageId,
  String? viewerId,
) {
  final counts = <String, int>{};
  final mine = <String>{};
  for (final r in rows) {
    if (r.messageId != messageId) continue;
    final key = parseDmReaction(r.reaction);
    if (key == null) continue;
    counts[key] = (counts[key] ?? 0) + 1;
    if (viewerId != null && r.userId == viewerId) mine.add(key);
  }
  return [
    for (final key in kDmReactions)
      if (counts[key] != null)
        DmReactionSummary(
          reaction: key,
          count: counts[key]!,
          mine: mine.contains(key),
        ),
  ];
}

/// The viewer's own reaction on a message, if any.
String? myDmReaction(
  List<DmReactionRow> rows,
  String messageId,
  String? viewerId,
) {
  if (viewerId == null) return null;
  for (final r in rows) {
    if (r.messageId == messageId && r.userId == viewerId) {
      return parseDmReaction(r.reaction);
    }
  }
  return null;
}

/// The rows after the viewer sets [next] (null clears) on a message, applied
/// locally before the server answers so the chip moves at once.
List<DmReactionRow> withMyDmReaction(
  List<DmReactionRow> rows,
  String messageId,
  String viewerId,
  String? next,
) {
  final rest = [
    for (final r in rows)
      if (!(r.messageId == messageId && r.userId == viewerId)) r,
  ];
  if (next == null) return rest;
  return [
    ...rest,
    DmReactionRow(messageId: messageId, userId: viewerId, reaction: next),
  ];
}
