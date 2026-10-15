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
