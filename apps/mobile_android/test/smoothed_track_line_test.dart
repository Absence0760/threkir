// ignore_for_file: avoid_relative_lib_imports
import 'package:core_models/core_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import '../lib/widgets/track_preview.dart';
import '../lib/widgets/track_segment.dart';

// A saved track carries the GPS distance smoother's position beside each raw
// fix (docs/features/gps_distance.md § Waypoint fields). Every reader that
// draws the run line draws the smoothed pair when both halves are present,
// and the raw fix otherwise.

// Metres per degree on the sphere `haversineMetres` measures (R = 6371 km),
// so a 10 m step in the fixture is 10 m to the reader under test.
const double _mPerLatDeg = 6371000 * pi / 180;

/// A north-bound line whose raw fixes zig-zag 3 m either side of it while
/// the smoothed positions sit on it.
List<Waypoint> _zigZag({required bool smoothed}) => [
      for (var i = 0; i < 11; i++)
        Waypoint(
          lat: i * 10 / _mPerLatDeg,
          lng: (i.isOdd ? 3 : -3) / _mPerLatDeg,
          smoothedLat: smoothed ? i * 10 / _mPerLatDeg : null,
          smoothedLng: smoothed ? 0 : null,
        ),
    ];

void main() {
  test('buildCumulativeDistances measures along the smoothed line', () {
    final cum = buildCumulativeDistances(_zigZag(smoothed: true));
    expect(cum.last, closeTo(100, 0.01));
    final raw = buildCumulativeDistances(_zigZag(smoothed: false));
    expect(raw.last, greaterThan(115),
        reason: 'the raw zig-zag reads long, so the fixture can tell them apart');
  });

  test('projectTrack draws the smoothed line, so it is a straight line', () {
    final pts = projectTrack(_zigZag(smoothed: true), 100, 100);
    final xs = pts.map((o) => o.dx).toSet();
    expect(xs, hasLength(1), reason: 'every smoothed fix shares a longitude');
    final raw = projectTrack(_zigZag(smoothed: false), 100, 100);
    expect(raw.map((o) => o.dx).toSet().length, greaterThan(1));
  });

  test('isTrackRenderable judges the smoothed span when present', () {
    // A stationary jitter cluster whose smoothed positions collapse to one
    // spot is not worth drawing, however far the raw fixes scatter.
    expect(
      isTrackRenderable(const [
        Waypoint(lat: 0, lng: 0, smoothedLat: 0, smoothedLng: 0),
        Waypoint(
            lat: 0.0001, lng: 0.0001, smoothedLat: 0.000001, smoothedLng: 0),
      ]),
      isFalse,
    );
  });

  test('a half smoothed pair falls back to the raw fix', () {
    final track = [
      const Waypoint(lat: 0, lng: 0, smoothedLat: 0.001),
      const Waypoint(lat: 0, lng: 0.001),
    ];
    final cum = buildCumulativeDistances(track);
    expect(cum.last, closeTo(111.3, 0.5),
        reason: 'measured raw to raw: 0.001 deg of longitude at the equator');
  });

  test('nearestTrackIdx snaps a tap to the smoothed line', () {
    final track = _zigZag(smoothed: true);
    final idx = nearestTrackIdx(LatLng(50 / _mPerLatDeg, 0), track);
    expect(idx, 5);
  });
}
