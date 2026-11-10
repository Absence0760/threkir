import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:api_client/api_client.dart' show ApiClient;
import 'package:core_models/core_models.dart' show Waypoint;
import 'package:flutter_test/flutter_test.dart';

import '../lib/gate_crossing.dart';
import '../lib/race_finish.dart';
import 'race_finish_replay.dart';

/// The replay regression (#1304 § 6, step 2). The synthetic cases pin the
/// tool on every run; the last test replays the owner's own stored tracks
/// and runs only when `RACE_REPLAY_DIR` is set — real tracks are never in
/// this repository (docs/testing/manual_testing.md § Timing-line
/// calibration).

const _lat0 = 51.5;
const _lng0 = -0.1;
const _mPerDegLat = 6371008.8 * math.pi / 180;
final _mPerDegLng = _mPerDegLat * math.cos(_lat0 * math.pi / 180);
final _t0 = DateTime.utc(2026, 11, 10, 8);

/// A run due east at 4 m/s with a fix a second, [northM] off the axis.
List<Waypoint> _east(double toM, {double northM = 0}) => [
      for (var x = 0.0, s = 0; x <= toM; x += 4, s++)
        Waypoint(
          lat: _lat0 + northM / _mPerDegLat,
          lng: _lng0 + x / _mPerDegLng,
          timestamp: _t0.add(Duration(seconds: s)),
        ),
    ];

double _lngAt(double eastM) => _lng0 + eastM / _mPerDegLng;

