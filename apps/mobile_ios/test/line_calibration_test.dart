import 'dart:math' as math;

import 'package:core_models/core_models.dart' show Waypoint;
import 'package:flutter_test/flutter_test.dart';
import 'package:run_recorder/run_recorder.dart' show RunSnapshot;

import '../lib/gate_crossing.dart';
import '../lib/line_calibration.dart';

/// The timing-line calibration figures (#1304 § 6): pairing true crossings
/// with detected ones, the error statistics, the capture's feed rule, and an
/// export that carries no position.

// A line at a distinctive spot, so a coordinate leaking into the CSV shows.
const _lat0 = 47.123456;
const _lng0 = 8.654321;
const _mPerDegLat = 6371008.8 * math.pi / 180;
final _mPerDegLng = _mPerDegLat * math.cos(_lat0 * math.pi / 180);

const _gate = Gate(lat: _lat0, lng: _lng0, bearingDeg: 90, halfWidthM: 15);
const _cell = CalibrationCell(
    CalibrationApproach.deg90, CalibrationPace.run, CalibrationCarry.hand);

final _t0 = DateTime.utc(2026, 11, 10, 7, 0, 0);

/// One fix [eastM] past the line and [northM] off its centre, [ms] after
/// 07:00:00 on the device clock.
GateFix _fix(double eastM, int ms, {double northM = 0}) => GateFix(
      lat: _lat0 + northM / _mPerDegLat,
      lng: _lng0 + eastM / _mPerDegLng,
      tMs: _t0.millisecondsSinceEpoch + ms.toDouble(),
      coveredM: eastM + 100,
    );

/// A pass west to east at 4 m/s with a fix a second, crossing the line
/// [crossAtMs] after 07:00:00, half-way between two fixes.
List<GateFix> _pass(int crossAtMs, {double northM = 0}) => [
      for (var k = -5; k <= 5; k++)
        _fix(4.0 * (k * 1000 - 500) / 1000, crossAtMs + k * 1000 - 500,
            northM: northM),
    ];

DateTime _true(int ms) => _t0.add(Duration(milliseconds: ms));

