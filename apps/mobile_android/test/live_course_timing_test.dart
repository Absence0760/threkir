// Live park course timing (#1446): the run screen's "Timing started" and
// "Finished!" come from LiveCourseTracker, which must never say "Finished!"
// for a recording the board would not time. Checked over the two case tables
// the `segments` pair shares with web and the server bundle:
// fixtures/segments_gate_cases.json (small synthetic lines) and
// fixtures/park_course_runs.json (1 Hz runs over the real Pocahontas
// courses), each fed to the tracker one fix at a time as the recorder would.

import 'dart:convert';
import 'dart:io';

import 'package:core_models/core_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/gate_crossing.dart';
import '../lib/live_course_timing.dart';
import '../lib/segments.dart';

const _root = '../..';

Map<String, dynamic> _readJson(String path) =>
    jsonDecode(File('$_root/$path').readAsStringSync()) as Map<String, dynamic>;

Gate? _gate(Object? raw) {
  if (raw == null) return null;
  final g = raw as Map<String, dynamic>;
  return Gate(
    lat: (g['lat'] as num).toDouble(),
    lng: (g['lng'] as num).toDouble(),
    bearingDeg: (g['bearing_deg'] as num).toDouble(),
    halfWidthM: (g['half_width_m'] as num).toDouble(),
  );
}

List<Waypoint> _points(Object? raw) => [
      for (final p in (raw as List? ?? const []).cast<Map<String, dynamic>>())
        Waypoint(
          lat: (p['lat'] as num).toDouble(),
          lng: (p['lng'] as num).toDouble(),
        ),
    ];

/// What the tracker said over [track], fed one fix at a time.
({List<LiveCourseEvent> events, LiveCourseTracker tracker}) _feed(
  LiveCourseTracker tracker,
  List<Waypoint> track,
) {
  final line = <Waypoint>[];
  final events = <LiveCourseEvent>[];
  for (final w in track) {
    line.add(w);
    events.addAll(tracker.offer(line));
  }
  return (events: events, tracker: tracker);
}

List<Waypoint> _decodeRun(Map<String, dynamic> track, DateTime base) {
  final first = (track['first'] as List).cast<num>();
  final d = (track['d'] as List).cast<num>();
  final gaps = {
    for (final g in (track['gaps'] as List).cast<List<dynamic>>())
      (g[0] as num).toInt(): (g[1] as num).toInt(),
  };
  var lat = first[0].toInt();
  var lng = first[1].toInt();
  var t = 0;
  final out = <Waypoint>[
    Waypoint(lat: lat / 1e6, lng: lng / 1e6, timestamp: base),
  ];
  for (var i = 1; i <= d.length ~/ 2; i++) {
    lat += d[2 * i - 2].toInt();
    lng += d[2 * i - 1].toInt();
    t += gaps[i] ?? 1;
    out.add(Waypoint(
      lat: lat / 1e6,
      lng: lng / 1e6,
      timestamp: base.add(Duration(seconds: t)),
    ));
  }
  return out;
}

/// The checks every case answers: the tracker finishes only when the board
/// times the recording at that moment, says its time, and is never left
/// waiting on a recording the board times.
void _expectAgreesWithMatcher(
  List<Waypoint> track,
  GlobalSegmentGeometry segment, {
  required bool singlePass,
}) {
  final tracker = LiveCourseTracker.forSegment(segment)!;
  final fed = _feed(tracker, track);
  final whole = computeGlobalSegmentEffort(track, segment);
  final finishes =
      fed.events.where((e) => e.kind == LiveCourseEventKind.finished).toList();
  expect(finishes.length, lessThanOrEqualTo(1));
  if (whole == null) {
    expect(finishes, isEmpty,
        reason: 'said "Finished!" on a recording the board does not time');
    expect(tracker.phase, isNot(LiveCoursePhase.finished));
    if (tracker.phase == LiveCoursePhase.timing) {
      expect(tracker.stopsShort(track), isTrue);
    }
    return;
  }
  expect(tracker.phase, isNot(LiveCoursePhase.waiting),
      reason: 'the board times this recording, so it left the start box');
  expect(tracker.stopsShort(track), isFalse);
  if (finishes.isEmpty) return;
  final said = finishes.single.timeSeconds!;
  expect(tracker.finishedSeconds, said);
  if (singlePass) {
    expect((said - whole.timeSeconds).abs() < 0.001, isTrue,
        reason: 'said $said s, the board times ${whole.timeSeconds} s');
  } else {
    // The first lap is said; the board keeps the fastest.
    expect(said, greaterThanOrEqualTo(whole.timeSeconds - 0.001));
  }
}

