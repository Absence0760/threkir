import 'package:core_models/core_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:run_recorder/run_recorder.dart';

void main() {
  Route route(List<List<double>> latLngs) {
    return Route(
      id: 'test',
      name: 'fixture',
      waypoints: latLngs
          .map((p) => Waypoint(lat: p[0], lng: p[1]))
          .toList(growable: false),
      distanceMetres: 0,
    );
  }

  Waypoint at(double lat, double lng) => Waypoint(lat: lat, lng: lng);

  group('route progress only follows fixes the distance filter accepted', () {
    // At lat 0 one degree of longitude is the full 111320 m, so metres map
    // straight onto lng and the fixtures stay readable.
    const metrePerDegLng = 111320.0;

    Route eastRoute({required int lengthM, required int stepM}) => route([
          for (var m = 0; m <= lengthM; m += stepM) [0.0, m / metrePerDegLng],
        ]);

    Position fix(double metresEast, int seconds) => Position(
          longitude: metresEast / metrePerDegLng,
          latitude: 0,
          timestamp: DateTime(2026, 4, 10, 10, 0, seconds),
          accuracy: 5,
          altitude: 100,
          altitudeAccuracy: 2,
          heading: 90,
          headingAccuracy: 5,
          speed: 2.5,
          speedAccuracy: 1,
        );

    /// Drive [fixes] through the full filter chain and return the last emitted
    /// snapshot.
    Future<RunSnapshot> lastSnapshotFor(List<Position> fixes) async {
      final r = RunRecorder()
        ..debugPrepareWithoutStream(route: eastRoute(lengthM: 3000, stepM: 100));
      final seen = <RunSnapshot>[];
      final sub = r.snapshots.listen(seen.add);
      addTearDown(() async {
        await sub.cancel();
        r.dispose();
      });
      r.begin();
      for (final f in fixes) {
        r.debugInjectPosition(f);
      }
      await Future<void>.delayed(Duration.zero);
      return seen.last;
    }

    test('a rejected teleport does not poison the monotonic floor', () async {
      // 1000 m in 1 s is rejected for distance (fails the < 100 m hop cap and
      // the speed clamp, and 1 s is under the re-anchor window). It must not
      // drag the closest-segment floor up to ~1500 m, which the floor's
      // never-lowered contract would then make permanent.
      final snap = await lastSnapshotFor([
        fix(500, 0),
        fix(1500, 1),
        fix(505, 2),
      ]);
      expect(snap.offRouteDistanceMetres, closeTo(0, 2));
      expect(snap.routeRemainingMetres, closeTo(2495, 5));
    });

    test('the rejected teleport is still excluded from distance', () async {
      // Guards the fix from "solving" the floor by accepting the bad fix.
      final r = RunRecorder()
        ..debugPrepareWithoutStream(route: eastRoute(lengthM: 3000, stepM: 100));
      addTearDown(r.dispose);
      r.begin();
      r.debugInjectPosition(fix(500, 0));
      r.debugInjectPosition(fix(1500, 1));
      r.debugInjectPosition(fix(505, 2));
      expect(r.debugDistanceMetres, closeTo(5, 1));
      expect(r.debugTrack.length, 2);
    });

    test('a rejected backwards teleport does not move the floor either',
        () async {
      final snap = await lastSnapshotFor([
        fix(1000, 0),
        fix(20, 1),
        fix(1005, 2),
      ]);
      expect(snap.offRouteDistanceMetres, closeTo(0, 2));
      expect(snap.routeRemainingMetres, closeTo(1995, 5));
    });

    test('a genuine GPS-gap re-anchor still advances the floor', () async {
      // The >= 10 s re-anchor branch appends the fix to the track, so it IS
      // trusted — without this case the fix above could over-correct and
      // freeze route progress across a real signal gap (#330).
      final snap = await lastSnapshotFor([
        fix(500, 0),
        fix(1500, 60),
      ]);
      expect(snap.routeRemainingMetres, closeTo(1500, 5));
      expect(snap.offRouteDistanceMetres, closeTo(0, 2));
    });

    test('sub-threshold jitter keeps the last trusted route values', () async {
      final snap = await lastSnapshotFor([
        fix(500, 0),
        fix(500.5, 1),
      ]);
      expect(snap.routeRemainingMetres, closeTo(2500, 5));
      expect(snap.offRouteDistanceMetres, closeTo(0, 2));
    });
  });

  group('_routeRemaining', () {
    test('returns null when no route is loaded', () {
      final r = RunRecorder()..debugPrepareWithoutStream();
      expect(r.debugRouteRemaining(at(0, 0)), isNull);
    });

    test('returns null when the route has fewer than 2 waypoints', () {
      final r = RunRecorder()
        ..debugPrepareWithoutStream(route: route([
          [0, 0],
        ]));
      expect(r.debugRouteRemaining(at(0, 0)), isNull);
    });

    test('at the route start, remaining equals the full route length', () {
      final r = RunRecorder()
        ..debugPrepareWithoutStream(route: route([
          [0, 0],
          [0, 0.001],
        ]));
      expect(r.debugRouteRemaining(at(0, 0)), closeTo(111.195, 0.5));
    });

    test('at segment midpoint, remaining is the unwalked tail', () {
      final r = RunRecorder()
        ..debugPrepareWithoutStream(route: route([
          [0, 0],
          [0, 0.001],
          [0, 0.002],
        ]));
      expect(
        r.debugRouteRemaining(at(0, 0.0005)),
        closeTo(111.195 * 1.5, 1.0),
      );
    });

    test('on the boundary between segments, remaining = total - first leg',
        () {
      final r = RunRecorder()
        ..debugPrepareWithoutStream(route: route([
          [0, 0],
          [0, 0.001],
          [0, 0.002],
        ]));
      expect(r.debugRouteRemaining(at(0, 0.001)), closeTo(111.195, 0.5));
    });

    test('at the route end, remaining is approximately zero', () {
      final r = RunRecorder()
        ..debugPrepareWithoutStream(route: route([
          [0, 0],
          [0, 0.001],
        ]));
      expect(r.debugRouteRemaining(at(0, 0.001)), closeTo(0, 0.5));
    });

    test('past the route end clamps to zero (t=1 on the last segment)', () {
      final r = RunRecorder()
        ..debugPrepareWithoutStream(route: route([
          [0, 0],
          [0, 0.001],
        ]));
      expect(r.debugRouteRemaining(at(0, 0.005)), closeTo(0, 0.5));
    });

    test('perpendicular offset projects onto the nearest segment', () {
      final r = RunRecorder()
        ..debugPrepareWithoutStream(route: route([
          [0, 0],
          [0, 0.001],
          [0, 0.002],
        ]));
      final remaining = r.debugRouteRemaining(at(0.0001, 0.0005));
      expect(remaining, isNotNull);
      expect(remaining, closeTo(111.195 * 1.5, 1.0));
    });

    test('multi-segment route sums correctly when at start', () {
      final r = RunRecorder()
        ..debugPrepareWithoutStream(route: route([
          [0, 0],
          [0, 0.001],
          [0, 0.002],
          [0, 0.003],
        ]));
      expect(r.debugRouteRemaining(at(0, 0)), closeTo(3 * 111.195, 1.0));
    });

    test('remaining never increases around a self-revisiting loop', () {
      // A rectangular loop that finishes back at its start. As the runner
      // comes down the closing (left) edge toward [0,0], the
      // perpendicular-closest segment is the opening edge [0,0]->[0,0.001]
      // already walked at the start, so a non-monotonic search would reset
      // remaining toward the full perimeter. The monotonic floor must keep
      // remaining non-increasing all the way round.
      final r = RunRecorder()
        ..debugPrepareWithoutStream(route: route([
          [0, 0],
          [0, 0.001],
          [0.001, 0.001],
          [0.001, 0],
          [0, 0],
        ]));
      final probes = [
        at(0, 0), // start, opening edge
        at(0, 0.0005),
        at(0, 0.001), // first corner
        at(0.0005, 0.001), // top edge
        at(0.001, 0.001), // second corner
        at(0.001, 0.0005), // right edge
        at(0.001, 0), // third corner
        at(0.0005, 0), // closing edge — perpendicular-near the opening edge
        at(0, 0), // back at the finish
      ];
      double? previous;
      for (final p in probes) {
        final remaining = r.debugRouteRemaining(p)!;
        if (previous != null) {
          expect(remaining, lessThanOrEqualTo(previous + 1e-6),
              reason: 'remaining jumped up at (${p.lat}, ${p.lng})');
        }
        previous = remaining;
      }
      // And it has genuinely wound down to ~0 by the finish.
      expect(previous, closeTo(0, 1.0));
    });
  });

  group('_offRouteDistance', () {
    test('returns null when no route is loaded', () {
      final r = RunRecorder()..debugPrepareWithoutStream();
      expect(r.debugOffRouteDistance(at(0, 0)), isNull);
    });

    test('returns null when the route has fewer than 2 waypoints', () {
      final r = RunRecorder()
        ..debugPrepareWithoutStream(route: route([
          [0, 0],
        ]));
      expect(r.debugOffRouteDistance(at(0, 0)), isNull);
    });

    test('on a route waypoint returns ~0', () {
      final r = RunRecorder()
        ..debugPrepareWithoutStream(route: route([
          [0, 0],
          [0, 0.001],
        ]));
      expect(r.debugOffRouteDistance(at(0, 0)), closeTo(0, 0.01));
    });

    test('inline along the route returns ~0', () {
      final r = RunRecorder()
        ..debugPrepareWithoutStream(route: route([
          [0, 0],
          [0, 0.001],
        ]));
      expect(r.debugOffRouteDistance(at(0, 0.0005)), closeTo(0, 0.01));
    });

    test('perpendicular offset returns the perpendicular distance', () {
      final r = RunRecorder()
        ..debugPrepareWithoutStream(route: route([
          [0, 0],
          [0, 0.001],
        ]));
      expect(
        r.debugOffRouteDistance(at(0.0001, 0.0005)),
        closeTo(11.132, 0.05),
      );
    });

    test('past the route end returns distance to the last waypoint', () {
      final r = RunRecorder()
        ..debugPrepareWithoutStream(route: route([
          [0, 0],
          [0, 0.001],
        ]));
      expect(
        r.debugOffRouteDistance(at(0, 0.002)),
        closeTo(111.32, 0.5),
      );
    });

    test('multi-segment route picks the closest segment, not the first', () {
      final r = RunRecorder()
        ..debugPrepareWithoutStream(route: route([
          [0, 0],
          [0, 0.001],
          [0.001, 0.001],
        ]));
      expect(
        r.debugOffRouteDistance(at(0.0005, 0.001)),
        closeTo(0, 0.05),
      );
    });

    test('zero-length segment is tolerated (degenerate waypoint pair)', () {
      final r = RunRecorder()
        ..debugPrepareWithoutStream(route: route([
          [0, 0],
          [0, 0],
          [0, 0.001],
        ]));
      expect(r.debugOffRouteDistance(at(0, 0)), closeTo(0, 0.01));
      expect(
        r.debugOffRouteDistance(at(0.0001, 0)),
        closeTo(11.132, 0.05),
      );
    });
  });

  group('non-finite route geometry', () {
    // The running minimum is seeded at +Infinity and a NaN never compares
    // less than it, so a route whose every segment projects to NaN left the
    // seed untouched and reported the runner as infinitely far off course.
    // That figure reached the live stats readout and the sustained-off-route
    // detector, which escalates to a trusted contact once per run.
    Route nanRoute() => route([
          [double.nan, double.nan],
          [double.nan, double.nan],
        ]);

    test('off-route distance is null, never +Infinity', () {
      final r = RunRecorder()..debugPrepareWithoutStream(route: nanRoute());
      expect(r.debugOffRouteDistance(at(0, 0)), isNull);
    });

    test('remaining is null, never NaN', () {
      final r = RunRecorder()..debugPrepareWithoutStream(route: nanRoute());
      expect(r.debugRouteRemaining(at(0, 0)), isNull);
    });

    test('the single-pass progress agrees with both', () {
      final r = RunRecorder()..debugPrepareWithoutStream(route: nanRoute());
      expect(r.debugRouteProgress(at(0, 0)), isNull);
    });

    test('a non-finite runner position is refused on a good route', () {
      final r = RunRecorder()
        ..debugPrepareWithoutStream(
            route: route([
          [0, 0],
          [0, 0.001],
        ]));
      expect(r.debugOffRouteDistance(at(double.nan, 0)), isNull);
      expect(r.debugRouteProgress(at(0, double.nan)), isNull);
    });
  });

  group('_routeProgress', () {
    test('returns null when no route is loaded', () {
      final r = RunRecorder()..debugPrepareWithoutStream();
      expect(r.debugRouteProgress(at(0, 0)), isNull);
    });
  });

  group('resumeSession restores the monotonic route floor', () {
    const metrePerDegLng = 111320.0;

    // 500 m east and back, sampled every 50 m: the return leg lies on top of
    // the outbound one, so the closest segment to a runner on the way home is
    // ambiguous and only the floor tells the two apart.
    Route outAndBack() => route([
          for (var m = 0; m <= 500; m += 50) [0.0, m / metrePerDegLng],
          for (var m = 450; m >= 0; m -= 50) [0.0, m / metrePerDegLng],
        ]);

    Position fix(double metresEast, int seconds) => Position(
          longitude: metresEast / metrePerDegLng,
          latitude: 0,
          timestamp: DateTime(2026, 4, 10, 10, 0, seconds),
          accuracy: 5,
          altitude: 100,
          altitudeAccuracy: 2,
          heading: 90,
          headingAccuracy: 5,
          speed: 2.5,
          speedAccuracy: 1,
        );

    /// Out to the turnaround, then back west as far as [returnToMetresEast].
    List<Position> outAndBackFixes({double returnToMetresEast = 300}) => [
          for (var m = 0; m <= 500; m += 50) fix(m.toDouble(), m ~/ 50 * 10),
          for (var m = 450; m >= returnToMetresEast; m -= 50)
            fix(m.toDouble(), (1000 - m) ~/ 50 * 10),
        ];

    test('a resumed run reports the same distance-remaining as a fresh one',
        () {
      final fixes = outAndBackFixes();
      final fresh = RunRecorder()
        ..debugPrepareWithoutStream(route: outAndBack());
      addTearDown(fresh.dispose);
      fresh.begin();
      for (final f in fixes) {
        fresh.debugInjectPosition(f);
      }
      final last = fresh.debugCurrentWaypoint!;
      final freshRemaining = fresh.debugRouteRemaining(last)!;
      expect(freshRemaining, closeTo(300, 5),
          reason: 'on the way home, 300 m out means 300 m to run');

      // The process is killed here and the partial resumed: same track, same
      // route. prepare() resets the floor to 1, so without a rebuild the
      // closest segment is the OUTBOUND one under the runner's feet and
      // remaining nearly doubles — permanently, the floor never being lowered.
      final resumed = RunRecorder();
      addTearDown(resumed.dispose);
      resumed.debugResumeWithoutStream(
        track: fresh.debugTrack,
        distanceMetres: fresh.debugDistanceMetres,
        elapsed: const Duration(minutes: 4),
        startedAt: DateTime(2026, 4, 10, 10, 0, 0),
        route: outAndBack(),
      );
      resumed.debugInjectPosition(fix(300, 200));
      expect(
        resumed.debugRouteRemaining(resumed.debugCurrentWaypoint!),
        closeTo(freshRemaining, 5),
        reason: 'resuming must not hand the route matcher back the ground '
            'already covered',
      );
    });

    test('the restored floor still cannot walk backwards', () {
      final fresh = RunRecorder()
        ..debugPrepareWithoutStream(route: outAndBack());
      addTearDown(fresh.dispose);
      fresh.begin();
      for (final f in outAndBackFixes()) {
        fresh.debugInjectPosition(f);
      }
      final resumed = RunRecorder();
      addTearDown(resumed.dispose);
      resumed.debugResumeWithoutStream(
        track: fresh.debugTrack,
        distanceMetres: fresh.debugDistanceMetres,
        elapsed: const Duration(minutes: 4),
        startedAt: DateTime(2026, 4, 10, 10, 0, 0),
        route: outAndBack(),
      );
      var previous = double.infinity;
      for (var m = 300; m >= 0; m -= 50) {
        resumed.debugInjectPosition(fix(m.toDouble(), 200 + (300 - m) ~/ 50 * 10));
        final remaining =
            resumed.debugRouteRemaining(resumed.debugCurrentWaypoint!)!;
        expect(remaining, lessThanOrEqualTo(previous + 1e-6),
            reason: 'distance remaining climbed back up at ${m}m');
        previous = remaining;
      }
      expect(previous, closeTo(0, 5));
    });

    test('a resumed run with no route loaded is unaffected', () {
      final r = RunRecorder();
      addTearDown(r.dispose);
      r.debugResumeWithoutStream(
        track: [Waypoint(lat: 0, lng: 0)],
        distanceMetres: 100,
        elapsed: const Duration(minutes: 1),
        startedAt: DateTime(2026, 4, 10, 10, 0, 0),
      );
      expect(r.recording, isTrue);
      expect(r.debugRouteRemaining(at(0, 0)), isNull);
    });
  });

  group('following a route that passes the same place twice', () {
    // At lat 0 one degree of either axis is ~111320 m in the recorder's own
    // projection, so metres map straight onto degrees and fixtures stay
    // readable.
    const mPerDeg = 111320.0;
    List<double> en(double eastM, double northM) =>
        [northM / mPerDeg, eastM / mPerDeg];

    Position fix(double eastM, double northM, int seconds) => Position(
          longitude: eastM / mPerDeg,
          latitude: northM / mPerDeg,
          timestamp:
              DateTime(2026, 4, 10, 10, 0).add(Duration(seconds: seconds)),
          accuracy: 5,
          altitude: 100,
          altitudeAccuracy: 2,
          heading: 90,
          headingAccuracy: 5,
          speed: 2.5,
          speedAccuracy: 1,
        );

    Future<List<RunSnapshot>> snapshotsFor(
        Route r, List<Position> fixes) async {
      final rec = RunRecorder()..debugPrepareWithoutStream(route: r);
      final seen = <RunSnapshot>[];
      final sub = rec.snapshots.listen(seen.add);
      addTearDown(() async {
        await sub.cancel();
        rec.dispose();
      });
      rec.begin();
      for (final f in fixes) {
        rec.debugInjectPosition(f);
      }
      await Future<void>.delayed(Duration.zero);
      return seen;
    }

    // 500 m square, start == finish, run anticlockwise: east, north, west,
    // south. The closing leg runs down x = 0 into the start.
    Route squareLoop() =>
        route([en(0, 0), en(500, 0), en(500, 500), en(0, 500), en(0, 0)]);

    test('a loop runner at the start has the whole loop to go and stays on it',
        () async {
      // Walk the opening leg 3 m north of the line. The first fix, 1 m east of
      // the start, is nearer the CLOSING leg (1 m) than the opening one (3 m).
      // A global nearest-segment search latched the closing leg there — "0.00
      // km to go" — and, the floor never coming back down, measured every
      // later fix against that leg alone, so "off route" grew with every step
      // the runner took along the line.
      final snaps = await snapshotsFor(squareLoop(), [
        for (var i = 0; i <= 20; i++) fix(1.0 + i * 10, 3, i * 4),
      ]);
      expect(snaps.first.routeRemainingMetres, closeTo(2000, 5));
      expect(snaps.first.offRouteDistanceMetres, closeTo(1, 0.5));
      expect(snaps.last.routeRemainingMetres, closeTo(2000 - 201, 5));
      expect(snaps.last.routeAlongMetres, closeTo(201, 5));
      expect(snaps.last.offRouteDistanceMetres, closeTo(3, 0.5));
    });

    test('a lap of the loop winds remaining down to zero at the finish',
        () async {
      final fixes = <Position>[fix(0, 0, 0)];
      var t = 0;
      const legs = [
        [0.0, 0.0, 500.0, 0.0],
        [500.0, 0.0, 500.0, 500.0],
        [500.0, 500.0, 0.0, 500.0],
        [0.0, 500.0, 0.0, 0.0],
      ];
      for (final l in legs) {
        for (var s = 1; s <= 50; s++) {
          fixes.add(fix(l[0] + (l[2] - l[0]) * s / 50,
              l[1] + (l[3] - l[1]) * s / 50, t += 4));
        }
      }
      final snaps = await snapshotsFor(squareLoop(), fixes);
      for (final s in snaps) {
        expect(s.offRouteDistanceMetres, lessThan(1));
      }
      expect(snaps[snaps.length ~/ 2].routeRemainingMetres, closeTo(1000, 15));
      expect(snaps.last.routeRemainingMetres, closeTo(0, 2));
    });

    test('an out-and-back runner past the turnaround is on the return leg',
        () async {
      final snaps = await snapshotsFor(
        route([en(0, 0), en(1000, 0), en(0, 0)]),
        [
          for (var m = 0; m <= 1000; m += 10)
            fix(m.toDouble(), 0, m ~/ 10 * 4),
          for (var m = 990; m >= 900; m -= 10)
            fix(m.toDouble(), 0, (2000 - m) ~/ 10 * 4),
        ],
      );
      expect(snaps.last.routeRemainingMetres, closeTo(900, 5));
      expect(snaps.last.routeAlongMetres, closeTo(1100, 5));
      expect(snaps.last.offRouteDistanceMetres, closeTo(0, 1));
    });

    test('a runner who leaves the loop is still flagged off route', () async {
      final snaps = await snapshotsFor(squareLoop(), [
        for (var i = 0; i <= 10; i++) fix(i * 10.0, 0, i * 4),
        for (var i = 1; i <= 12; i++) fix(100, i * 10.0, 40 + i * 4),
      ]);
      // 120 m north of the opening leg is 100 m east of the closing one.
      expect(snaps.last.offRouteDistanceMetres, closeTo(100, 1));
      expect(snaps.last.routeAlongMetres, lessThan(250));
    });
  });
}
