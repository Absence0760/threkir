import 'package:flutter_test/flutter_test.dart';
import 'package:core_models/core_models.dart';
import 'package:geolocator/geolocator.dart';
import 'package:run_recorder/run_recorder.dart';

import 'fix_clock.dart';

void main() {
  const lat = 47.37;
  const lngBase = 8.54;
  const metrePerDegLng = 111320 * 0.6773;

  late FixClock clock;
  setUp(() => clock = FixClock());

  // Distance, and so pace, comes from the GPS distance estimator, which
  // integrates the reported Doppler speed when there is one. Every fixture
  // therefore reports the speed its positions actually move at.
  Position makePosition({
    required double metresEast,
    required int secondsFromStart,
    double metresNorth = 0,
    double accuracy = 5,
    double speed = 2.5,
    double speedAccuracy = 1,
    double heading = 90,
    double headingAccuracy = 5,
  }) {
    return Position(
      longitude: lngBase + metresEast / metrePerDegLng,
      latitude: lat + metresNorth / 111320,
      timestamp: DateTime(2026, 4, 10, 10, 0, secondsFromStart),
      accuracy: accuracy,
      altitude: 400,
      altitudeAccuracy: 2,
      heading: heading,
      headingAccuracy: headingAccuracy,
      speed: speed,
      speedAccuracy: speedAccuracy,
    );
  }

  group('_calculatePace via debugPaceSecondsPerKm', () {
    test('returns null when track is empty', () {
      final r = RunRecorder(clock: clock)..debugPrepareWithoutStream();
      r.begin();
      expect(r.debugPaceSecondsPerKm, isNull);
    });

    test('returns null when track has fewer than 5 points', () {
      final r = RunRecorder(clock: clock)..debugPrepareWithoutStream();
      r.begin();
      for (int i = 0; i < 4; i++) {
        clock.inject(
          r,
          makePosition(metresEast: i * 50.0, secondsFromStart: i * 10),
        );
      }
      expect(r.debugTrack.length, 4);
      expect(r.debugPaceSecondsPerKm, isNull);
    });

    test('returns null when total tracked distance is below 50m', () async {
      final r = RunRecorder(clock: clock)..debugPrepareWithoutStream();
      r.begin();
      for (int i = 0; i < 6; i++) {
        clock.inject(
          r,
          makePosition(
              metresEast: i * 4.0, secondsFromStart: i * 5, speed: 0.8),
        );
        await Future.delayed(const Duration(milliseconds: 2));
      }
      expect(r.debugTrack.length, greaterThanOrEqualTo(5));
      expect(r.debugDistanceMetres, lessThan(50));
      expect(r.debugPaceSecondsPerKm, isNull);
    });

    test('returns the GPS-derived pace once track has 5 points and ≥50m', () {
      final r = RunRecorder(clock: clock)..debugPrepareWithoutStream();
      r.begin();
      for (int i = 0; i < 5; i++) {
        clock.inject(
          r,
          makePosition(metresEast: i * 50.0, secondsFromStart: i * 10, speed: 5),
        );
      }
      expect(r.debugTrack.length, 5);
      expect(r.debugDistanceMetres, closeTo(200, 1));

      final pace = r.debugPaceSecondsPerKm;
      expect(pace, isNotNull);
      expect(pace, closeTo(200, 1));
    });

    test('synchronous inject loop still produces a non-null pace', () {
      final r = RunRecorder(clock: clock)..debugPrepareWithoutStream();
      r.begin();
      for (int i = 0; i < 5; i++) {
        clock.inject(
          r,
          makePosition(
              metresEast: i * 50.0, secondsFromStart: i * 10, speed: 5),
        );
      }
      expect(r.debugTrack.length, 5);
      expect(r.debugPaceSecondsPerKm, isNotNull);
      expect(r.debugPaceSecondsPerKm, closeTo(200, 1));
    });

    test('window slides — early-slow segments excluded from pace', () {
      final r = RunRecorder(clock: clock)..debugPrepareWithoutStream();
      r.begin();
      // 90 m at 1 m/s (1000 s/km), then 250 m at 5 m/s (200 s/km).
      for (int i = 0; i < 10; i++) {
        clock.inject(r, makePosition(
            metresEast: i * 10.0, secondsFromStart: i * 10, speed: 1));
      }
      for (int j = 1; j <= 5; j++) {
        clock.inject(r, makePosition(
            metresEast: 90 + j * 50.0,
            secondsFromStart: 90 + j * 10,
            speed: 5));
      }

      expect(r.debugTrack.length, 15);

      final pace = r.debugPaceSecondsPerKm;
      expect(pace, isNotNull);
      expect(pace, closeTo(200, 5));
    });

    test('snapshot stream reports the same pace value as debugPaceSecondsPerKm',
        () async {
      final r = RunRecorder(clock: clock)..debugPrepareWithoutStream();
      final received = <double?>[];
      final sub = r.snapshots.listen((s) => received.add(s.currentPaceSecondsPerKm));
      r.begin();
      for (int i = 0; i < 5; i++) {
        clock.inject(
          r,
          makePosition(metresEast: i * 50.0, secondsFromStart: i * 10),
        );
        await Future.delayed(const Duration(milliseconds: 3));
      }
      await Future.delayed(const Duration(milliseconds: 20));
      await sub.cancel();
      await r.stop();

      expect(received, isNotEmpty);
      expect(received.last, r.debugPaceSecondsPerKm);
    });

    test('pace stays null while paused (no new track points)', () async {
      final r = RunRecorder(clock: clock)..debugPrepareWithoutStream();
      r.begin();
      clock.inject(r, makePosition(metresEast: 0, secondsFromStart: 0));
      await Future.delayed(const Duration(milliseconds: 2));
      clock.inject(r, makePosition(metresEast: 50, secondsFromStart: 10));
      await Future.delayed(const Duration(milliseconds: 2));
      r.pause();

      for (int i = 2; i < 6; i++) {
        clock.inject(
          r,
          makePosition(metresEast: i * 50.0, secondsFromStart: i * 10),
        );
        await Future.delayed(const Duration(milliseconds: 2));
      }

      expect(r.debugTrack.length, 2);
      expect(r.debugPaceSecondsPerKm, isNull);
    });
  });

  group('pace never spans a pause or a resumed-session gap', () {
    /// Five accepted fixes at a true 200 s/km, ending 200 m along at t=40 s.
    void runPrePauseLeg(RunRecorder r) {
      for (int i = 0; i < 5; i++) {
        clock.inject(
          r,
          makePosition(
              metresEast: i * 50.0, secondsFromStart: i * 10, speed: 5),
        );
      }
    }

    test('a 10-minute pause is not charged to the post-resume distance', () {
      final r = RunRecorder(clock: clock)..debugPrepareWithoutStream();
      addTearDown(r.dispose);
      r.begin();
      runPrePauseLeg(r);
      r.pause();
      // The runner rests 600 s at an aid station without moving, then resumes
      // and covers 75 m in 25 s (3 m/s -> 333 s/km).
      r.resume();
      for (int i = 0; i < 6; i++) {
        clock.inject(r, makePosition(
          metresEast: 200 + i * 15.0,
          secondsFromStart: 640 + i * 5,
          speed: 3,
        ));
      }
      // Walking back across the pause billed 225 m against 645 s of wall clock
      // and reported ~2866 s/km — which run_screen feeds to the pace-alert and
      // cut-off catch-up voice cues.
      expect(r.debugPaceSecondsPerKm, closeTo(333, 20));
    });

    test('pace is null until enough post-resume fixes exist', () {
      final r = RunRecorder(clock: clock)..debugPrepareWithoutStream();
      addTearDown(r.dispose);
      r.begin();
      runPrePauseLeg(r);
      expect(r.debugPaceSecondsPerKm, isNotNull);
      r.pause();
      r.resume();
      // Two post-resume points is below the 5-point smoothing floor, so the
      // honest answer is "unknown" rather than a pace timed off a stale fix.
      clock.inject(
          r,
          makePosition(metresEast: 200, secondsFromStart: 640, speed: 5));
      clock.inject(
          r,
          makePosition(metresEast: 250, secondsFromStart: 650, speed: 5));
      expect(r.debugPaceSecondsPerKm, isNull);
    });

    test('pace recovers to the true value once the post-resume leg is long',
        () {
      final r = RunRecorder(clock: clock)..debugPrepareWithoutStream();
      addTearDown(r.dispose);
      r.begin();
      runPrePauseLeg(r);
      r.pause();
      r.resume();
      // 300 m post-resume at a true 200 s/km — past the ~200 m window, so the
      // walk never reaches the floor and the answer is the normal rolling pace.
      for (int i = 0; i < 7; i++) {
        clock.inject(r, makePosition(
          metresEast: 200 + i * 50.0,
          secondsFromStart: 640 + i * 10,
          speed: 5,
        ));
      }
      expect(r.debugPaceSecondsPerKm, closeTo(200, 10));
    });

    test('repeated pauses each reseal the window', () {
      final r = RunRecorder(clock: clock)..debugPrepareWithoutStream();
      addTearDown(r.dispose);
      r.begin();
      runPrePauseLeg(r);
      r.pause();
      r.resume();
      for (int i = 0; i < 6; i++) {
        clock.inject(r, makePosition(
          metresEast: 200 + i * 15.0,
          secondsFromStart: 640 + i * 5,
          speed: 3,
        ));
      }
      r.pause();
      r.resume();
      for (int i = 0; i < 6; i++) {
        clock.inject(r, makePosition(
          metresEast: 275 + i * 15.0,
          secondsFromStart: 1300 + i * 5,
          speed: 3,
        ));
      }
      expect(r.debugPaceSecondsPerKm, closeTo(333, 20));
    });

    test('a resumed session does not time against the pre-kill track', () {
      // The seeded track's last timestamp can be up to kResumableWindow (48 h)
      // old, so timing the first post-resume metres against it reported a pace
      // hundreds of times too slow.
      final seeded = [
        for (int i = 0; i < 5; i++)
          Waypoint(
            lat: lat,
            lng: lngBase + (i * 50.0) / metrePerDegLng,
            timestamp: DateTime(2026, 4, 9, 10, 0, i * 10),
          ),
      ];
      final r = RunRecorder(clock: clock)
        ..debugResumeWithoutStream(
          track: seeded,
          distanceMetres: 200,
          elapsed: const Duration(seconds: 40),
          startedAt: DateTime(2026, 4, 9, 10, 0),
        );
      addTearDown(r.dispose);
      expect(r.debugPaceSecondsPerKm, isNull,
          reason: 'the seeded track is all pre-kill — nothing to time yet');
      for (int i = 0; i < 6; i++) {
        clock.inject(r, makePosition(
          metresEast: 200 + i * 15.0,
          secondsFromStart: i * 5,
          speed: 3,
        ));
      }
      expect(r.debugPaceSecondsPerKm, closeTo(333, 20));
    });
  });

  group('pace never spans a re-anchored GPS gap (#330 follow-up)', () {
    test('a GPS gap seals the window instead of timing its chord credit',
        () {
      // A dropout longer than the estimator's 10 s gap window re-anchors it,
      // and spec v1.4 (gps_distance.md, Algorithm item 9) credits the gap a
      // lower bound: the chord from the filter's last position to the first
      // fix back, less both ends' 1-sigma uncertainty. That is a floor, not a
      // sampled path, so a window timing it against the gap's clock reads a
      // pace nobody ran. Measured when pace was the track hop-sum: 5 clean
      // fixes at a true 200 s/km, then a 12 s dropout 150 m on, reported
      // 128 s/km. resume() and _beginResumed() seal the window for the same
      // kind of discontinuity.
      //
      // It matters beyond the display: run_screen feeds this to the pace-alert
      // and cut-off catch-up voice cues, and live_cutoff_eta projects cut-off
      // arrival from recent pace — so a too-fast reading SUPPRESSES a warning.
      final r = RunRecorder(clock: clock)
        ..debugPrepareWithoutStream(maxSpeedMps: 1000);
      r.begin();
      for (var i = 0; i <= 4; i++) {
        clock.inject(
            r,
            makePosition(
                metresEast: 50.0 * i, secondsFromStart: 10 * i, speed: 5));
      }
      expect(r.debugPaceSecondsPerKm, closeTo(200, 1),
          reason: 'baseline: 50 m per 10 s is 200 s/km');
      expect(r.debugDistanceMetres, closeTo(200, 0.01));

      clock.inject(
          r, makePosition(metresEast: 350, secondsFromStart: 52, speed: 5));
      // scripts/gps_distance/reference.py over the same six fixes with the
      // speed cap lifted: 140.247 m for the gap, the 150 m chord less
      // sqrt(ax + ay + 2r).
      expect(r.debugDistanceMetres, closeTo(340.247, 0.01),
          reason: 'the gap is credited its chord lower bound');
      expect(r.debugPaceSecondsPerKm, isNull,
          reason: 'no window may span the gap');
    });

    test('at the default speed cap the gap credit is capped at maxSpeed x dt',
        () {
      // The same fixes on a phone's 10 m/s cap: 150 m in 12 s is 12.5 m/s, so
      // the chord bound is capped at 10 x 12 = 120 m (reference.py: 320.0 m).
      final r = RunRecorder(clock: clock)..debugPrepareWithoutStream();
      addTearDown(r.dispose);
      r.begin();
      for (var i = 0; i <= 4; i++) {
        clock.inject(
            r,
            makePosition(
                metresEast: 50.0 * i, secondsFromStart: 10 * i, speed: 5));
      }
      clock.inject(
          r, makePosition(metresEast: 350, secondsFromStart: 52, speed: 5));
      expect(r.debugDistanceMetres, closeTo(320.0, 0.01));
      expect(r.debugPaceSecondsPerKm, isNull,
          reason: 'no window may span the gap');
    });

    test('pace recovers to the true value once enough post-gap fixes land', () {
      // Sealing the window must not disable pace for the rest of the run.
      final r = RunRecorder(clock: clock)
        ..debugPrepareWithoutStream(maxSpeedMps: 1000);
      r.begin();
      clock.inject(r, makePosition(metresEast: 0, secondsFromStart: 0));
      clock.inject(r, makePosition(metresEast: 300, secondsFromStart: 40));
      expect(r.debugPaceSecondsPerKm, isNull);
      // Post-gap: 40 m per 10 s == 250 s/km, over enough distance to fill the
      // look-back window.
      for (var i = 1; i <= 8; i++) {
        clock.inject(r, makePosition(
            metresEast: 300.0 + 40 * i,
            secondsFromStart: 40 + 10 * i,
            speed: 4));
      }
      expect(r.debugPaceSecondsPerKm, closeTo(250, 5),
          reason: 'post-gap pace is measured only against post-gap fixes');
    });

    test('a rejected teleport does not seal the window', () {
      // The other side of the branch: a short-dt implausible hop is rejected
      // outright, so it must not disturb a healthy pace reading.
      final r = RunRecorder(clock: clock)
        ..debugPrepareWithoutStream(maxSpeedMps: 1000);
      r.begin();
      for (var i = 0; i <= 4; i++) {
        clock.inject(r, makePosition(
            metresEast: 50.0 * i, secondsFromStart: 10 * i, speed: 5));
      }
      final before = r.debugPaceSecondsPerKm;
      // 500 m in 2 s: fails the hop cap and both re-anchor gates. The
      // estimator still takes the fix, and credits its 5 m/s Doppler speed.
      clock.inject(
          r,
          makePosition(metresEast: 700, secondsFromStart: 42, speed: 5));
      expect(r.debugPaceSecondsPerKm, closeTo(before!, 0.01));
    });
  });

  group('pace reads the GPS distance estimator, not the hop-sum (#1090)', () {
    // A steady 5:00/km (10/3 m/s) straight east, one fix a second, with each
    // fix 1.25 m either side of the true line. Every hop is then 4.17 m for
    // 3.33 m of progress, so summing hops over-reads distance by 25% and
    // reported 4:00/km — a pace alert told the runner to slow down, and the
    // cut-off projection read them as ahead. scripts/gps_distance/reference.py
    // over the same track gives 300.0 s/km with Doppler and 299.9 s/km from
    // positions alone.
    const speed = 10 / 3;
    const fixes = 121;

    Position zigZag(int i, {required bool doppler}) => makePosition(
          metresEast: speed * i,
          metresNorth: i.isOdd ? 1.25 : -1.25,
          secondsFromStart: i,
          speed: doppler ? speed : 0,
          speedAccuracy: doppler ? 0.5 : 0,
          heading: doppler ? 90 : 0,
          headingAccuracy: doppler ? 5 : 0,
        );

    double hopSumPace(List<Waypoint> track, int hops) {
      var metres = 0.0;
      for (var k = track.length - hops; k < track.length; k++) {
        metres += Geolocator.distanceBetween(
            track[k - 1].lat, track[k - 1].lng, track[k].lat, track[k].lng);
      }
      return hops / metres * 1000;
    }

    test('with Doppler speed', () {
      final r = RunRecorder(clock: clock)..debugPrepareWithoutStream();
      addTearDown(r.dispose);
      r.begin();
      for (var i = 0; i < fixes; i++) {
        clock.inject(r, zigZag(i, doppler: true));
      }
      expect(r.debugTrack.length, fixes,
          reason: 'every zig-zag hop clears the 3 m track threshold');
      expect(hopSumPace(r.debugTrack, 60), closeTo(240, 3),
          reason: 'precondition: the raw hop-sum reads 4:00/km');
      expect(r.debugPaceSecondsPerKm, closeTo(300, 1));
    });

    test('from positions alone', () {
      final r = RunRecorder(clock: clock)..debugPrepareWithoutStream();
      addTearDown(r.dispose);
      r.begin();
      for (var i = 0; i < fixes; i++) {
        clock.inject(r, zigZag(i, doppler: false));
      }
      expect(hopSumPace(r.debugTrack, 60), closeTo(240, 3));
      expect(r.debugPaceSecondsPerKm, closeTo(300, 3));
    });
  });

  // Every comparison against NaN is false, so a NaN sample used to pass the
  // ordering and gap checks and make the pace NaN; an infinite distance made
  // it 0 s/km. Both are dropped now, as PaceWindow (watch_ios) and
  // LivePaceWindow (watch_wear) drop them.
  group('live pace rejects a non-finite sample', () {
    // Five samples 10 s and 50 m apart: 40 s over 200 m is 200 s/km.
    RunRecorder steadyWindow() {
      final r = RunRecorder(clock: clock)..debugPrepareWithoutStream();
      r.begin();
      for (var i = 0; i < 5; i++) {
        r.debugAddPaceSample(i * 10.0, i * 50.0);
      }
      expect(r.debugPaceSecondsPerKm, closeTo(200, 1e-9));
      return r;
    }

    test('a non-finite time leaves the pace as it was', () {
      final r = steadyWindow();
      addTearDown(r.dispose);
      r.debugAddPaceSample(double.nan, 250);
      r.debugAddPaceSample(double.infinity, 250);
      r.debugAddPaceSample(double.negativeInfinity, 250);
      expect(r.debugPaceSecondsPerKm, closeTo(200, 1e-9));
      // The next finite sample still lands: the window prunes to (10 s, 50 m)
      // and reads 35 s over 200 m.
      r.debugAddPaceSample(45, 250);
      expect(r.debugPaceSecondsPerKm, closeTo(175, 1e-9));
    });

    test('a non-finite distance leaves the pace as it was', () {
      final r = steadyWindow();
      addTearDown(r.dispose);
      r.debugAddPaceSample(41, double.nan);
      r.debugAddPaceSample(42, double.infinity);
      r.debugAddPaceSample(43, double.negativeInfinity);
      final pace = r.debugPaceSecondsPerKm;
      expect(pace, isNotNull);
      expect(pace!.isFinite, isTrue);
      expect(pace, closeTo(200, 1e-9));
      r.debugAddPaceSample(45, 250);
      expect(r.debugPaceSecondsPerKm, closeTo(175, 1e-9));
    });
  });

  // The live Pace tile asks the same readiness question as Avg pace and the
  // workout band (paceIsReady), so a fast 50 m does not light Pace up while
  // Avg pace is still blank (issue #1300).
  group('live pace waits for the shared readiness rule', () {
    test('five fixes over 60 m stay null until the window spans 20 s', () {
      final r = RunRecorder(clock: clock)..debugPrepareWithoutStream();
      addTearDown(r.dispose);
      r.begin();
      for (var i = 0; i < 5; i++) {
        r.debugAddPaceSample(i * 4.0, i * 15.0);
      }
      expect(r.debugPaceSecondsPerKm, isNull,
          reason: '60 m in 16 s clears the distance floor, not the time one');
      r.debugAddPaceSample(kPaceReadyMinSeconds.toDouble(), 75);
      expect(r.debugPaceSecondsPerKm, closeTo(20 / 75 * 1000, 1e-9));
    });

    test('a cyclist past 10 m/s keeps a pace once the window has 20 s', () {
      final r = RunRecorder(clock: clock)..debugPrepareWithoutStream();
      addTearDown(r.dispose);
      r.begin();
      for (var i = 0; i <= 60; i++) {
        r.debugAddPaceSample(i.toDouble(), i * 15.0);
      }
      expect(r.debugPaceSecondsPerKm, closeTo(1000 / 15, 1e-9));
    });

    test('20 s under 50 m stays null', () {
      final r = RunRecorder(clock: clock)..debugPrepareWithoutStream();
      addTearDown(r.dispose);
      r.begin();
      for (var i = 0; i < 6; i++) {
        r.debugAddPaceSample(i * 5.0, i * 9.0);
      }
      expect(r.debugPaceSecondsPerKm, isNull);
    });
  });
}
