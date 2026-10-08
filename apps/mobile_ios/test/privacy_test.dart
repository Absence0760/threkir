import 'package:flutter_test/flutter_test.dart';
import '../lib/privacy.dart';

const _home = PrivacyZone(lat: 40.7128, lng: -74.006, radiusM: 200);

class _Pt {
  final double lat;
  final double lng;
  final double? smoothedLat;
  final double? smoothedLng;
  const _Pt(this.lat, this.lng, {this.smoothedLat, this.smoothedLng});
}

double _lat(_Pt p) => p.lat;
double _lng(_Pt p) => p.lng;
double? _sLat(_Pt p) => p.smoothedLat;
double? _sLng(_Pt p) => p.smoothedLng;

/// A fix whose raw position is ~840 m east of home but whose smoothed
/// position the RTS smoother pulled onto home itself.
_Pt _smoothedHome(double dLng) => _Pt(_home.lat, _home.lng + dLng,
    smoothedLat: _home.lat, smoothedLng: _home.lng);

/// Tiny offset that crosses outside a 200 m radius — about 350 m east.
_Pt _offset(double lat, double lng, double dLng) => _Pt(lat, lng + dLng);

void main() {
  group('isInAnyZone', () {
    test('empty zones returns false', () {
      expect(isInAnyZone(0, 0, const []), isFalse);
    });

    test('center is in zone', () {
      expect(isInAnyZone(_home.lat, _home.lng, const [_home]), isTrue);
    });

    test('far point is not', () {
      final p = _offset(_home.lat, _home.lng, 0.01);
      expect(isInAnyZone(p.lat, p.lng, const [_home]), isFalse);
    });
  });

  group('isFixInAnyZone', () {
    test('a smoothed position in a zone is in, though the raw one is out', () {
      final p = _smoothedHome(0.01);
      expect(isInAnyZone(p.lat, p.lng, const [_home]), isFalse);
      expect(
          isFixInAnyZone(
              p.lat, p.lng, p.smoothedLat, p.smoothedLng, const [_home]),
          isTrue);
    });

    test('half a smoothed pair is ignored and the raw position decides', () {
      final p = _offset(_home.lat, _home.lng, 0.01);
      expect(
          isFixInAnyZone(p.lat, p.lng, _home.lat, null, const [_home]),
          isFalse);
    });
  });

  group('clipPointsToZones', () {
    test('empty zones returns input', () {
      final pts = const [_Pt(1, 1), _Pt(2, 2)];
      final out = clipPointsToZones<_Pt>(pts, const [],
          latOf: _lat, lngOf: _lng, smoothedLatOf: _sLat, smoothedLngOf: _sLng);
      expect(out, equals(pts));
    });

    test('drops leading + trailing in-zone', () {
      final pts = [
        _Pt(_home.lat, _home.lng), // in
        _Pt(_home.lat, _home.lng), // in
        _offset(_home.lat, _home.lng, 0.01), // out (mid)
        _offset(_home.lat, _home.lng, 0.02), // out (mid)
        _Pt(_home.lat, _home.lng), // in (trailing)
      ];
      final out = clipPointsToZones<_Pt>(pts, const [_home],
          latOf: _lat, lngOf: _lng, smoothedLatOf: _sLat, smoothedLngOf: _sLng);
      expect(out.length, 2);
      expect(identical(out[0], pts[2]), isTrue);
      expect(identical(out[1], pts[3]), isTrue);
    });

    test('keeps interior in-zone segments (only ends are clipped)', () {
      final pts = [
        _offset(_home.lat, _home.lng, 0.01), // out
        _Pt(_home.lat, _home.lng), // in (interior — kept)
        _offset(_home.lat, _home.lng, 0.02), // out
      ];
      final out = clipPointsToZones<_Pt>(pts, const [_home],
          latOf: _lat, lngOf: _lng, smoothedLatOf: _sLat, smoothedLngOf: _sLng);
      expect(out, equals(pts));
    });

    test('every point in zone returns empty', () {
      final pts = [
        _Pt(_home.lat, _home.lng),
        _Pt(_home.lat + 0.0001, _home.lng + 0.0001),
      ];
      final out = clipPointsToZones<_Pt>(pts, const [_home],
          latOf: _lat, lngOf: _lng, smoothedLatOf: _sLat, smoothedLngOf: _sLng);
      expect(out, isEmpty);
    });

    // The zone test is haversine, and sin/cos are periodic, so a whole-turn
    // longitude error cancels — privacy is the one route helper that needed
    // no antimeridian fix. Pinned so a future reader doesn't have to take
    // that on trust, and so nobody "fixes" it into a planar frame.
    test('a zone on the antimeridian still catches a point across it', () {
      const line = PrivacyZone(lat: 0, lng: 179.999, radiusM: 300);
      expect(isInAnyZone(0, -179.999, const [line]), isTrue);
      expect(isInAnyZone(0, -179.99, const [line]), isFalse);
    });

    test('multiple zones — clips against the union', () {
      const work = PrivacyZone(lat: 40.75, lng: -73.99, radiusM: 200);
      final pts = [
        _Pt(_home.lat, _home.lng), // in home
        _offset(_home.lat, _home.lng, 0.01), // out (mid)
        _Pt(work.lat, work.lng), // in work (trailing)
      ];
      final out = clipPointsToZones<_Pt>(pts, const [_home, work],
          latOf: _lat, lngOf: _lng, smoothedLatOf: _sLat, smoothedLngOf: _sLng);
      expect(out.length, 1);
      expect(identical(out[0], pts[1]), isTrue);
    });

    test('drops leading + trailing fixes whose smoothed position is in a zone',
        () {
      final pts = [
        _smoothedHome(0.01), // raw out, smoothed in (leading)
        _offset(_home.lat, _home.lng, 0.02), // out
        _offset(_home.lat, _home.lng, 0.03), // out
        _smoothedHome(0.01), // raw out, smoothed in (trailing)
      ];
      final out = clipPointsToZones<_Pt>(pts, const [_home],
          latOf: _lat, lngOf: _lng, smoothedLatOf: _sLat, smoothedLngOf: _sLng);
      expect(out.length, 2);
      expect(identical(out[0], pts[1]), isTrue);
      expect(identical(out[1], pts[2]), isTrue);
    });

    test('keeps an interior fix whose smoothed position is in a zone', () {
      final pts = [
        _offset(_home.lat, _home.lng, 0.02), // out
        _smoothedHome(0.01), // interior — kept
        _offset(_home.lat, _home.lng, 0.03), // out
      ];
      final out = clipPointsToZones<_Pt>(pts, const [_home],
          latOf: _lat, lngOf: _lng, smoothedLatOf: _sLat, smoothedLngOf: _sLng);
      expect(out, equals(pts));
    });
  });
}
