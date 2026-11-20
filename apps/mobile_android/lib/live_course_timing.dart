/// Live park course timing during a recording (#1446): "Timing started" when
/// the runner leaves the start box going forward, "Finished!" with the course
/// time when the board would time the run. Pure: no clock, no I/O, no
/// Flutter.
///
/// The finish is never decided here. When a fix enters the finish box, the
/// recording so far is scored by [computeGlobalSegmentEffort], the matcher the
/// server's segment-match function bundles (the `segments` pair), so the
/// phone says "Finished!" only for a run the board would time: checkpoints in
/// order, the 25% length guard, the box slack and the gap rule all come from
/// that one function. The start is the matcher's own start rule (the start
/// box's exit edge crossed forward, or a first fix within the slack past it),
/// read with the same [GateCrossingDetector].
library;

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';

import 'course_gates.dart'
    show GateBoxLayout, GateTimingEdges, bearingDelta, gateTimingEdges;
import 'gate_crossing.dart';
import 'park_courses.dart' show parseCourseCheckpoints;
import 'run_stats.dart' show haversineMetres;
import 'segments.dart';

/// The geometry a park course is timed by, read as the server reads it: the
/// segment's polyline, length and lines, and the course's checkpoints. Null
/// when the course has no usable pair of lines (it is then matched by the
/// circles, which this does not follow live) or checkpoints the parser
/// refuses (the server does not score it at all).
GlobalSegmentGeometry? liveCourseGeometry(ParkCourseListing listing) {
  final segment = listing.segment;
  final checkpoints = parseCourseCheckpoints(listing.course.checkpoints);
  if (checkpoints == null) return null;
  Gate? gate(double? lat, double? lng, double? bearing, double? halfWidth) {
    if (lat == null || lng == null || bearing == null || halfWidth == null) {
      return null;
    }
    final g =
        Gate(lat: lat, lng: lng, bearingDeg: bearing, halfWidthM: halfWidth);
    return gateUsable(g) ? g : null;
  }

  final start = gate(segment.startGateLat, segment.startGateLng,
      segment.startGateBearingDeg, segment.startGateHalfWidthM);
  final end = gate(segment.endGateLat, segment.endGateLng,
      segment.endGateBearingDeg, segment.endGateHalfWidthM);
  final points = ApiClient.globalSegmentGeometry(segment);
  if (start == null || end == null || points.length < 2) return null;
  if (!(segment.distanceM > 0)) return null;
  return GlobalSegmentGeometry(
    points: points,
    distanceM: segment.distanceM,
    checkpoints: [
      for (final c in checkpoints) Waypoint(lat: c.lat, lng: c.lng),
    ],
    startGate: start,
    endGate: end,
  );
}

enum LiveCoursePhase {
  /// Not yet out of the start box going forward.
  waiting,

  /// Out of the start box; the board has not timed the run yet.
  timing,

  /// The board would time the run; [LiveCourseTracker.finishedSeconds] holds
  /// the course time.
  finished,
}

enum LiveCourseEventKind { started, finished }

class LiveCourseEvent {
  const LiveCourseEvent.started()
      : kind = LiveCourseEventKind.started,
        timeSeconds = null;
  const LiveCourseEvent.finished(double this.timeSeconds)
      : kind = LiveCourseEventKind.finished;

  final LiveCourseEventKind kind;

  /// The course time, for [LiveCourseEventKind.finished].
  final double? timeSeconds;
}

/// Fed the recorder's line ([offer]) as it grows. One start and one finish
/// per recording: after the finish it says nothing more, so a runner going
/// round a loop again is not told a slower lap's time over the one that
/// already counts.
class LiveCourseTracker {
  LiveCourseTracker(GlobalSegmentGeometry segment)
      : this._(segment, gateTimingEdges(segment.startGate!, segment.endGate!));

  LiveCourseTracker._(this.segment, this._edges)
      // An out-and-back finishes back through the start box's exit edge, so
      // re-entering there is the finish, not a restart.
      : _finishesThroughStartExit = _edges.layout == GateBoxLayout.shared &&
            bearingDelta(segment.startGate!.bearingDeg,
                    segment.endGate!.bearingDeg) >
                90 {
    _startDetector = GateCrossingDetector(_edges.startExit);
    _entryDetector = GateCrossingDetector(_edges.finishEntry);
  }

  /// A tracker for [segment], or null when it has no usable pair of lines.
  static LiveCourseTracker? forSegment(GlobalSegmentGeometry segment) {
    final s = segment.startGate;
    final e = segment.endGate;
    if (s == null || e == null || !gateUsable(s) || !gateUsable(e)) {
      return null;
    }
    if (segment.points.length < 2 || !(segment.distanceM > 0)) return null;
    return LiveCourseTracker(segment);
  }

