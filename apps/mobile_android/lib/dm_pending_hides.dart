import 'package:flutter/foundation.dart';

import 'monotonic_clock.dart';

/// Conversations the viewer deleted for themselves (issue #1216), and when
/// each delete landed on the server. The server is told only when the undo
/// window closes, so every read until then still lists the conversation; and
/// a read that started before the delete landed still lists it after, so a
/// list holding such a read leaves it out too. Web keeps the same marker
/// (`#hiddenAt` in `messages_inbox.svelte.ts`). Every time here is
/// [monotonicNow], read starts included.
///
/// App-scoped because the delete starts in a conversation that is usually
/// popped before the window closes, while the inbox and the You tab's badge
/// under it keep reading.
class DmPendingHides extends ChangeNotifier {
  DmPendingHides._();

  static final DmPendingHides instance = DmPendingHides._();

  /// Null while the undo window is open or the commit is in flight.
  final Map<String, Duration?> _hiddenAt = {};
  final Set<DmHideReader> _readers = {};
  int _outcomes = 0;

  /// Bumped when a delete lands, is undone or is refused. A listener re-reads
  /// the server only when this moved: a delete is answered by leaving out
  /// what the list already holds, while an outcome is the server's to report.
  int get outcomes => _outcomes;

  /// The delete is inside its undo window or still in flight.
  bool contains(String conversationId) =>
      _hiddenAt.containsKey(conversationId) &&
      _hiddenAt[conversationId] == null;

  /// Whether a list read that started at [readStartedAt] must leave the
  /// conversation out: it was deleted before that read could know. The
  /// landing time is taken once the server has answered, so a read started
  /// at that same instant already carries the delete.
  bool hides(String conversationId, Duration readStartedAt) {
    if (!_hiddenAt.containsKey(conversationId)) return false;
    final at = _hiddenAt[conversationId];
    return at == null || at > readStartedAt;
  }

  /// A list that applies reads and filters them through [hides]. While it
  /// holds a read that started before a delete landed, that delete's marker
  /// is kept; [DmHideReader.close] it with the list.
  DmHideReader reader() {
    final r = DmHideReader._(this);
    _readers.add(r);
    return r;
  }

  void add(String conversationId) {
    if (contains(conversationId)) return;
    _hiddenAt[conversationId] = null;
    notifyListeners();
  }

  /// The server has hidden the conversation.
  void landed(String conversationId) {
    if (!contains(conversationId)) return;
    _hiddenAt[conversationId] = monotonicNow();
    _outcomes++;
    _prune();
    notifyListeners();
  }

  /// Undo, or a refused commit: the conversation is the viewer's again.
  void remove(String conversationId) {
    if (!_hiddenAt.containsKey(conversationId)) return;
    _hiddenAt.remove(conversationId);
    _outcomes++;
    notifyListeners();
  }

  /// Drops each landed marker no open list still needs: every reader holds
  /// a read that started once it had landed, or holds none. The readers' own
  /// generation guards keep an older read in flight from being applied.
  void _prune() {
    _hiddenAt.removeWhere((_, at) =>
        at != null &&
        _readers.every((r) => !((r._heldSince ?? at) < at)));
  }

  @visibleForTesting
  bool debugHasMarker(String conversationId) =>
      _hiddenAt.containsKey(conversationId);

  @visibleForTesting
  void debugClear() => _hiddenAt.clear();
}

class DmHideReader {
  DmHideReader._(this._owner);

  final DmPendingHides _owner;
  Duration? _heldSince;

  /// The list now holds the read that started at [readStartedAt].
  void applied(Duration readStartedAt) {
    _heldSince = readStartedAt;
    _owner._prune();
  }

  /// The list was emptied (the account changed): it holds no read, so no
  /// marker is kept for it.
  void reset() {
    _heldSince = null;
    _owner._prune();
  }

  void close() {
    _owner._readers.remove(this);
    _owner._prune();
  }
}
