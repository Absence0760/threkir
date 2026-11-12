// A run over a real park course is timed on that course and nowhere else
// (issue #1342 step 5c). The Dart reader of fixtures/park_course_runs.json,
// the case table the `segments` pair shares with
// apps/web/src/lib/parks/park_course_runs.test.ts: synthetic 1 Hz runs with
// realistic GPS error over the six committed Pocahontas course lines, each
// scored against all six courses at once.
//
// Each case is checked against what it is for (an effort within tolerance of
// the true elapsed time, or none) and against `matched`, what the web matcher
// gave it on every course, to the millisecond.

import 'dart:convert';
import 'dart:io';

import 'package:core_models/core_models.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/gate_crossing.dart';
import '../lib/segments.dart';

const _root = '../..';

Map<String, dynamic> _readJson(String path) =>
    jsonDecode(File('$_root/$path').readAsStringSync()) as Map<String, dynamic>;

List<Waypoint> _decode(Map<String, dynamic> track, DateTime base) {
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

Gate _gate(Map<String, dynamic> g) => Gate(
      lat: (g['lat'] as num).toDouble(),
      lng: (g['lng'] as num).toDouble(),
      bearingDeg: (g['bearing_deg'] as num).toDouble(),
      halfWidthM: (g['half_width_m'] as num).toDouble(),
    );

List<Waypoint> _points(Object? raw) => [
      for (final p in (raw as List).cast<Map<String, dynamic>>())
        Waypoint(
          lat: (p['lat'] as num).toDouble(),
          lng: (p['lng'] as num).toDouble(),
        ),
    ];

void main() {
  final fixture = _readJson('fixtures/park_course_runs.json');
  final base = DateTime.parse(fixture['base_time'] as String);
  final courses = (fixture['courses'] as List).cast<Map<String, dynamic>>();
  final cases = (fixture['cases'] as List).cast<Map<String, dynamic>>();
  final slugs = [for (final c in courses) c['slug'] as String];
  final geometries = [
    for (final c in courses)
      () {
        final gj = _readJson(c['geojson'] as String);
        final line = (gj['features'] as List)
            .cast<Map<String, dynamic>>()
            .firstWhere((f) => (f['geometry'] as Map)['type'] == 'LineString');
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
          startGate: _gate(c['start_gate'] as Map<String, dynamic>),
          endGate: _gate(c['end_gate'] as Map<String, dynamic>),
        );
      }(),
  ];
  Map<String, dynamic> caseBy(String key) =>
      cases.firstWhere((c) => c['key'] == key);

  for (final c in cases) {
    test('park course run: ${c['name']}', () {
      final track = _decode(c['track'] as Map<String, dynamic>, base);
      final results = computeGlobalSegmentEfforts(track, geometries);
      final own = results[slugs.indexOf(c['course'] as String)];
      final want = c['want'] as Map<String, dynamic>;
      if (want['effort'] == true) {
        expect(own, isNotNull, reason: c['why'] as String);
        expect(own!.matchedBy, GlobalSegmentMatchedBy.gate);
        final off = own.timeSeconds - (want['truth_s'] as num);
        expect(off.abs() <= (want['tolerance_s'] as num), isTrue,
            reason: 'timed ${own.timeSeconds} s against a true '
                '${want['truth_s']} s');
      } else {
        expect(own, isNull, reason: c['why'] as String);
      }
      final matched = c['matched'] as Map<String, dynamic>;
      for (var i = 0; i < slugs.length; i++) {
        final recorded = matched[slugs[i]] as Map<String, dynamic>?;
        final r = results[i];
        if (recorded == null) {
          expect(r, isNull, reason: '${slugs[i]}: timed ${r?.timeSeconds} s');
          continue;
        }
        expect(r, isNotNull, reason: '${slugs[i]}: no effort');
        expect(
          (r!.timeSeconds - (recorded['time_seconds'] as num)).abs() < 0.001,
          isTrue,
          reason: '${slugs[i]}: ${r.timeSeconds} vs ${recorded['time_seconds']}',
        );
        expect(r.startedAt.difference(base).inMilliseconds,
            recorded['started_offset_ms']);
        expect(r.matchedBy.name, recorded['matched_by']);
      }
    });
  }

  test('every course has a run of the net timed on it', () {
    for (final slug in slugs) {
      expect(
        cases.any((c) =>
            c['course'] == slug &&
            (c['want'] as Map)['effort'] == true &&
            (c['matched'] as Map).containsKey(slug)),
        isTrue,
        reason: slug,
      );
    }
  });

  for (final key in ['beaver_shortcut', 'beaver_cut']) {
    test(
        '$key is refused by the checkpoints alone: without them the same run '
        'is timed', () {
      final beaver = geometries[slugs.indexOf('beaver-lake-trail')];
      final track = _decode(caseBy(key)['track'] as Map<String, dynamic>, base);
      expect(computeGlobalSegmentEfforts(track, [beaver]).first, isNull);
      final unguarded = computeGlobalSegmentEfforts(track, [
        GlobalSegmentGeometry(
          points: beaver.points,
          distanceM: beaver.distanceM,
          startGate: beaver.startGate,
          endGate: beaver.endGate,
        ),
      ]).first;
      expect(unguarded, isNotNull);
      expect(unguarded!.matchedBy, GlobalSegmentMatchedBy.gate);
    });
  }

  // decisions § 2463: the evenly spaced half-mark checkpoint (1797 m) sat
  // 22 m from the straight cut from 1450 m to 2150 m, so the cut was timed.
  test(
      'the 1450 m to 2150 m cut was timed by the evenly spaced checkpoints, '
      'and is refused by the placed ones', () {
    final beaver = geometries[slugs.indexOf('beaver-lake-trail')];
    final cps = beaver.checkpoints;
    final track =
        _decode(caseBy('beaver_cut')['track'] as Map<String, dynamic>, base);
    final old = computeGlobalSegmentEfforts(track, [
      GlobalSegmentGeometry(
        points: beaver.points,
        distanceM: beaver.distanceM,
        checkpoints: [
          cps.first,
          const Waypoint(lat: 37.38116, lng: -77.591165),
          cps.last,
        ],
        startGate: beaver.startGate,
        endGate: beaver.endGate,
      ),
    ]).first;
    expect(old, isNotNull);
    expect(computeGlobalSegmentEfforts(track, [beaver]).first, isNull);
  });
}
