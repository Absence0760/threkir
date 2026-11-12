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

    test('a run\'s track keeps it through the local store\'s JSON', () {
      final run = Run(
        id: 'r1',
        startedAt: DateTime.utc(2026, 10, 15, 7),
        duration: const Duration(minutes: 30),
        distanceMetres: 5000,
        source: RunSource.app,
        track: const [
          Waypoint(
            lat: 1,
            lng: 2,
            elevationMetres: 412,
            baroElevationMetres: 405.25,
          ),
          Waypoint(lat: 1.001, lng: 2, elevationMetres: 398),
          Waypoint(
            lat: 1.002,
            lng: 2,
            elevationMetres: 420,
            baroElevationMetres: 409.5,
          ),
        ],
      );
      final back = Run.fromJson(
        jsonDecode(jsonEncode(run.toJson())) as Map<String, dynamic>,
      );
      expect(back.track.map((w) => w.baroElevationMetres), [
        405.25,
        null,
        409.5,
      ]);
      expect(back.track.map((w) => w.elevationMetres), [412, 398, 420]);
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
