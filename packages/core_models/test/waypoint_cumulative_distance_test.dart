import 'dart:convert';

import 'package:core_models/core_models.dart';
import 'package:test/test.dart';

// The recorder's cumulative credited distance per stored fix
// (docs/features/gps_distance.md § Waypoint fields).
void main() {
  group('Waypoint cumulative distance', () {
    test('round-trips through JSON and is omitted when absent', () {
      const w = Waypoint(lat: 1, lng: 2, cumulativeDistanceMetres: 1234.56);
      final back = Waypoint.fromJson(
        jsonDecode(jsonEncode(w.toJson())) as Map<String, dynamic>,
      );
      expect(back.cumulativeDistanceMetres, 1234.56);
      expect(
        const Waypoint(lat: 1, lng: 2)
            .toJson()
            .containsKey('cumulativeDistanceMetres'),
        isFalse,
      );
    });

    test('withSmoothedPosition keeps it and withCumulativeDistance sets it',
        () {
      const w = Waypoint(
        lat: 1,
        lng: 2,
        baroElevationMetres: 88,
        cumulativeDistanceMetres: 10,
      );
      expect(
        w.withSmoothedPosition(1.00001, 2.00002).cumulativeDistanceMetres,
        10,
      );
      final moved = w
          .withSmoothedPosition(1.00001, 2.00002)
          .withCumulativeDistance(12.5);
      expect(moved.cumulativeDistanceMetres, 12.5);
      expect(moved.smoothedLat, 1.00001);
      expect(moved.baroElevationMetres, 88);
      expect(w.withCumulativeDistance(null).cumulativeDistanceMetres, isNull);
    });

    test('finiteWaypoints drops a non-finite one and keeps the point', () {
      final out = finiteWaypoints(const [
        Waypoint(lat: 1, lng: 2, cumulativeDistanceMetres: double.nan),
        Waypoint(lat: 1, lng: 2, cumulativeDistanceMetres: 51),
      ]);
      expect(out, hasLength(2));
      expect(out[0].cumulativeDistanceMetres, isNull);
      expect(out[1].cumulativeDistanceMetres, 51);
    });
  });
}
