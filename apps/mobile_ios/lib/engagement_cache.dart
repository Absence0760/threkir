import 'package:core_models/core_models.dart';
import 'package:flutter/foundation.dart';

/// The newest kudos and comment counts this app has seen for each run, so a
/// change on one surface shows on every other.
///
/// The feed card kept the engagement it was loaded with, so after giving
/// kudos and commenting on the run's own page, Back showed the card without
/// them; tapping its kudos then "gave" one that already existed (issue #1374
/// NS-9). Every surface that reads or writes a run's engagement puts what it
/// now knows here, and a surface showing that run listens.
///
/// Keyed by viewer as well as run, because `viewerHasKudos` belongs to the
/// account that read it: a second account on the same phone never sees the
/// first one's kudos state.
class EngagementCache extends ChangeNotifier {
  EngagementCache._();

  static final instance = EngagementCache._();

  final Map<(String?, String), EngagementSummary> _byRun = {};

  EngagementSummary? of(String? viewerId, String runId) =>
      _byRun[(viewerId, runId)];

  /// Records [eng] for [runId] as [viewerId] sees it, and tells listeners
  /// when it differs from what was there.
  void put(String? viewerId, String runId, EngagementSummary eng) {
    final before = _byRun[(viewerId, runId)];
    if (before != null &&
        before.kudosCount == eng.kudosCount &&
        before.viewerHasKudos == eng.viewerHasKudos &&
        before.commentCount == eng.commentCount) {
      return;
    }
    _byRun[(viewerId, runId)] = eng;
    notifyListeners();
  }

  @visibleForTesting
  void debugClear() => _byRun.clear();
}
