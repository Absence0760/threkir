// Embedded bests prefer the file's own per-waypoint distance stream (FIT
// `record.distance`) over re-estimating from positions, and fall back to the
// estimator when the stream cannot stand in for it (issue #1090 item 7a).
// Lockstep with apps/web/src/lib/integrations/device_distance_stream.test.ts.

import 'package:core_models/core_models.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/embedded_bests.dart';

const _mPerDeg = 6371000 * 3.141592653589793 / 180;

/// 6 km due east at 5:00/km: 100 m per 30 s.
List<Waypoint> _evenTrack() => List.generate(
      61,
      (i) => Waypoint(
        lat: 0,
        lng: i * 100 / _mPerDeg,
        timestamp: DateTime.utc(2026, 1, 1, 9).add(Duration(seconds: i * 30)),
      ),
    );

void main() {
  test('deviceCumulativeMetres rebases a monotonic stream to the first point',
      () {
    expect(deviceCumulativeMetres([12, 12, 40.5, 100], 4), [0, 0, 28.5, 88]);
  });

  test('deviceCumulativeMetres refuses a stream that cannot stand in', () {
    expect(deviceCumulativeMetres(null, 3), isNull);
    expect(deviceCumulativeMetres([0, 10], 3), isNull);
    expect(deviceCumulativeMetres([0], 1), isNull);
    expect(deviceCumulativeMetres([0, double.nan, 20], 3), isNull);
    expect(deviceCumulativeMetres([0, double.infinity, 20], 3), isNull);
    expect(deviceCumulativeMetres([0, null, 20], 3), isNull);
    expect(deviceCumulativeMetres([-1, 0, 20], 3), isNull);
    expect(deviceCumulativeMetres([0, 30, 20], 3), isNull);
    expect(deviceCumulativeMetres([0, 0, 0], 3), isNull);
    expect(deviceCumulativeMetres([55, 55, 55], 3), isNull);
  });

  test('embedded bests are measured on a valid device stream', () {
    // The stream reads 200 m per 30 s (12 km) over a 6 km track: an exact
    // 750 s 5k and 1500 s 10k, where the estimator alone finds no 10k.
    final track = _evenTrack();
    final out = enrichMetadataWithEmbeddedBests(
      track: track,
      deviceDistancesMetres: List.generate(track.length, (i) => i * 200.0),
    )!;
    expect(out['fastest_5k_s'], 750);
    expect(out['fastest_10k_s'], 1500);
  });

  test('an invalid device stream falls back to the estimator', () {
    final track = _evenTrack();
    final estimated = enrichMetadataWithEmbeddedBests(track: track)!;
    expect(estimated.containsKey('fastest_10k_s'), isFalse);
    for (final bad in <List<double?>>[
      List.generate(track.length, (i) => i == 30 ? null : i * 200.0),
      List.generate(track.length, (i) => i == 30 ? double.nan : i * 200.0),
      List.generate(track.length, (i) => i == 30 ? 0 : i * 200.0),
      List.filled(track.length, 0),
      [0, 200],
    ]) {
      expect(
        enrichMetadataWithEmbeddedBests(
          track: track,
          deviceDistancesMetres: bad,
        ),
        estimated,
      );
    }
  });
}
