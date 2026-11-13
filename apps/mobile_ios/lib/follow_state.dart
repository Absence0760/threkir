import 'package:flutter/foundation.dart';

/// Who the signed-in runner follows, as the app last changed it, so a
/// follow made on one surface shows on every other.
///
/// Following someone from their profile left the People row beside them on
/// Follow; tapping it sent a second follow, or an unfollow in the other
/// direction (issue #1374 NS-10). Each follow or unfollow that lands writes
/// here, and a list showing Follow buttons listens.
///
/// Keyed by viewer as well as person, so a second account on the phone never
/// inherits the first one's follows.
class FollowState extends ChangeNotifier {
  FollowState._();

  static final instance = FollowState._();

  final Map<(String?, String), bool> _follows = {};

  /// Whether [viewerId] follows [userId], as last changed here; null when
  /// nothing on this phone has changed it this session.
  bool? of(String? viewerId, String userId) => _follows[(viewerId, userId)];

  /// Records a follow or unfollow that has landed (a request to a private
  /// profile is not a follow until it is accepted).
  void put(String? viewerId, String userId, {required bool following}) {
    if (_follows[(viewerId, userId)] == following) return;
    _follows[(viewerId, userId)] = following;
    notifyListeners();
  }

  /// Forgets everything; the shell calls it on sign-out so the departing
  /// account's follows do not linger in memory.
  void clear() {
    if (_follows.isEmpty) return;
    _follows.clear();
    notifyListeners();
  }
}
