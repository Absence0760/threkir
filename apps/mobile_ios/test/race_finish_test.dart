import 'package:flutter_test/flutter_test.dart';

import '../lib/race_finish.dart';

const _finishLat = 51.5;
const _finishLng = -0.1;
const _mPerDegLat = 6371000 * 3.141592653589793 / 180;

final _t0 = DateTime.utc(2026, 10, 13, 9);

/// A fix [northM] metres due north of the finish (negative = south), at
/// [second] seconds after [_t0], with [coveredM] metres covered.
RaceFix _fix(double northM, int second, double coveredM) => RaceFix(
      lat: _finishLat + northM / _mPerDegLat,
      lng: _finishLng,
      at: _t0.add(Duration(seconds: second)),
      coveredM: coveredM,
    );

RaceFinishDetector _detector({double courseM = 5000}) => RaceFinishDetector(
      finishLat: _finishLat,
      finishLng: _finishLng,
      courseDistanceM: courseM,
    );

/// Feeds every fix and returns the finish the detector finalised, if any.
RaceFinish? _run(RaceFinishDetector d, List<RaceFix> fixes) {
  RaceFinish? out;
  for (final f in fixes) {
    final r = d.offer(f);
    if (r != null) {
      expect(out, isNull, reason: 'a detector must finalise exactly once');
      out = r;
    }
  }
  return out;
}

