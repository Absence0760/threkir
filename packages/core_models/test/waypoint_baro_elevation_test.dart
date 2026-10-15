import 'dart:convert';

import 'package:core_models/core_models.dart';
import 'package:test/test.dart';

// The fused barometric altitude the phone recorder stamps beside the GPS
// altitude (docs/features/gps_distance.md § Waypoint fields).
void main() {
  group('Waypoint barometric altitude', () {
    test('round-trips through JSON and is omitted when absent', () {
      const w = Waypoint(
        lat: 1,
        lng: 2,
        elevationMetres: 120,
        baroElevationMetres: 117.5,
      );
      final back = Waypoint.fromJson(
        jsonDecode(jsonEncode(w.toJson())) as Map<String, dynamic>,
      );
      expect(back.elevationMetres, 120);
      expect(back.baroElevationMetres, 117.5);
      expect(
        const Waypoint(
          lat: 1,
          lng: 2,
        ).toJson().containsKey('baroElevationMetres'),
        isFalse,
      );
    });

    test('withSmoothedPosition keeps it', () {
      const w = Waypoint(lat: 1, lng: 2, baroElevationMetres: 88);
      expect(w.withSmoothedPosition(1.00001, 2.00002).baroElevationMetres, 88);
    });

    test('finiteWaypoints drops a non-finite one and keeps the point', () {
      final out = finiteWaypoints(const [
        Waypoint(
          lat: 1,
          lng: 2,
          elevationMetres: 50,
          baroElevationMetres: double.infinity,
        ),
        Waypoint(lat: 1, lng: 2, baroElevationMetres: 51),
      ]);
      expect(out, hasLength(2));
      expect(out[0].baroElevationMetres, isNull);
      expect(out[0].elevationMetres, 50);
      expect(out[1].baroElevationMetres, 51);
    });
  });
}
