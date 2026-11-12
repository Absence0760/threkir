// ignore_for_file: avoid_relative_lib_imports
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import '../lib/widgets/track_decorations.dart';

const double _metresPerLatDegree = 111320;

/// Build a straight north-bound track of [n] waypoints, [stepM] apart,
/// anchored at lat0 / lng0.
List<LatLng> _straight({
  required int n,
  required double stepM,
  double lat0 = 0,
  double lng0 = 0,
}) {
  final out = <LatLng>[];
  for (int i = 0; i < n; i++) {
    out.add(LatLng(lat0 + i * stepM / _metresPerLatDegree, lng0));
  }
  return out;
}

void main() {
  group('computeDistanceMarkers', () {
    test('emits one marker per km on a 5 km straight track', () {
      final track = _straight(n: 51, stepM: 100); // 5000 m
      final markers = computeDistanceMarkers(track, useMiles: false);
      // Markers at 1, 2, 3, 4 km; the 5 km mark coincides with the end
      // cap so it's optional — accept 4 or 5.
      expect(markers.length, inInclusiveRange(4, 5));
      expect(markers.first.label, 1);
      expect(markers[1].label, 2);
      expect(markers[2].label, 3);
      expect(markers[3].label, 4);
    });

    test('returns empty for tracks under 2 points', () {
      expect(computeDistanceMarkers(const [], useMiles: false), isEmpty);
      expect(
        computeDistanceMarkers([const LatLng(0, 0)], useMiles: false),
        isEmpty,
      );
    });

    test('returns empty when the track is shorter than one step', () {
      final track = _straight(n: 5, stepM: 100); // 400 m, less than 1 km
      expect(computeDistanceMarkers(track, useMiles: false), isEmpty);
    });

    test('miles produces fewer markers than km on the same track', () {
      final track = _straight(n: 51, stepM: 100); // 5000 m
      final km = computeDistanceMarkers(track, useMiles: false).length;
      final mi = computeDistanceMarkers(track, useMiles: true).length;
      expect(mi, lessThan(km), reason: '5 km is only ~3.1 mi');
      expect(mi, inInclusiveRange(2, 3));
    });

    test('totalDistanceM rescales markers when polyline is sparse', () {
      // 1 km of polyline geometry but the authoritative route distance
      // is 5 km — markers should still cover 1..5 along the polyline.
      final track = _straight(n: 11, stepM: 100); // 1000 m polyline
      final markers = computeDistanceMarkers(
        track,
        useMiles: false,
        totalDistanceM: 5000,
      );
      expect(markers.length, inInclusiveRange(4, 5));
      expect(markers.last.label, inInclusiveRange(4, 5));
    });

    test('places an official distance shorter than the line at its own km',
        () {
      // 12 km of line for a 10.5 km course: km k sits k·12/10.5 km along it.
      final track = _straight(n: 121, stepM: 100);
      final markers = computeDistanceMarkers(
        track,
        useMiles: false,
        totalDistanceM: 12000,
        officialDistanceM: 10500,
      );
      expect(markers.map((m) => m.label).toList(),
          [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
      expect(
        (markers[4].position.latitude * _metresPerLatDegree -
                5000 * 12000 / 10500)
            .abs(),
        lessThan(1),
      );
    });

    test('lets an official distance win over the sparse-line heuristic', () {
      final track = _straight(n: 11, stepM: 100);
      final markers = computeDistanceMarkers(
        track,
        useMiles: false,
        totalDistanceM: 4000,
        officialDistanceM: 2500,
      );
      expect(markers.map((m) => m.label).toList(), [1, 2]);
    });

    test('marker positions interpolate within segments', () {
      // Two-point track, ~2 km long via haversine. The 1 km marker
      // should land at roughly the midpoint — within 5 m, which is
      // GPS noise floor.
      final track = [
        const LatLng(0, 0),
        LatLng(2000 / _metresPerLatDegree, 0),
      ];
      final markers = computeDistanceMarkers(track, useMiles: false);
      expect(markers.length, 1);
      // 5 m / 111_320 m per lat degree ≈ 4.5e-5 degrees of slack.
      expect(
        (markers.first.position.latitude - 1000 / _metresPerLatDegree).abs(),
        lessThan(5e-5),
      );
    });
  });

  group('computeChevrons', () {
    test('emits chevrons every stepMetres along the track', () {
      final track = _straight(n: 21, stepM: 100); // 2000 m
      final chevrons = computeChevrons(track, stepMetres: 500);
      // 500, 1000, 1500 — 1750 cap is past 2000 - 250.
      expect(chevrons.length, inInclusiveRange(3, 4));
    });

    test('returns empty for tracks shorter than stepMetres', () {
      final short = _straight(n: 3, stepM: 100); // 200 m
      expect(computeChevrons(short, stepMetres: 500), isEmpty);
    });

    test('north-bound chevrons rotate to point up', () {
      final track = _straight(n: 11, stepM: 100); // 1 km north
      final chevrons = computeChevrons(track, stepMetres: 500);
      // Screen-y grows downward; a north-bound segment maps to angle
      // -π/2 (the chevron icon points right at angle 0 and rotates
      // counter-clockwise to point up).
      expect(chevrons.first.angleRadians, closeTo(-pi / 2, 0.05));
    });

    test('returns empty for invalid stepMetres', () {
      final track = _straight(n: 11, stepM: 100);
      expect(computeChevrons(track, stepMetres: 0), isEmpty);
      expect(computeChevrons(track, stepMetres: -10), isEmpty);
    });
  });

  group('distanceMarkerRank', () {
    test('ranks every 10th, then every 5th, then even, then odd', () {
      expect([10, 20, 40].map(distanceMarkerRank), [0, 0, 0]);
      expect([5, 15, 35].map(distanceMarkerRank), [1, 1, 1]);
      expect([2, 4, 42].map(distanceMarkerRank), [2, 2, 2]);
      expect([1, 3, 41].map(distanceMarkerRank), [3, 3, 3]);
    });
  });

  group('thinDistanceMarkers', () {
    // A 42 km straight course on the equator: 1 km is ~52 px at zoom 13
    // and ~3.3 px at zoom 9, so zoom 13 keeps every badge and zoom 9 keeps
    // only the ones a 28 px (~8.6 km) gap allows, best rank first.
    final marathon = computeDistanceMarkers(
      _straight(n: 421, stepM: 100),
      useMiles: false,
    );

    test('keeps every badge when they already sit apart', () {
      final kept = thinDistanceMarkers(marathon, zoom: 13);
      expect(kept.map((m) => m.label), marathon.map((m) => m.label));
    });

    test('zoomed out, keeps the tens and drops what would touch them', () {
      final kept = thinDistanceMarkers(marathon, zoom: 9).map((m) => m.label);
      expect(kept, containsAll([10, 20, 30, 40]));
      // 5 sits 5 km (~16 px) from 10, which outranks it.
      expect(kept, isNot(contains(5)));
      expect(kept.length, lessThan(10));
    });

    test('drops the second leg of an out-and-back that lands on the first',
        () {
      final out = _straight(n: 31, stepM: 100);
      final track = [...out, ...out.reversed.skip(1)];
      final markers = computeDistanceMarkers(track, useMiles: false);
      final kept = thinDistanceMarkers(markers, zoom: 14).map((m) => m.label);
      // 1 and 5 sit on the same spot (km 1 out, km 5 back); 5 outranks 1.
      expect(kept, contains(5));
      expect(kept, isNot(contains(1)));
      expect(kept, contains(3));
    });

    test('returns markers in their input order', () {
      final kept = thinDistanceMarkers(marathon, zoom: 10).map((m) => m.label);
      expect(kept.toList(), [...kept]..sort());
    });
  });
}