void main() {
  group('raceDistanceM', () {
    test('one degree of latitude is ~111.2 km', () {
      expect(raceDistanceM(0, 0, 1, 0), closeTo(111195, 1));
    });

    test('is zero for the same point', () {
      expect(raceDistanceM(_finishLat, _finishLng, _finishLat, _finishLng), 0);
    });
  });

  group('in-zone closest approach', () {
    test('the finish time is the closest fix, not the first in-zone fix', () {
      final d = _detector();
      final finish = _run(d, [
        _fix(-60, 0, 4940),
        _fix(-28, 6, 4972),
        _fix(-12, 9, 4988),
        _fix(-2, 11, 4998),
        _fix(9, 13, 5009),
        _fix(20, 15, 5020),
      ]);
      expect(finish, isNotNull);
      expect(finish!.at, _t0.add(const Duration(seconds: 11)));
      expect(finish.distanceToFinishM, closeTo(2, 0.01));
      expect(finish.coveredM, 4998);
    });

    test('the first strictly farther fix finalises', () {
      final d = _detector();
      expect(_run(d, [_fix(-20, 0, 4980), _fix(-4, 3, 4996)]), isNull);
      final finish = d.offer(_fix(5, 5, 5005));
      expect(finish!.at, _t0.add(const Duration(seconds: 3)));
    });

    test('nothing finalises while the runner is still closing', () {
      final d = _detector();
      expect(
          _run(d, [_fix(-29, 0, 4971), _fix(-15, 3, 4985), _fix(-4, 5, 4996)]),
          isNull);
      expect(d.candidate!.at, _t0.add(const Duration(seconds: 5)));
    });

    test('a fix outside the zone is never a candidate', () {
      final d = _detector();
      _run(d, [_fix(-31, 0, 4969), _fix(-45, 3, 4955)]);
      expect(d.candidate, isNull);
      expect(d.settle(), isNull);
    });

    test('a fix exactly on the zone edge counts', () {
      final edge = _fix(-30, 0, 4970);
      final d = RaceFinishDetector(
        finishLat: _finishLat,
        finishLng: _finishLng,
        courseDistanceM: 5000,
        zoneM: raceDistanceM(edge.lat, edge.lng, _finishLat, _finishLng),
      );
      d.offer(edge);
      expect(d.candidate!.at, _t0);
    });

    test('settle() finalises an open approach on its closest fix', () {
      final d = _detector();
      _run(d, [_fix(-20, 0, 4980), _fix(-3, 4, 4997)]);
      final s = d.settle();
      expect(s!.at, _t0.add(const Duration(seconds: 4)));
      expect(d.result, same(s));
      expect(d.offer(_fix(50, 20, 5050)), isNull,
          reason: 'a settled detector takes no more fixes');
    });

    test('a tie keeps the earlier fix and does not finalise', () {
      final d = _detector();
      expect(_run(d, [_fix(-5, 0, 4995), _fix(-5, 2, 4995)]), isNull);
      final finish = d.offer(_fix(15, 4, 5015));
      expect(finish!.at, _t0);
    });
  });

  group('GPS jitter in and out of the zone', () {
    test('jitter outside the zone before reaching it changes nothing', () {
      final d = _detector();
      final finish = _run(d, [
        _fix(-33, 0, 4967),
        _fix(-31, 1, 4969),
        _fix(-40, 2, 4970),
        _fix(-29, 3, 4971),
        _fix(-14, 7, 4986),
        _fix(-3, 10, 4997),
        _fix(4, 12, 5004),
      ]);
      expect(finish!.at, _t0.add(const Duration(seconds: 10)));
    });

    test('a fix jittering out of the zone ends the approach on the best so far',
        () {
      final d = _detector();
      final finish = _run(d, [
        _fix(-20, 0, 4980),
        _fix(-12, 2, 4988),
        _fix(-31, 3, 4990),
        _fix(-4, 4, 4996),
      ]);
      expect(finish!.at, _t0.add(const Duration(seconds: 2)));
    });

    test('jitter inside the zone that is not farther keeps it open', () {
      final d = _detector();
      expect(
          _run(d, [_fix(-10, 0, 4990), _fix(-10, 1, 4990), _fix(-6, 2, 4994)]),
          isNull);
      expect(d.candidate!.at, _t0.add(const Duration(seconds: 2)));
    });
  });

  group('the coverage gate', () {
    test('a loop course does not finish on its start', () {
      final d = _detector();
      final finish = _run(d, [
        _fix(-5, 0, 0),
        _fix(10, 4, 15),
        _fix(40, 10, 45),
        _fix(80, 20, 85),
      ]);
      expect(finish, isNull);
      expect(d.candidate, isNull);
    });

    test('a loop course passing the finish below 90% does not finish', () {
      final d = _detector(courseM: 10000);
      final early = _run(d, [
        _fix(-20, 0, 8900),
        _fix(-1, 4, 8919),
        _fix(20, 8, 8940),
        _fix(40, 12, 8960),
      ]);
      expect(early, isNull, reason: '8919 m is under 90% of 10 km');
      final finish = _run(d, [
        _fix(-20, 2000, 9990),
        _fix(-2, 2004, 10008),
        _fix(20, 2008, 10030),
        _fix(40, 2012, 10050),
      ]);
      expect(finish!.at, _t0.add(const Duration(seconds: 2004)));
    });

    test('an out-and-back course finishes on the return only', () {
      final d = _detector(courseM: 2000);
      final out = <RaceFix>[
        for (var i = 0; i <= 10; i++) _fix(-100.0 * i, i * 30, 100.0 * i),
      ];
      final back = <RaceFix>[
        for (var i = 10; i >= 0; i--)
          _fix(-100.0 * i, 600 + (10 - i) * 30, 1000 + 100.0 * (10 - i)),
        _fix(15, 930, 2015),
        _fix(30, 935, 2030),
      ];
      expect(_run(d, out), isNull);
      final finish = _run(d, back);
      expect(finish!.at, _t0.add(const Duration(seconds: 900)));
      expect(finish.coveredM, 2000);
    });

    test('exactly 90% covered is enough', () {
      expect(raceCoverageMet(4500, 5000), isTrue);
      expect(raceCoverageMet(4499.9, 5000), isFalse);
    });

    test('an unknown course distance cannot be gated', () {
      expect(raceCoverageMet(10, null), isTrue);
      expect(raceCoverageMet(10, 0), isTrue);
      expect(raceCoverageMet(10, double.nan), isTrue);
    });
  });

  group('raceStartFlagged', () {
    final gun = DateTime.utc(2026, 10, 13, 9);

    test('a start within five minutes near the start line is not flagged', () {
      expect(
          raceStartFlagged(
            gunAt: gun,
            recordingStartedAt: gun.add(const Duration(minutes: 5)),
            firstFixFromStartM: 200,
          ),
          isFalse);
    });

    test('a start more than five minutes after GO is flagged', () {
      expect(
          raceStartFlagged(
            gunAt: gun,
            recordingStartedAt: gun.add(const Duration(minutes: 5, seconds: 1)),
          ),
          isTrue);
    });

    test('a first fix more than 200 m from the start is flagged', () {
      expect(
          raceStartFlagged(
            gunAt: gun,
            recordingStartedAt: gun,
            firstFixFromStartM: 201,
          ),
          isTrue);
    });
  });

  group('ServerClockOffset', () {
    test('is zero and unknown until a sample lands', () {
      final c = ServerClockOffset();
      expect(c.known, isFalse);
      expect(c.offset, Duration.zero);
    });

    test('measures against the midpoint of the round trip', () {
      final c = ServerClockOffset()
        ..addSample(
          sentAt: _t0,
          receivedAt: _t0.add(const Duration(milliseconds: 400)),
          serverAt: _t0.add(const Duration(seconds: 3, milliseconds: 200)),
        );
      expect(c.offset, const Duration(seconds: 3));
      expect(c.toServer(_t0), _t0.add(const Duration(seconds: 3)));
    });

    test('keeps the shortest round trip', () {
      final c = ServerClockOffset()
        ..addSample(
          sentAt: _t0,
          receivedAt: _t0.add(const Duration(milliseconds: 100)),
          serverAt: _t0.add(const Duration(milliseconds: 1050)),
        )
        ..addSample(
          sentAt: _t0,
          receivedAt: _t0.add(const Duration(seconds: 4)),
          serverAt: _t0.add(const Duration(seconds: 9)),
        );
      expect(c.offset, const Duration(seconds: 1));
    });

    test('ignores a sample whose clock ran backwards', () {
      final c = ServerClockOffset()
        ..addSample(
          sentAt: _t0,
          receivedAt: _t0.subtract(const Duration(seconds: 1)),
          serverAt: _t0,
        );
      expect(c.known, isFalse);
    });
  });

  group('raceGunTimeS', () {
    final gun = DateTime.utc(2026, 10, 13, 9);

    test('corrects the device instant onto the server clock', () {
      expect(
          raceGunTimeS(
            finishAtDevice: gun.add(const Duration(minutes: 20)),
            gunAt: gun,
            clockOffset: const Duration(seconds: -7),
          ),
          1193);
    });

    test('is omitted, not clamped, when negative', () {
      expect(
          raceGunTimeS(
              finishAtDevice: gun.subtract(const Duration(seconds: 5)),
              gunAt: gun),
          isNull);
    });
  });

  group('raceChipTimeS', () {
    final start = DateTime.utc(2026, 10, 13, 9, 2);

    test('runs from the runner\'s Start to the finish, pauses included', () {
      expect(
          raceChipTimeS(
              finishAtDevice: start.add(const Duration(minutes: 21, seconds: 3)),
              recordingStartedAt: start),
          1263);
    });

    test('is omitted when negative', () {
      expect(
          raceChipTimeS(
              finishAtDevice: start.subtract(const Duration(seconds: 1)),
              recordingStartedAt: start),
          isNull);
    });
  });

  group('raceStopOutcome', () {
    final now = DateTime.utc(2026, 10, 13, 10);

    test('an open approach finishes automatically at its closest fix', () {
      final o = raceStopOutcome(
        candidate: RaceFinish(at: _t0, distanceToFinishM: 3, coveredM: 4997),
        coveredM: 5010,
        courseDistanceM: 5000,
        now: now,
      );
      expect(o.finisherStatus, 'finished');
      expect(o.method, RaceFinishMethod.auto);
      expect(o.finishAt, _t0);
    });

    test('90% covered without an approach is a manual finish now', () {
      final o = raceStopOutcome(
          candidate: null, coveredM: 4600, courseDistanceM: 5000, now: now);
      expect(o.finished, isTrue);
      expect(o.method, RaceFinishMethod.manual);
      expect(o.finishAt, now);
    });

    test('under 90% covered is a DNF with no finish instant', () {
      final o = raceStopOutcome(
          candidate: null, coveredM: 4400, courseDistanceM: 5000, now: now);
      expect(o.finisherStatus, 'dnf');
      expect(o.finishAt, isNull);
      expect(o.method, isNull, reason: 'a DNF has no finish method');
    });

    test('the method wire values match the result CHECK', () {
      expect(RaceFinishMethod.values.map((m) => m.wire),
          ['auto', 'manual', 'host']);
    });
  });
}
