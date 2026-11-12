/// Searching the viewer's own direct messages (issue #1216, migration
/// 20271213121603). `search_direct_messages` runs under the caller's own
/// RLS; this only shapes the query and the snippet. Web twin:
/// `apps/web/src/lib/social/dm_search.ts`.
library;

/// The query length the RPC accepts, in characters.
const int kDmSearchMinChars = 2;
const int kDmSearchMaxChars = 100;

/// The query as the server will read it, or null when it would match
/// nothing.
String? normalizeDmSearchQuery(String raw) {
  final q = raw.trim();
  final n = q.runes.length;
  return n >= kDmSearchMinChars && n <= kDmSearchMaxChars ? q : null;
}

class DmSearchSnippet {
  const DmSearchSnippet({
    required this.before,
    required this.match,
    required this.after,
  });

  final String before;
  final String match;
  final String after;

  @override
  bool operator ==(Object other) =>
      other is DmSearchSnippet &&
      other.before == before &&
      other.match == match &&
      other.after == after;

  @override
  int get hashCode => Object.hash(before, match, after);

  @override
  String toString() => 'DmSearchSnippet($before|$match|$after)';
}

/// The part of [body] around the first case-insensitive match of [query],
/// with up to [radius] characters each side and an ellipsis where text was
/// cut. A body with no match (the server and the client case-fold
/// differently for a few scripts) is shown from its start.
DmSearchSnippet dmSearchSnippet(String body, String query, {int radius = 40}) {
  final chars = body.runes.map(String.fromCharCode).toList();
  final lower = chars.map((c) => c.toLowerCase()).toList();
  final needle =
      query.trim().runes.map((r) => String.fromCharCode(r).toLowerCase()).toList();
  var at = -1;
  if (needle.isNotEmpty) {
    for (var i = 0; i + needle.length <= lower.length; i++) {
      var hit = true;
      for (var j = 0; j < needle.length; j++) {
        if (lower[i + j] != needle[j]) {
          hit = false;
          break;
        }
      }
      if (hit) {
        at = i;
        break;
      }
    }
  }
  if (at < 0) {
    final head = chars.take(radius * 2).toList();
    return DmSearchSnippet(
      before: '',
      match: '',
      after: head.join() + (chars.length > head.length ? '…' : ''),
    );
  }
  final start = at - radius < 0 ? 0 : at - radius;
  final endRaw = at + needle.length + radius;
  final end = endRaw > chars.length ? chars.length : endRaw;
  return DmSearchSnippet(
    before: (start > 0 ? '…' : '') + chars.sublist(start, at).join(),
    match: chars.sublist(at, at + needle.length).join(),
    after: chars.sublist(at + needle.length, end).join() +
        (end < chars.length ? '…' : ''),
  );
}
