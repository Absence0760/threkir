/// The head-to-head share card's pure half: the rows the `head_to_head` RPC
/// returns, who won and by how much, and how the card prints a time and a name.
/// Decisions § 2267.
///
/// TS↔Dart parity pair with `apps/web/src/lib/social/head_to_head.ts` — keep
/// the two in lockstep: algorithm, edge cases, outputs, test counts.
library;

const List<String> headToHeadKinds = ['route', 'segment', 'global_segment'];

class HeadToHeadRow {
  final String friendId;
  final String? friendDisplayName;
  final String? friendHandle;
  final String? friendAvatarUrl;
  final String targetName;
  final String myRunId;
  final num mySeconds;
  final String friendRunId;
  final num friendSeconds;

  const HeadToHeadRow({
    required this.friendId,
    required this.friendDisplayName,
    required this.friendHandle,
    required this.friendAvatarUrl,
    required this.targetName,
    required this.myRunId,
    required this.mySeconds,
    required this.friendRunId,
    required this.friendSeconds,
  });

  @override
  bool operator ==(Object other) =>
      other is HeadToHeadRow &&
      other.friendId == friendId &&
      other.friendDisplayName == friendDisplayName &&
      other.friendHandle == friendHandle &&
      other.friendAvatarUrl == friendAvatarUrl &&
      other.targetName == targetName &&
      other.myRunId == myRunId &&
      other.mySeconds == mySeconds &&
      other.friendRunId == friendRunId &&
      other.friendSeconds == friendSeconds;

  @override
  int get hashCode => Object.hash(friendId, friendDisplayName, friendHandle,
      friendAvatarUrl, targetName, myRunId, mySeconds, friendRunId,
      friendSeconds);
}

enum HeadToHeadWinner { me, friend, tie }

class HeadToHeadOutcome {
  final HeadToHeadWinner winner;

  /// Whole seconds between the two times; 0 for a tie.
  final int marginSeconds;

  const HeadToHeadOutcome(this.winner, this.marginSeconds);

  @override
  bool operator ==(Object other) =>
      other is HeadToHeadOutcome &&
      other.winner == winner &&
      other.marginSeconds == marginSeconds;

  @override
  int get hashCode => Object.hash(winner, marginSeconds);
}

String? _text(Object? v) => v is String && v.trim().isNotEmpty ? v : null;

num? _seconds(Object? v) => v is num && v.isFinite && v > 0 ? v : null;

/// The RPC's rows, keeping only those that carry both sides. A malformed row is
/// dropped rather than drawn with a missing time.
List<HeadToHeadRow> parseHeadToHeadRows(Object? raw) {
  if (raw is! List) return const [];
  final rows = <HeadToHeadRow>[];
  for (final r in raw) {
    if (r is! Map) continue;
    final friendId = _text(r['friend_id']);
    final targetName = _text(r['target_name']);
    final myRunId = _text(r['my_run_id']);
    final friendRunId = _text(r['friend_run_id']);
    final mySeconds = _seconds(r['my_seconds']);
    final friendSeconds = _seconds(r['friend_seconds']);
    if (friendId == null ||
        targetName == null ||
        myRunId == null ||
        friendRunId == null ||
        mySeconds == null ||
        friendSeconds == null) {
      continue;
    }
    rows.add(HeadToHeadRow(
      friendId: friendId,
      friendDisplayName: _text(r['friend_display_name']),
      friendHandle: _text(r['friend_handle']),
      friendAvatarUrl: _text(r['friend_avatar_url']),
      targetName: targetName,
      myRunId: myRunId,
      mySeconds: mySeconds,
      friendRunId: friendRunId,
      friendSeconds: friendSeconds,
    ));
  }
  return rows;
}

/// JavaScript's `Math.round`: halves go up, so `-0.5` rounds to 0 and the two
/// platforms agree on every input.
int _jsRound(num v) => (v + 0.5).floor();

/// Lower time wins. Both are rounded to whole seconds first, so the card never
/// names a winner by a margin it prints as 0:00.
HeadToHeadOutcome headToHeadOutcome(num mySeconds, num friendSeconds) {
  final mine = _jsRound(mySeconds);
  final theirs = _jsRound(friendSeconds);
  if (mine == theirs) return const HeadToHeadOutcome(HeadToHeadWinner.tie, 0);
  return HeadToHeadOutcome(
    mine < theirs ? HeadToHeadWinner.me : HeadToHeadWinner.friend,
    (mine - theirs).abs(),
  );
}

/// `m:ss` under an hour, `h:mm:ss` from one. Rounded; never negative.
String formatHeadToHeadTime(num totalSeconds) {
  final t = totalSeconds.isFinite
      ? (_jsRound(totalSeconds) < 0 ? 0 : _jsRound(totalSeconds))
      : 0;
  final h = t ~/ 3600;
  final m = (t % 3600) ~/ 60;
  final s = t % 60;
  final ss = s.toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$ss' : '$m:$ss';
}

/// `@handle` when the runner has one, else their display name, else null so
/// the caller supplies its own fallback.
String? headToHeadName(String? handle, String? displayName) {
  final h = handle?.trim();
  if (h != null && h.isNotEmpty) return '@$h';
  final d = displayName?.trim();
  return d != null && d.isNotEmpty ? d : null;
}
