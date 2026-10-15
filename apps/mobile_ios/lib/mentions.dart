// @mentions in run comments (decisions § 1971). TS↔Dart parity pair with
// apps/web/src/lib/social/mentions.ts, and the client half of
// private.extract_mention_handles (migration 20270823000001): the same rule
// decides what the server notifies and what the clients draw as a mention.
//
// A mention is `@` followed by a § 269 handle — 3 to 30 of [A-Za-z0-9_] — that
// is not glued to a word or a second `@` on its left, so `me@example.com`
// mentions nobody, and is not followed by another handle character, so a
// 31-character run is not truncated into a 30-character handle.

const int maxMentionsPerComment = 10;

final RegExp _mention =
    RegExp(r'(?<![A-Za-z0-9_@])@([A-Za-z0-9_]{3,30})(?![A-Za-z0-9_])');

/// The lowercased, de-duplicated handles a body mentions, first-seen order,
/// at most ten.
List<String> parseMentionHandles(String body) {
  final out = <String>[];
  for (final m in _mention.allMatches(body)) {
    final handle = m.group(1)!.toLowerCase();
    if (out.contains(handle)) continue;
    out.add(handle);
    if (out.length == maxMentionsPerComment) break;
  }
  return out;
}

/// One run of a comment body: plain text, or a mention with its handle.
class MentionSegment {
  final String text;

  /// Lowercased handle; null for a plain-text segment.
  final String? handle;

  const MentionSegment.text(this.text) : handle = null;
  const MentionSegment.mention(this.text, String this.handle);

  bool get isMention => handle != null;

  @override
  bool operator ==(Object other) =>
      other is MentionSegment && other.text == text && other.handle == handle;

  @override
  int get hashCode => Object.hash(text, handle);

  @override
  String toString() => isMention ? 'mention($text)' : 'text($text)';
}

/// The body cut into plain text and mentions, in order, for rendering. Every
/// well-formed mention is a segment (the ten-handle cap is a notification
/// limit, not a display one).
List<MentionSegment> splitMentions(String body) {
  final out = <MentionSegment>[];
  var last = 0;
  for (final m in _mention.allMatches(body)) {
    if (m.start > last) out.add(MentionSegment.text(body.substring(last, m.start)));
    out.add(MentionSegment.mention(m.group(0)!, m.group(1)!.toLowerCase()));
    last = m.end;
  }
  if (last < body.length) out.add(MentionSegment.text(body.substring(last)));
  return out;
}

/// The mention being typed at [caret], if any: the `@` it starts at and the
/// handle prefix after it (possibly empty).
({int start, String query})? activeMentionQuery(String text, int caret) {
  final end = caret.clamp(0, text.length);
  final before = text.substring(0, end);
  final m = RegExp(r'(?<![A-Za-z0-9_@])@([A-Za-z0-9_]{0,30})$').firstMatch(before);
  if (m == null) return null;
  return (start: m.start, query: m.group(1)!.toLowerCase());
}

/// Replace the `@query` at [start]..[caret] with `@handle ` and return the new
/// text and caret.
({String text, int caret}) insertMention(
  String text,
  int start,
  int caret,
  String handle,
) {
  final inserted = '@$handle ';
  final rest = text
      .substring(caret)
      .replaceFirst(RegExp(r'^[A-Za-z0-9_]*'), '')
      .replaceFirst(RegExp(r'^ '), '');
  return (
    text: text.substring(0, start) + inserted + rest,
    caret: start + inserted.length,
  );
}
