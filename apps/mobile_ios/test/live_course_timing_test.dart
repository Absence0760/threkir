// Live park course timing (#1446): the run screen's "Timing started" and
// "Finished!" come from LiveCourseTracker, which must never say "Finished!"
// for a recording the board would not time. Checked over the two case tables
// the `segments` pair shares with web and the server bundle:
// fixtures/segments_gate_cases.json (small synthetic lines) and
// fixtures/park_course_runs.json (1 Hz runs over the real Pocahontas
// courses), each fed to the tracker one fix at a time as the recorder would.

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

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

  group('checkpoints and the off-course warning', () {
    const lat0 = 37.5;
    const lng0 = -77.5;
    const mPerDegLng = 111195 * 0.7933533402912352;
    Waypoint at(double northM, int s, {double eastM = 0}) => Waypoint(
          lat: lat0 + northM / 111195,
          lng: lng0 + eastM / mPerDegLng,
          timestamp: DateTime.utc(2026, 11, 20, 8).add(Duration(seconds: s)),
        );
    // 600 m north, checkpoints at 200 m and 400 m.
    final segment = GlobalSegmentGeometry(
      points: [at(0, 0), at(600, 0)],
      distanceM: 600,
      checkpoints: [at(200, 0), at(400, 0)],
      startGate:
          const Gate(lat: lat0, lng: lng0, bearingDeg: 0, halfWidthM: 15),
      endGate: Gate(
          lat: lat0 + 600 / 111195, lng: lng0, bearingDeg: 0, halfWidthM: 15),
    );
    // One fix a second, 4 m apart, along [points] (north, east) metres.
    List<Waypoint> path(List<(double, double)> points) {
      final out = <Waypoint>[];
      var s = 0;
      for (var k = 0; k + 1 < points.length; k++) {
        final (n0, e0) = points[k];
        final (n1, e1) = points[k + 1];
        final d = math.sqrt((n1 - n0) * (n1 - n0) + (e1 - e0) * (e1 - e0));
        final steps = math.max(1, (d / 4).ceil());
        for (var j = k == 0 ? 0 : 1; j <= steps; j++) {
          final f = j / steps;
          out.add(at(n0 + (n1 - n0) * f, s++, eastM: e0 + (e1 - e0) * f));
        }
      }
      return out;
    }

    List<LiveCourseEventKind> kinds(List<LiveCourseEvent> events) =>
        [for (final e in events) e.kind];

    test('passing each checkpoint ticks it, by the matcher\'s own walk', () {
      final tracker = LiveCourseTracker.forSegment(segment)!;
      _feed(tracker, path([(-10, 0), (150, 0)]));
      expect(tracker.checkpointsPassed, 0);
      expect(tracker.nextCheckpoint, 1);
      final t2 = _feed(LiveCourseTracker.forSegment(segment)!,
              path([(-10, 0), (250, 0)]))
          .tracker;
      expect(t2.checkpointsPassed, 1);
      expect(t2.nextCheckpoint, 2);
      final t3 = _feed(LiveCourseTracker.forSegment(segment)!,
              path([(-10, 0), (450, 0)]))
          .tracker;
      expect(t3.checkpointsPassed, 2);
      expect(t3.nextCheckpoint, isNull);
    });

    test('a finished course has every checkpoint ticked', () {
      final fed = _feed(
          LiveCourseTracker.forSegment(segment)!, path([(-10, 0), (620, 0)]));
      expect(fed.tracker.phase, LiveCoursePhase.finished);
      expect(fed.tracker.checkpointsPassed, 2);
      expect(fed.tracker.offCourse, isFalse);
    });

    test(
        'straying past the tolerance names the next checkpoint, once, and '
        'clears back on the line', () {
      final fed = _feed(
        LiveCourseTracker.forSegment(segment)!,
        path([(-10, 0), (250, 0), (270, 60), (290, 60), (300, 0), (350, 0)]),
      );
      expect(
          kinds(fed.events),
          [
            LiveCourseEventKind.started,
            LiveCourseEventKind.offCourse,
            LiveCourseEventKind.backOnCourse,
          ]);
      expect(fed.tracker.offCourse, isFalse);
      expect(fed.tracker.nextCheckpoint, 2);
    });

    test('while off, the warning holds and names checkpoint 2', () {
      final fed = _feed(LiveCourseTracker.forSegment(segment)!,
          path([(-10, 0), (250, 0), (270, 60), (300, 60)]));
      expect(fed.tracker.offCourse, isTrue);
      expect(fed.tracker.nextCheckpoint, 2);
      expect(fed.tracker.offsetFromLineM, greaterThan(kLiveCourseOffCourseM));
    });

    test('jitter at the edge of the tolerance does not say it again', () {
      // In and out between 30 m and 40 m off the line: above 35 m once, and
      // never back under 25 m, so one warning and no clear.
      final fed = _feed(
        LiveCourseTracker.forSegment(segment)!,
        path([
          (-10, 0),
          (100, 0),
          (110, 40),
          for (var k = 0; k < 8; k++) ...[(120.0 + 8 * k, 30), (124.0 + 8 * k, 40)],
        ]),
      );
      expect(
          kinds(fed.events)
              .where((k) => k == LiveCourseEventKind.offCourse)
              .length,
          1);
      expect(kinds(fed.events), isNot(contains(LiveCourseEventKind.backOnCourse)));
    });

    test('after the last checkpoint, it points back to the course line', () {
      final fed = _feed(LiveCourseTracker.forSegment(segment)!,
          path([(-10, 0), (450, 0), (470, 80)]));
      expect(fed.tracker.offCourse, isTrue);
      expect(fed.tracker.nextCheckpoint, isNull);
    });

    test('nothing is said off the line before the start', () {
      final fed = _feed(LiveCourseTracker.forSegment(segment)!,
          path([(-200, 80), (-60, 80)]));
      expect(fed.events, isEmpty);
      expect(fed.tracker.offCourse, isFalse);
      expect(fed.tracker.offsetFromLineM, isNull);
    });

    test('back into the start box clears the warning and the ticks', () {
      final fed = _feed(LiveCourseTracker.forSegment(segment)!,
          path([(-10, 0), (220, 0), (220, 60), (30, 60), (30, 0), (-10, 0)]));
      expect(fed.tracker.phase, LiveCoursePhase.waiting);
      expect(fed.tracker.offCourse, isFalse);
      expect(fed.tracker.checkpointsPassed, 0);
    });

    test('the resumable walk agrees with one walk over the whole line', () {
      final line = path([(-10, 0), (220, 0), (250, 50), (420, 0)]);
      var state = (passed: 0, nextIdx: 0);
      for (var i = 0; i < line.length; i++) {
        state = advanceCheckpointWalk(line, segment.checkpoints,
            passed: state.passed,
            fromIdx: state.nextIdx,
            toIdx: i,
            toleranceM: kGlobalSegmentToleranceM);
      }
      final once = advanceCheckpointWalk(line, segment.checkpoints,
          passed: 0,
          fromIdx: 0,
          toIdx: line.length - 1,
          toleranceM: kGlobalSegmentToleranceM);
      expect(state.passed, once.passed);
      expect(once.passed, 2);
    });
  });

  group('finding a course the runner did not pick', () {
    const lat0 = 37.5;
    const lng0 = -77.5;
    const mPerDegLng = 111195 * 0.7933533402912352;
    Waypoint at(double northM, double eastM, [int s = 0]) => Waypoint(
          lat: lat0 + northM / 111195,
          lng: lng0 + eastM / mPerDegLng,
          timestamp: DateTime.utc(2026, 11, 20, 8).add(Duration(seconds: s)),
        );
    // A course from ([n0], [e0]) heading [bearing] for 400 m.
    LiveCourseCandidate course(String name, double n0, double e0,
        {double bearing = 0, List<Waypoint> via = const []}) {
      final rad = bearing * math.pi / 180;
      final start = at(n0, e0);
      final end = at(n0 + 400 * math.cos(rad), e0 + 400 * math.sin(rad));
      return LiveCourseCandidate(
        name: name,
        segment: GlobalSegmentGeometry(
          points: [start, ...via, end],
          distanceM: 400,
          startGate: Gate(
              lat: start.lat,
              lng: start.lng,
              bearingDeg: bearing,
              halfWidthM: 15),
          endGate: Gate(
              lat: end.lat, lng: end.lng, bearingDeg: bearing, halfWidthM: 15),
        ),
      );
    }

    List<Waypoint> walk(List<(double, double)> points) {
      final out = <Waypoint>[];
      var s = 0;
      for (var k = 0; k + 1 < points.length; k++) {
        final (n0, e0) = points[k];
        final (n1, e1) = points[k + 1];
        final d = math.sqrt((n1 - n0) * (n1 - n0) + (e1 - e0) * (e1 - e0));
        final steps = math.max(1, (d / 4).ceil());
        for (var j = k == 0 ? 0 : 1; j <= steps; j++) {
          final f = j / steps;
          out.add(at(n0 + (n1 - n0) * f, e0 + (e1 - e0) * f, s++));
        }
      }
      return out;
    }

    LiveCourseAdoption? feed(LiveCourseDetector d, List<Waypoint> track) {
      final line = <Waypoint>[];
      for (final w in track) {
        line.add(w);
        final a = d.offer(line);
        if (a != null) return a;
      }
      return null;
    }

    test('no candidates, nothing to follow', () {
      final d = LiveCourseDetector(const []);
      expect(d.isEmpty, isTrue);
      expect(feed(d, walk([(-20, 0), (100, 0)])), isNull);
    });

    test('one course, adopted when its start box is left forward', () {
      final d = LiveCourseDetector([course('Lake loop', 0, 0)]);
      final line = walk([(-20, 0), (40, 0)]);
      final a = feed(d, line)!;
      expect(a.candidate.name, 'Lake loop');
      expect([for (final e in a.events) e.kind], [LiveCourseEventKind.started]);
      expect(a.tracker.phase, LiveCoursePhase.timing);
    });

    test('standing near a course without leaving its start box adopts '
        'nothing', () {
      final d = LiveCourseDetector([course('Lake loop', 0, 0)]);
      expect(feed(d, walk([(-30, 0), (-8, 0), (-30, 0)])), isNull);
    });

    test('of two courses, the one whose start box is left is adopted', () {
      final d = LiveCourseDetector([
        course('North path', 0, 0),
        course('East path', 0, 150, bearing: 90),
      ]);
      final a = feed(d, walk([(0, 120), (0, 200)]))!;
      expect(a.candidate.name, 'East path');
    });

    test('two courses sharing a start wait until the line picks one', () {
      // Both leave the same start north; one bends east 100 m in.
      final d = LiveCourseDetector([
        course('Straight', 0, 0),
        course('Bend', 0, 0, via: [at(100, 0), at(100, 300)]),
      ]);
      final first = walk([(-20, 0), (60, 0)]);
      expect(feed(d, first), isNull,
          reason: 'both started on the same fix and both are under the line');
      final a = feed(d, walk([(-20, 0), (100, 0), (100, 80)]))!;
      expect(a.candidate.name, 'Bend');
    });

    test('nearbyCourseCandidates keeps open courses whose start is in reach',
        () {
      ParkCourseListing listing(String id, double startLat, String status) =>
          ParkCourseListing(
            course: ParkCourseRow.fromJson({
              'id': id,
              'park_id': 'p1',
              'global_segment_id': 's$id',
              'slug': id,
              'course_shape': 'point_to_point',
              'status': status,
              'geometry_source': 'osm',
              'checkpoints': const [],
              'created_at': '2026-11-20T00:00:00Z',
            }),
            segment: GlobalSegmentRow.fromJson({
              'id': 's$id',
              'name': 'Course $id',
              'waypoints': [
                {'lat': startLat, 'lng': lng0},
                {'lat': startLat + 0.004, 'lng': lng0},
              ],
              'distance_m': 444,
              'surface': 'trail',
              'is_active': true,
              'created_at': '2026-11-20T00:00:00Z',
              'start_gate_lat': startLat,
              'start_gate_lng': lng0,
              'start_gate_bearing_deg': 0,
              'start_gate_half_width_m': 15,
              'end_gate_lat': startLat + 0.004,
              'end_gate_lng': lng0,
              'end_gate_bearing_deg': 0,
              'end_gate_half_width_m': 15,
            }),
          );
      final got = nearbyCourseCandidates([
        listing('near', lat0 + 100 / 111195, 'open'),
        listing('far', lat0 + 2000 / 111195, 'open'),
        listing('shut', lat0, 'closed'),
      ], lat0, lng0);
      expect([for (final c in got) c.name], ['Course near']);
    });

    test('the search box spans the radius around the runner', () {
      final b = courseSearchBox(lat0, lng0);
      expect(b.minLat, lessThan(lat0));
      expect(b.maxLat, greaterThan(lat0));
      expect((b.maxLat - b.minLat) * 111195,
          closeTo(2 * kLiveCourseDetectRadiusM, 1));
      expect((b.maxLng - b.minLng) * mPerDegLng,
          closeTo(2 * kLiveCourseDetectRadiusM, 1));
    });
  });
}
