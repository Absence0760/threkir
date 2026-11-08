import 'dart:math';

import 'package:core_models/core_models.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/run_altitude.dart';
import '../lib/run_stats.dart';

void main() {
  group('live moving time (issue #1300)', () {
    final t0 = DateTime(2026, 11, 7, 7, 0, 0);
    Waypoint at(int s, double cumM) => Waypoint(
          lat: 47.37,
          lng: 8.54 + cumM / (111320 * 0.6773),
          timestamp: t0.add(Duration(seconds: s)),
        ).withCumulativeDistance(cumM);

    // 60 s at 3 m/s, a 90 s stop the filter credits 0.3 m/s of drift over,
    // then 30 s at 3 m/s.
    final stopAndGo = <Waypoint>[
      for (var s = 0; s <= 60; s++) at(s, 3.0 * s),
      for (var s = 70; s <= 150; s += 10) at(s, 180 + 0.3 * (s - 60)),
      for (var s = 151; s <= 180; s++) at(s, 207 + 3.0 * (s - 150)),
    ];

    test('extending as the line grows matches the finished movingTimeOf', () {
      final acc = MovingTimeAccumulator();
      for (var n = 1; n <= stopAndGo.length; n += 7) {
        acc.extend(stopAndGo.sublist(0, n));
      }
      acc.extend(stopAndGo);
      expect(acc.movingTime, movingTimeOf(stopAndGo));
      expect(acc.movingTime, const Duration(seconds: 90));
    });

    test('an unstamped track measures on positions, as movingTimeOf does', () {
      final unstamped = [
        for (final w in stopAndGo) w.withCumulativeDistance(null),
      ];
      final acc = MovingTimeAccumulator()..extend(unstamped);
      expect(acc.movingTime, movingTimeOf(unstamped));
    });

    test('a stop adds no moving time, so the average it divides holds', () {
      final acc = MovingTimeAccumulator()..extend(stopAndGo.sublist(0, 61));
      final before = acc.movingTime;
      acc.extend(stopAndGo.sublist(0, 70));
      expect(acc.movingTime, before);
      expect(acc.lastMovingAt, t0.add(const Duration(seconds: 60)));
    });

    test('a shorter line is a new recording and starts over', () {
      final acc = MovingTimeAccumulator()..extend(stopAndGo);
      acc.extend(stopAndGo.sublist(0, 11));
      expect(acc.movingTime, const Duration(seconds: 10));
    });

    test('averagingTime takes moving time on GPS and the clock otherwise', () {
      const moving = Duration(minutes: 5);
      const elapsed = Duration(minutes: 7);
      expect(
          averagingTime(
              gpsMeasured: true, movingTime: moving, elapsed: elapsed),
          moving);
      expect(
          averagingTime(
              gpsMeasured: false, movingTime: Duration.zero, elapsed: elapsed),
          elapsed);
    });

    group('isStandingStill', () {
      DateTime s(int sec) => t0.add(Duration(seconds: sec));

      test('says Stopped once the latest fix is 10 s past the last movement',
          () {
        expect(
            isStandingStill(latestFixAt: s(69), lastMovingAt: s(60), since: s(0)),
            isFalse);
        expect(
            isStandingStill(latestFixAt: s(70), lastMovingAt: s(60), since: s(0)),
            isTrue);
      });

      test('a standing start counts from the first fix', () {
        expect(isStandingStill(latestFixAt: s(9), lastMovingAt: null, since: s(0)),
            isFalse);
        expect(isStandingStill(latestFixAt: s(10), lastMovingAt: null, since: s(0)),
            isTrue);
      });

      test('a resume counts from its own first fix, not the old movement', () {
        expect(
            isStandingStill(
                latestFixAt: s(305), lastMovingAt: s(60), since: s(300)),
            isFalse);
      });

      test('no fix yet, or no anchor yet, is never Stopped', () {
        expect(isStandingStill(latestFixAt: null, lastMovingAt: null, since: s(0)),
            isFalse);
        expect(isStandingStill(latestFixAt: s(99), lastMovingAt: null, since: null),
            isFalse);
      });
    });
  });

  group('movingTimeOf', () {
    // Zürich coordinates, moving eastward. ~0.00001 degree of longitude at
    // 47.37°N is ~0.75 m — usable for constructing realistic short segments.
    const lat = 47.37;
    const lngBase = 8.54;

    Waypoint wp({
      required double metresEast,
      required int secondsFromStart,
    }) {
      // 1 metre east ≈ 1 / (111320 * cos(lat)) degrees of longitude.
      final metrePerDeg = 111320 * 0.6773; // cos(47.37°)
      final lng = lngBase + metresEast / metrePerDeg;
      return Waypoint(
        lat: lat,
        lng: lng,
        timestamp: DateTime(2026, 4, 10, 10, 0, secondsFromStart),
      );
    }

    test('returns zero for empty or single-point tracks', () {
      expect(movingTimeOf(const []), Duration.zero);
      expect(
        movingTimeOf([wp(metresEast: 0, secondsFromStart: 0)]),
        Duration.zero,
      );
    });

    test('includes fast segments (running pace)', () {
      // 12 m in 4 s → 3 m/s → running
      final track = [
        wp(metresEast: 0, secondsFromStart: 0),
        wp(metresEast: 12, secondsFromStart: 4),
      ];
      expect(movingTimeOf(track), const Duration(seconds: 4));
    });

    test('excludes slow segments below the default 0.5 m/s threshold', () {
      // 1 m in 5 s → 0.2 m/s → standing still / GPS jitter
      final track = [
        wp(metresEast: 0, secondsFromStart: 0),
        wp(metresEast: 1, secondsFromStart: 5),
      ];
      expect(movingTimeOf(track), Duration.zero);
    });

    test('mixed: running then long stop then running', () {
      // 10 m in 5 s (2 m/s, moving)
      // 0.5 m in 90 s (0.006 m/s, stopped at a light)
      // 10 m in 5 s (2 m/s, moving again)
      final track = [
        wp(metresEast: 0, secondsFromStart: 0),
        wp(metresEast: 10, secondsFromStart: 5),
        wp(metresEast: 10.5, secondsFromStart: 95),
        wp(metresEast: 20.5, secondsFromStart: 100),
      ];
      // Moving = 5 + 5 = 10s. Elapsed = 100s. Stop segment excluded.
      expect(movingTimeOf(track), const Duration(seconds: 10));
    });

    test('custom threshold can include slower walks', () {
      // 1.5 m in 5 s → 0.3 m/s → below default, above custom 0.2
      final track = [
        wp(metresEast: 0, secondsFromStart: 0),
        wp(metresEast: 1.5, secondsFromStart: 5),
      ];
      expect(movingTimeOf(track), Duration.zero); // default threshold
      expect(
        movingTimeOf(track, minSpeedMps: 0.2),
        const Duration(seconds: 5),
      );
    });

    test('skips segments with missing timestamps', () {
      final track = [
        wp(metresEast: 0, secondsFromStart: 0),
        Waypoint(lat: lat, lng: lngBase + 0.0001), // no timestamp
        wp(metresEast: 10, secondsFromStart: 5),
      ];
      // First segment skipped (no timestamp on either end); second segment
      // is counted because both endpoints have timestamps. But wait — the
      // second segment compares point[1] (no ts) to point[2]. That one is
      // also skipped. So nothing counted.
      expect(movingTimeOf(track), Duration.zero);
    });

    test('skips segments with zero or negative dt', () {
      // Two points with the same timestamp → dt = 0
      final ts = DateTime(2026, 4, 10, 10, 0, 0);
      final track = [
        Waypoint(lat: lat, lng: lngBase, timestamp: ts),
        Waypoint(lat: lat, lng: lngBase + 0.0001, timestamp: ts),
      ];
      expect(movingTimeOf(track), Duration.zero);
    });

    test('sums across many fast segments', () {
      // Ten 3-second segments at 3 m/s each → 30s moving
      final track = <Waypoint>[];
      for (var i = 0; i <= 10; i++) {
        track.add(wp(metresEast: i * 9.0, secondsFromStart: i * 3));
      }
      expect(movingTimeOf(track), const Duration(seconds: 30));
    });
  });

  group('fastestWindowOf', () {
    const lat = 47.37;
    const lngBase = 8.54;
    final metrePerDeg = 111320 * 0.6773;

    Waypoint wp({
      required double metresEast,
      required int secondsFromStart,
    }) {
      final lng = lngBase + metresEast / metrePerDeg;
      return Waypoint(
        lat: lat,
        lng: lng,
        timestamp: DateTime(2026, 4, 10, 10, 0, secondsFromStart),
      );
    }

    test('returns null for empty or short tracks', () {
      expect(fastestWindowOf(const [], 5000), isNull);
      expect(
        fastestWindowOf([wp(metresEast: 0, secondsFromStart: 0)], 5000),
        isNull,
      );
    });

    test('returns null when track covers less than the window', () {
      // 4 km straight line in 20 min — not enough for a 5 km window.
      final track = [
        wp(metresEast: 0, secondsFromStart: 0),
        wp(metresEast: 4000, secondsFromStart: 20 * 60),
      ];
      expect(fastestWindowOf(track, 5000), isNull);
    });

    test('even-paced 10 km gives half-time for fastest 5 km', () {
      // 10 km in 50:00 at constant pace — fastest 5 km must be 25:00.
      // Use 50 waypoints at 200 m apart, 60 s apart.
      final track = <Waypoint>[
        for (var i = 0; i <= 50; i++)
          wp(metresEast: i * 200.0, secondsFromStart: i * 60),
      ];
      final best = fastestWindowOf(track, 5000);
      expect(best, isNotNull);
      // Allow 1-second interpolation slack.
      expect(best!.inSeconds, closeTo(25 * 60, 1));
    });

    test('picks the fast middle 5 km out of a slow → fast → slow run', () {
      // 3 km warmup at 300 s/km (slow)
      // 5 km fast at 240 s/km (the PB window)
      // 3 km cooldown at 300 s/km
      // 11 km total. Best 5k should be 1200 s = 20:00.
      final track = <Waypoint>[];
      var distance = 0.0;
      var seconds = 0;
      track.add(wp(metresEast: distance, secondsFromStart: seconds));

      // 3 km warmup: 30 segments of 100 m at 30 s each
      for (var i = 0; i < 30; i++) {
        distance += 100;
        seconds += 30;
        track.add(wp(metresEast: distance, secondsFromStart: seconds));
      }
      // 5 km fast: 50 segments of 100 m at 24 s each
      for (var i = 0; i < 50; i++) {
        distance += 100;
        seconds += 24;
        track.add(wp(metresEast: distance, secondsFromStart: seconds));
      }
      // 3 km cooldown: 30 segments of 100 m at 30 s each
      for (var i = 0; i < 30; i++) {
        distance += 100;
        seconds += 30;
        track.add(wp(metresEast: distance, secondsFromStart: seconds));
      }

      final best = fastestWindowOf(track, 5000);
      expect(best, isNotNull);
      expect(best!.inSeconds, closeTo(20 * 60, 2));
    });

    test('does not project: a 10 km at even pace stays at its real 5k time', () {
      // Regression for the "Fastest 5k" scaled-pace bug. A 10 km in
      // 1:14:34 (4474 s) at perfectly even pace → fastest 5 km is 37:17.
      // Build 100 segments of 100 m each, total 4474 s.
      final track = <Waypoint>[
        for (var i = 0; i <= 100; i++)
          wp(
            metresEast: i * 100.0,
            secondsFromStart: (i * 4474 / 100).round(),
          ),
      ];
      final best = fastestWindowOf(track, 5000);
      expect(best, isNotNull);
      // 37:17 ± small interpolation slack
      expect(best!.inSeconds, closeTo(2237, 2));
    });
  });

  group('bestEffortsFromPersonalRecords', () {
    PersonalRecordRow pr(String distance, int seconds) => PersonalRecordRow(
          userId: 'u',
          distance: distance,
          bestTimeS: seconds,
          achievedAt: DateTime.utc(2026, 1, 1),
          updatedAt: DateTime.utc(2026, 1, 1),
        );

    test('maps cache rows to labels ordered shortest-first', () {
      // Deliberately out of order on input.
      final efforts = bestEffortsFromPersonalRecords([
        pr('marathon', 12000),
        pr('5k', 1200),
        pr('12k', 3100),
        pr('1_mile', 360),
        pr('half_marathon', 5400),
        pr('8k', 2000),
        pr('10k', 2500),
      ]);
      expect(efforts.keys.toList(),
          ['Mile', '5 km', '8 km', '10 km', '12 km', 'Half Marathon', 'Marathon']);
      expect(efforts['5 km'], const Duration(seconds: 1200));
      expect(efforts['Marathon'], const Duration(seconds: 12000));
    });

    test('drops unknown brackets and returns empty for none', () {
      expect(bestEffortsFromPersonalRecords([pr('50k', 99999)]), isEmpty);
      expect(bestEffortsFromPersonalRecords(const []), isEmpty);
    });
  });

  group('computeSplitDurations', () {
    final start = DateTime(2026, 4, 10, 10, 0, 0);
    // Move east along the equator, where haversineMetres(0,0,0,deg) is exactly
    // R·deg·π/180, so `metres` maps to a precise longitude (6371000·π/180
    // metres per degree). Tracks overshoot the last asserted boundary so it is
    // unambiguously crossed (no reliance on exact float equality).
    const mPerDeg = 6371000 * 3.141592653589793 / 180;
    Waypoint at(double metres, int seconds) => Waypoint(
          lat: 0,
          lng: metres / mPerDeg,
          timestamp: start.add(Duration(seconds: seconds)),
        );

    /// A waypoint with NO timestamp — what gpx_parser emits for a `<trkpt>`
    /// that carries no `<time>`, which strava_importer copies straight onto the
    /// saved run track.
    Waypoint untimed(double metres) =>
        Waypoint(lat: 0, lng: metres / mPerDeg);

    test('an untimestamped mid-track point never yields a negative split', () {
      // Substituting startedAt for the missing timestamp made
      // bTime.difference(aTime) ≈ -50 min, so the interpolated crossing landed
      // before tickStart and split 10 came out negative — which then poisoned
      // tickStart and every split after it.
      final track = [
        for (var m = 0; m <= 9500; m += 500) at(m.toDouble(), m * 6 ~/ 1000),
        untimed(10200),
        at(11000, 3960),
      ];
      final splits = computeSplitDurations(track, 1000, start);
      expect(splits, isNotEmpty);
      for (final s in splits) {
        expect(s.duration, greaterThanOrEqualTo(Duration.zero),
            reason: 'split ${s.tick} is negative: ${s.duration}');
      }
      expect(splits.map((s) => s.tick).toList(), [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]);
    });

    test('splits stay monotonic when a track has several untimed points', () {
      final track = [
        at(0, 0),
        at(500, 150),
        untimed(1200),
        untimed(1800),
        at(2400, 720),
        at(3000, 900),
      ];
      final splits = computeSplitDurations(track, 1000, start);
      for (final s in splits) {
        expect(s.duration, greaterThanOrEqualTo(Duration.zero),
            reason: 'split ${s.tick} is negative: ${s.duration}');
      }
      // Cumulative crossing times must be non-decreasing, so the summed splits
      // can never exceed the run's own elapsed time.
      final total = splits.fold(Duration.zero, (a, s) => a + s.duration);
      expect(total, lessThanOrEqualTo(const Duration(seconds: 900)));
    });

    test('a backwards timestamp clamps to 0:00 rather than going negative', () {
      // Android batching queued fixes / an NTP correction can walk a timestamp
      // backwards; the same clamp must absorb it.
      final track = [
        at(0, 0),
        at(900, 270),
        Waypoint(lat: 0, lng: 1100 / mPerDeg, timestamp: start),
        at(2100, 600),
      ];
      final splits = computeSplitDurations(track, 1000, start);
      for (final s in splits) {
        expect(s.duration, greaterThanOrEqualTo(Duration.zero),
            reason: 'split ${s.tick} is negative: ${s.duration}');
      }
    });

    test('a fully-timestamped track is unaffected by the clamp', () {
      // Even 300 s/km, overshooting each boundary so it is unambiguously
      // crossed (see the group's float-equality note).
      final splits = computeSplitDurations(
        [at(0, 0), at(1050, 315), at(2100, 630)],
        1000,
        start,
      );
      expect(splits.length, 2);
      expect(splits[0].duration.inSeconds, closeTo(300, 1));
      expect(splits[1].duration.inSeconds, closeTo(300, 1));
    });

    test('returns nothing for short tracks or a non-positive tick', () {
      expect(computeSplitDurations(const [], 1000, start), isEmpty);
      expect(computeSplitDurations([at(0, 0)], 1000, start), isEmpty);
      expect(computeSplitDurations([at(0, 0), at(1000, 300)], 0, start), isEmpty);
    });

    test('a multi-boundary GPS gap yields one timed split per tick, no 0:00 phantoms', () {
      // Dense to 500 m, then a single 2500 m fix-to-fix gap (a tunnel, a
      // canyon/forest signal loss, or a downsampled import), then on past
      // 4000 m — all at an even 300 s/km. The gap segment straddles the 1/2/3
      // km boundaries. The old loop emitted the first split then 0:00 phantoms
      // for km 2 and km 3 (which also poisoned the fastest-split highlight).
      final track = [at(0, 0), at(500, 150), at(3000, 900), at(4100, 1230)];
      final splits = computeSplitDurations(track, 1000, start);
      expect(splits.map((s) => s.tick).toList(), [1, 2, 3, 4]);
      for (final s in splits) {
        expect(s.duration.inSeconds, closeTo(300, 2),
            reason: 'tick ${s.tick} was ${s.duration.inSeconds}s (0 = phantom)');
      }
    });

    test('even-paced dense run splits into full km ticks', () {
      final track = <Waypoint>[];
      for (var m = 0; m <= 3100; m += 100) {
        track.add(at(m.toDouble(), (m * 3) ~/ 10)); // 300 s/km
      }
      final splits = computeSplitDurations(track, 1000, start);
      expect(splits.map((s) => s.tick).toList(), [1, 2, 3]);
      for (final s in splits) {
        expect(s.duration.inSeconds, closeTo(300, 2));
      }
    });

    test('mile tick produces a mile-long split (full ticks only, no partial)', () {
      final track = <Waypoint>[];
      for (var m = 0; m <= 2000; m += 100) {
        track.add(at(m.toDouble(), (m * 3) ~/ 10)); // 300 s/km
      }
      final splits = computeSplitDurations(track, 1609.344, start);
      expect(splits.length, 1);
      expect(splits.first.tick, 1);
      // 1609.344 m at 300 s/km ≈ 483 s.
      expect(splits.first.duration.inSeconds, closeTo(483, 3));
    });
  });

  group('averagePaceSecPerKm', () {
    test('positive inputs return elapsed / distance-in-km', () {
      // 2 km in 600 s → 300 s/km.
      expect(averagePaceSecPerKm(2000, 600), closeTo(300, 1e-9));
    });

    test('zero (or negative) distance returns null', () {
      expect(averagePaceSecPerKm(0, 600), isNull);
      expect(averagePaceSecPerKm(-5, 600), isNull);
    });

    test('zero (or negative) elapsed returns null', () {
      expect(averagePaceSecPerKm(2000, 0), isNull);
      expect(averagePaceSecPerKm(2000, -1), isNull);
    });
  });

  group('fastestWindowOf boundary', () {
    const mPerDeg = 6371000 * pi / 180;

    List<Waypoint> evenEquatorTrack(int legs, double stepM, int stepS) => [
          for (var i = 0; i <= legs; i++)
            Waypoint(
              lat: 0,
              lng: i * stepM / mPerDeg,
              timestamp: DateTime.utc(2026, 1, 1, 9, 0, i * stepS),
            ),
        ];

    test('a track that measures exactly the window still yields a best', () {
      // Fifty 100 m legs at the equator IS a 5 km run at 5:00/km, and the
      // accumulated haversine sum of it lands a hair under 5 000 m. Compared
      // strictly, that decided there was no 5 km effort in a 5 km run on the
      // last bit of a float. [windowToleranceRatio] scales with the window
      // because the drift does. Web's twin case is in
      // `integrations/embedded_best_efforts.test.ts`.
      final track = evenEquatorTrack(50, 100, 30);
      var cum = 0.0;
      for (var i = 1; i < track.length; i++) {
        cum += haversineMetres(
          track[i - 1].lat,
          track[i - 1].lng,
          track[i].lat,
          track[i].lng,
        );
      }
      expect(cum, lessThan(5000),
          reason: 'fixture must land short of the window, measured $cum');
      expect(5000 - cum, lessThan(1e-9),
          reason: 'and only just, measured ${5000 - cum}');
      expect(fastestWindowOf(track, 5000)?.inSeconds, 1500);
    });

    test('the tolerance is relative, so it never admits a real shortfall', () {
      // A millimetre short is a real shortfall at every distance the app
      // measures: the ratio of the marathon window is 42 um, twenty times
      // less than a millimetre, so the answer stays null.
      expect(windowToleranceRatio * 42195, lessThan(0.001));
      expect(fastestWindowOf(evenEquatorTrack(50, 100 - 0.001 / 50, 30), 5000),
          isNull);
    });
  });

  test('haversineMetres clamps instead of returning NaN near antipodal', () {
    // web clamps with 2*asin(min(1, sqrt(a))); the unclamped atan2 form went
    // NaN when rounding pushed `a` past 1, and NaN then propagates silently
    // (Dart's NaN.clamp(0, 1) is 1.0, so interpolateAlongRoute returned the
    // END waypoint rather than the midpoint).
    final d = haversineMetres(-87.5, 0, 87.5, 180);
    expect(d.isFinite, isTrue);
    expect(d, closeTo(20015086.796, 1.0));
  });

  test('degenerate tracks — no moving time, no splits, never NaN', () {
    // The tracks a brand-new account's first recordings reach: nothing, a
    // single fix, a 10 s / 3 m blip (slower than the moving floor), a
    // stand-still pair, and an untimed pair. Same table as the degenerate
    // tracks test in web's run_stats.test.ts.
    final start = DateTime.utc(2026, 4, 1, 7);
    Waypoint p(double lngM, int? s) => Waypoint(
          lat: 0,
          lng: lngM / 111320,
          timestamp: s == null ? null : start.add(Duration(seconds: s)),
        );
    final cases = <(String, List<Waypoint>)>[
      ('empty', const []),
      ('one fix', [p(0, 0)]),
      ('10 s / 3 m', [p(0, 0), p(3, 10)]),
      ('stand-still', [p(0, 0), p(0, 10)]),
      ('untimed', [p(0, null), p(3000, null)]),
    ];
    for (final (name, t) in cases) {
      expect(movingTimeOf(t), Duration.zero, reason: name);
      expect(computeSplitDurations(t, 1000, start), isEmpty, reason: name);
      expect(computeSplitDurations(t, 1609.344, start), isEmpty, reason: name);
    }
    final real = [for (var i = 0; i < 400; i++) p(i * 10.0, i * 3)];
    expect(computeSplitDurations(real, 0, start), isEmpty);
    expect(computeSplitDurations(real, -1000, start), isEmpty);
    expect(computeSplitDurations(real, double.nan, start), isEmpty);
  });

  // The recorder's cumulative credited distance as the split and moving-time
  // axis. Same cases as the trackCumulativeMetres / recorded-track tests in
  // web's run_stats.test.ts.
  group('recorded distance axis', () {
    final start = DateTime.utc(2026, 4, 1, 7);
    Waypoint at(double lngM, int s, {double? distM, double? smoothedLngM}) =>
        Waypoint(
          lat: 0,
          lng: lngM / 111320,
          timestamp: start.add(Duration(seconds: s)),
          cumulativeDistanceMetres: distM,
          smoothedLat: smoothedLngM == null ? null : 0,
          smoothedLng: smoothedLngM == null ? null : smoothedLngM / 111320,
        );

    test('reads the recorded distance, scaled so the last point is the run '
        'distance', () {
      final t = [
        at(0, 0, distM: 0),
        at(410, 100, distM: 400),
        at(790, 200, distM: 800),
        at(1010, 250, distM: 1000),
      ];
      expect(trackCumulativeMetres(t), [0, 400, 800, 1000]);
      final scaled = trackCumulativeMetres(t, totalDistanceMetres: 1100);
      for (final (i, m) in [0.0, 440.0, 880.0, 1100.0].indexed) {
        expect(scaled[i], closeTo(m, 1e-9), reason: 'scaled[$i]');
      }
      expect(trackCumulativeMetres(t, totalDistanceMetres: null),
          [0, 400, 800, 1000]);
      expect(trackCumulativeMetres(t, totalDistanceMetres: 0),
          [0, 400, 800, 1000]);
      expect(trackCumulativeMetres(t, totalDistanceMetres: double.nan),
          [0, 400, 800, 1000]);
    });

    test('positions unless every point carries a non-decreasing distance', () {
      final missing = [at(0, 0, distM: 0), at(100, 30), at(200, 60, distM: 200)];
      final backwards = [
        at(0, 0, distM: 0),
        at(100, 30, distM: 120),
        at(200, 60, distM: 110),
      ];
      final negative = [at(0, 0, distM: -1), at(100, 30, distM: 100)];
      for (final t in [missing, backwards, negative]) {
        expect(hasRecordedDistances(t), isFalse);
        final cum = trackCumulativeMetres(t, totalDistanceMetres: 5000);
        expect(cum.last, closeTo(haversineMetres(0, 0, 0, t.last.lng), 0.01));
      }
      expect(hasRecordedDistances([at(0, 0, distM: 0)]), isFalse);
      expect(
          hasRecordedDistances([at(0, 0, distM: 0), at(100, 30, distM: 100)]),
          isTrue);
      expect(trackCumulativeMetres(const []), isEmpty);
    });

    test('the position fallback measures the smoothed line, else raw', () {
      final smoothed = [
        at(0, 0, smoothedLngM: 0),
        at(100, 30, smoothedLngM: 60),
      ];
      expect(trackCumulativeMetres(smoothed, totalDistanceMetres: 5000)[1],
          closeTo(haversineMetres(0, 0, 0, 60 / 111320), 0.01));
      expect(trackCumulativeMetres([at(0, 0), at(100, 30)])[1],
          closeTo(haversineMetres(0, 0, 0, 100 / 111320), 0.01));
    });

    test('a recorded track splits on its distance and ends on the run '
        'distance', () {
      // 2.5 m/s for 2120 s, a fix every 2 s, raw positions zig-zagging 12 m
      // across the line. The estimator credited 5300 m to the last stored fix
      // and the run saved 5312 m.
      final pts = [
        for (var i = 0; i <= 1060; i++)
          Waypoint(
            lat: (i.isEven ? 6 : -6) / 111320,
            lng: i * 5 / 111320,
            timestamp: start.add(Duration(seconds: i * 2)),
            cumulativeDistanceMetres: i * 5.0,
          ),
      ];
      final splits =
          computeSplitDurations(pts, 1000, start, totalDistanceMetres: 5312);
      expect(splits, hasLength(5));
      for (final s in splits) {
        expect(s.duration.inMilliseconds / 1000, closeTo(399.1, 1));
      }
      final unscaled = computeSplitDurations(pts, 1000, start);
      for (final s in unscaled) {
        expect(s.duration.inMilliseconds / 1000, closeTo(400, 0.01));
      }
      final raw = computeSplitDurations(
        [for (final w in pts) w.withCumulativeDistance(null)],
        1000,
        start,
        totalDistanceMetres: 5312,
      );
      expect(raw.length, greaterThan(7), reason: 'raw zig-zag reads long');
    });

    test('a stop the estimator held still is not moving time', () {
      // Raw fixes wander 5 m a second while the runner stands; the recorder
      // credited nothing over those 60 s.
      final pts = [
        for (var i = 0; i <= 60; i++) at(i.isEven ? 0 : 5, i, distM: 100),
      ];
      expect(movingTimeOf(pts), Duration.zero);
      expect(
        movingTimeOf([for (final w in pts) w.withCumulativeDistance(null)]),
        const Duration(seconds: 60),
      );
    });

    test('mile splits on the recorded distance land on the mile boundaries',
        () {
      // 2.5 m/s for 2120 s on the recorded distance, raw positions zig-zagging
      // off the line: three whole miles at 643.7 s each.
      final pts = [
        for (var i = 0; i <= 1060; i++)
          Waypoint(
            lat: (i.isEven ? 6 : -6) / 111320,
            lng: i * 5 / 111320,
            timestamp: start.add(Duration(seconds: i * 2)),
            cumulativeDistanceMetres: i * 5.0,
          ),
      ];
      final splits = computeSplitDurations(pts, 1609.344, start);
      expect(splits.map((s) => s.tick), [1, 2, 3]);
      for (final s in splits) {
        expect(s.duration.inMilliseconds / 1000, closeTo(643.7376, 0.002));
      }
    });

    test('a recorded run, stop, run counts only the credited stretches', () {
      // 3 m/s for 60 s, 60 s held still while the raw fixes wander 5 m, then
      // 3 m/s for 60 s more.
      final pts = [
        for (var i = 0; i <= 180; i++)
          () {
            final d = i <= 60
                ? 3.0 * i
                : i <= 120
                    ? 180.0
                    : 180.0 + 3 * (i - 120);
            final stopped = i > 60 && i < 120;
            return at(d + (stopped && i.isOdd ? 5 : 0), i, distM: d);
          }(),
      ];
      expect(movingTimeOf(pts), const Duration(seconds: 120));
      expect(
        movingTimeOf([for (final w in pts) w.withCumulativeDistance(null)]),
        const Duration(seconds: 180),
      );
    });
  });
  group('split elevation', () {
    final start = DateTime.utc(2026, 4, 1, 7);
    // A barometer run whose GPS altitude disagrees with it in shape and level:
    // the barometer climbs 2 m per 100 m, GPS altitude falls 1 m per 100 m and
    // sits 50 m above it. 2.1 km on the recorded distance, a fix every 10 m
    // and 3 s. Twin of `baroRun` in run_stats.test.ts.
    List<Waypoint> baroRun([double? Function(int i)? baroAt]) => [
          for (var i = 0; i <= 210; i++)
            Waypoint(
              lat: 0,
              lng: i * 10 / 111320,
              timestamp: start.add(Duration(seconds: i * 3)),
              cumulativeDistanceMetres: i * 10.0,
              elevationMetres: 150 - 0.1 * i + (i.isEven ? -6 : 6),
              baroElevationMetres:
                  baroAt == null ? 100 + 0.2 * i : baroAt(i),
            ),
        ];

    test('a barometer run reads split elevation off the barometer, as the '
        'climb does', () {
      final pts = baroRun();
      final splits =
          computeSplitDurations(pts, 1000, start, totalDistanceMetres: 2100);
      // Whole ticks only: the 100 m tail web shows as a third split is not one
      // here.
      expect(splits.map((s) => s.elevationMetres), [20, 20]);
      final line = runAltitude(pts, RunSource.app).track;
      expect(
        [
          line[100].elevationMetres! - line[0].elevationMetres!,
          line[200].elevationMetres! - line[100].elevationMetres!,
        ].map((d) => d.round()),
        [20, 20],
      );
      final gpsOnly = computeSplitDurations(
        [
          for (final w in pts)
            Waypoint(
              lat: w.lat,
              lng: w.lng,
              timestamp: w.timestamp,
              cumulativeDistanceMetres: w.cumulativeDistanceMetres,
              elevationMetres: w.elevationMetres,
            ),
        ],
        1000,
        start,
        totalDistanceMetres: 2100,
      );
      expect(gpsOnly.map((s) => s.elevationMetres), [-10, -10]);
    });

    test('split elevation carries a dropout across and never reads an '
        'off-track fix', () {
      // No barometer reading until the anchor levels (the first five fixes)
      // and none through a stall from 500 m to 1490 m; an off-track canopy fix
      // at 1010 m, inside the stall and beside the 1 km boundary, carries a
      // wild altitude in both series.
      final pts = baroRun(
          (i) => i < 5 || (i >= 50 && i < 150) ? null : 100 + 0.2 * i);
      final w = pts[101];
      pts[101] = Waypoint(
        lat: w.lat,
        lng: w.lng,
        timestamp: w.timestamp,
        cumulativeDistanceMetres: w.cumulativeDistanceMetres,
        elevationMetres: 999,
        baroElevationMetres: 999,
        offTrack: true,
      );
      final splits =
          computeSplitDurations(pts, 1000, start, totalDistanceMetres: 2100);
      // The first reading (101 m at 50 m) holds back to the start.
      expect(splits.map((s) => s.elevationMetres), [19, 20]);
      // A barometer that stops for good at 890 m: the split it reaches into
      // holds its last reading, the ones after it read nothing rather than
      // 0 m.
      final stalled = computeSplitDurations(
          baroRun((i) => i < 90 ? 100 + 0.2 * i : null), 1000, start,
          totalDistanceMetres: 2100);
      expect(stalled.map((s) => s.elevationMetres), [18, null]);
    });

    test('a half-metre split elevation rounds toward +infinity, as the web '
        'twin does', () {
      final pts = [
        for (var i = 0; i <= 110; i++)
          Waypoint(
            lat: 0,
            lng: i * 10 / 111320,
            timestamp: start.add(Duration(seconds: i * 3)),
            cumulativeDistanceMetres: i * 10.0,
            baroElevationMetres: 10 - 0.025 * i,
          ),
      ];
      expect(computeSplitDurations(pts, 1000, start).first.elevationMetres, -2);
    });
  });
}
