import 'package:core_models/core_models.dart';

// Badge awards from people you follow, placed in the following feed as
// compact chronological rows instead of a sideways strip (issue #1374).
// TS↔Dart parity pair with apps/web/src/lib/social/feed_highlights.ts — keep
// the algorithm, edge cases and test counts in lockstep.
//
// Two cursor-paged streams meet here: the activity feed (started_at desc) and
// the badge awards (earned_at desc). A highlight is only placed once the
// activity page reaches back past it, so it never sits under the last loaded
// card while older activity has yet to load, and the badge stream is read on
// until it reaches back as far as the activity has.

/// One person's awards on one local day, newest first.
class FeedHighlight {
  /// `$authorId|$day`.
  final String key;
  final String authorId;
  final List<BadgeAwardEntry> awards;

  /// The newest award's `earnedAt`, where the row sits in the feed.
  final DateTime at;

  FeedHighlight._(this.key, this.authorId, this.awards, this.at);
}

/// A row of the feed: an activity entry or a highlight.
sealed class FeedRow<E> {
  const FeedRow();
}

class FeedEntryRow<E> extends FeedRow<E> {
  final E entry;
  const FeedEntryRow(this.entry);
}

class FeedHighlightRow<E> extends FeedRow<E> {
  final FeedHighlight highlight;
  const FeedHighlightRow(this.highlight);
}

/// The viewer's local calendar day of an instant.
String localDayKey(DateTime t) {
  final d = t.toLocal();
  return '${d.year}-${d.month}-${d.day}';
}

/// Highlights are not an activity, so a chip naming one hides them.
bool highlightsShowFor(String activityFilter) => activityFilter == 'all';

int _newerFirst(BadgeAwardEntry a, BadgeAwardEntry b) {
  final c = b.badge.earnedAt.compareTo(a.badge.earnedAt);
  if (c != 0) return c;
  return b.badge.id.compareTo(a.badge.id);
}

/// Collapse awards into one highlight per (person, local day), newest first.
/// An award seen twice (an overlapping page) counts once.
List<FeedHighlight> groupHighlights(
  List<BadgeAwardEntry> awards, {
  String Function(DateTime) dayKey = localDayKey,
}) {
  final seen = <String>{};
  final sorted = [
    for (final a in awards)
      if (seen.add(a.badge.id)) a,
  ]..sort(_newerFirst);
  final byKey = <String, FeedHighlight>{};
  for (final a in sorted) {
    final key = '${a.authorId}|${dayKey(a.badge.earnedAt)}';
    final group = byKey[key];
    if (group != null) {
      group.awards.add(a);
    } else {
      byKey[key] = FeedHighlight._(key, a.authorId, [a], a.badge.earnedAt);
    }
  }
  return byKey.values.toList();
}

/// The feed as one vertical list: activity entries in their order, each
/// highlight placed by its newest award. While more activity can still load,
/// a highlight older than the oldest loaded entry waits for that page.
/// At an equal instant the activity entry comes first.
List<FeedRow<E>> interleaveHighlights<E>(
  List<E> entries,
  DateTime Function(E) entryAt,
  List<FeedHighlight> highlights,
  bool feedExhausted,
) {
  if (!feedExhausted && entries.isEmpty) return const [];
  final floor = feedExhausted ? null : entryAt(entries.last);
  final placed = [
    for (final h in highlights)
      if (floor == null || !h.at.isBefore(floor)) h,
  ];
  final rows = <FeedRow<E>>[];
  var h = 0;
  for (final entry in entries) {
    final t = entryAt(entry);
    while (h < placed.length && placed[h].at.isAfter(t)) {
      rows.add(FeedHighlightRow<E>(placed[h++]));
    }
    rows.add(FeedEntryRow<E>(entry));
  }
  while (h < placed.length) {
    rows.add(FeedHighlightRow<E>(placed[h++]));
  }
  return rows;
}

/// Whether the badge stream must read another page before the rows are
/// complete: it has more, and what it has loaded does not yet reach back as
/// far as the activity (or the activity has run out).
bool needsMoreHighlights({
  required DateTime? oldestAwardAt,
  required bool awardsExhausted,
  required DateTime? oldestEntryAt,
  required bool feedExhausted,
}) {
  if (awardsExhausted) return false;
  if (oldestAwardAt == null) return true;
  if (feedExhausted || oldestEntryAt == null) return true;
  return !oldestAwardAt.isBefore(oldestEntryAt);
}
