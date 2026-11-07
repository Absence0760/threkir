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
}
