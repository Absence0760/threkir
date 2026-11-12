/// Replay regression for timing lines (#1304 § 6, step 2): run a stored
/// track through `race_finish` v1 (the 30 m circle, no lines) and v2 (the
/// start and finish lines) and say where the old one finished a race the new
/// one does not.
///
/// Test support only, so none of it ships. `race_finish_replay_test.dart`
/// drives it over synthetic tracks on every run, and over the owner's own
/// stored tracks only when `RACE_REPLAY_DIR` names a local directory of them
/// (docs/testing/manual_testing.md § Timing-line calibration). Real tracks
/// are never committed: this repository is public.
library;

import 'dart:math' as math;

import 'package:core_models/core_models.dart' show Waypoint;

import '../lib/gate_crossing.dart';
import '../lib/race_finish.dart';

/// The fixes a stored track stands for, as the live feed offered them: the
/// on-track points only, each at its line position (the smoothed one where
/// the track carries it, as a re-time reads it), with a distinct, later
/// instant than the one before, and the distance covered by then — the
/// track's own `distM` where present, else the running sum of the line.
List<RaceFix> replayFeed(List<Waypoint> track) {
  final out = <RaceFix>[];
  double sum = 0;
  Waypoint? prev;
  for (final w in track) {
    if (w.offTrack) continue;
    final at = w.timestamp;
    if (at == null) continue;
    final lat = w.lineLat;
    final lng = w.lineLng;
    if (!lat.isFinite || !lng.isFinite) continue;
    if (out.isNotEmpty && !at.isAfter(out.last.at)) continue;
    final p = prev;
    if (p != null) sum += raceDistanceM(p.lineLat, p.lineLng, lat, lng);
    prev = w;
    final covered = w.cumulativeDistanceMetres;
    out.add(RaceFix(
      lat: lat,
      lng: lng,
      at: at,
      coveredM: covered != null && covered.isFinite ? covered : sum,
    ));
  }
  return out;
}

/// A race course to replay a track over: what `race_finish` is built from.
class ReplayCourse {
  const ReplayCourse({
    required this.distanceM,
    required this.finishLat,
    required this.finishLng,
    this.startGate,
    this.finishGate,
    this.finishLineSelfCross = false,
    this.lapCount,
  });

  final double distanceM;
  final double finishLat;
  final double finishLng;
  final Gate? startGate;
  final Gate? finishGate;
  final bool finishLineSelfCross;
  final int? lapCount;
}

/// A course laid over the track itself, for a run that raced no course: a
/// start line [startAtM] into the run and a finish line [finishBeforeEndM]
/// before its end, each across the direction of travel there, with the v1
/// finish point at the finish line's centre. The runner then crosses both
/// lines and stops past the finish, as in a race. Null for a track too
/// short to carry both.
ReplayCourse? synthesizeCourse(
  List<RaceFix> feed, {
  double startAtM = 20,
  double finishBeforeEndM = 50,
  double halfWidthM = kGateHalfWidthRaceM,
}) {
  if (feed.length < 4) return null;
  final first = feed.first.coveredM;
  final last = feed.last.coveredM;
  final startM = first + startAtM;
  final finishM = last - finishBeforeEndM;
  if (finishM - startM < 200) return null;
  final start = _lineAt(feed, startM, halfWidthM);
  final finish = _lineAt(feed, finishM, halfWidthM);
  if (start == null || finish == null) return null;
  return ReplayCourse(
    distanceM: finishM - startM,
    finishLat: finish.lat,
    finishLng: finish.lng,
    startGate: start,
    finishGate: finish,
  );
}

Gate? _lineAt(List<RaceFix> feed, double coveredM, double halfWidthM) {
  final at = _pointAt(feed, coveredM);
  final before = _pointAt(feed, coveredM - 15);
  final after = _pointAt(feed, coveredM + 15);
  if (at == null || before == null || after == null) return null;
  final bearing = _bearingDeg(before.lat, before.lng, after.lat, after.lng);
  if (!bearing.isFinite) return null;
  return Gate(
      lat: at.lat, lng: at.lng, bearingDeg: bearing, halfWidthM: halfWidthM);
}

({double lat, double lng})? _pointAt(List<RaceFix> feed, double coveredM) {
  for (var i = 1; i < feed.length; i++) {
    final a = feed[i - 1];
    final b = feed[i];
    if (b.coveredM < coveredM) continue;
    final span = b.coveredM - a.coveredM;
    final f = span <= 0 ? 0.0 : ((coveredM - a.coveredM) / span).clamp(0, 1);
    return (lat: a.lat + f * (b.lat - a.lat), lng: a.lng + f * (b.lng - a.lng));
  }
  return null;
}

double _bearingDeg(double lat1, double lng1, double lat2, double lng2) {
  double rad(double d) => d * math.pi / 180;
  final dl = rad(lng2 - lng1);
  final y = math.sin(dl) * math.cos(rad(lat2));
  final x = math.cos(rad(lat1)) * math.sin(rad(lat2)) -
      math.sin(rad(lat1)) * math.cos(rad(lat2)) * math.cos(dl);
  if (x == 0 && y == 0) return double.nan;
  return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
}

