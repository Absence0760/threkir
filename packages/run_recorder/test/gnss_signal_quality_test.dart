import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:run_recorder/run_recorder.dart';

// Shared with the Wear OS port (GnssSignalQualityTest.kt). `flutter test`
// runs with the package root as cwd, so the repo-root fixture is two levels up.
Map<String, dynamic> _vectors() =>
    jsonDecode(
          File('../../fixtures/gnss_signal_vectors.json').readAsStringSync(),
        )
        as Map<String, dynamic>;

List<double> _doubles(Object? v) =>
    (v as List).map((e) => (e as num).toDouble()).toList();

GnssStatusSample _sample(Map<String, dynamic> m) => GnssStatusSample(
  meanTopCn0DbHz: (m['meanTopCn0DbHz'] as num?)?.toDouble(),
  usedInFix: m['usedInFix'] as int,
  l5Used: m['l5Used'] as bool,
);

void main() {
  final vectors = _vectors();

  group('GnssStatusSample.fromUsedSatellites', () {
    for (final c
        in (vectors['sampleCases'] as List).cast<Map<String, dynamic>>()) {
      test(c['name'], () {
        final s = GnssStatusSample.fromUsedSatellites(
          _doubles(c['cn0DbHz']),
          _doubles(c['carrierHz']),
        );
        final want = c['expect'] as Map<String, dynamic>;
        expect(s.meanTopCn0DbHz, (want['meanTopCn0DbHz'] as num?)?.toDouble());
        expect(s.usedInFix, want['usedInFix']);
        expect(s.l5Used, want['l5Used']);
      });
    }

    test('a non-finite C/N0 is used but not averaged', () {
      final s = GnssStatusSample.fromUsedSatellites(
        [double.nan, 30, 34],
        [double.nan, 0, 0],
      );
      expect(s.usedInFix, 3);
      expect(s.meanTopCn0DbHz, 32);
      expect(s.l5Used, isFalse);
    });
  });

  group('GnssSignalAccumulator.toMetadata', () {
    for (final c
        in (vectors['summaryCases'] as List).cast<Map<String, dynamic>>()) {
      test(c['name'], () {
        final acc = GnssSignalAccumulator();
        for (final s in (c['samples'] as List).cast<Map<String, dynamic>>()) {
          acc.add(_sample(s));
        }
        final want = c['expect'] as Map<String, dynamic>?;
        expect(acc.toMetadata(), want);
      });
    }

    test('memory does not grow with the run', () {
      final acc = GnssSignalAccumulator();
      for (var i = 0; i < 360000; i++) {
        acc.add(
          GnssStatusSample(
            meanTopCn0DbHz: 30 + (i % 100) / 10,
            usedInFix: 10,
            l5Used: i.isEven,
          ),
        );
      }
      final m = acc.toMetadata()!;
      expect(m['samples'], 360000);
      expect(m['l5_fraction'], 0.5);
      expect(m['used_median'], 10);
    });
  });

  group('RunRecorder gnss_signal', () {
    GnssStatusSample at(double cn0) =>
        GnssStatusSample(meanTopCn0DbHz: cn0, usedInFix: 9, l5Used: false);

    test('summarises readings taken while recording and not paused', () async {
      final status = StreamController<GnssStatusSample>();
      final r = RunRecorder(gnssStatus: () => status.stream)
        ..debugPrepareWithoutStream();
      status.add(at(10));
      await pumpEventQueue();
      r.begin();
      status
        ..add(at(30))
        ..add(at(32));
      await pumpEventQueue();
      r.pause();
      status.add(at(5));
      await pumpEventQueue();
      r.resume();
      status.add(at(34));
      await pumpEventQueue();
      final run = await r.stop();
      expect(run.metadata?['gnss_signal'], {
        'samples': 3,
        'used_median': 9,
        'cn0_median_dbhz': 32.0,
        'cn0_p10_dbhz': 30.0,
        'l5_fraction': 0.0,
      });
      expect(status.hasListener, isFalse);
      await status.close();
    });

    test('a realistic satellite stream lands as the registry shape', () async {
      // Four readings as the Android bridge sends them: C/N0 and carrier per
      // used satellite. The third is a stretch with no fix.
      const gps = 1575.42e6, l5 = 1176.45e6;
      final status = StreamController<GnssStatusSample>();
      final r = RunRecorder(gnssStatus: () => status.stream)
        ..debugPrepareWithoutStream();
      r.begin();
      status
        ..add(GnssStatusSample.fromUsedSatellites(
          [42, 40, 38, 36, 30],
          [gps, l5, gps, 1561.098e6, 1602e6],
        ))
        ..add(GnssStatusSample.fromUsedSatellites(
          [35, 33, 31, 29, 27, 25],
          [gps, gps, gps, gps, gps, gps],
        ))
        ..add(GnssStatusSample.fromUsedSatellites(const [], const []))
        ..add(GnssStatusSample.fromUsedSatellites(
          [45, 41, 39, 37, 35, 33, 30],
          [l5, gps, gps, gps, gps, gps, gps],
        ));
      await pumpEventQueue();
      final run = await r.stop();
      // Used counts 5, 6, 0, 7: the lower middle is 5. Top-four means over
      // the three fixed readings 39, 32, 40.5; two of three on L5.
      expect(run.metadata?['gnss_signal'], {
        'samples': 4,
        'used_median': 5,
        'cn0_median_dbhz': 39.0,
        'cn0_p10_dbhz': 32.0,
        'l5_fraction': 0.667,
      });
      await status.close();
    });

    test('a resumed session summarises only its own readings', () async {
      // Broadcast, like the platform channel: a reading before the session
      // reopens the stream reaches no one.
      final status = StreamController<GnssStatusSample>.broadcast();
      final r = RunRecorder(gnssStatus: () => status.stream);
      status.add(at(5));
      await pumpEventQueue();
      r.debugResumeWithoutStream(
        track: const [],
        distanceMetres: 1000,
        elapsed: const Duration(minutes: 20),
        startedAt: DateTime(2026, 4, 10, 10),
      );
      status
        ..add(at(28))
        ..add(at(30))
        ..add(at(36));
      await pumpEventQueue();
      final run = await r.stop();
      expect(run.metadata?['gnss_signal'], {
        'samples': 3,
        'used_median': 9,
        'cn0_median_dbhz': 30.0,
        'cn0_p10_dbhz': 28.0,
        'l5_fraction': 0.0,
      });
      await status.close();
    });

    test('no status source and no reading both leave the key off', () async {
      final none = RunRecorder()..debugPrepareWithoutStream();
      none.begin();
      expect((await none.stop()).metadata?['gnss_signal'], isNull);

      final silent = StreamController<GnssStatusSample>();
      final quiet = RunRecorder(gnssStatus: () => silent.stream)
        ..debugPrepareWithoutStream();
      quiet.begin();
      expect((await quiet.stop()).metadata?['gnss_signal'], isNull);
      await silent.close();
    });

    test('a failing status source costs only the summary', () async {
      final r = RunRecorder(gnssStatus: () => throw StateError('no receiver'))
        ..debugPrepareWithoutStream();
      r.begin();
      expect(r.recording, isTrue);
      final failing = StreamController<GnssStatusSample>();
      final s = RunRecorder(gnssStatus: () => failing.stream)
        ..debugPrepareWithoutStream();
      s.begin();
      failing.addError(StateError('callback unregistered'));
      await pumpEventQueue();
      expect(s.recording, isTrue);
      expect((await r.stop()).metadata?['gnss_signal'], isNull);
      expect((await s.stop()).metadata?['gnss_signal'], isNull);
      await failing.close();
    });
  });
}