  final GlobalSegmentGeometry segment;
  final GateTimingEdges _edges;
  final bool _finishesThroughStartExit;
  late GateCrossingDetector _startDetector;
  late GateCrossingDetector _entryDetector;

  LiveCoursePhase _phase = LiveCoursePhase.waiting;
  LiveCoursePhase get phase => _phase;

  double? _finishedSeconds;
  double? get finishedSeconds => _finishedSeconds;

  int _seen = 0;
  int _accepted = 0;
  double _prevMs = double.negativeInfinity;
  double _coveredM = 0;
  Waypoint? _prevFix;
  bool _wasInFinish = false;

  /// Reads the fixes [line] gained since the last call. [line] is the
  /// recorder's line ([RunSnapshot.track]), which only grows; a shorter one
  /// is a new recording and starts over. Returns what changed, oldest first.
  List<LiveCourseEvent> offer(List<Waypoint> line) {
    if (line.length < _seen) _reset();
    final events = <LiveCourseEvent>[];
    for (var i = _seen; i < line.length; i++) {
      if (_phase == LiveCoursePhase.finished) break;
      final event = _offerFix(line, i);
      if (event != null) events.add(event);
    }
    _seen = line.length;
    return events;
  }

  /// Whether stopping now leaves a course started and not timed: out of the
  /// start box, and the recording so far is not one the board would time
  /// (a recording that ends in the finish box counts, by the matcher's tail
  /// rule).
  bool stopsShort(List<Waypoint> line) {
    if (_phase != LiveCoursePhase.timing) return false;
    return computeGlobalSegmentEffort(line, segment) == null;
  }

  void _reset() {
    _startDetector = GateCrossingDetector(_edges.startExit);
    _entryDetector = GateCrossingDetector(_edges.finishEntry);
    _phase = LiveCoursePhase.waiting;
    _finishedSeconds = null;
    _seen = 0;
    _accepted = 0;
    _prevMs = double.negativeInfinity;
    _coveredM = 0;
    _prevFix = null;
    _wasInFinish = false;
  }

  LiveCourseEvent? _offerFix(List<Waypoint> line, int i) {
    final p = line[i];
    final ts = p.timestamp;
    if (p.offTrack || ts == null) return null;
    final tMs = ts.millisecondsSinceEpoch.toDouble();
    final lat = p.lineLat;
    final lng = p.lineLng;
    if (!lat.isFinite || !lng.isFinite || tMs <= _prevMs) return null;
    final prev = _prevFix;
    if (prev != null) {
      _coveredM += haversineMetres(prev.lineLat, prev.lineLng, lat, lng);
    }
    _prevFix = p;
    _prevMs = tMs;
    final first = _accepted == 0;
    _accepted++;

    final fix = GateFix(lat: lat, lng: lng, tMs: tMs, coveredM: _coveredM);
    final startCrossing = _startDetector.offer(fix);
    final entryCrossing = _entryDetector.offer(fix);

    final entry = _edges.finishEntry;
    final inFinish = gateProjection(entry, lat, lng);
    final nowInFinish = inFinish.s >= 0 &&
        inFinish.s <= _edges.depthM &&
        inFinish.u.abs() <= entry.halfWidthM;
    final enteredFinish = (nowInFinish && !_wasInFinish) ||
        entryCrossing?.direction == GateDirection.forward;
    _wasInFinish = nowInFinish;

    if (_phase == LiveCoursePhase.timing && enteredFinish) {
      final effort = computeGlobalSegmentEffort(line.sublist(0, i + 1), segment);
      if (effort != null) {
        _phase = LiveCoursePhase.finished;
        _finishedSeconds = effort.timeSeconds;
        return LiveCourseEvent.finished(effort.timeSeconds);
      }
    }

    if (startCrossing != null) {
      if (startCrossing.direction == GateDirection.forward) {
        if (_phase == LiveCoursePhase.waiting) {
          _phase = LiveCoursePhase.timing;
          return const LiveCourseEvent.started();
        }
      } else if (_phase == LiveCoursePhase.timing &&
          !_finishesThroughStartExit) {
        // Back into the start box: the start the board reads is the next
        // forward exit, so that is when timing is said to start.
        _phase = LiveCoursePhase.waiting;
      }
    } else if (first && _phase == LiveCoursePhase.waiting) {
      final atStart = gateProjection(_edges.startExit, lat, lng);
      if (atStart.s >= 0 &&
          atStart.s <= kGlobalSegmentBoxSlackM &&
          atStart.u.abs() <= _edges.startExit.halfWidthM) {
        _phase = LiveCoursePhase.timing;
        return const LiveCourseEvent.started();
      }
    }
    return null;
  }
}
