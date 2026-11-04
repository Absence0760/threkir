import 'package:flutter/foundation.dart';

/// Conversations the viewer deleted for themselves whose undo window is still
/// open (issue #1216). The server is told only when the window closes, so
/// every inbox read until then still lists them; the inbox leaves these out.
///
/// App-scoped because the delete starts in a conversation that is usually
/// popped before the window closes, while the inbox under it keeps polling.
class DmPendingHides extends ChangeNotifier {
  DmPendingHides._();

  static final DmPendingHides instance = DmPendingHides._();

  final Set<String> _ids = {};

  bool contains(String conversationId) => _ids.contains(conversationId);

  void add(String conversationId) {
    if (_ids.add(conversationId)) notifyListeners();
  }

  void remove(String conversationId) {
    if (_ids.remove(conversationId)) notifyListeners();
  }

  @visibleForTesting
  void debugClear() => _ids.clear();
}