void main() {
  group('the shared gate cases', () {
    final fixture = _readJson('fixtures/segments_gate_cases.json');
    final base = DateTime.parse(fixture['base_time'] as String);
    final cases = (fixture['cases'] as List).cast<Map<String, dynamic>>();
    for (final c in cases) {
      final seg = c['segment'] as Map<String, dynamic>;
      final segment = GlobalSegmentGeometry(
        points: _points(seg['points']),
        distanceM: (seg['distance_m'] as num).toDouble(),
        checkpoints: _points(seg['checkpoints']),
        startGate: _gate(seg['start_gate']),
        endGate: _gate(seg['end_gate']),
      );
      final track = [
        for (final p in (c['track'] as List).cast<Map<String, dynamic>>())
          Waypoint(
            lat: (p['lat'] as num).toDouble(),
            lng: (p['lng'] as num).toDouble(),
            timestamp: base.add(
                Duration(milliseconds: ((p['t'] as num) * 1000).round())),
            offTrack: p['off_track'] == true,
          ),
      ];
      test('${c['name']}', () {
        if (LiveCourseTracker.forSegment(segment) == null) {
          // Matched by the circles: nothing is followed live.
          expect(segment.startGate == null || segment.endGate == null, isTrue);
          return;
        }
        final name = c['name'] as String;
        _expectAgreesWithMatcher(
          trackLine(track),
          segment,
          singlePass: !name.contains('two passes') && !name.contains('three'),
        );
      });
    }
  });

  group('runs over the real park courses', () {
    final fixture = _readJson('fixtures/park_course_runs.json');
    final base = DateTime.parse(fixture['base_time'] as String);
    final courses = (fixture['courses'] as List).cast<Map<String, dynamic>>();
    final cases = (fixture['cases'] as List).cast<Map<String, dynamic>>();
    final bySlug = {
      for (final c in courses)
        c['slug'] as String: () {
          final gj = _readJson(c['geojson'] as String);
          final line = (gj['features'] as List)
              .cast<Map<String, dynamic>>()
              .firstWhere(
                  (f) => (f['geometry'] as Map)['type'] == 'LineString');
          final coords = ((line['geometry'] as Map)['coordinates'] as List)
              .cast<List<dynamic>>();
          return GlobalSegmentGeometry(
            points: [
              for (final p in coords)
                Waypoint(
                  lat: (p[1] as num).toDouble(),
                  lng: (p[0] as num).toDouble(),
                ),
            ],
            distanceM: (c['distance_m'] as num).toDouble(),
            checkpoints: _points(c['checkpoints']),
            startGate: _gate(c['start_gate']),
            endGate: _gate(c['end_gate']),
          );
        }(),
    };
    for (final c in cases) {
      test('${c['name']}', () {
        final key = c['key'] as String;
        _expectAgreesWithMatcher(
          _decodeRun(c['track'] as Map<String, dynamic>, base),
          bySlug[c['course'] as String]!,
          singlePass: !key.contains('laps') && !key.contains('passes'),
        );
      });
    }

    test('a clean run says both, in order, and the finish is its course time',
        () {
      final c = cases.firstWhere((c) => c['key'] == 'beaver_clean');
      final segment = bySlug['beaver-lake-trail']!;
      final fed = _feed(LiveCourseTracker.forSegment(segment)!,
          _decodeRun(c['track'] as Map<String, dynamic>, base));
      expect([for (final e in fed.events) e.kind],
          [LiveCourseEventKind.started, LiveCourseEventKind.finished]);
      final truth = (c['want'] as Map)['truth_s'] as num;
      expect((fed.events.last.timeSeconds! - truth).abs() < 6, isTrue);
    });

    test('stopping short of the finish leaves the course started, not timed',
        () {
      final c = cases.firstWhere((c) => c['key'] == 'beaver_short');
      final track = _decodeRun(c['track'] as Map<String, dynamic>, base);
      final fed =
          _feed(LiveCourseTracker.forSegment(bySlug['beaver-lake-trail']!)!,
              track);
      expect([for (final e in fed.events) e.kind],
          [LiveCourseEventKind.started]);
      expect(fed.tracker.stopsShort(track), isTrue);
    });

    test('a shortcut is started and never finished', () {
      final c = cases.firstWhere((c) => c['key'] == 'beaver_shortcut');
      final track = _decodeRun(c['track'] as Map<String, dynamic>, base);
      final fed =
          _feed(LiveCourseTracker.forSegment(bySlug['beaver-lake-trail']!)!,
              track);
      expect(
          fed.events.any((e) => e.kind == LiveCourseEventKind.finished), isFalse);
      expect(fed.tracker.stopsShort(track), isTrue);
    });
  });

  group('a straight course north', () {
    const lat0 = 37.5;
    const lng0 = -77.5;
    Waypoint at(double northM, int s, {double eastM = 0}) => Waypoint(
          lat: lat0 + northM / 111195,
          lng: lng0 + eastM / (111195 * 0.7933533402912352),
          timestamp: DateTime.utc(2026, 11, 20, 8).add(Duration(seconds: s)),
        );
    final segment = GlobalSegmentGeometry(
      points: [at(0, 0), at(400, 0)],
      distanceM: 400,
      startGate: const Gate(
          lat: lat0, lng: lng0, bearingDeg: 0, halfWidthM: 15),
      endGate: Gate(
          lat: lat0 + 400 / 111195, lng: lng0, bearingDeg: 0, halfWidthM: 15),
    );
    List<Waypoint> run(double fromM, double toM, {int startS = 0}) => [
          for (var m = fromM, s = startS; m <= toM; m += 4, s++) at(m, s),
        ];

    test('leaving the start box forward says "started" once', () {
      final fed = _feed(LiveCourseTracker.forSegment(segment)!, run(-10, 100));
      expect([for (final e in fed.events) e.kind],
          [LiveCourseEventKind.started]);
      expect(fed.tracker.phase, LiveCoursePhase.timing);
    });

    // The start box lies behind the start line and the finish box ahead of
    // the finish line, so the start line is the box's exit edge and the
    // finish line its entry edge.
    test('nothing before the start box is left', () {
      final fed = _feed(LiveCourseTracker.forSegment(segment)!, run(-40, -2));
      expect(fed.events, isEmpty);
      expect(fed.tracker.phase, LiveCoursePhase.waiting);
      expect(fed.tracker.stopsShort(run(-40, -2)), isFalse);
    });

    test('running it the wrong way never starts', () {
      final track = [
        for (var m = 420.0, s = 0; m >= -20; m -= 4, s++) at(m, s),
      ];
      final fed = _feed(LiveCourseTracker.forSegment(segment)!, track);
      expect(fed.events, isEmpty);
    });

    test('the finish says the time the board gives', () {
      final track = run(-10, 430);
      final fed = _feed(LiveCourseTracker.forSegment(segment)!, track);
      expect([for (final e in fed.events) e.kind],
          [LiveCourseEventKind.started, LiveCourseEventKind.finished]);
      expect(fed.events.last.timeSeconds,
          computeGlobalSegmentEffort(track, segment)!.timeSeconds);
      expect(fed.tracker.stopsShort(track), isFalse);
    });

    test('nothing more is said after the finish', () {
      final track = [...run(-10, 430), ...run(-10, 430, startS: 200)];
      final fed = _feed(LiveCourseTracker.forSegment(segment)!, track);
      expect(fed.events.length, 2);
    });

    test('back into the start box, the next exit starts it again', () {
      final track = [
        ...run(-10, 30),
        for (var m = 26.0, s = 11; m >= -10; m -= 4, s++) at(m, s),
        ...run(-6, 60, startS: 30),
      ];
      final fed = _feed(LiveCourseTracker.forSegment(segment)!, track);
      expect([for (final e in fed.events) e.kind],
          [LiveCourseEventKind.started, LiveCourseEventKind.started]);
    });

    test('a recording that ends in the finish box is not stopped short', () {
      // 2 m short of the finish line, inside the slack: the board's tail rule.
      final track = run(-10, 398);
      final fed = _feed(LiveCourseTracker.forSegment(segment)!, track);
      expect(fed.tracker.phase, LiveCoursePhase.timing);
      expect(computeGlobalSegmentEffort(track, segment), isNotNull);
      expect(fed.tracker.stopsShort(track), isFalse);
    });

    test('a new, shorter line starts the tracker over', () {
      final tracker = LiveCourseTracker.forSegment(segment)!;
      _feed(tracker, run(-10, 430));
      expect(tracker.phase, LiveCoursePhase.finished);
      final again = _feed(tracker, run(-10, 40));
      expect(again.tracker.phase, LiveCoursePhase.timing);
      expect(tracker.finishedSeconds, isNull);
    });

    test('a course without both lines is not followed live', () {
      expect(
        LiveCourseTracker.forSegment(GlobalSegmentGeometry(
            points: segment.points,
            distanceM: 400,
            startGate: segment.startGate)),
        isNull,
      );
    });
  });

  group('liveCourseGeometry', () {
    ParkCourseListing listing({
      Object? checkpoints = const [],
      double? endBearing = 0,
    }) =>
        ParkCourseListing(
          course: ParkCourseRow.fromJson({
            'id': 'c1',
            'park_id': 'p1',
            'global_segment_id': 's1',
            'slug': 'loop',
            'course_shape': 'loop',
            'status': 'open',
            'geometry_source': 'osm',
            'checkpoints': checkpoints,
            'created_at': '2026-11-20T00:00:00Z',
          }),
          segment: GlobalSegmentRow.fromJson({
            'id': 's1',
            'name': 'Loop',
            'waypoints': [
              {'lat': 37.5, 'lng': -77.5},
              {'lat': 37.504, 'lng': -77.5},
            ],
            'distance_m': 444,
            'surface': 'trail',
            'is_active': true,
            'created_at': '2026-11-20T00:00:00Z',
            'start_gate_lat': 37.5,
            'start_gate_lng': -77.5,
            'start_gate_bearing_deg': 0,
            'start_gate_half_width_m': 15,
            'end_gate_lat': 37.504,
            'end_gate_lng': -77.5,
            'end_gate_bearing_deg': endBearing,
            'end_gate_half_width_m': 15,
          }),
        );

    test('reads the lines, length and checkpoints the server scores by', () {
      final g = liveCourseGeometry(listing(checkpoints: [
        {'lat': 37.502, 'lng': -77.5},
      ]))!;
      expect(g.distanceM, 444);
      expect(g.points.length, 2);
      expect(g.checkpoints.single.lat, 37.502);
      expect(g.startGate!.bearingDeg, 0);
      expect(g.endGate!.lat, 37.504);
    });

    test('no finish line, nothing to follow', () {
      expect(liveCourseGeometry(listing(endBearing: null)), isNull);
    });

    test('checkpoints the parser refuses, nothing to follow', () {
      expect(liveCourseGeometry(listing(checkpoints: 'oops')), isNull);
    });
  });
}
