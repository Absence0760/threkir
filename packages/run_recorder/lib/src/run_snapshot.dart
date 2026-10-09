import 'package:core_models/core_models.dart';

/// A point-in-time snapshot emitted during a live recording session.
class RunSnapshot {
  final Duration elapsed;
  final double distanceMetres;

  /// Rolling pace, s/km, over the GPS distance estimator's last ~200 m. Null
  /// until five fixes and 50 m have landed since the last pause, resume or
  /// re-anchored GPS gap.
  final double? currentPaceSecondsPerKm;

  /// Latest GPS fix, if any. Null during the initial warmup and for indoor
  /// runs where location services were never available — the stopwatch
  /// keeps ticking and the live map falls back to its "Waiting for GPS..."
  /// placeholder until a fix arrives.
  final Waypoint? currentPosition;

  /// Wall-clock time the fix in [currentPosition] was accepted from the
  /// sensor, or null while no fix has arrived. The 1-second timer re-emits
  /// the LAST fix on every tick, so the arrival time of a snapshot is not
  /// the age of its position — anything deciding "is the GPS still alive"
  /// (a lost-signal banner, a spectator ping, a cut-off projection) must
  /// threshold on this and never on `currentPosition != null`.
  final DateTime? positionFixedAt;

  /// False when [currentPosition] is a fix the distance filter REJECTED
  /// (jitter below the movement threshold, or an implausible teleport). It
  /// still drives the blue dot at sensor rate, but it must never advance
  /// route progress — a rejected teleport would otherwise latch every
  /// course-marker cue it skipped over.
  final bool positionTrusted;

  final double? offRouteDistanceMetres;

  /// Distance remaining to the end of the selected route, in metres.
  /// Null when no route is selected.
  final double? routeRemainingMetres;

  /// How far along the selected route the runner has been matched, in metres
  /// from its start. The recorder's matcher remembers the previous match, so
  /// on a loop, an out-and-back or a figure-eight this is the lap or leg the
  /// runner is actually on — consumers placing the runner on the route (turn
  /// cues, course markers, cut-off ETAs) read it rather than re-projecting
  /// [currentPosition] onto the whole line. Null when no route is selected.
  final double? routeAlongMetres;

  /// The full GPS track recorded so far (unmodifiable).
  final List<Waypoint> track;

  /// True when the most recent GPS fix was rejected by the accuracy gate
  /// (low-accuracy fix under tree cover / urban canyon), so distance is
  /// not advancing even though the stopwatch keeps ticking. Lets the UI
  /// disclose "distance paused" instead of looking frozen. Cleared as soon
  /// as a fix passes the gate again. Always false before the first dropped
  /// fix and for indoor / no-GPS runs.
  final bool weakGps;

  const RunSnapshot({
    required this.elapsed,
    required this.distanceMetres,
    this.currentPaceSecondsPerKm,
    this.currentPosition,
    this.positionFixedAt,
    this.positionTrusted = true,
    this.offRouteDistanceMetres,
    this.routeRemainingMetres,
    this.routeAlongMetres,
    this.track = const [],
    this.weakGps = false,
  });
}
