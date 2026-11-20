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
///
/// While timing, the tracker also walks the course's checkpoints by the
/// matcher's own rule ([advanceCheckpointWalk]) for the live map's ticks,
/// and measures the runner against the course line for the off-course
/// warning, which names the next checkpoint. [LiveCourseDetector] finds a
/// course the runner starts without having picked it.
library;

import 'dart:math' as math;

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';

import 'course_gates.dart'
    show GateBoxLayout, GateTimingEdges, bearingDelta, gateTimingEdges;
import 'gate_crossing.dart';
import 'park_courses.dart' show parseCourseCheckpoints;
import 'route_snap.dart' show snapToPolyline;
import 'run_stats.dart' show haversineMetres;
import 'segments.dart';

/// Further than this from the course line, a runner can pass the next
/// checkpoint outside its circle and the board will not time the run, so the
/// run screen says "You're off the course" (#1446). The matcher's own
/// checkpoint tolerance.
const double kLiveCourseOffCourseM = kGlobalSegmentToleranceM;

/// Back within this of the line, the warning clears. Ten metres inside the
/// tolerance, so GPS jitter at the edge does not flick the warning on and off
/// and re-say it.
const double kLiveCourseBackOnCourseM = kGlobalSegmentToleranceM - 10;

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

enum LiveCourseEventKind {
  started,
  finished,

  /// Timing, and further than [kLiveCourseOffCourseM] from the course line.
  offCourse,

  /// Back within [kLiveCourseBackOnCourseM] of the line after [offCourse].
  backOnCourse,
}

class LiveCourseEvent {
  const LiveCourseEvent.started()
      : kind = LiveCourseEventKind.started,
        timeSeconds = null;
  const LiveCourseEvent.finished(double this.timeSeconds)
      : kind = LiveCourseEventKind.finished;
  const LiveCourseEvent.offCourse()
      : kind = LiveCourseEventKind.offCourse,
        timeSeconds = null;
  const LiveCourseEvent.backOnCourse()
      : kind = LiveCourseEventKind.backOnCourse,
        timeSeconds = null;

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
    _courseCoords = [
      for (final p in segment.points) [p.lng, p.lat],
    ];
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
  late final List<List<double>> _courseCoords;

  LiveCoursePhase _phase = LiveCoursePhase.waiting;
  LiveCoursePhase get phase => _phase;

  double? _finishedSeconds;
  double? get finishedSeconds => _finishedSeconds;

  int _seen = 0;
  double _prevMs = double.negativeInfinity;
  double _coveredM = 0;
  Waypoint? _prevFix;
  bool _wasInFinish = false;

  /// The fixes read so far, in order: the line the checkpoint walk reads.
  final List<Waypoint> _fixes = [];

  int _checkpointsPassed = 0;
  int _walkFrom = 0;

  /// How many of the course's checkpoints this attempt has passed, in order,
  /// by the matcher's own rule ([advanceCheckpointWalk]). Zero until timing
  /// starts; all of them once finished.
  int get checkpointsPassed => _phase == LiveCoursePhase.finished
      ? segment.checkpoints.length
      : _checkpointsPassed;

  /// The checkpoint to head for, 1-based; null when every one is passed.
  int? get nextCheckpoint => checkpointsPassed < segment.checkpoints.length
      ? checkpointsPassed + 1
      : null;

  double? _offsetM;

  /// How far the latest fix is from the course line, while timing; null
  /// otherwise.
  double? get offsetFromLineM => _offsetM;

  bool _offCourse = false;

  /// Timing and off the course line: the run screen's warning.
  bool get offCourse => _offCourse;

