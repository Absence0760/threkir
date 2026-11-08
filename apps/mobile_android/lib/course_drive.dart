import 'dart:math' as math;

import 'geo.dart' show lonDeltaDeg, wrapLonDeg;
import 'route_markers.dart' show CutoffParts, parseAidServices, parseCutoff;
import 'run_stats.dart' show haversineMetres;

/// Drive this course (docs/features/course_drive.md, decisions § 2380): the
/// pure core behind handing a course to a Maps app and speaking course notes
/// while someone drives it.
///
/// Four pieces, all distances along the line the caller was SERVED (the
/// privacy-clipped line for a non-owner, never the raw one): [buildDriveNotes]
/// places course markers on that line; [driveLeadM] / [DriveCueAnnouncer]
/// decide when to speak each note; [planDriveLegs] and the `*Url` builders cut
/// the course into legs a Maps app will take; [undrivableStretches] finds where
/// a road router's line leaves the course.
///
/// Twin of web's `routes/course_drive.ts` — keep the constants, algorithms,
/// edge cases and test count in lockstep.

class DrivePoint {
  const DrivePoint(this.lat, this.lng, {this.ele});
  final double lat;
  final double lng;
  final double? ele;
}

/// A marker farther than this from the served line gets no note.
const double kDriveNoteMaxOffsetM = 150;

/// How far ahead a note is spoken, in seconds at the current speed.
const double kDriveLeadS = 15;
const double kDriveLeadMinM = 150;
const double kDriveLeadMaxM = 1000;

/// The "you're at it" window: at least this far, or [kDriveAtS] seconds.
const double kDriveAtMinM = 30;
const double kDriveAtS = 3;

/// A note passed by less than this with nothing said is still reported.
const double kDriveMissedReportM = 400;

/// Target spacing between the stops a Maps leg is pinned to.
const double kDriveStopSpacingM = 1500;

/// A single-destination app gets one leg per this many metres.
const double kDriveSingleStopSpacingM = 3000;

/// A gap between two served points wider than this is never driven across.
const double kDriveMaxJoinM = 2000;

/// A course point farther than this from the router's line is undrivable.
const double kDriveUndrivableToleranceM = 75;

/// Shorter undrivable runs than this are router noise, not a stretch.
const double kDriveUndrivableMinM = 200;

/// How densely the course is sampled for the undrivable check.
const double kDriveUndrivableSampleM = 25;

/// A climb is reported once it gains this much over this distance at least.
const double kDriveClimbMinGainM = 10;
const double kDriveClimbMinLengthM = 100;

/// A drop this far below the high point ends the climb a marker opens.
const double kDriveClimbEndDropM = 10;
const double kDriveClimbMaxLengthM = 5000;

/// Stops each Maps app accepts in one link, counting every waypoint before
/// the destination. Google documents nine, and three in a mobile browser;
/// Apple Maps has no documented multi-stop parameter and Waze takes one
/// destination, so both are driven leg by leg.
enum MapsApp { google, apple, waze }

const int kMapsWaypointCapGoogle = 9;
const int kMapsWaypointCapGoogleMobileWeb = 3;
const int kMapsWaypointCapApple = 0;
const int kMapsWaypointCapWaze = 0;

const double _r = 6371000.0;
double _toRad(double d) => d * math.pi / 180;

/// Cumulative distance to each point of [line], metres.
List<double> cumulativeM(List<DrivePoint> line) {
  final out = <double>[];
  var acc = 0.0;
  for (var i = 0; i < line.length; i++) {
    if (i > 0) {
      acc += haversineMetres(
          line[i - 1].lat, line[i - 1].lng, line[i].lat, line[i].lng);
    }
    out.add(acc);
  }
  return out;
}

class LineSnap {
  const LineSnap({
    required this.lat,
    required this.lng,
    required this.alongM,
    required this.offsetM,
  });
  final double lat;
  final double lng;
  final double alongM;
  final double offsetM;
}

