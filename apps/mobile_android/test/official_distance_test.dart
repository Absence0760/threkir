// Mirrors apps/web/src/lib/routes/official_distance.test.ts case for case.
import 'package:flutter_test/flutter_test.dart';

import '../lib/official_distance.dart';

void main() {
  test('a route shows its official distance when it has one', () {
    expect(routeDisplayDistanceM(42670, 42195), 42195);
  });

  test('a route without an official distance shows the measured one', () {
    expect(routeDisplayDistanceM(42670, null), 42670);
    expect(routeDisplayDistanceM(42670, 0), 42670);
    expect(routeDisplayDistanceM(42670, -1), 42670);
    expect(routeDisplayDistanceM(42670, double.nan), 42670);
  });

  test('the scale is official metres per metre of line', () {
    expect(courseDistanceScale(42670, 42195), 42195 / 42670);
    // Richmond: the race's km 42 sits 42,000 / scale = 42,473 m along the trace.
    expect((42000 / courseDistanceScale(42670, 42195)).round(), 42473);
  });

  test('the scale is 1 when either figure is missing', () {
    expect(courseDistanceScale(42670, null), 1);
    expect(courseDistanceScale(42670, 0), 1);
    expect(courseDistanceScale(0, 42195), 1);
    expect(courseDistanceScale(double.nan, 42195), 1);
  });

  test('an official distance within 10% of the measured one is accepted', () {
    expect(officialDistanceVerdict(42670, 42195), OfficialDistanceVerdict.ok);
    expect(officialDistanceVerdict(10000, 11000), OfficialDistanceVerdict.ok);
    expect(officialDistanceVerdict(10000, 9000), OfficialDistanceVerdict.ok);
  });

  test('an official distance more than 10% off the measured one is refused',
      () {
    expect(
        officialDistanceVerdict(10000, 11001), OfficialDistanceVerdict.tooFar);
    expect(
        officialDistanceVerdict(42670, 50000), OfficialDistanceVerdict.tooFar);
  });

  test('a non-positive or over-1,000 km official distance is out of range',
      () {
    expect(officialDistanceVerdict(42670, 0), OfficialDistanceVerdict.outOfRange);
    expect(
        officialDistanceVerdict(42670, -1), OfficialDistanceVerdict.outOfRange);
    expect(officialDistanceVerdict(990000, 1000001),
        OfficialDistanceVerdict.outOfRange);
    expect(officialDistanceVerdict(42670, double.nan),
        OfficialDistanceVerdict.outOfRange);
  });
}
