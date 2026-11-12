import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:run_recorder/run_recorder.dart';

void main() {
  group('BaroAltitudeAnchor', () {
    test('nothing is stamped before a GPS altitude levels the barometer', () {
      final a = BaroAltitudeAnchor();
      expect(a.altitudeAt(0), isNull);
      a.addBarometer(0, 12);
      expect(a.anchored, isFalse);
      expect(a.altitudeAt(0), isNull);
    });

    test(
      'the first GPS altitude sets the level; the shape is the barometer',
      () {
        final a = BaroAltitudeAnchor()
          ..addBarometer(0, 0)
          ..addGps(0, 400, 5);
        expect(a.altitudeAt(0), 400);
        a.addBarometer(1, 3.5);
        expect(a.altitudeAt(1), 403.5);
      },
    );

    test('a GPS altitude without a barometer reading is not paired', () {
      final a = BaroAltitudeAnchor()..addGps(0, 400, 5);
      expect(a.anchored, isFalse);
    });

    test('an unrated or poorly rated GPS altitude is ignored', () {
      final a = BaroAltitudeAnchor()..addBarometer(0, 0);
      for (final acc in [0.0, -1.0, double.nan, double.infinity, 40.0]) {
        a.addGps(0, 400, acc);
      }
      expect(a.anchored, isFalse);
      a.addGps(0, 400, 25);
      expect(a.anchored, isTrue);
    });

    test('a stale barometer stamps nothing and pairs nothing', () {
      final a = BaroAltitudeAnchor()
        ..addBarometer(0, 0)
        ..addGps(0, 400, 5);
      expect(a.altitudeAt(5), 400);
      expect(a.altitudeAt(5.1), isNull);
      a.addGps(10, 900, 5);
      expect(a.offsetM, 400);
    });

    test('GPS noise averages out of the level instead of into the shape', () {
      // A flat run: the barometer reads 0 throughout while GPS altitude
      // scatters +/-15 m around a true 500 m. The fused altitude must stay
      // within a few metres of 500 once a few minutes have been averaged,
      // where the raw GPS series would have swung 30 m.
      final a = BaroAltitudeAnchor();
      final rng = math.Random(7);
      for (var t = 0; t < 600; t++) {
        a.addBarometer(t.toDouble(), 0);
        a.addGps(t.toDouble(), 500 + (rng.nextDouble() * 30 - 15), 10);
      }
      expect((a.altitudeAt(599)! - 500).abs(), lessThan(2));
    });

    test('before one time constant it is the plain mean of the samples', () {
      final a = BaroAltitudeAnchor()..addBarometer(0, 0);
      a.addGps(0, 100, 5);
      a.addBarometer(1, 0);
      a.addGps(1, 110, 5);
      a.addBarometer(2, 0);
      a.addGps(2, 120, 5);
      expect(a.offsetM, closeTo(110, 1e-9));
    });

    test(
      'after it, a step in GPS level is followed with the time constant',
      () {
        final a = BaroAltitudeAnchor(timeConstantS: 60);
        for (var t = 0; t <= 600; t++) {
          a.addBarometer(t.toDouble(), 0);
          a.addGps(t.toDouble(), 200, 5);
        }
        expect(a.offsetM, closeTo(200, 1e-9));
        for (var t = 601; t <= 660; t++) {
          a.addBarometer(t.toDouble(), 0);
          a.addGps(t.toDouble(), 210, 5);
        }
        // One time constant after a 10 m step: 1 - e^-1 of the way there.
        expect(a.offsetM, closeTo(200 + 10 * (1 - math.exp(-1)), 0.1));
      },
    );

    test('a non-finite barometer reading is dropped', () {
      final a = BaroAltitudeAnchor()
        ..addBarometer(0, 5)
        ..addBarometer(0.5, double.nan)
        ..addGps(1, 100, 5);
      expect(a.altitudeAt(1), 100);
      expect(a.offsetM, 95);
    });
  });
}
