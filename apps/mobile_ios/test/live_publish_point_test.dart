import 'package:core_models/core_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:run_recorder/run_recorder.dart';

import '../lib/live_publish_point.dart';

final _now = DateTime(2026, 11, 6, 9, 0, 0);
const _fresh = Duration(seconds: 10);

Waypoint _wp(double lng, {bool offTrack = false}) =>
    Waypoint(lat: 47.37, lng: lng, offTrack: offTrack);

RunSnapshot _snap({
  Waypoint? current,
  bool trusted = true,
  DateTime? positionAt,
  DateTime? distanceAt,
  List<Waypoint> track = const [],
  List<Waypoint>? stored,
}) =>
    RunSnapshot(
      elapsed: const Duration(minutes: 5),
      distanceMetres: 800,
      currentPosition: current,
      positionTrusted: trusted,
      positionFixedAt: positionAt,
      distanceFixedAt: distanceAt,
      track: track,
      storedTrack: stored ?? track,
    );

void main() {
  test('a fresh trusted fix publishes the end of the line', () {
    final line = [_wp(8.5400), _wp(8.5402)];
    final p = livePublishPoint(
      _snap(current: line.last, positionAt: _now, distanceAt: _now, track: line),
      now: _now,
      freshWithin: _fresh,
    );
    expect(p!.point.lng, 8.5402);
    expect(p.weakGps, false);
  });

  test('a rejected teleport is never published; the line end is', () {
    final line = [_wp(8.5400), _wp(8.5402)];
    final teleport = _wp(8.6000);
    final p = livePublishPoint(
      _snap(
        current: teleport,
        trusted: false,
        positionAt: _now,
        distanceAt: _now,
        track: line,
        stored: [...line, teleport.withOffTrack(true)],
      ),
      now: _now,
      freshWithin: _fresh,
    );
    expect(p!.point.lng, 8.5402);
    expect(p.weakGps, false);
  });

  test('before the line has a point, a trusted current fix is published', () {
    final p = livePublishPoint(
      _snap(current: _wp(8.5400), positionAt: _now),
      now: _now,
      freshWithin: _fresh,
    );
    expect(p!.point.lng, 8.5400);
  });

  test('before the line has a point, an untrusted current fix is not', () {
    final p = livePublishPoint(
      _snap(current: _wp(8.5400), trusted: false, positionAt: _now),
      now: _now,
      freshWithin: _fresh,
    );
    expect(p, isNull);
  });

  test('no fix through the gate but a fresh estimator fix publishes it weak',
      () {
    final coarse = _wp(8.5410, offTrack: true);
    final p = livePublishPoint(
      _snap(
        distanceAt: _now.subtract(const Duration(seconds: 2)),
        stored: [coarse],
      ),
      now: _now,
      freshWithin: _fresh,
    );
    expect(p!.point.lng, 8.5410);
    expect(p.weakGps, true);
  });

  test('a stale gated fix gives way to a fresher weak one', () {
    final line = [_wp(8.5400)];
    final coarse = _wp(8.5420, offTrack: true);
    final p = livePublishPoint(
      _snap(
        current: line.last,
        positionAt: _now.subtract(const Duration(seconds: 30)),
        distanceAt: _now,
        track: line,
        stored: [...line, coarse],
      ),
      now: _now,
      freshWithin: _fresh,
    );
    expect(p!.point.lng, 8.5420);
    expect(p.weakGps, true);
  });

  test('a race ping refuses the weak fallback', () {
    final p = livePublishPoint(
      _snap(distanceAt: _now, stored: [_wp(8.5410, offTrack: true)]),
      now: _now,
      freshWithin: _fresh,
      allowWeak: false,
    );
    expect(p, isNull);
  });

  test('nothing fresh publishes nothing', () {
    final line = [_wp(8.5400)];
    final p = livePublishPoint(
      _snap(
        current: line.last,
        positionAt: _now.subtract(const Duration(seconds: 30)),
        distanceAt: _now.subtract(const Duration(seconds: 30)),
        track: line,
        stored: [...line, _wp(8.5410, offTrack: true)],
      ),
      now: _now,
      freshWithin: _fresh,
    );
    expect(p, isNull);
  });

  test('a fresh estimator stamp over an on-line last store is not weak', () {
    final line = [_wp(8.5400)];
    final p = livePublishPoint(
      _snap(
        positionAt: _now.subtract(const Duration(seconds: 30)),
        distanceAt: _now,
        track: line,
      ),
      now: _now,
      freshWithin: _fresh,
    );
    expect(p, isNull);
  });
}
