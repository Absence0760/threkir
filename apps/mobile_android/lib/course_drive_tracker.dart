import 'dart:math' as math;

import 'course_drive.dart';

/// Where a drive is on the course (docs/features/course_drive.md, gotchas 1,
/// 3 and 9). Deliberately not `RunRecorder`: its distance estimator rejects
/// anything over 10 m/s, and a drive must never produce a run, a PR, a
/// live-tracking session or any credit. This holds a distance along the
/// served line and nothing else — no track, no writes.
enum DriveTrackState { approaching, onCourse, offCourse, finished, abandoned }

class DriveFix {
  const DriveFix({
    required this.state,
    required this.alongM,
    required this.offsetM,
    required this.speedMps,
    this.joined = false,
  });
  final DriveTrackState state;

  /// Distance along the served line; meaningless while [state] is
  /// [DriveTrackState.approaching].
  final double alongM;
  final double offsetM;

  /// Speed along the course, smoothed — the GPS speed field is not used,
  /// because some devices leave it at zero.
  final double speedMps;

  /// True on the one update that first put the drive on the course.
  final bool joined;
}

class CourseDriveTracker {
  CourseDriveTracker(this.line) : _cum = cumulativeM(line);

  final List<DrivePoint> line;
  final List<double> _cum;

  /// A fix this close to the course joins it.
  static const double joinRadiusM = 300;

  /// Within this of the course window is on course.
  static const double onCourseM = 150;

  /// How far behind the last position a fix may still snap.
  static const double backWindowM = 50;

  /// The forward window is the larger of this and [maxSpeedMps] times the
  /// time since the last on-course fix.
  static const double minForwardM = 300;
  static const double maxSpeedMps = 60;

  /// This close to the end of the served line is the finish.
  static const double finishM = 75;

  /// This long off the course in a row ends the drive.
  static const Duration abandonAfter = Duration(minutes: 10);

  double? _alongM;
  DateTime? _lastOnCourseAt;
  DateTime? _offSince;
  double _speedMps = 0;
  DriveTrackState _state = DriveTrackState.approaching;

  double get totalM => _cum.isEmpty ? 0 : _cum.last;
  DriveTrackState get state => _state;

  DriveFix update(double lat, double lng, DateTime at) {
    final p = (lat: lat, lng: lng);
    if (_state == DriveTrackState.finished ||
        _state == DriveTrackState.abandoned) {
      return DriveFix(
        state: _state,
        alongM: _alongM ?? 0,
        offsetM: 0,
        speedMps: _speedMps,
      );
    }
    final along = _alongM;
    if (along == null) {
      final snap = _joinSnap(p);
      if (snap == null || snap.offsetM > joinRadiusM) {
        return DriveFix(
          state: DriveTrackState.approaching,
          alongM: 0,
          offsetM: snap?.offsetM ?? double.infinity,
          speedMps: 0,
        );
      }
      _alongM = snap.alongM;
      _lastOnCourseAt = at;
      _state = _finishedAt(snap.alongM)
          ? DriveTrackState.finished
          : DriveTrackState.onCourse;
      return DriveFix(
        state: _state,
        alongM: snap.alongM,
        offsetM: snap.offsetM,
        speedMps: 0,
        joined: true,
      );
    }

    final last = _lastOnCourseAt ?? at;
    final dtS = math.max(0, at.difference(last).inMilliseconds) / 1000;
    final forward = math.max(minForwardM, maxSpeedMps * dtS);
    final snap = snapWithinAlong(
      p,
      line,
      _cum,
      math.max(0, along - backWindowM),
      along + forward,
    );
    if (snap != null && snap.offsetM <= onCourseM) {
      final next = math.max(along, snap.alongM);
      if (dtS > 0) {
        _speedMps = 0.5 * _speedMps + 0.5 * ((next - along) / dtS);
      }
      _alongM = next;
      _lastOnCourseAt = at;
      _offSince = null;
      _state = _finishedAt(next)
          ? DriveTrackState.finished
          : DriveTrackState.onCourse;
      return DriveFix(
        state: _state,
        alongM: next,
        offsetM: snap.offsetM,
        speedMps: _speedMps,
      );
    }

    final since = _offSince ??= at;
    _state = at.difference(since) >= abandonAfter
        ? DriveTrackState.abandoned
        : DriveTrackState.offCourse;
    return DriveFix(
      state: _state,
      alongM: along,
      offsetM: snap?.offsetM ?? double.infinity,
      speedMps: _speedMps,
    );
  }

  bool _finishedAt(double alongM) => alongM >= totalM - finishM;

  /// The join point: the earliest pass within [joinTieM] of the nearest one,
  /// so a loop whose start and finish share a spot joins at the start, not
  /// at the finish.
  static const double joinTieM = 50;
  static const double _joinWindowM = 500;

  LineSnap? _joinSnap(({double lat, double lng}) p) {
    final nearest = snapWithinAlong(p, line, _cum, 0, totalM);
    if (nearest == null) return null;
    final limit = nearest.offsetM + joinTieM;
    for (var from = 0.0; from < totalM; from += _joinWindowM) {
      final s = snapWithinAlong(p, line, _cum, from, from + _joinWindowM);
      if (s != null && s.offsetM <= limit) return s;
    }
    return nearest;
  }
}