  /// Reads the fixes [line] gained since the last call. [line] is the
  /// recorder's line ([RunSnapshot.track]), which only grows; a shorter one
  /// is a new recording and starts over. Returns what changed, oldest first.
  List<LiveCourseEvent> offer(List<Waypoint> line) {
    if (line.length < _seen) _reset();
    final events = <LiveCourseEvent>[];
    for (var i = _seen; i < line.length; i++) {
      if (_phase == LiveCoursePhase.finished) break;
      _offerFix(line, i, events);
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
    _prevMs = double.negativeInfinity;
    _coveredM = 0;
    _prevFix = null;
    _wasInFinish = false;
    _fixes.clear();
    _clearAttempt();
  }

  void _clearAttempt() {
    _checkpointsPassed = 0;
    _walkFrom = 0;
    _offsetM = null;
    _offCourse = false;
  }

  /// Walks the checkpoints over the fixes since the last walk and measures
  /// the latest one against the course line, while timing.
  LiveCourseEvent? _follow(double lat, double lng) {
    if (_phase != LiveCoursePhase.timing) return null;
    final walk = advanceCheckpointWalk(_fixes, segment.checkpoints,
        passed: _checkpointsPassed,
        fromIdx: _walkFrom,
        toIdx: _fixes.length - 1,
        toleranceM: kGlobalSegmentToleranceM);
    _checkpointsPassed = walk.passed;
    _walkFrom = walk.nextIdx;
    final offset = snapToPolyline((lng: lng, lat: lat), _courseCoords)?.offsetM;
    _offsetM = offset;
    if (offset == null) return null;
    if (!_offCourse && offset > kLiveCourseOffCourseM) {
      _offCourse = true;
      return const LiveCourseEvent.offCourse();
    }
    if (_offCourse && offset < kLiveCourseBackOnCourseM) {
      _offCourse = false;
      return const LiveCourseEvent.backOnCourse();
    }
    return null;
  }

  void _offerFix(List<Waypoint> line, int i, List<LiveCourseEvent> events) {
    final before = _fixes.length;
    final event = _decide(line, i);
    if (event != null) events.add(event);
    if (_fixes.length == before || _phase != LiveCoursePhase.timing) return;
    final follow = _follow(line[i].lineLat, line[i].lineLng);
    if (follow != null) events.add(follow);
  }

  LiveCourseEvent? _decide(List<Waypoint> line, int i) {
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
    final first = _fixes.isEmpty;
    _fixes.add(p);

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
        _clearAttempt();
        return LiveCourseEvent.finished(effort.timeSeconds);
      }
    }

    if (startCrossing != null) {
      if (startCrossing.direction == GateDirection.forward) {
        if (_phase == LiveCoursePhase.waiting) {
          _startTiming(_fixes.length - 2);
          return const LiveCourseEvent.started();
        }
      } else if (_phase == LiveCoursePhase.timing &&
          !_finishesThroughStartExit) {
        // Back into the start box: the start the board reads is the next
        // forward exit, so that is when timing is said to start.
        _phase = LiveCoursePhase.waiting;
        _clearAttempt();
      }
    } else if (first && _phase == LiveCoursePhase.waiting) {
      final atStart = gateProjection(_edges.startExit, lat, lng);
      if (atStart.s >= 0 &&
          atStart.s <= kGlobalSegmentBoxSlackM &&
          atStart.u.abs() <= _edges.startExit.halfWidthM) {
        _startTiming(0);
        return const LiveCourseEvent.started();
      }
    }
    return null;
  }

  /// Checkpoints count from the fix before the start crossing, as the
  /// matcher counts them.
  void _startTiming(int fromIdx) {
    _phase = LiveCoursePhase.timing;
    _clearAttempt();
    _walkFrom = fromIdx < 0 ? 0 : fromIdx;
  }
}

/// How near the runner a course's start line must be, when the recording
/// starts (or at the second look), for the course to be a candidate.
const double kLiveCourseDetectRadiusM = 400;

/// How far into a recording without a found course the run screen looks once
/// more.
const double kLiveCourseSecondLookM = 200;

