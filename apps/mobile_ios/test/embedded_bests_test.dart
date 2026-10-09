// Persona-hunt Round 2 finding Pro #4 — embedded-best metadata
// enrichment writes per-canonical-distance fastest times into
// runs.metadata so the SQL trigger can include them in
// personal_records alongside whole-run candidates.

import 'dart:math' as math;

import 'package:core_models/core_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:run_recorder/run_recorder.dart' show GpsFixEvent, smoothDistance;
import '../lib/embedded_bests.dart';
import '../lib/run_stats.dart';

// Build a constant-speed track 5050 m long over 1170 s — the fastest
// 5k window inside should clock exactly 1170 * (5000 / 5050) ≈ 1158
// seconds (the rolling window covers 5000 m at the same constant
// speed).
List<Waypoint> _constantSpeedTrack({
  required double totalMetres,
  required int totalSeconds,
  required int points,
}) {
  // East-only at ~3 m steps. Latitudes are approximated; the helper's
  // distance math is haversine which handles this fine.
  final track = <Waypoint>[];
  final stepMetres = totalMetres / (points - 1);
  // 1 degree of longitude at equator ≈ 111_320 m
  final stepDeg = stepMetres / 111320.0;
  final stepSeconds = totalSeconds / (points - 1);
  for (var i = 0; i < points; i++) {
    track.add(Waypoint(
      lat: 0,
      lng: i * stepDeg,
      timestamp: DateTime.utc(2026, 4, 1).add(
        Duration(milliseconds: (i * stepSeconds * 1000).round()),
      ),
    ));
  }
  return track;
}

void main() {
  group('enrichMetadataWithEmbeddedBests', () {
    test('null metadata + sub-3-point track returns null unchanged', () {
      expect(
        enrichMetadataWithEmbeddedBests(
          track: const [],
          metadata: null,
        ),
        isNull,
      );
    });

    test('< 3 waypoints leaves metadata untouched', () {
      final out = enrichMetadataWithEmbeddedBests(
        track: const [],
        metadata: {'activity_type': 'run'},
      );
      expect(out, {'activity_type': 'run'});
    });

    test('a long track writes the per-distance fastest_X_s keys', () {
      // 6 km @ 4:00/km — fastest 5k = 1200s. Anything past 5k that's
      // shorter than 10k → only 5k key written.
      final track = _constantSpeedTrack(
        totalMetres: 6000,
        totalSeconds: 1440,
        points: 200,
      );
      final out = enrichMetadataWithEmbeddedBests(
        track: track,
        metadata: {'activity_type': 'run'},
      );
      expect(out!['activity_type'], 'run');
      expect(out.containsKey('fastest_5k_s'), isTrue);
      final s = out['fastest_5k_s'] as int;
      // Allow a small slack — haversine + sub-step interpolation
      // means we won't hit 1200 exactly.
      expect(s > 1180 && s < 1220, isTrue,
          reason: 'fastest_5k_s should be ≈ 1200 s for 4:00/km, got $s');
      expect(out.containsKey('fastest_10k_s'), isFalse);
      expect(out.containsKey('fastest_marathon_s'), isFalse);
    });

    test('preserves a faster existing manual override', () {
      // Computed best for the track is some value; the runner has a
      // manually-edited 1100 (sub-19) that's actually faster. Auto
      // result must NOT clobber the manual override.
      final track = _constantSpeedTrack(
        totalMetres: 6000,
        totalSeconds: 1440,
        points: 200,
      );
      final out = enrichMetadataWithEmbeddedBests(
        track: track,
        metadata: {'fastest_5k_s': 1100},
      );
      expect(out!['fastest_5k_s'], 1100,
          reason: 'a faster existing value wins');
    });

    test('clobbers a slower existing value with the computed one', () {
      final track = _constantSpeedTrack(
        totalMetres: 6000,
        totalSeconds: 1440,
        points: 200,
      );
      final out = enrichMetadataWithEmbeddedBests(
        track: track,
        metadata: {'fastest_5k_s': 9999},
      );
      final s = out!['fastest_5k_s'] as int;
      expect(s < 1500, isTrue,
          reason: 'a slower existing value is overwritten with the auto value, got $s');
    });
  });

  group('estimator cumulative', () {
    const mPerDeg = 6371000 * math.pi / 180;

    test('GPS zig-zag no longer closes the 5k window early', () {
      // 6 km due east at 5:00/km, one fix a second, each fix 2 m either
      // side of the line: the hop-sum reads ~9.4 km and its 5k ~960 s.
      final start = DateTime.utc(2026, 4, 1);
      final track = <Waypoint>[
        for (var i = 0; i <= 1800; i++)
          Waypoint(
            lat: (i.isOdd ? 2.0 : -2.0) / mPerDeg,
            lng: i * (6000 / 1800) / mPerDeg,
            timestamp: start.add(Duration(seconds: i)),
          ),
      ];
      final raw = fastestWindowOf(track, 5000)!.inSeconds;
      expect(raw, lessThan(1100), reason: 'fixture must be noisy, got $raw');
      final out = enrichMetadataWithEmbeddedBests(
        track: track,
        metadata: {'activity_type': 'run'},
      );
      final s = out!['fastest_5k_s'] as int;
      expect(s, inInclusiveRange(1480, 1520));
    });

    test('cumulative is non-decreasing and carries over untimestamped points',
        () {
      final start = DateTime.utc(2026, 4, 1);
      final track = <Waypoint>[
        for (var i = 0; i <= 20; i++)
          Waypoint(
            lat: 0,
            lng: i * 3 / mPerDeg,
            timestamp: i == 10 ? null : start.add(Duration(seconds: i)),
          ),
      ];
      final cum = estimatorCumulativeMetres(track);
      expect(cum.length, track.length);
      expect(cum.first, 0);
      for (var i = 1; i < cum.length; i++) {
        expect(cum[i], greaterThanOrEqualTo(cum[i - 1]));
      }
      expect(cum[10], cum[9]);
    });

    test('cumulative is the smoothed distance a saved run carries', () {
      // Not the forward filter the live screen shows: the smoother the
      // recorder saves with and the server recompute writes.
      final start = DateTime.utc(2026, 4, 1);
      final track = <Waypoint>[
        for (var i = 0; i <= 300; i++)
          Waypoint(
            lat: (i.isOdd ? 2 : -2) / mPerDeg,
            lng: i * 3 / mPerDeg,
            timestamp: start.add(Duration(seconds: i)),
          ),
      ];
      final cum = estimatorCumulativeMetres(track);
      final smoothed = smoothDistance([
        for (var i = 0; i < track.length; i++)
          GpsFixEvent(t: i.toDouble(), lat: track[i].lat, lng: track[i].lng),
      ]).cumulativeM;
      expect(cum.length, track.length);
      for (var i = 0; i < cum.length; i++) {
        expect(cum[i], closeTo(smoothed[i], 1e-9), reason: 'point $i');
      }
    });

    test('medianFixIntervalS takes the median positive interval', () {
      final start = DateTime.utc(2026, 4, 1);
      Waypoint at(int s) =>
          Waypoint(lat: 0, lng: 0, timestamp: start.add(Duration(seconds: s)));
      expect(medianFixIntervalS(const []), 1.0);
      expect(
        medianFixIntervalS([
          at(0),
          at(1),
          at(1),
          const Waypoint(lat: 0, lng: 0),
          at(2),
          at(7),
          at(67),
        ]),
        3.0,
      );
    });
  });
}
