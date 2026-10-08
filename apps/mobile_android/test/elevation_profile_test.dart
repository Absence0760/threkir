import 'package:core_models/core_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/elevation_profile.dart';

/// Mirror of `apps/web/src/lib/runs/elevation_profile.test.ts`, plus the
/// `elevationSeries` cases whose web half lives in `key_stats.test.ts`.
void main() {
  List<double> evenSpacing(int n, double stepM) =>
      [for (var i = 0; i < n; i++) i * stepM];

  group('smoothElevation', () {
    test('keeps a constant series constant', () {
      final out = smoothElevation(List.filled(50, 120.0), evenSpacing(50, 3));
      for (final v in out) {
        expect(v, closeTo(120, 1e-9));
      }
    });

    test('flattens per-fix altitude jitter', () {
      final series = [for (var i = 0; i < 200; i++) i.isEven ? 102.0 : 98.0];
      final out = smoothElevation(series, evenSpacing(200, 3));
      for (final v in out.sublist(20, 180)) {
        expect(v, closeTo(100, 0.2));
      }
    });

    test('a window wider than the track averages the whole track', () {
      final out = smoothElevation([10, 20, 30], [0, 5, 10], halfWindowM: 1000);
      expect(out, [20, 20, 20]);
    });

    test('keeps one value per point', () {
      expect(smoothElevation([1, 2, 3, 4], evenSpacing(4, 50)).length, 4);
    });
  });

  group('elevationDomain', () {
    test('a flat run is drawn at least 30 m tall, centred', () {
      final d = elevationDomain(100, 104);
      expect(d.hi - d.lo, closeTo(36, 1e-9));
      expect((d.hi + d.lo) / 2, closeTo(102, 1e-9));
    });

    test('a hilly run gets 10 % headroom each side', () {
      final d = elevationDomain(200, 700);
      expect(d.lo, closeTo(150, 1e-9));
      expect(d.hi, closeTo(750, 1e-9));
    });
  });

  test('cumulativeMetres starts at zero and only grows', () {
    final track = [
      for (var i = 0; i < 5; i++) Waypoint(lat: 37 + i * 0.001, lng: -122),
    ];
    final cum = cumulativeMetres(track);
    expect(cum.first, 0);
    for (var i = 1; i < cum.length; i++) {
      expect(cum[i], greaterThan(cum[i - 1]));
    }
  });

  group('elevationSeries', () {
    Waypoint at(int i, double? ele) =>
        Waypoint(lat: 37 + i * 0.001, lng: -122, elevationMetres: ele);

    test('fills an interior gap linearly instead of with sea level', () {
      final out = elevationSeries([at(0, 100), at(1, null), at(2, null), at(3, 130)]);
      expect(out, [100, 110, 120, 130]);
    });

    test('carries the nearest sample across leading and trailing gaps', () {
      final out = elevationSeries([at(0, null), at(1, 50), at(2, 60), at(3, null)]);
      expect(out, [50, 50, 60, 60]);
    });

    test('is null with fewer than two real samples', () {
      expect(elevationSeries([at(0, null), at(1, 50), at(2, null)]), isNull);
      expect(elevationSeries([at(0, 50)]), isNull);
    });
  });
}