LineSnap _project(
  ({double lat, double lng}) p,
  List<DrivePoint> line,
  List<double> cum,
  int i,
  double tMin,
  double tMax,
) {
  final a = line[i];
  final b = line[i + 1];
  final cosLat = math.cos(_toRad(a.lat));
  final bx = _toRad(lonDeltaDeg(a.lng, b.lng)) * _r * cosLat;
  final by = _toRad(b.lat - a.lat) * _r;
  final px = _toRad(lonDeltaDeg(a.lng, p.lng)) * _r * cosLat;
  final py = _toRad(p.lat - a.lat) * _r;
  final lenSq = bx * bx + by * by;
  final raw = lenSq > 0 ? (px * bx + py * by) / lenSq : 0.0;
  final t = math.max(tMin, math.min(tMax, raw));
  final lng = wrapLonDeg(a.lng + lonDeltaDeg(a.lng, b.lng) * t);
  final lat = a.lat + (b.lat - a.lat) * t;
  return LineSnap(
    lat: lat,
    lng: lng,
    alongM: cum[i] + (cum[i + 1] - cum[i]) * t,
    offsetM: haversineMetres(p.lat, p.lng, lat, lng),
  );
}

/// The nearest point to [p] on the part of [line] between [minAlongM] and
/// [maxAlongM]. This is how a course that crosses or doubles back on itself
/// is followed: the caller asks only about the stretch around where the
/// driver already is, so the other pass of an out-and-back is never a
/// candidate. Null when the line has fewer than two points or the window
/// misses it.
LineSnap? snapWithinAlong(
  ({double lat, double lng}) p,
  List<DrivePoint> line,
  List<double> cum,
  double minAlongM,
  double maxAlongM,
) {
  if (line.length < 2 || !p.lat.isFinite || !p.lng.isFinite) return null;
  if (!(maxAlongM >= minAlongM)) return null;
  LineSnap? best;
  for (var i = 0; i < line.length - 1; i++) {
    final s = cum[i];
    final e = cum[i + 1];
    if (e < minAlongM || s > maxAlongM) continue;
    final len = e - s;
    final tMin = len > 0 ? math.max(0.0, (minAlongM - s) / len) : 0.0;
    final tMax = len > 0 ? math.min(1.0, (maxAlongM - s) / len) : 0.0;
    final c = _project(p, line, cum, i, tMin, tMax);
    if (best == null || c.offsetM < best.offsetM) best = c;
  }
  return best;
}

/// Where a marker sits on the served line. Every segment within
/// [kDriveNoteMaxOffsetM] is a candidate; with a [hintAlongM] (the marker's
/// server-derived `position_m`) the candidate nearest that distance wins, so
/// a marker on an out-and-back lands on the pass it was placed on. A
/// non-owner's line starts after a clipped privacy zone, so its distances run
/// short of `position_m` by the clipped length; the other pass is still
/// kilometres further off than that. Without a hint the nearest wins.
LineSnap? placeOnLine(
  ({double lat, double lng}) p,
  List<DrivePoint> line,
  List<double> cum,
  double? hintAlongM,
) {
  if (line.length < 2 || !p.lat.isFinite || !p.lng.isFinite) return null;
  LineSnap? best;
  for (var i = 0; i < line.length - 1; i++) {
    final c = _project(p, line, cum, i, 0, 1);
    if (c.offsetM > kDriveNoteMaxOffsetM) continue;
    if (best == null) {
      best = c;
      continue;
    }
    if (hintAlongM == null || !hintAlongM.isFinite) {
      if (c.offsetM < best.offsetM) best = c;
      continue;
    }
    final dc = (c.alongM - hintAlongM).abs();
    final db = (best.alongM - hintAlongM).abs();
    if (dc < db || (dc == db && c.offsetM < best.offsetM)) best = c;
  }
  return best;
}

