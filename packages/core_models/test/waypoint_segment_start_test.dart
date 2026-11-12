import 'dart:convert';

import 'package:core_models/core_models.dart';
import 'package:test/test.dart';

// The first fix of a watch run's segment after its first
// (docs/features/gps_distance.md § Stored track, spec v1.8).
void main() {
  group('Waypoint.segmentStart', () {
    test('defaults to false and is serialised only when true', () {
      const plain = Waypoint(lat: 1, lng: 2);
      expect(plain.segmentStart, isFalse);
      expect(plain.toJson().containsKey('segmentStart'), isFalse);

      const first = Waypoint(lat: 1, lng: 2, segmentStart: true);
      final json = first.toJson();
      expect(json['segmentStart'], isTrue);
      final back = Waypoint.fromJson(
        jsonDecode(jsonEncode(json)) as Map<String, dynamic>,
      );
      expect(back.segmentStart, isTrue);
      expect(back.offTrack, isFalse);
    });

    test('a stored fix from before the mark, or one carrying false, starts none',
        () {
      expect(Waypoint.fromJson(const {'lat': 1.0, 'lng': 2.0}).segmentStart,
          isFalse);
      expect(
        Waypoint.fromJson(const {'lat': 1.0, 'lng': 2.0, 'segmentStart': false})
            .segmentStart,
        isFalse,
      );
      expect(
        Waypoint.fromJson(const {'lat': 1.0, 'lng': 2.0, 'segmentStart': 1})
            .segmentStart,
        isFalse,
      );
    });

    test('every with* helper and finiteWaypoints keep it', () {
      const w = Waypoint(lat: 1, lng: 2, segmentStart: true);
      expect(w.withSmoothedPosition(1.00001, 2.00002).segmentStart, isTrue);
      expect(w.withCumulativeDistance(40).segmentStart, isTrue);
      expect(w.withOffTrack(true).segmentStart, isTrue);
      final out = finiteWaypoints(const [
        Waypoint(lat: 1, lng: 2, accuracyMetres: double.nan, segmentStart: true),
        Waypoint(lat: 1, lng: 2),
      ]);
      expect(out[0].accuracyMetres, isNull);
      expect(out[0].segmentStart, isTrue);
      expect(out[1].segmentStart, isFalse);
    });

    test('the line keeps a segment-start fix', () {
      const a = Waypoint(lat: 1, lng: 1);
      const b = Waypoint(lat: 2, lng: 2, segmentStart: true);
      const c = Waypoint(lat: 3, lng: 3, offTrack: true);
      expect(trackLine(const [a, b, c]), [a, b]);
    });
  });
}
