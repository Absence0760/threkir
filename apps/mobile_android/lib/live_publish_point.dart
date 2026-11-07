import 'package:core_models/core_models.dart';
import 'package:run_recorder/run_recorder.dart';

/// The position a recording may publish to spectators, and whether it is a
/// weak-GPS fix.
class LivePublishPoint {
  const LivePublishPoint(this.point, {required this.weakGps});

  final Waypoint point;

  /// True when [point] is a fix the distance estimator kept but the map gate
  /// refused (stated accuracy 20-50 m). Spectators draw it as an approximate
  /// position and never join it into the trace (decisions § 2357).
  final bool weakGps;
}

/// What a live ping (spectator link or race) should carry for [snapshot], or
/// null when there is nothing honest to publish (issue #1300 BUG-003 /
/// BUG-007).
///
/// Precise: while a fix has cleared the map gate within [freshWithin], the
/// point is the end of the recorder's line — [RunSnapshot.track], the same
/// filtered source the saved run is drawn from. [RunSnapshot.currentPosition]
/// is NOT used during a recording: it follows every fix at sensor rate,
/// including the jitter and teleports the movement filter rejected
/// ([RunSnapshot.positionTrusted] false), and publishing one drew a spike
/// across the spectator's map that the saved run never had. Before the line
/// has a point (the countdown), a trusted current position is the only one.
///
/// Weak (only when [allowWeak]): while no fix has cleared the gate within
/// [freshWithin] but the estimator took one, the point is the newest stored
/// fix. That fix is necessarily the estimator-only one: a fix that clears
/// the gate stamps [RunSnapshot.positionFixedAt] at the same instant as
/// [RunSnapshot.distanceFixedAt], so a stale position with fresh distance
/// means the newest store was a 20-50 m fix kept off the line. A phone that
/// never clears 20 m (a budget phone in a pocket) used to publish nothing
/// for a whole walk.
LivePublishPoint? livePublishPoint(
  RunSnapshot snapshot, {
  required DateTime now,
  required Duration freshWithin,
  bool allowWeak = true,
}) {
  bool fresh(DateTime? at) => at != null && now.difference(at) <= freshWithin;

  if (fresh(snapshot.positionFixedAt)) {
    final track = snapshot.track;
    if (track.isNotEmpty) return LivePublishPoint(track.last, weakGps: false);
    final current = snapshot.currentPosition;
    if (current != null && snapshot.positionTrusted) {
      return LivePublishPoint(current, weakGps: false);
    }
    return null;
  }
  if (!allowWeak || !fresh(snapshot.distanceFixedAt)) return null;
  final stored = snapshot.storedTrack;
  if (stored.isEmpty || !stored.last.offTrack) return null;
  return LivePublishPoint(stored.last, weakGps: true);
}