/// Linear-interpolate the point at [alongM] on the line.
({double lat, double lng})? pointAtAlong(
  List<DrivePoint> line,
  List<double> cum,
  double alongM,
) {
  if (line.isEmpty) return null;
  if (line.length == 1 || alongM <= 0) {
    return (lat: line[0].lat, lng: line[0].lng);
  }
  final last = line.length - 1;
  if (alongM >= cum[last]) return (lat: line[last].lat, lng: line[last].lng);
  for (var i = 1; i <= last; i++) {
    if (alongM <= cum[i]) {
      final span = cum[i] - cum[i - 1];
      final t = span > 0 ? (alongM - cum[i - 1]) / span : 0.0;
      final a = line[i - 1];
      final b = line[i];
      return (
        lat: a.lat + (b.lat - a.lat) * t,
        lng: wrapLonDeg(a.lng + lonDeltaDeg(a.lng, b.lng) * t),
      );
    }
  }
  return (lat: line[last].lat, lng: line[last].lng);
}

class DriveMarkerInput {
  const DriveMarkerInput({
    required this.kind,
    required this.label,
    required this.lat,
    required this.lng,
    required this.positionM,
    required this.meta,
  });
  final String kind;
  final String label;
  final double lat;
  final double lng;
  final double? positionM;
  final Object? meta;
}

class DriveClimb {
  const DriveClimb({required this.lengthM, required this.gradePct});
  final double lengthM;
  final double gradePct;
}

class DriveNote {
  const DriveNote({
    required this.alongM,
    required this.kind,
    required this.label,
    this.services = const [],
    this.cutoff,
    this.climb,
  });
  final double alongM;
  final String kind;
  final String label;
  final List<String> services;
  final CutoffParts? cutoff;
  final DriveClimb? climb;
}

const _noteKinds = {
  'aid_station',
  'cutoff',
  'crew_access',
  'hazard',
  'note',
  'climb',
  'custom',
};

double? _eleAt(List<DrivePoint> line, List<double> cum, double alongM) {
  for (var i = 1; i < line.length; i++) {
    if (alongM <= cum[i]) {
      final a = line[i - 1].ele;
      final b = line[i].ele;
      if (a == null || b == null) return null;
      final span = cum[i] - cum[i - 1];
      final t = span > 0 ? (alongM - cum[i - 1]) / span : 0.0;
      return a + (b - a) * t;
    }
  }
  return line.isEmpty ? null : line.last.ele;
}

/// The climb a `climb` marker opens: from the marker to the highest point
/// before the line drops [kDriveClimbEndDropM] below it, read off the served
/// line's own heights. Null when the line has no usable heights or the rise
/// is too small to call a climb.
DriveClimb? climbFrom(List<DrivePoint> line, List<double> cum, double alongM) {
  final distinct = <double>{};
  for (final p in line) {
    final e = p.ele;
    if (e != null && e.isFinite) distinct.add(e);
  }
  if (distinct.length < 2) return null;
  final foot = _eleAt(line, cum, alongM);
  if (foot == null) return null;
  var topEle = foot;
  var topAlong = alongM;
  for (var i = 0; i < line.length; i++) {
    if (cum[i] <= alongM) continue;
    if (cum[i] - alongM > kDriveClimbMaxLengthM) break;
    final e = line[i].ele;
    if (e == null || !e.isFinite) break;
    if (e > topEle) {
      topEle = e;
      topAlong = cum[i];
    } else if (e < topEle - kDriveClimbEndDropM) {
      break;
    }
  }
  final gain = topEle - foot;
  final lengthM = topAlong - alongM;
  if (gain < kDriveClimbMinGainM || lengthM < kDriveClimbMinLengthM) {
    return null;
  }
  return DriveClimb(
    lengthM: lengthM,
    gradePct: (gain / lengthM * 1000).round() / 10,
  );
}

