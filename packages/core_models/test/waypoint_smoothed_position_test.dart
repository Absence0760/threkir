import 'dart:convert';

import 'package:core_models/core_models.dart';
import 'package:test/test.dart';

// The smoothed position the GPS distance smoother writes onto a saved track
// (docs/features/gps_distance.md § Waypoint fields).
void main() {
  group('Waypoint smoothed position', () {
    test('the line reads the smoothed pair when both halves are present', () {
      const w = Waypoint(
        lat: 1,
        lng: 2,
        smoothedLat: 1.00001,
        smoothedLng: 2.00002,
      );
      expect(w.hasSmoothedPosition, isTrue);
      expect(w.lineLat, 1.00001);
      expect(w.lineLng, 2.00002);
      expect(w.lat, 1);
      expect(w.lng, 2);
    });

    test('a missing, half or non-finite pair falls back to the raw fix', () {
      for (final w in const [
        Waypoint(lat: 1, lng: 2),
        Waypoint(lat: 1, lng: 2, smoothedLat: 1.00001),
        Waypoint(lat: 1, lng: 2, smoothedLng: 2.00002),
        Waypoint(lat: 1, lng: 2, smoothedLat: double.nan, smoothedLng: 2.00002),
        Waypoint(
            lat: 1, lng: 2, smoothedLat: 1.00001, smoothedLng: double.infinity),
      ]) {
        expect(w.hasSmoothedPosition, isFalse);
        expect(w.lineLat, 1);
        expect(w.lineLng, 2);
      }
    });

    test('round-trips through JSON and is omitted when absent', () {
      const w = Waypoint(
        lat: 1,
        lng: 2,
        speedMps: 2.5,
        smoothedLat: 1.00001,
        smoothedLng: 2.00002,
      );
      final back = Waypoint.fromJson(
        jsonDecode(jsonEncode(w.toJson())) as Map<String, dynamic>,
      );
      expect(back.smoothedLat, 1.00001);
      expect(back.smoothedLng, 2.00002);
      final bare = const Waypoint(lat: 1, lng: 2).toJson();
      expect(bare.containsKey('smoothedLat'), isFalse);
      expect(bare.containsKey('smoothedLng'), isFalse);
    });

    test('withSmoothedPosition keeps every other field', () {
      final t = DateTime.utc(2026, 4, 1);
      final w = Waypoint(
        lat: 1,
        lng: 2,
        elevationMetres: 30,
        timestamp: t,
        bpm: 150,
        accuracyMetres: 4,
        speedMps: 2.5,
        speedAccuracyMps: 0.4,
        bearingDeg: 90,
      ).withSmoothedPosition(1.00001, 2.00002);
      expect(w.smoothedLat, 1.00001);
      expect(w.smoothedLng, 2.00002);
      expect(w.elevationMetres, 30);
      expect(w.timestamp, t);
      expect(w.bpm, 150);
      expect(w.accuracyMetres, 4);
      expect(w.speedMps, 2.5);
      expect(w.speedAccuracyMps, 0.4);
      expect(w.bearingDeg, 90);
    });

    test('finiteWaypoints drops a non-finite pair as a whole', () {
      final out = finiteWaypoints(const [
        Waypoint(lat: 1, lng: 2, smoothedLat: double.nan, smoothedLng: 2.0),
        Waypoint(lat: 1, lng: 2, smoothedLat: 1.0, smoothedLng: 2.0),
      ]);
      expect(out, hasLength(2));
      expect(out[0].smoothedLat, isNull);
      expect(out[0].smoothedLng, isNull);
      expect(out[1].smoothedLat, 1.0);
      expect(out[1].smoothedLng, 2.0);
    });
  });
}
