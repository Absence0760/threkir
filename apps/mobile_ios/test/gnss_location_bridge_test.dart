import 'package:flutter_test/flutter_test.dart';

import '../lib/gnss_location_bridge.dart';

void main() {
  group('positionFromGnssEvent', () {
    test('carries every reading the receiver reported', () {
      final p = positionFromGnssEvent({
        'lat': 37.5,
        'lng': -77.25,
        'timeMs': 1792000000000,
        'mocked': false,
        'accuracy': 3.8,
        'altitude': 41.0,
        'altitudeAccuracy': 6.0,
        'speed': 2.25,
        'speedAccuracy': 0.15,
        'bearing': 123.0,
        'bearingAccuracy': 9.0,
      });
      expect(p.latitude, 37.5);
      expect(p.longitude, -77.25);
      expect(
        p.timestamp,
        DateTime.fromMillisecondsSinceEpoch(1792000000000, isUtc: true),
      );
      expect(p.accuracy, 3.8);
      expect(p.altitude, 41.0);
      expect(p.altitudeAccuracy, 6.0);
      expect(p.speed, 2.25);
      expect(p.speedAccuracy, 0.15);
      expect(p.heading, 123.0);
      expect(p.headingAccuracy, 9.0);
      expect(p.isMocked, isFalse);
    });

    test('an unreported speed or bearing is NaN, not a measured zero', () {
      // The recorder's fix-quality check reads speed 0 with no accuracy as
      // "not measured"; NaN keeps a genuine standstill distinguishable.
      final p = positionFromGnssEvent({
        'lat': 1.0,
        'lng': 2.0,
        'timeMs': 0,
        'mocked': true,
      });
      expect(p.speed.isNaN, isTrue);
      expect(p.heading.isNaN, isTrue);
      expect(p.accuracy, 0);
      expect(p.speedAccuracy, 0);
      expect(p.altitudeAccuracy, 0);
      expect(p.isMocked, isTrue);
    });

    test('integer-typed numbers from the channel are accepted', () {
      final p = positionFromGnssEvent({
        'lat': 10,
        'lng': 20,
        'timeMs': 5,
        'speed': 3,
        'accuracy': 4,
      });
      expect(p.latitude, 10.0);
      expect(p.speed, 3.0);
      expect(p.accuracy, 4.0);
    });
  });

  group('gnssStatusSampleFromEvent', () {
    test('reduces the used satellites the bridge sent', () {
      final s = gnssStatusSampleFromEvent({
        'cn0DbHz': [41.0, 38, 44.0, 22.0, 35.0],
        'carrierHz': [1575.42e6, 1575.42e6, 1176.45e6, 0.0, 1561.098e6],
      });
      expect(s.usedInFix, 5);
      expect(s.meanTopCn0DbHz, closeTo(39.5, 1e-9));
      expect(s.l5Used, isTrue);
    });

    test('an empty or missing list is a reading with no fix', () {
      for (final e in [
        <Object?, Object?>{'cn0DbHz': <Object?>[], 'carrierHz': <Object?>[]},
        <Object?, Object?>{},
      ]) {
        final s = gnssStatusSampleFromEvent(e);
        expect(s.usedInFix, 0);
        expect(s.meanTopCn0DbHz, isNull);
        expect(s.l5Used, isFalse);
      }
    });
  });
}