/// The course notes for a drive, ordered by distance along the served line.
/// Markers that land nowhere near the line (a redacted end, a stray pin) are
/// left out rather than spoken at a guessed position. Turns are not notes:
/// the Maps app already gives turn-by-turn directions.
List<DriveNote> buildDriveNotes(
  List<DriveMarkerInput> markers,
  List<DrivePoint> line,
) {
  final cum = cumulativeM(line);
  final placed = <({DriveNote note, int order})>[];
  for (var order = 0; order < markers.length; order++) {
    final m = markers[order];
    final snap = placeOnLine((lat: m.lat, lng: m.lng), line, cum, m.positionM);
    if (snap == null) continue;
    final kind = _noteKinds.contains(m.kind) ? m.kind : 'custom';
    final meta = m.meta is Map ? m.meta as Map : const {};
    placed.add((
      order: order,
      note: DriveNote(
        alongM: snap.alongM,
        kind: kind,
        label: m.label.trim(),
        services:
            kind == 'aid_station' ? parseAidServices(meta['services']) : const [],
        cutoff: kind == 'cutoff' ? parseCutoff(meta) : null,
        climb: kind == 'climb' ? climbFrom(line, cum, snap.alongM) : null,
      ),
    ));
  }
  placed.sort((a, b) {
    final d = a.note.alongM.compareTo(b.note.alongM);
    return d != 0 ? d : a.order.compareTo(b.order);
  });
  return [for (final p in placed) p.note];
}

/// How far ahead of a note to speak it at [speedMps].
double driveLeadM(double speedMps) {
  final v = speedMps.isFinite && speedMps > 0 ? speedMps : 0.0;
  return math.min(kDriveLeadMaxM, math.max(kDriveLeadMinM, v * kDriveLeadS));
}

/// How close to a note counts as "at it" at [speedMps].
double driveAtM(double speedMps) {
  final v = speedMps.isFinite && speedMps > 0 ? speedMps : 0.0;
  return math.max(kDriveAtMinM, v * kDriveAtS);
}

enum DriveCueBand { ahead, at, passed }

class DriveCue {
  const DriveCue({
    required this.index,
    required this.note,
    required this.band,
    required this.aheadM,
  });
  final int index;
  final DriveNote note;
  final DriveCueBand band;

  /// Real distance to the note when the cue fired; negative once passed.
  final double aheadM;
}

/// Decides which note to speak on each position update. Each note speaks at
/// most twice — once [driveLeadM] ahead and once at it — and only the nearest
/// unfinished note is considered, so two close notes do not talk over each
/// other. When a fix lands inside both bands at once, only "at" speaks. A
/// note the driver passed between two fixes with nothing said is reported
/// once as "passed" when it is less than [kDriveMissedReportM] behind;
/// further back (a long GPS gap, a late join) it is retired silently.
///
/// `startAlongM` is where the drive joined the course: notes behind it are
/// retired without a word, so joining at mile 8 does not read out miles 0-8.
class DriveCueAnnouncer {
  DriveCueAnnouncer(List<DriveNote> notes, [double startAlongM = 0])
      : _notes = List.unmodifiable(notes),
        _ahead = List.filled(notes.length, false),
        _at = List.filled(notes.length, false),
        _done = [for (final n in notes) n.alongM < startAlongM];

  final List<DriveNote> _notes;
  final List<bool> _ahead;
  final List<bool> _at;
  final List<bool> _done;

  int get remaining => _done.where((d) => !d).length;

  DriveCue? next(double alongM, double speedMps) {
    final lead = driveLeadM(speedMps);
    final atM = driveAtM(speedMps);
    for (var i = 0; i < _notes.length; i++) {
      if (_done[i]) continue;
      final note = _notes[i];
      final aheadM = note.alongM - alongM;
      if (aheadM < -atM) {
        _done[i] = true;
        if (!_ahead[i] && !_at[i] && -aheadM <= kDriveMissedReportM) {
          return DriveCue(
              index: i, note: note, band: DriveCueBand.passed, aheadM: aheadM);
        }
        continue;
      }
      if (_at[i]) continue;
      if (aheadM <= atM) {
        _at[i] = true;
        _ahead[i] = true;
        return DriveCue(
            index: i, note: note, band: DriveCueBand.at, aheadM: aheadM);
      }
      if (aheadM <= lead && !_ahead[i]) {
        _ahead[i] = true;
        return DriveCue(
            index: i, note: note, band: DriveCueBand.ahead, aheadM: aheadM);
      }
      return null;
    }
    return null;
  }
}

