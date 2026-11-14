/// What a runner was typing into each conversation, so leaving a thread and
/// coming back keeps the text (issue #1374 NS-8; web keeps a draft per thread
/// too). Held in memory for the app's life, like web's.
///
/// A key carries the account, so a draft never follows the reader into
/// another account, and the conversation, so it never follows them into
/// another conversation's audience. One map serves 1:1 threads and groups.
abstract final class DmDrafts {
  static final Map<String, String> _drafts = {};

  /// A 1:1 thread with [partner] (a user id, or a deleted partner's key).
  static String directKey(String? userId, String partner) =>
      '$userId|dm|$partner';

  /// A group conversation.
  static String groupKey(String? userId, String conversationId) =>
      '$userId|group|$conversationId';

  static String read(String key) => _drafts[key] ?? '';

  /// Drops every draft: on sign-out, so the departing account's unsent text
  /// is gone, and between tests.
  static void clear() => _drafts.clear();

  /// Stores [text] under [key]; an empty text drops the draft.
  static void write(String key, String text) {
    if (text.isEmpty) {
      _drafts.remove(key);
    } else {
      _drafts[key] = text;
    }
  }
}
