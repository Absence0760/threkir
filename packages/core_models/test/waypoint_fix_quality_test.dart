import 'dart:convert';

import 'package:core_models/core_models.dart';
import 'package:test/test.dart';

void main() {
  group('Waypoint fix-quality fields', () {
    test('a pre-v1 track point without them still parses', () {
      final w = Waypoint.fromJson(<String, dynamic>{
        'lat': 47.37,
        'lng': 8.54,
        'elevationMetres': 400,
        'timestamp': '2026-04-10T10:00:00.000',
        'bpm': 150,
      });
      expect(w.lat, 47.37);
      expect(w.lng, 8.54);
      expect(w.elevationMetres, 400);
      expect(w.bpm, 150);
      expect(w.accuracyMetres, isNull);
      expect(w.speedMps, isNull);
      expect(w.speedAccuracyMps, isNull);
      expect(w.bearingDeg, isNull);
    });

    test('absent fields are omitted from the JSON, not written as null', () {
      final json = const Waypoint(lat: 1, lng: 2).toJson();
      expect(json.containsKey('accuracyMetres'), isFalse);
      expect(json.containsKey('speedMps'), isFalse);
      expect(json.containsKey('speedAccuracyMps'), isFalse);
      expect(json.containsKey('bearingDeg'), isFalse);
      expect(json.containsKey('lat'), isTrue);
      expect(json.containsKey('elevationMetres'), isTrue);
    });

    test('present fields round-trip through JSON', () {
      const w = Waypoint(
        lat: 1,
        lng: 2,
        accuracyMetres: 4.25,
        speedMps: 2.68,
        speedAccuracyMps: 0.41,
        bearingDeg: 359.5,
      );
      final back = Waypoint.fromJson(
        jsonDecode(jsonEncode(w.toJson())) as Map<String, dynamic>,
      );
      expect(back.accuracyMetres, 4.25);
      expect(back.speedMps, 2.68);
      expect(back.speedAccuracyMps, 0.41);
      expect(back.bearingDeg, 359.5);
    });

    test('integer-valued JSON numbers read as doubles', () {
      final w = Waypoint.fromJson(<String, dynamic>{
        'lat': 1,
        'lng': 2,
        'accuracyMetres': 5,
        'speedMps': 0,
        'speedAccuracyMps': 1,
        'bearingDeg': 90,
      });
      expect(w.accuracyMetres, 5.0);
      expect(w.speedMps, 0.0);
      expect(w.speedAccuracyMps, 1.0);
      expect(w.bearingDeg, 90.0);
    });

    test('a non-finite fix-quality field drops to null and keeps the point', () {
      final out = finiteWaypoints(const [
        Waypoint(
          lat: 1,
          lng: 2,
          accuracyMetres: double.nan,
          speedMps: double.infinity,
          speedAccuracyMps: 0.3,
          bearingDeg: double.nan,
        ),
      ]);
      expect(out, hasLength(1));
      expect(out.single.accuracyMetres, isNull);
      expect(out.single.speedMps, isNull);
      expect(out.single.speedAccuracyMps, 0.3);
      expect(out.single.bearingDeg, isNull);
      expect(jsonEncode(out.single.toJson()), isNot(contains('NaN')));
    });
  });
}