class DriveStop {
  const DriveStop({required this.lat, required this.lng, required this.alongM});
  final double lat;
  final double lng;
  final double alongM;
}

class DriveLeg {
  const DriveLeg({
    required this.index,
    required this.start,
    required this.via,
    required this.end,
  });
  final int index;
  final DriveStop start;

  /// Stops between start and end, in order.
  final List<DriveStop> via;
  final DriveStop end;
}

/// Cut the served line into legs a Maps app will take. [maxWaypoints] is the
/// app's cap on stops before the destination; the leg's start is the first of
/// them, so the app routes from wherever the driver is to the start of the
/// leg and then along it. A leg is pinned every [spacingM] so the router has
/// little room to pick a different road, and legs never span a gap wider than
/// [kDriveMaxJoinM] between two served points: whatever is missing there is
/// not the driver's to fill in.
List<DriveLeg> planDriveLegs(
  List<DrivePoint> line,
  int maxWaypoints, [
  double? spacingM,
]) {
  final spacing = spacingM ??
      (maxWaypoints > 0 ? kDriveStopSpacingM : kDriveSingleStopSpacingM);
  final cum = cumulativeM(line);
  final pieces = <(int, int)>[];
  var pieceStart = 0;
  for (var i = 1; i < line.length; i++) {
    if (cum[i] - cum[i - 1] > kDriveMaxJoinM) {
      pieces.add((pieceStart, i - 1));
      pieceStart = i;
    }
  }
  if (line.isNotEmpty) pieces.add((pieceStart, line.length - 1));

  final via = math.max(0, maxWaypoints - 1);
  final legLenTarget = math.max(1.0, spacing) * (via + 1);
  final legs = <DriveLeg>[];
  DriveStop stopAt(double alongM) {
    final p = pointAtAlong(line, cum, alongM)!;
    return DriveStop(lat: p.lat, lng: p.lng, alongM: alongM);
  }

  for (final (a, b) in pieces) {
    final from = cum[a];
    final to = cum[b];
    final length = to - from;
    if (b <= a || length < 50) continue;
    final n = (length / legLenTarget).ceil();
    final legLen = length / n;
    for (var k = 0; k < n; k++) {
      final s = from + k * legLen;
      final e = k == n - 1 ? to : from + (k + 1) * legLen;
      final vias = [
        for (var j = 1; j <= via; j++) stopAt(s + (e - s) * j / (via + 1)),
      ];
      legs.add(DriveLeg(
          index: legs.length, start: stopAt(s), via: vias, end: stopAt(e)));
    }
  }
  return legs;
}

String _coord(double lat, double lng) =>
    '${lat.toStringAsFixed(5)},${lng.toStringAsFixed(5)}';

/// Google Maps driving directions through a leg, from the device's location.
String googleMapsLegUrl(DriveLeg leg) {
  final waypoints =
      [leg.start, ...leg.via].map((s) => _coord(s.lat, s.lng)).join('|');
  return 'https://www.google.com/maps/dir/?api=1'
      '&destination=${Uri.encodeComponent(_coord(leg.end.lat, leg.end.lng))}'
      '&waypoints=${Uri.encodeComponent(waypoints)}'
      '&travelmode=driving';
}

/// Apple Maps driving directions to one point, from the device's location.
String appleMapsUrl(double lat, double lng) =>
    'https://maps.apple.com/?daddr=${Uri.encodeComponent(_coord(lat, lng))}&dirflg=d';

/// Waze navigation to one point.
String wazeUrl(double lat, double lng) =>
    'https://waze.com/ul?ll=${Uri.encodeComponent(_coord(lat, lng))}&navigate=yes';

