import 'package:core_models/core_models.dart' show DistanceUnit;
import 'package:flutter_test/flutter_test.dart';
import '../lib/preferences.dart';

// Mirrored case for case by apps/web/src/lib/format/short_distance.test.ts.
void main() {
  String km(double m, [String tag = 'en']) =>
      UnitFormat.shortDistance(m, DistanceUnit.km, tag);
  String mi(double m, [String tag = 'en']) =>
      UnitFormat.shortDistance(m, DistanceUnit.mi, tag);

  test('metric: metres below a kilometre, kilometres from one up', () {
    expect(km(0), '0 m');
    expect(km(400), '400 m');
    expect(km(999.4), '999 m');
    expect(km(1000), '1.00 km');
    expect(km(5234), '5.23 km');
  });

  test('imperial: yards below a mile, miles from one up', () {
    expect(mi(400), '437 yd');
    expect(mi(1371.6), '1,500 yd');
    expect(mi(1609.344), '1.00 mi');
    expect(mi(8046.72), '5.00 mi');
  });

  test('a 5 mi step 15 s in reads in miles, not 8779 yd (issue #1300)', () {
    expect(mi(8027.7), '4.99 mi');
  });

  test('follows the locale separators', () {
    expect(km(5234, 'de'), '5,23 km');
    expect(mi(1371.6, 'de'), '1.500 yd');
  });

  String thr(double m, DistanceUnit u, int digits, [String tag = 'en']) =>
      UnitFormat.thresholdDistance(m, u, digits, tag);

  test('threshold: one decimal for a race distance, dropped when whole', () {
    expect(thr(5000, DistanceUnit.km, 1), '5 km');
    expect(thr(21097, DistanceUnit.km, 1), '21.1 km');
    expect(thr(42195, DistanceUnit.mi, 1), '26.2 mi');
    expect(thr(50000, DistanceUnit.mi, 1), '31.1 mi');
  });

  test('threshold: a whole number for a total, grouped by the locale', () {
    expect(thr(1000000, DistanceUnit.km, 0), '1,000 km');
    expect(thr(1000000, DistanceUnit.mi, 0), '621 mi');
    expect(thr(5000000, DistanceUnit.mi, 0, 'de'), '3.107 mi');
    expect(thr(21097, DistanceUnit.km, 1, 'de'), '21,1 km');
  });
}
