import 'dart:convert';

import 'package:core_models/core_models.dart';
import 'package:test/test.dart';

// A fix the estimator took past the recorder's track gate
// (docs/features/gps_distance.md § Stored track).
void main() {
  group('Waypoint.offTrack', () {
    test('defaults to false and is serialised only when true', () {
      const onTrack = Waypoint(lat: 1, lng: 2);
      expect(onTrack.offTrack, isFalse);
      expect(onTrack.toJson().containsKey('offTrack'), isFalse);

      const off = Waypoint(lat: 1, lng: 2, offTrack: true);
      final json = off.toJson();
      expect(json['offTrack'], isTrue);
      final back = Waypoint.fromJson(
        jsonDecode(jsonEncode(json)) as Map<String, dynamic>,
      );
      expect(back.offTrack, isTrue);
    });

    test('a stored fix from before the flag, or one carrying false, is on track',
        () {
      expect(Waypoint.fromJson(const {'lat': 1.0, 'lng': 2.0}).offTrack,
          isFalse);
      expect(
        Waypoint.fromJson(const {'lat': 1.0, 'lng': 2.0, 'offTrack': false})
            .offTrack,
        isFalse,
      );
      expect(
        Waypoint.fromJson(const {'lat': 1.0, 'lng': 2.0, 'offTrack': 'yes'})
            .offTrack,
        isFalse,
      );
    });

    test('every with* helper keeps it', () {
      const w = Waypoint(lat: 1, lng: 2, offTrack: true);
      expect(w.withSmoothedPosition(1.00001, 2.00002).offTrack, isTrue);
      expect(w.withCumulativeDistance(40).offTrack, isTrue);
      expect(w.withOffTrack(false).offTrack, isFalse);
      final marked = const Waypoint(
        lat: 1,
        lng: 2,
        accuracyMetres: 35,
        cumulativeDistanceMetres: 12,
      ).withOffTrack(true);
      expect(marked.offTrack, isTrue);
      expect(marked.accuracyMetres, 35);
      expect(marked.cumulativeDistanceMetres, 12);
    });

    test('finiteWaypoints keeps it on a point it rebuilds', () {
      final out = finiteWaypoints(const [
        Waypoint(lat: 1, lng: 2, accuracyMetres: double.nan, offTrack: true),
        Waypoint(lat: 1, lng: 2),
      ]);
      expect(out[0].accuracyMetres, isNull);
      expect(out[0].offTrack, isTrue);
      expect(out[1].offTrack, isFalse);
    });
  });

  group('trackLine', () {
    test('drops off-track points and keeps the order of the rest', () {
      const a = Waypoint(lat: 1, lng: 1);
      const b = Waypoint(lat: 2, lng: 2, offTrack: true);
      const c = Waypoint(lat: 3, lng: 3);
      expect(trackLine(const [a, b, c]), [a, c]);
    });

    test('returns the same list when nothing is flagged', () {
      const track = [Waypoint(lat: 1, lng: 1), Waypoint(lat: 2, lng: 2)];
      expect(identical(trackLine(track), track), isTrue);
    });
  });
}