/// The link that opens [leg] in [app]. Single-destination apps go to its end.
String mapsLegUrl(MapsApp app, DriveLeg leg) => switch (app) {
      MapsApp.google => googleMapsLegUrl(leg),
      MapsApp.apple => appleMapsUrl(leg.end.lat, leg.end.lng),
      MapsApp.waze => wazeUrl(leg.end.lat, leg.end.lng),
    };

/// The link that drives to the start of the course in [app].
String mapsStartUrl(MapsApp app, double lat, double lng) => switch (app) {
      MapsApp.google => 'https://www.google.com/maps/dir/?api=1'
          '&destination=${Uri.encodeComponent(_coord(lat, lng))}&travelmode=driving',
      MapsApp.apple => appleMapsUrl(lat, lng),
      MapsApp.waze => wazeUrl(lat, lng),
    };

class CourseStretch {
  const CourseStretch({required this.startM, required this.endM});
  final double startM;
  final double endM;

  @override
  bool operator ==(Object other) =>
      other is CourseStretch && other.startM == startM && other.endM == endM;

  @override
  int get hashCode => Object.hash(startM, endM);
}

/// The stretches of the course a road router's line does not follow: every
/// run of course samples (one each [kDriveUndrivableSampleM]) farther than
/// [kDriveUndrivableToleranceM] from [routed], kept when it is at least
/// [kDriveUndrivableMinM] long. A closed road, a path or a bridge the router
/// went round shows up here; an empty routed line reports the whole course,
/// since nothing was shown to follow it.
List<CourseStretch> undrivableStretches(
  List<DrivePoint> line,
  List<DrivePoint> routed,
) {
  final cum = cumulativeM(line);
  if (line.length < 2) return const [];
  final total = cum.last;
  if (total <= 0) return const [];
  if (routed.length < 2) return [CourseStretch(startM: 0, endM: total)];

  final rcum = cumulativeM(routed);
  const padLat = kDriveUndrivableToleranceM / 111320;
  final boxes =
      <({double minLat, double maxLat, double minLng, double maxLng, double refLng})>[];
  for (var i = 0; i < routed.length - 1; i++) {
    final a = routed[i];
    final b = routed[i + 1];
    final cosv = math.max(0.01, math.cos(_toRad((a.lat + b.lat) / 2)));
    final padLng = padLat / cosv;
    final bLng = a.lng + lonDeltaDeg(a.lng, b.lng);
    boxes.add((
      minLat: math.min(a.lat, b.lat) - padLat,
      maxLat: math.max(a.lat, b.lat) + padLat,
      minLng: math.min(a.lng, bLng) - padLng,
      maxLng: math.max(a.lng, bLng) + padLng,
      refLng: a.lng,
    ));
  }
  bool offCourse(({double lat, double lng}) p) {
    for (var i = 0; i < boxes.length; i++) {
      final box = boxes[i];
      final lng = box.refLng + lonDeltaDeg(box.refLng, p.lng);
      if (p.lat < box.minLat ||
          p.lat > box.maxLat ||
          lng < box.minLng ||
          lng > box.maxLng) {
        continue;
      }
      if (_project(p, routed, rcum, i, 0, 1).offsetM <=
          kDriveUndrivableToleranceM) {
        return false;
      }
    }
    return true;
  }

  final stretches = <CourseStretch>[];
  double? openAt;
  var lastOff = 0.0;
  final samples = (total / kDriveUndrivableSampleM).ceil();
  for (var k = 0; k <= samples; k++) {
    final along = math.min(total, k * kDriveUndrivableSampleM);
    final p = pointAtAlong(line, cum, along)!;
    if (offCourse(p)) {
      openAt ??= along;
      lastOff = along;
    } else if (openAt != null) {
      if (lastOff - openAt >= kDriveUndrivableMinM) {
        stretches.add(CourseStretch(startM: openAt, endM: lastOff));
      }
      openAt = null;
    }
  }
  if (openAt != null && lastOff - openAt >= kDriveUndrivableMinM) {
    stretches.add(CourseStretch(startM: openAt, endM: lastOff));
  }
  return stretches;
}