/// The box the nearby-course read asks for: [kLiveCourseDetectRadiusM]
/// around ([lat], [lng]). Only this box leaves the phone.
({double minLat, double minLng, double maxLat, double maxLng}) courseSearchBox(
    double lat, double lng) {
  const metresPerDeg = 111195.0;
  final dLat = kLiveCourseDetectRadiusM / metresPerDeg;
  final cosLat = math.cos(lat * math.pi / 180).abs();
  final dLng = math.min(
      180.0, kLiveCourseDetectRadiusM / (metresPerDeg * math.max(cosLat, 1e-6)));
  return (
    minLat: math.max(-90.0, lat - dLat),
    minLng: math.max(-180.0, lng - dLng),
    maxLat: math.min(90.0, lat + dLat),
    maxLng: math.min(180.0, lng + dLng),
  );
}

/// A park course near the runner that they did not pick (#1446): its name
/// and the geometry it is timed by.
class LiveCourseCandidate {
  const LiveCourseCandidate({required this.name, required this.segment});

  final String name;
  final GlobalSegmentGeometry segment;
}

/// The courses in [listings] that can be followed live and whose start line
/// is within [kLiveCourseDetectRadiusM] of ([lat], [lng]).
List<LiveCourseCandidate> nearbyCourseCandidates(
  List<ParkCourseListing> listings,
  double lat,
  double lng,
) {
  final out = <LiveCourseCandidate>[];
  for (final listing in listings) {
    if (listing.course.status == 'closed') continue;
    final geometry = liveCourseGeometry(listing);
    final start = geometry?.startGate;
    if (geometry == null || start == null) continue;
    if (haversineMetres(lat, lng, start.lat, start.lng) >
        kLiveCourseDetectRadiusM) {
      continue;
    }
    out.add(LiveCourseCandidate(name: listing.segment.name, segment: geometry));
  }
  return out;
}

/// A course the runner started without picking it, with what to say now.
class LiveCourseAdoption {
  const LiveCourseAdoption({
    required this.candidate,
    required this.tracker,
    required this.events,
  });

  final LiveCourseCandidate candidate;

  /// Already fed the line so far; the run screen keeps feeding it.
  final LiveCourseTracker tracker;

  /// "Timing started", and "Finished!" if the board already times the line.
  final List<LiveCourseEvent> events;
}

/// Follows every candidate course at once, silently, until the runner leaves
/// one's start box going forward ([offer] then adopts it). When several
/// start on the same fix (courses sharing a start), it waits until the line
/// leaves all but one of them, or one finishes.
class LiveCourseDetector {
  LiveCourseDetector(List<LiveCourseCandidate> candidates)
      : _entries = [
          for (final c in candidates)
            if (LiveCourseTracker.forSegment(c.segment) case final t?)
              (candidate: c, tracker: t),
        ];

  final List<({LiveCourseCandidate candidate, LiveCourseTracker tracker})>
      _entries;

  bool get isEmpty => _entries.isEmpty;

  LiveCourseAdoption? offer(List<Waypoint> line) {
    for (final e in _entries) {
      e.tracker.offer(line);
    }
    final going = [
      for (final e in _entries)
        if (e.tracker.phase != LiveCoursePhase.waiting) e,
    ];
    if (going.isEmpty) return null;
    final finished = [
      for (final e in going)
        if (e.tracker.phase == LiveCoursePhase.finished) e,
    ];
    final onLine = [
      for (final e in going)
        if ((e.tracker.offsetFromLineM ?? double.infinity) <=
            kLiveCourseOffCourseM)
          e,
    ];
    final pick = going.length == 1
        ? going.single
        : finished.isNotEmpty
            ? finished.first
            : onLine.length == 1
                ? onLine.single
                : null;
    if (pick == null) return null;
    final t = pick.tracker;
    return LiveCourseAdoption(
      candidate: pick.candidate,
      tracker: t,
      events: [
        const LiveCourseEvent.started(),
        if (t.finishedSeconds case final s?) LiveCourseEvent.finished(s),
      ],
    );
  }
}
