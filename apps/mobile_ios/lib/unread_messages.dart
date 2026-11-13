import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleListener;

import 'dm_pending_hides.dart';
import 'messages_inbox.dart' show unreadDmBadgeCount;
import 'monotonic_clock.dart';

/// One conversation's badge inputs, as `ApiClient.fetchDmBadgeStates` reads
/// them.
typedef DmBadgeState = ({
  String conversationId,
  int unread,
  bool muted,
  bool archived,
  bool request,
});

/// The signed-in runner's unread direct messages, as one count every badge
/// that points at the inbox reads: the Social hub's Messages button and the
/// Social item in the bottom nav (issue #1374, owner decision "Messages move
/// to Social"). Web's twin is `dmUnreadStore`.
///
/// App-scoped, like [DmPendingHides], because the badges that read it live on
/// pages that are built lazily and at different times: the shell's nav bar
/// exists before the Social page does. Whoever holds the client [bind]s it,
/// and binding the same client again is free.
///
/// The count is [unreadDmBadgeCount] over the last read (muted, archived and
/// request conversations excluded), with a conversation the runner deleted
/// but whose delete has not landed left out at once ([DmPendingHides.hides]).
/// It is read again when the client is bound, when the signed-in account
/// changes (the old account's count is dropped first), when a delete lands or
/// is undone, when the app comes back to the foreground, and on [refresh],
/// which the inbox calls as it closes. A failed read keeps the count it had:
/// the badge is an auxiliary signal (L4) and the inbox still opens.
class UnreadMessages extends ChangeNotifier implements ValueListenable<int> {
  UnreadMessages({DmPendingHides? hides, bool listenToLifecycle = true})
      : _hides = hides ?? DmPendingHides.instance {
    _reader = _hides.reader();
    _seenOutcomes = _hides.outcomes;
    _hides.addListener(_onPendingHidesChanged);
    if (listenToLifecycle) {
      _lifecycle = AppLifecycleListener(onResume: refresh);
    }
  }

  static final UnreadMessages instance = UnreadMessages();

  final DmPendingHides _hides;
  late final DmHideReader _reader;
  late int _seenOutcomes;
  AppLifecycleListener? _lifecycle;

  ApiClient? _api;
  StreamSubscription<String?>? _authSub;
  String? _userId;

  List<DmBadgeState> _states = const [];
  Duration? _readAt;
  int _value = 0;

  /// Bumped by every read; only the newest may answer, since a poll and a
  /// return from the inbox can overlap.
  int _gen = 0;

  bool _disposed = false;

  /// Unread messages, 0 while unknown or signed out.
  @override
  int get value => _value;

  /// Reads for [api] from now on. Null unbinds and clears the count. The same
  /// client again only re-reads when nothing has been read for it yet.
  void bind(ApiClient? api) {
    if (identical(api, _api)) {
      if (api != null && _readAt == null) refresh();
      return;
    }
    _authSub?.cancel();
    _authSub = null;
    _api = api;
    _userId = api?.userId;
    _clear();
    if (api == null) return;
    _authSub = api.authUserChanges.listen((_) {
      final current = _api?.userId;
      if (current == _userId) return;
      _userId = current;
      _clear();
      refresh();
    }, onError: (Object e) {
      debugPrint('UnreadMessages auth stream error: ${safeErrorLabel(e)}');
    });
    refresh();
  }

  /// Reads the badge states again. Resolves once this read has been applied
  /// or dropped; never throws.
  Future<void> refresh() async {
    final api = _api;
    final asked = api?.userId;
    final gen = ++_gen;
    if (api == null || asked == null || _disposed) return;
    final startedAt = monotonicNow();
    try {
      final states = await api.fetchDmBadgeStates();
      if (_disposed || gen != _gen || !identical(api, _api)) return;
      if (api.userId != asked) return;
      _states = states;
      _readAt = startedAt;
      _reader.applied(startedAt);
      _recount();
    } catch (e) {
      debugPrint('UnreadMessages read failed: ${safeErrorLabel(e)}');
    }
  }

  void _clear() {
    _gen++;
    _states = const [];
    _readAt = null;
    _reader.reset();
    _recount();
  }

  void _recount() {
    final readAt = _readAt;
    final next = unreadDmBadgeCount([
      for (final s in _states)
        if (readAt == null || !_hides.hides(s.conversationId, readAt))
          (
            unread: s.unread,
            muted: s.muted,
            archived: s.archived,
            request: s.request,
          ),
    ]);
    if (next == _value || _disposed) return;
    _value = next;
    notifyListeners();
  }

  /// A pending delete is applied to the count already held; Undo or a landed
  /// commit is answered by a fresh read, the server being the one that knows.
  void _onPendingHidesChanged() {
    _recount();
    final outcomes = _hides.outcomes;
    if (outcomes == _seenOutcomes) return;
    _seenOutcomes = outcomes;
    refresh();
  }

  @override
  void dispose() {
    _disposed = true;
    _authSub?.cancel();
    _lifecycle?.dispose();
    _hides.removeListener(_onPendingHidesChanged);
    _reader.close();
    super.dispose();
  }
}
