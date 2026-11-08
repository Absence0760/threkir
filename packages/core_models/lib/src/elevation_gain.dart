import 'waypoint.dart';

// The one Dart elevation-gain gate. It lives here rather than in the app so
// the file importers in `gpx_parser` grade a route's climb the way a recorded
// run is graded (issue #1297).

/// Smallest elevation move that counts as real climb, in metres. Consumer GPS
/// altitude is noisy at the 1-3 m level sample to sample, and a raw 1 Hz sum
/// over a long run integrates that jitter into thousands of metres of vert that
/// never happened. The reference height only moves once a change clears this
/// band in either direction, so noise inside it contributes nothing while a
/// genuine climb is counted in full.
const double kElevationGainMinDeltaM = 3;

/// Total elevation LOSS across the raw track, in metres — the exact mirror of
/// [computeElevationGain], gate and dropout-carry included. Mobile-only: the
/// run-detail screen shows the two side by side, and grading one through the
/// noise band while summing the other raw would read as a bug (a flat road
/// would report 0 m of climb next to hundreds of metres of descent).
double computeElevationLoss(
  List<Waypoint> track, {
  double minDeltaM = kElevationGainMinDeltaM,
}) {
  double loss = 0;
  double? ref;
  for (final p in track) {
    final ele = p.elevationMetres;
    if (ele == null) continue;
    if (ref == null) {
      ref = ele;
      continue;
    }
    final delta = ele - ref;
    if (delta <= -minDeltaM) {
      loss += -delta;
      ref = ele;
    } else if (delta >= minDeltaM) {
      ref = ele;
    }
  }
  return loss;
}

/// Total positive elevation change across the track, in metres, over the RAW
/// track — never a simplified one. Twin of `computeElevationGain` in
/// `apps/web/src/lib/routes/route_simplify.ts`; keep in lockstep.
///
/// Two rules, both load-bearing:
///
/// 1. A waypoint with no elevation is skipped and the last valid reading is
///    carried across the gap, so an intermittent dropout (tree cover, a tunnel,
///    satellite reacquisition on a long ultra) doesn't silently erase the climb
///    that spans the missing samples.
/// 2. A change only counts once it clears [minDeltaM], which defaults to
///    [kElevationGainMinDeltaM]. A recorded run passes the band the app's
///    `runAltitude` picks for its altitude source; an imported route file
///    takes the default.
///
/// Callers must pass the raw track. Running this over an RDP-simplified
/// polyline reads a hill as flat: RDP measures perpendicular distance in 2-D
/// only, so a straight road over a summit collapses to its endpoints and the
/// climb between them disappears.
double computeElevationGain(
  List<Waypoint> track, {
  double minDeltaM = kElevationGainMinDeltaM,
}) {
  final acc = ElevationGainAccumulator(minDeltaM: minDeltaM);
  acc.addAll(track);
  return acc.gainMetres;
}

/// Streaming form of [computeElevationGain] — the same gate and dropout-carry,
/// fed one waypoint at a time. The live recording screen sees the track grow
/// every GPS tick and cannot re-scan the whole thing per tick on a multi-hour
/// run, so it holds an accumulator and appends the tail. [computeElevationGain]
/// is this class run to completion, which is what keeps the live counter and
/// the finished-run figure from ever disagreeing.
class ElevationGainAccumulator {
  ElevationGainAccumulator({this.minDeltaM = kElevationGainMinDeltaM});

  final double minDeltaM;
  double _gain = 0;
  double? _ref;

  double get gainMetres => _gain;

  void reset() {
    _gain = 0;
    _ref = null;
  }

  void add(Waypoint point) => addElevation(point.elevationMetres);

  /// [add] for a bare altitude, so a caller choosing between two series per
  /// point need not build a [Waypoint] for each.
  void addElevation(double? ele) {
    if (ele == null) return;
    final ref = _ref;
    if (ref == null) {
      _ref = ele;
      return;
    }
    final delta = ele - ref;
    if (delta >= minDeltaM) {
      _gain += delta;
      _ref = ele;
    } else if (delta <= -minDeltaM) {
      // A real descent — move the reference down so the next climb is measured
      // from the valley, not from the previous summit.
      _ref = ele;
    }
  }

  void addAll(Iterable<Waypoint> points) {
    for (final p in points) {
      add(p);
    }
  }
}
