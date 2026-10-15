import 'package:core_models/core_models.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/route_simplify.dart';
import '../lib/run_altitude.dart';

// Twin of apps/web/src/lib/runs/run_altitude.test.ts; keep the shared cases in
// lockstep. The loss and live-accumulator groups are mobile-only, as their
// helpers are.
void main() {
  Waypoint pt(int i, [double? ele, double? baroEle]) => Waypoint(
    lat: 47.37,
    lng: 8.54 + i * 0.0001,
    elevationMetres: ele,
    baroElevationMetres: baroEle,
  );

  // GPS altitude wandering 8 m up and back down, three times: no real climb.
  final gpsWander = [
    for (final (i, e) in [
      400.0,
      408.0,
      400.0,
      408.0,
      400.0,
      408.0,
      400.0,
    ].indexed)
      pt(i, e),
  ];

  group('runAltitude', () {
    test('a phone run without a barometer is gated at the GPS band', () {
      expect(kElevationGainGpsMinDeltaM, 10);
      expect(
        runAltitude(gpsWander, RunSource.app).minDeltaM,
        kElevationGainGpsMinDeltaM,
      );
      expect(computeRunElevationGain(gpsWander, RunSource.app), 0);
      final climb = [
        for (final (i, e) in [400.0, 411.0, 422.0, 433.0].indexed) pt(i, e),
      ];
      expect(computeRunElevationGain(climb, RunSource.app), 33);
    });

    test('an import keeps the route band', () {
      for (final source in [
        RunSource.strava,
        RunSource.garmin,
        RunSource.watch,
        null,
      ]) {
        expect(
          runAltitude(gpsWander, source).minDeltaM,
          kElevationGainMinDeltaM,
        );
        expect(computeRunElevationGain(gpsWander, source), 24);
      }
    });

    test('a barometric series wins over GPS at the route band', () {
      final track = [
        pt(0, 400, 300),
        pt(1, 430, 303),
        pt(2, 380, 306),
        pt(3, 425, 309),
      ];
      final alt = runAltitude(track, RunSource.app);
      expect(alt.barometric, isTrue);
      expect(alt.minDeltaM, kElevationGainMinDeltaM);
      expect(alt.track.map((w) => w.elevationMetres), [300, 303, 306, 309]);
      expect(computeRunElevationGain(track, RunSource.app), 9);
    });

    test('a realistic barometric hill reads its climb where GPS altitude '
        'overstates it', () {
      // Up 40 m, down 20, up 20 over 81 fixes: 60 m of real climb. The
      // barometer jitters 0.4 m; GPS altitude sits 100 m off it and wanders
      // 16 m over twenty-fix stretches.
      double hill(int i) =>
          (i <= 40
                  ? i
                  : i <= 60
                  ? 80 - i
                  : i - 40)
              .toDouble();
      final track = <Waypoint>[];
      final gpsOnly = <Waypoint>[];
      for (var i = 0; i <= 80; i++) {
        final baro = 300 + hill(i) + ((i % 3) - 1) * 0.4;
        final gps = baro + 100 + (i % 20 < 10 ? 8 : -8);
        track.add(pt(i, gps, baro));
        gpsOnly.add(pt(i, gps));
      }
      expect(runAltitude(track, RunSource.app).barometric, isTrue);
      expect(computeRunElevationGain(track, RunSource.app), closeTo(57, 1e-9));
      expect(
        computeRunElevationGain(gpsOnly, RunSource.app),
        closeTo(77.8, 1e-9),
      );
    });

    test(
      'a point without a barometric reading is a dropout, not a GPS splice',
      () {
        final track = [
          pt(0, 400, 300),
          pt(1, 480),
          pt(2, 490),
          pt(3, 400, 305),
        ];
        final alt = runAltitude(track, RunSource.app);
        expect(alt.track[1].elevationMetres, isNull);
        expect(alt.track[2].elevationMetres, isNull);
        expect(computeRunElevationGain(track, RunSource.app), 5);
      },
    );

    test('without a barometer the track is the input, untouched', () {
      final alt = runAltitude(gpsWander, RunSource.app);
      expect(identical(alt.track, gpsWander), isTrue);
      expect(alt.barometric, isFalse);
      final baro = runAltitude([pt(0, 400, 300)], RunSource.app).track.single;
      expect(baro.lat, 47.37);
      expect(baro.lng, 8.54);
      expect(baro.baroElevationMetres, 300);
    });

    test('hasBarometricAltitude: a non-finite reading is no reading', () {
      expect(hasBarometricAltitude(const []), isFalse);
      expect(hasBarometricAltitude(gpsWander), isFalse);
      expect(hasBarometricAltitude([pt(0, 400, double.nan)]), isFalse);
      expect(hasBarometricAltitude([pt(0, 400), pt(1, null, 0)]), isTrue);
    });
  });

  group('computeRunElevationLoss', () {
    test('reads the same series and band as the gain beside it', () {
      expect(computeRunElevationLoss(gpsWander, RunSource.app), 0);
      expect(computeRunElevationLoss(gpsWander, RunSource.strava), 24);
      final track = [pt(0, 400, 309), pt(1, 450, 306), pt(2, 350, 300)];
      expect(computeRunElevationLoss(track, RunSource.app), 9);
    });
  });

  group('RunElevationGainAccumulator', () {
    test('GPS only, it matches the phone-run batch figure', () {
      final acc = RunElevationGainAccumulator()..addAll(gpsWander);
      expect(acc.gainMetres, computeRunElevationGain(gpsWander, RunSource.app));
      expect(acc.gainMetres, 0);
    });

    test('from the first barometric point it answers with that series', () {
      final track = [
        pt(0, 400),
        pt(1, 450),
        pt(2, 400, 300),
        pt(3, 500, 304),
        pt(4, 380, 308),
      ];
      final acc = RunElevationGainAccumulator();
      for (final w in track) {
        acc.add(w);
      }
      expect(acc.gainMetres, computeRunElevationGain(track, RunSource.app));
      expect(acc.gainMetres, 8);
    });

    test('reset forgets the barometer too', () {
      final acc = RunElevationGainAccumulator()
        ..addAll([pt(0, 400, 300), pt(1, 400, 310)]);
      expect(acc.gainMetres, 10);
      acc.reset();
      acc.addAll([pt(0, 400), pt(1, 415)]);
      expect(acc.gainMetres, 15);
    });
  });
}
