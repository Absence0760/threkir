import 'package:api_client/api_client.dart';
import 'package:flutter/foundation.dart';

import 'dm_pending_hides.dart';
import 'messages_inbox.dart' show unreadDmBadgeCount;
import 'monotonic_clock.dart';

/// How many messages wait unread for the runner, for the dot on the Social
/// nav item (issue #1374: Messages move to Social). The shell reads only this
/// interface, so whichever object owns the count (today a read of its own, or
/// the Social inbox's source once it has one) can stand behind the dot.
abstract interface class SocialUnreadSource implements Listenable {
  /// Unread messages that count toward a badge (`unreadDmBadgeCount`: muted,
  /// archived and request conversations do not). Zero until read.
  int get unreadCount;

  /// Reads the count again; a failure leaves the last count (L4).
  Future<void> refresh();

  void dispose();
}

/// The count the You header's Messages button has always shown, read the
/// same way: `ApiClient.fetchDmBadgeStates` through `unreadDmBadgeCount`,
/// with a conversation whose delete is still inside its undo window left out
/// (`DmPendingHides`, direct_messages.md). A read made for one account is
/// dropped if another is signed in when it lands, and only the newest read
/// may answer.
class DmBadgeUnreadSource extends ChangeNotifier implements SocialUnreadSource {
  DmBadgeUnreadSource(this._api) {
    DmPendingHides.instance.addListener(_onPendingHidesChanged);
  }

  final ApiClient _api;
  final DmHideReader _hideReader = DmPendingHides.instance.reader();
  int _seenHideOutcomes = DmPendingHides.instance.outcomes;

  List<({String conversationId, int unread, bool muted, bool archived, bool request})>
      _states = const [];
  Duration? _readAt;
  int _gen = 0;
  int _count = 0;
  bool _disposed = false;

  @override
  int get unreadCount => _count;

  @override
  Future<void> refresh() async {
    final asked = _api.userId;
    final gen = ++_gen;
    if (asked == null) {
      _apply(const [], null);
      _hideReader.reset();
      return;
    }
    final startedAt = monotonicNow();
    try {
      final states = await _api.fetchDmBadgeStates();
      if (_disposed || gen != _gen || _api.userId != asked) return;
      _hideReader.applied(startedAt);
      _apply(states, startedAt);
    } catch (e) {
      // L4 — a failed count leaves the dot as it was; Social still opens.
      debugPrint('social unread read failed: ${safeErrorLabel(e)}');
    }
  }

  void _apply(
      List<({String conversationId, int unread, bool muted, bool archived, bool request})>
          states,
      Duration? readAt) {
    _states = states;
    _readAt = readAt;
    _recount();
  }

  void _recount() {
    final hides = DmPendingHides.instance;
    final readAt = _readAt;
    final next = unreadDmBadgeCount([
      for (final s in _states)
        if (readAt == null || !hides.hides(s.conversationId, readAt))
          (
            unread: s.unread,
            muted: s.muted,
            archived: s.archived,
            request: s.request,
          ),
    ]);
    if (next == _count) return;
    _count = next;
    notifyListeners();
  }

  /// A pending delete is applied to the count already held; Undo or the
  /// commit is answered by a fresh read, the server being the one that knows.
  void _onPendingHidesChanged() {
    if (_disposed) return;
    _recount();
    final outcomes = DmPendingHides.instance.outcomes;
    if (outcomes == _seenHideOutcomes) return;
    _seenHideOutcomes = outcomes;
    refresh();
  }

  @override
  void dispose() {
    _disposed = true;
    DmPendingHides.instance.removeListener(_onPendingHidesChanged);
    _hideReader.close();
    super.dispose();
  }
}