void main() {
  group('replayFeed', () {
    test('keeps on-track fixes at their line position, once per instant', () {
      final t = _t0;
      final feed = replayFeed([
        Waypoint(lat: 51.5, lng: -0.1, timestamp: t),
        Waypoint(
            lat: 51.6,
            lng: -0.2,
            timestamp: t.add(const Duration(seconds: 1)),
            offTrack: true),
        Waypoint(
            lat: 51.5001,
            lng: -0.1,
            timestamp: t.add(const Duration(seconds: 2)),
            smoothedLat: 51.50012,
            smoothedLng: -0.1),
        Waypoint(lat: 51.5002, lng: -0.1, timestamp: t.add(const Duration(seconds: 2))),
        Waypoint(lat: 51.5003, lng: -0.1, timestamp: null),
        Waypoint(
            lat: 51.5004,
            lng: -0.1,
            timestamp: t.add(const Duration(seconds: 4)),
            cumulativeDistanceMetres: 99),
      ]);
      expect(feed, hasLength(3));
      expect(feed[1].lat, 51.50012, reason: 'the smoothed position');
      expect(feed[1].coveredM, closeTo(0.00012 * _mPerDegLat, 0.01));
      expect(feed[2].coveredM, 99, reason: "the track's own distM wins");
    });
  });

  group('replayRace', () {
    test('a clean finish: both detectors finish, the lines by the gate', () {
      final feed = replayFeed(_east(1100));
      final course = synthesizeCourse(feed)!;
      final v = replayRace(feed, course);
      expect(v.v1, isNotNull);
      expect(v.v2, isNotNull);
      expect(v.v2!.detection, RaceFinishDetection.gate);
      expect(v.regression, isFalse);
      expect(v.deltaS!.abs(), lessThan(1),
          reason: 'the closest approach and the crossing are the same place');
    });

    test('a pass 20 m beside the finish line is reported as a regression', () {
      // The course's lines are on the axis; the track runs 20 m north of it,
      // inside the 30 m circle and outside the 15 m half-width.
      final course = ReplayCourse(
        distanceM: 900,
        finishLat: _lat0,
        finishLng: _lngAt(1000),
        startGate: Gate(
            lat: _lat0, lng: _lngAt(50), bearingDeg: 90, halfWidthM: 30),
        finishGate: Gate(
            lat: _lat0, lng: _lngAt(1000), bearingDeg: 90, halfWidthM: 15),
      );
      final v = replayRace(replayFeed(_east(1100, northM: 20)), course);
      expect(v.v1, isNotNull);
      expect(v.v2, isNull);
      expect(v.regression, isTrue);
    });

    test('a finish line the route crosses early gets no v2 auto-finish', () {
      final feed = replayFeed(_east(1100));
      final c = synthesizeCourse(feed)!;
      final v = replayRace(
        feed,
        ReplayCourse(
          distanceM: c.distanceM,
          finishLat: c.finishLat,
          finishLng: c.finishLng,
          startGate: c.startGate,
          finishGate: c.finishGate,
          finishLineSelfCross: true,
        ),
      );
      expect(v.regression, isTrue, reason: 'it finishes by hand only');
    });

    test('v1 sees nothing before GO', () {
      final feed = replayFeed(_east(1100));
      final course = synthesizeCourse(feed)!;
      final v = replayRace(feed, course,
          goAt: _t0.add(const Duration(hours: 1)));
      expect(v.v1, isNull);
      expect(v.regression, isFalse);
    });

    test('a track too short for two lines has no synthetic course', () {
      expect(synthesizeCourse(replayFeed(_east(200))), isNull);
    });
  });

  group('cases.json', () {
    test('reads the documented query row', () {
      final c = ReplayCase.fromJson(jsonDecode('''{
        "run_id": "r1", "start_mode": "self_timed",
        "started_at": "2026-11-01T08:00:00Z", "distance_m": 5000,
        "finish_lat": 51.5, "finish_lng": -0.03, "finish_line_self_cross": false,
        "start_gate_lat": 51.5, "start_gate_lng": -0.1,
        "start_gate_bearing_deg": 90, "start_gate_half_width_m": 15,
        "finish_gate_lat": null, "finish_gate_lng": null,
        "finish_gate_bearing_deg": null, "finish_gate_half_width_m": null
      }'''))!;
      expect(c.runId, 'r1');
      expect(c.selfTimed, isTrue);
      expect(c.goAt, DateTime.utc(2026, 11, 1, 8));
      expect(c.course.startGate!.bearingDeg, 90);
      expect(c.course.finishGate, isNull);
      expect(ReplayCase.fromJson({'run_id': 'r2'}), isNull);
    });
  });

  test('the report carries no coordinate', () {
    final feed = replayFeed(_east(1100));
    final csv = replayReportCsv([
      (id: 'run-a', synthetic: true, verdict: replayRace(feed, synthesizeCourse(feed)!)),
    ]);
    expect(csv.split('\n').first,
        'case,course,v1_finished,v2_finished,v2_detection,delta_s,regression');
    expect(csv, startsWith(
        'case,course,v1_finished,v2_finished,v2_detection,delta_s,regression\n'
        'run-a,synthetic,1,1,gate,'));
    for (final leak in ['51.5', '-0.1', '2026']) {
      expect(csv, isNot(contains(leak)));
    }
  });

  final replayDir = Platform.environment['RACE_REPLAY_DIR'];
  test(
    "the owner's stored tracks: no finish the circle caught is lost to the lines",
    () {
      final dir = Directory(replayDir!);
      final cases = <String, ReplayCase>{};
      final casesFile = File('${dir.path}/cases.json');
      if (casesFile.existsSync()) {
        for (final j in jsonDecode(casesFile.readAsStringSync()) as List) {
          final c = ReplayCase.fromJson(j);
          if (c != null) cases[c.runId] = c;
        }
      }
      final synth = Platform.environment['RACE_REPLAY_SYNTH'] != '0';
      final rows = <({String id, bool synthetic, ReplayVerdict verdict})>[];
      var unreadable = 0;
      for (final f in Directory('${dir.path}/tracks').listSync()) {
        if (f is! File) continue;
        final name = f.uri.pathSegments.last;
        final id = name.split('.').first;
        List<Waypoint> track;
        try {
          track = name.endsWith('.gz')
              ? ApiClient.decodeTrackBlob(f.readAsBytesSync())
              : ApiClient.debugDecodeTrack(f.readAsBytesSync());
        } catch (_) {
          unreadable++;
          continue;
        }
        final feed = replayFeed(track);
        final c = cases[id];
        if (c != null) {
          rows.add((
            id: id,
            synthetic: false,
            verdict: replayRace(feed, c.course,
                goAt: c.goAt, selfTimed: c.selfTimed),
          ));
        } else if (synth) {
          final course = synthesizeCourse(feed);
          if (course == null) continue;
          rows.add((id: id, synthetic: true, verdict: replayRace(feed, course)));
        }
      }
      final csv = replayReportCsv(rows);
      final out = Platform.environment['RACE_REPLAY_OUT'];
      if (out != null) File(out).writeAsStringSync(csv);
      final lost = [
        for (final r in rows)
          if (r.verdict.regression) '${r.id} (${r.synthetic ? 'synthetic' : 'race'})',
      ];
      final both = rows.where((r) => r.verdict.deltaS != null).length;
      // ignore: avoid_print
      print('replayed ${rows.length} tracks (${rows.where((r) => !r.synthetic).length} '
          'raced courses), $both finished by both, ${lost.length} lost by v2, '
          '$unreadable unreadable');
      expect(lost, isEmpty,
          reason: 'v1 finished these and v2 does not: ${lost.join(', ')}');
    },
    skip: replayDir == null
        ? 'set RACE_REPLAY_DIR to replay your own stored tracks'
        : false,
  );
}