class ReplayVerdict {
  const ReplayVerdict({required this.v1, required this.v2});

  /// The circle's finish: the closest approach, or the Stop inside it.
  final RaceFinish? v1;

  /// The lines' finish, or the circle on Stop when there is no finish line.
  final RaceFinish? v2;

  /// The old detector finished this race and the new one does not.
  bool get regression => v1 != null && v2 == null;

  /// v2's finish minus v1's, seconds; null unless both finished.
  double? get deltaS {
    final a = v1;
    final b = v2;
    if (a == null || b == null) return null;
    return b.at.difference(a.at).inMicroseconds / 1e6;
  }
}

/// Both detectors over [feed], the recording stopped at its last fix. A gun
/// race's GO is [goAt], else the first fix (the Start press at GO); a
/// self-timed race has none. A course whose finish line the route crosses
/// before its end gets no v2 auto-finish, as on the phone.
ReplayVerdict replayRace(
  List<RaceFix> feed,
  ReplayCourse course, {
  DateTime? goAt,
  bool selfTimed = false,
}) {
  RaceFinish? run(RaceFinishDetector d) {
    for (final fix in feed) {
      final f = d.offer(fix);
      if (f != null) return f;
    }
    return d.settle();
  }

  final go = goAt ?? (feed.isEmpty ? null : feed.first.at);
  // v1 holds nothing before GO, as the phone shows it fixes from GO on.
  final v1Feed = selfTimed || go == null
      ? feed
      : [for (final f in feed) if (!f.at.isBefore(go)) f];
  RaceFinish? runV1() {
    final d = RaceFinishDetector(
      finishLat: course.finishLat,
      finishLng: course.finishLng,
      courseDistanceM: course.distanceM,
    );
    for (final fix in v1Feed) {
      final f = d.offer(fix);
      if (f != null) return f;
    }
    return d.settle();
  }

  final v1 = runV1();
  final v2 = course.finishLineSelfCross
      ? null
      : run(RaceFinishDetector(
          finishLat: course.finishLat,
          finishLng: course.finishLng,
          courseDistanceM: course.distanceM,
          startGate: course.startGate,
          finishGate: course.finishGate,
          mode: selfTimed ? RaceStartMode.selfTimed : RaceStartMode.gun,
          goAt: selfTimed ? null : go,
          lapCount: course.lapCount,
        ));
  return ReplayVerdict(v1: v1, v2: v2);
}

/// One replay case read from `cases.json`: the columns of the owner's own
/// `event_results` joined to the race's frozen course (`race_session_courses`)
/// and session, as the documented query writes them.
class ReplayCase {
  const ReplayCase({
    required this.runId,
    required this.course,
    this.goAt,
    this.selfTimed = false,
  });

  final String runId;
  final ReplayCourse course;
  final DateTime? goAt;
  final bool selfTimed;

  static ReplayCase? fromJson(Object? j) {
    if (j is! Map) return null;
    final runId = j['run_id'];
    final distance = _num(j['distance_m']);
    final fLat = _num(j['finish_lat']) ?? _num(j['finish_gate_lat']);
    final fLng = _num(j['finish_lng']) ?? _num(j['finish_gate_lng']);
    if (runId is! String || distance == null || fLat == null || fLng == null) {
      return null;
    }
    Gate? gate(String p) {
      final lat = _num(j['${p}_gate_lat']);
      final lng = _num(j['${p}_gate_lng']);
      final b = _num(j['${p}_gate_bearing_deg']);
      final w = _num(j['${p}_gate_half_width_m']);
      if (lat == null || lng == null || b == null || w == null) return null;
      return Gate(lat: lat, lng: lng, bearingDeg: b, halfWidthM: w);
    }

    final go = j['started_at'];
    return ReplayCase(
      runId: runId,
      course: ReplayCourse(
        distanceM: distance,
        finishLat: fLat,
        finishLng: fLng,
        startGate: gate('start'),
        finishGate: gate('finish'),
        finishLineSelfCross: j['finish_line_self_cross'] == true,
        lapCount: j['finish_lap_count'] is int ? j['finish_lap_count'] as int : null,
      ),
      goAt: go is String ? DateTime.tryParse(go) : null,
      selfTimed: j['start_mode'] == 'self_timed',
    );
  }
}

double? _num(Object? v) {
  if (v is! num) return null;
  final d = v.toDouble();
  return d.isFinite ? d : null;
}

/// One line per case: no coordinate, only what each detector decided.
String replayReportCsv(
    List<({String id, bool synthetic, ReplayVerdict verdict})> rows) {
  final out = StringBuffer(
      'case,course,v1_finished,v2_finished,v2_detection,delta_s,regression\n');
  for (final r in rows) {
    final v = r.verdict;
    out.writeln([
      r.id,
      r.synthetic ? 'synthetic' : 'race',
      v.v1 != null ? 1 : 0,
      v.v2 != null ? 1 : 0,
      v.v2?.detection.wire ?? '',
      v.deltaS?.toStringAsFixed(3) ?? '',
      v.regression ? 1 : 0,
    ].join(','));
  }
  return out.toString();
}