void main() {
  group('analyseCalibration', () {
    test('pairs each true crossing with the nearest detection on the server '
        'clock', () {
      // Two passes; the device clock runs 1.5 s behind the server, so a
      // detection at device 07:00:10 is server 07:00:11.5.
      final fixes = [..._pass(10000), ..._pass(40000)];
      final r = analyseCalibration(
        cell: _cell,
        recordings: [fixes],
        gate: _gate,
        trueCrossings: [_true(11300), _true(41800)],
        clockOffsetMs: 1500,
      );
      expect(r.trueCount, 2);
      expect(r.forwardCount, 2);
      expect(r.matched, 2);
      expect(r.missed, 0);
      expect(r.falseCrossings, 0);
      expect([for (final x in r.rows) x.errorMs], [200, -300]);
      expect(r.medianErrorMs, -50);
      expect(r.medianAbsErrorMs, 250);
      expect(r.p95AbsErrorMs, 300);
    });

    test('a crossing outside the half-width is missed, and says so', () {
      final r = analyseCalibration(
        cell: _cell,
        recordings: [_pass(10000, northM: 25)],
        gate: _gate,
        trueCrossings: [_true(10000)],
        clockOffsetMs: 0,
      );
      expect(r.missed, 1);
      final row = r.rows.single;
      expect(row.outcome, CalibrationOutcome.missed);
      expect(row.missReason, CalibrationMissReason.outsideHalfWidth);
      expect(row.offsetM!.abs(), closeTo(25, 0.01));
    });

    test('a gap past rejectGapS is missed as gap_rejected, by its span', () {
      // Stood 60 s behind the line, then crossed: the interpolated instant
      // (35 s) is 25 s from the truth, so only the pair's span can say it.
      final r = analyseCalibration(
        cell: _cell,
        recordings: [[_fix(-40, 0), _fix(40, 70000)]],
        gate: _gate,
        trueCrossings: [_true(60000)],
        clockOffsetMs: 0,
      );
      expect(r.rows.single.missReason, CalibrationMissReason.gapRejected);
    });

    test('no crossing anywhere near is missed as no_crossing', () {
      final r = analyseCalibration(
        cell: _cell,
        recordings: [_pass(10000)],
        gate: _gate,
        trueCrossings: [_true(60000)],
        clockOffsetMs: 0,
      );
      expect(r.missed, 1);
      expect(r.falseCrossings, 1,
          reason: 'the pass at 07:00:10 matches no true crossing');
      expect(r.rows.first.missReason, CalibrationMissReason.noCrossing);
    });

    test('jitter standing on the line counts false and backward crossings',
        () {
      final fixes = [
        for (var k = 0; k < 10; k++) _fix(k.isEven ? -1.5 : 1.5, k * 1000),
      ];
      final r = analyseCalibration(
        cell: const CalibrationCell(CalibrationApproach.standing,
            CalibrationPace.still, CalibrationCarry.pocket),
        recordings: [fixes],
        gate: _gate,
        trueCrossings: const [],
        clockOffsetMs: 0,
      );
      expect(r.forwardCount, 5);
      expect(r.backwardCount, 4);
      expect(r.falseCrossings, 5);
      expect(r.medianAbsErrorMs, isNull);
    });

    test('a bearing entered the wrong way round reads as backward_only', () {
      final r = analyseCalibration(
        cell: _cell,
        recordings: [_pass(10000)],
        gate: const Gate(
            lat: _lat0, lng: _lng0, bearingDeg: 270, halfWidthM: 15),
        trueCrossings: [_true(10000)],
        clockOffsetMs: 0,
      );
      expect(r.rows.single.missReason, CalibrationMissReason.backwardOnly);
    });

    test('a parallel pass leaves a near miss with its offset, out to three '
        'half-widths', () {
      final r = analyseCalibration(
        cell: const CalibrationCell(CalibrationApproach.parallel20,
            CalibrationPace.run, CalibrationCarry.hand),
        recordings: [
          _pass(10000, northM: 20),
          _pass(40000, northM: 40),
          _pass(70000, northM: 50),
        ],
        gate: _gate,
        trueCrossings: const [],
        clockOffsetMs: 0,
      );
      expect(r.falseCrossings, 0);
      expect(r.nearMisses, 2);
      expect([for (final x in r.rows) x.offsetM!.round()], [-20, -40]);
    });

    test('recordings are never paired across', () {
      // One run ends past the line, the next starts behind it 20 s later.
      final a = [_fix(-10, 0), _fix(10, 5000)];
      final b = [_fix(-10, 25000), _fix(-5, 26000)];
      final apart = analyseCalibration(
        cell: _cell,
        recordings: [a, b],
        gate: _gate,
        trueCrossings: [_true(2500)],
        clockOffsetMs: 0,
      );
      expect(apart.backwardCount, 0);
      final joined = analyseCalibration(
        cell: _cell,
        recordings: [
          [...a, ...b]
        ],
        gate: _gate,
        trueCrossings: [_true(2500)],
        clockOffsetMs: 0,
      );
      expect(joined.backwardCount, 1);
    });

    test('a time-zone slip shows as detections an hour from every truth', () {
      final r = analyseCalibration(
        cell: _cell,
        recordings: [_pass(10000)],
        gate: _gate,
        trueCrossings: [_true(10000 + 3600000)],
        clockOffsetMs: 0,
      );
      expect(r.matched, 0);
      expect(r.nearestDiffMs, -3600000);
    });

    test('one detection pairs with one true crossing, the closer one', () {
      final r = analyseCalibration(
        cell: _cell,
        recordings: [_pass(10000)],
        gate: _gate,
        trueCrossings: [_true(13000), _true(10400)],
        clockOffsetMs: 0,
      );
      expect(r.rows[0].outcome, CalibrationOutcome.missed);
      expect(r.rows[1].errorMs, -400);
    });
  });

  group('statistics', () {
    test('median of an even count is the mean of the middle two', () {
      expect(calibrationMedianMs([4, 1, 3, 2]), 3);
      expect(calibrationMedianMs([5, 1, 3]), 3);
      expect(calibrationMedianMs([]), isNull);
    });

    test('the 95th percentile is nearest-rank', () {
      final v = [for (var i = 1; i <= 20; i++) i * 10];
      expect(calibrationPercentileMs(v, 95), 190);
      expect(calibrationPercentileMs([7], 95), 7);
      expect(calibrationPercentileMs(
          [for (var i = 1; i <= 120; i++) i], 95), 114);
    });
  });

  group('CalibrationClock', () {
    test('keeps the shortest round trip, at its midpoint', () {
      final c = CalibrationClock();
      c.addSample(
          sentAt: _t0,
          receivedAt: _t0.add(const Duration(milliseconds: 400)),
          serverAt: _t0.add(const Duration(milliseconds: 1700)));
      c.addSample(
          sentAt: _t0,
          receivedAt: _t0.add(const Duration(milliseconds: 100)),
          serverAt: _t0.add(const Duration(milliseconds: 1550)));
      c.addSample(
          sentAt: _t0,
          receivedAt: _t0.add(const Duration(milliseconds: 300)),
          serverAt: _t0.add(const Duration(milliseconds: 9000)));
      expect(c.rtt, const Duration(milliseconds: 100));
      expect(c.offset, const Duration(milliseconds: 1500));
    });
  });

  group('calibrationCsv', () {
    test('holds error figures and counts, and no coordinate or instant', () {
      final r = analyseCalibration(
        cell: _cell,
        recordings: [[..._pass(10000), ..._pass(40000, northM: 25)]],
        gate: _gate,
        trueCrossings: [_true(10250), _true(40000)],
        clockOffsetMs: 0,
        offsetRttMs: 7,
      );
      final csv = calibrationCsv([r]);
      final lines = csv.trim().split('\n');
      expect(lines.first, kCalibrationCsvColumns.join(','));
      expect(lines, hasLength(4), reason: 'two crossings and a summary');
      // The walk back between the passes crosses the line backward.
      expect(lines[1], startsWith('crossing,90,run,phone_hand,1,matched,-250,'));
      expect(lines[2], contains('missed,,-25.0,0,outside_half_width'));
      expect(lines[3],
          'summary,90,run,phone_hand,,,,,,,2,1,1,1,1,0,0,-250,250,250,7');
      for (final leak in ['47.12', '8.65', '2026', '07:00', 'lat', 'lng']) {
        expect(csv, isNot(contains(leak)), reason: '$leak left the device');
      }
      for (final line in lines) {
        expect(line.split(','), hasLength(kCalibrationCsvColumns.length));
      }
    });
  });

  group('LineCalibrationCapture.offer', () {
    RunSnapshot snap(DateTime? at, {bool trusted = true, double d = 10}) =>
        RunSnapshot(
          elapsed: Duration.zero,
          distanceMetres: d,
          currentPosition: const Waypoint(lat: _lat0, lng: _lng0),
          positionFixedAt: at,
          positionTrusted: trusted,
        );

    test('takes each fresh trusted fix once, timed at its fix instant', () {
      final c = LineCalibrationCapture()..start();
      final at = _t0.add(const Duration(milliseconds: 1250));
      c.offer(snap(at), fresh: true, paused: false);
      c.offer(snap(at), fresh: true, paused: false);
      expect(c.fixCount, 1, reason: 'a re-emitted fix is not a second fix');
      expect(c.recordings.single.single.tMs, at.millisecondsSinceEpoch.toDouble());

      c.offer(snap(at.add(const Duration(seconds: 1)), trusted: false),
          fresh: true, paused: false);
      c.offer(snap(at.add(const Duration(seconds: 2))),
          fresh: false, paused: false);
      c.offer(snap(at.add(const Duration(seconds: 3))),
          fresh: true, paused: true);
      expect(c.fixCount, 1, reason: 'rejected, stale and paused fixes are not');
    });

    test('a recording restarted from zero starts a new series', () {
      final c = LineCalibrationCapture()..start();
      RunSnapshot at(int s) => RunSnapshot(
            elapsed: Duration(seconds: s),
            distanceMetres: 1,
            currentPosition: const Waypoint(lat: _lat0, lng: _lng0),
            positionFixedAt: _t0.add(Duration(minutes: s)),
          );
      for (final s in [1, 2, 3, 1, 2]) {
        c.offer(at(s), fresh: true, paused: false);
      }
      expect([for (final r in c.recordings) r.length], [3, 2]);
    });

    test('takes nothing until started, and nothing after stop', () {
      final c = LineCalibrationCapture();
      c.offer(snap(_t0), fresh: true, paused: false);
      expect(c.fixCount, 0);
      c.start();
      c.offer(snap(_t0), fresh: true, paused: false);
      c.stop();
      c.offer(snap(_t0.add(const Duration(seconds: 1))),
          fresh: true, paused: false);
      expect(c.fixCount, 1);
      c.clear();
      expect(c.fixCount, 0);
    });
  });

  group('parseCalibrationInstants', () {
    final day = DateTime(2026, 11, 10, 12);

    test('reads times of day on the capture day and ISO instants', () {
      final got = parseCalibrationInstants(
          '07:42:13.48\n\n07:43:01\n2026-11-10T12:00:00.250Z', day)!;
      expect(got[0], DateTime(2026, 11, 10, 7, 42, 13, 480));
      expect(got[1], DateTime(2026, 11, 10, 7, 43, 1));
      expect(got[2], DateTime.utc(2026, 11, 10, 12, 0, 0, 250));
    });

    test('refuses a line that is not an instant', () {
      expect(parseCalibrationInstants('07:42:13\nlater', day), isNull);
      expect(parseCalibrationInstants('25:00:00', day), isNull);
      expect(parseCalibrationInstants('', day), isEmpty);
    });
  });
}
