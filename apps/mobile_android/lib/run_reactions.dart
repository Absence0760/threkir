import 'package:flutter/material.dart';

// Run reactions (decisions § 1971). TS↔Dart parity pair with
// apps/web/src/lib/social/reactions.ts. The key list is the client rail of the
// run_reactions_reaction_check CHECK (check_constraint_unions.mjs). Keys are
// stable strings, never emoji; each renders as a Material icon.

const List<String> reactionKeys = ['fire', 'strong', 'trophy', 'thumbs_up', 'wave'];

const Map<String, IconData> reactionIcons = {
  'fire': Icons.local_fire_department,
  'strong': Icons.fitness_center,
  'trophy': Icons.emoji_events,
  'thumbs_up': Icons.thumb_up,
  'wave': Icons.waving_hand,
};

bool isReactionKey(Object? v) => v is String && reactionKeys.contains(v);

class ReactionTally {
  final String key;
  final int count;
  final bool viewerReacted;

  const ReactionTally(this.key, this.count, this.viewerReacted);
}

/// One tally per whitelisted key, in whitelist order, from the summary RPC's
/// rows. A key nobody used reads zero; a row naming a key this client does not
/// know (a newer server) is dropped rather than drawn without an icon.
List<ReactionTally> reactionTallies(List<Map<String, dynamic>> rows) {
  final byKey = <String, ReactionTally>{};
  for (final r in rows) {
    final key = r['reaction'];
    if (!isReactionKey(key)) continue;
    final raw = r['reaction_count'];
    final count = raw is num && raw.isFinite ? raw.floor() : 0;
    byKey[key as String] = ReactionTally(
      key,
      count < 0 ? 0 : count,
      r['viewer_reacted'] == true,
    );
  }
  return [
    for (final key in reactionKeys) byKey[key] ?? ReactionTally(key, 0, false),
  ];
}

/// The tallies after the viewer toggled [key]. [changed] is whether the server
/// actually inserted / deleted a row: a no-op flips the flag without moving
/// the count, so the total cannot drift from the server's.
List<ReactionTally> applyReactionToggle(
  List<ReactionTally> tallies,
  String key,
  bool nowReacted,
  bool changed,
) =>
    [
      for (final t in tallies)
        if (t.key != key)
          t
        else
          ReactionTally(
            key,
            (t.count + (changed ? (nowReacted ? 1 : -1) : 0)).clamp(0, 1 << 30),
            nowReacted,
          ),
    ];
