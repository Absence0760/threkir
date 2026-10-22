/// The Messages inbox: the runner's direct-message conversations plus the AI
/// Coach as one more row (issue #1215, decisions § 2227).
///
/// The two are merged here, in the list, and nowhere else. `direct_messages`
/// and `coach_messages` keep their own tables, RLS, retention and rendering
/// (decisions § 110): nothing here reads a message body beyond the coach row's
/// plain-text preview, and no AI text is ever placed in a human conversation.
///
/// Web twin: `apps/web/src/lib/social/messages_inbox.ts`.
library;

/// Where the AI Coach sits in the inbox. `pinned` keeps it above every
/// conversation, `listed` files it among them by its latest message, and
/// `hidden` leaves it out. The runner picks this freely, on any tier.
enum CoachInboxPlacement { pinned, listed, hidden }

/// The universal settings key the placement is stored under
/// (docs/backend/settings.md); `SettingsKeys.messagesCoachRow`.
const String kMessagesCoachRowKey = 'messages_coach_row';

/// The stored placement. Anything but the two non-default spellings reads as
/// [CoachInboxPlacement.pinned]: an absent key is a runner who never chose,
/// and a corrupt one is not a decision to hide the Coach.
CoachInboxPlacement parseCoachInboxPlacement(Object? raw) => switch (raw) {
      'listed' => CoachInboxPlacement.listed,
      'hidden' => CoachInboxPlacement.hidden,
      _ => CoachInboxPlacement.pinned,
    };

/// One row of the inbox: the Coach, or a conversation.
sealed class InboxEntry<T> {
  const InboxEntry();
}

class CoachInboxEntry<T> extends InboxEntry<T> {
  const CoachInboxEntry();
}

class DmInboxEntry<T> extends InboxEntry<T> {
  final T thread;
  const DmInboxEntry(this.thread);
}

class CoachInboxRow {
  final CoachInboxPlacement placement;

  /// When the newest Coach message was written; null when there is none, or
  /// when it was not read because the runner has not consented to the Coach.
  /// A listed row with no time goes after every conversation.
  final DateTime? lastAt;

  const CoachInboxRow({required this.placement, this.lastAt});
}

/// The inbox's rows in display order. [threads] keep the order they came in
/// (`dm_threads()` returns newest first); the Coach row is placed among them.
/// [coach] is null when the Coach is off for this deploy or this runner, and
/// then the inbox is the conversations alone.
///
/// A listed Coach row goes before the first conversation whose latest message
/// is strictly older than its own, so on a tie the conversation stays first.
List<InboxEntry<T>> inboxEntries<T>(
  List<T> threads,
  CoachInboxRow? coach, {
  required DateTime Function(T) lastAt,
}) {
  final dms = [for (final t in threads) DmInboxEntry<T>(t)];
  if (coach == null || coach.placement == CoachInboxPlacement.hidden) {
    return dms;
  }
  final row = CoachInboxEntry<T>();
  if (coach.placement == CoachInboxPlacement.pinned) return [row, ...dms];
  final at = coach.lastAt;
  if (at == null) return [...dms, row];
  // Milliseconds, as web compares: Postgres stamps microseconds, which
  // DateTime keeps and JavaScript's Date.parse drops.
  final atMs = at.millisecondsSinceEpoch;
  final index =
      threads.indexWhere((t) => lastAt(t).millisecondsSinceEpoch < atMs);
  if (index == -1) return [...dms, row];
  return [...dms.sublist(0, index), row, ...dms.sublist(index)];
}

/// How long the Coach row's preview may run, in code points, before it is cut
/// with an ellipsis.
const int kCoachPreviewMax = 140;

final _link = RegExp(r'!?\[([^\]]*)\]\([^)]*\)');
final _fence = RegExp(r'```[^\n]*');
final _lineMarker =
    RegExp(r'^[ \t]*(?:#{1,6}|>|[-*+]|\d+[.)])[ \t]+', multiLine: true);
final _emphasis = RegExp(r'\*\*|__|~~|\*');
// One explicit whitespace set, because String.trim and \s disagree between
// Dart and JavaScript (Dart's trim strips U+0085).
const _wsClass =
    r'[\t\n\v\f\r \u0085\u00a0\u1680\u2000-\u200a\u2028\u2029\u202f\u205f\u3000\ufeff]';
final _space = RegExp('$_wsClass+');
final _edgeSpace = RegExp('^$_wsClass+|$_wsClass+\$');

/// A Coach message as one line of plain text for the inbox row. The Coach
/// writes markdown; the row shows text only, so the markup is dropped rather
/// than rendered.
String coachInboxPreview(String content) {
  final text = content
      .replaceAllMapped(_link, (m) => m.group(1) ?? '')
      .replaceAll(_fence, ' ')
      .replaceAll('`', '')
      .replaceAll(_lineMarker, '')
      .replaceAll(_emphasis, '')
      .replaceAll(_space, ' ')
      .replaceAll(_edgeSpace, '');
  final points = text.runes.toList();
  if (points.length <= kCoachPreviewMax) return text;
  final cut = String.fromCharCodes(points.sublist(0, kCoachPreviewMax - 1));
  return '${cut.replaceAll(_edgeSpace, '')}…';
}
