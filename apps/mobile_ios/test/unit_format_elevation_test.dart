import 'package:core_models/core_models.dart' show DistanceUnit;
import 'package:flutter_test/flutter_test.dart';

import '../lib/preferences.dart';

// The live Elevation tile and every elevation readout format through these,
// so an imperial runner reads feet (issue #1300 section 1). Expected values
// are hand-computed at 3.28084 ft per metre. The first four tests are
// mirrored case for case by apps/web/src/lib/format/elevation.test.ts.
void main() {
  const km = DistanceUnit.km;
  const mi = DistanceUnit.mi;

  test('metric reads whole metres', () {
    expect(UnitFormat.elevationValue(0, km, 'en'), '0');
    expect(UnitFormat.elevationValue(0.4, km, 'en'), '0');
    expect(UnitFormat.elevationValue(120.5, km, 'en'), '121');
    expect(UnitFormat.elevationValue(120.6, km, 'en'), '121');
    // A point below sea level rounds half up, as Math.round does.
    expect(UnitFormat.elevationValue(-0.5, km, 'en'), '0');
    expect(UnitFormat.elevationValue(-430.5, km, 'en'), '-430');
    expect(UnitFormat.elevationLabel(km), 'm');
  });

  test('imperial converts to whole feet', () {
    // 1 m = 3.28 ft; 100 m = 328.08 ft; 120 m = 393.70 ft.
    expect(UnitFormat.elevationValue(1, mi, 'en'), '3');
    expect(UnitFormat.elevationValue(100, mi, 'en'), '328');
    expect(UnitFormat.elevationValue(120, mi, 'en'), '394');
    expect(UnitFormat.elevationLabel(mi), 'ft');
  });

  test('joins value and unit, and a missing gain is a dash', () {
    expect(UnitFormat.elevation(120, km, 'en'), '120 m');
    expect(UnitFormat.elevation(120, mi, 'en'), '394 ft');
    expect(UnitFormat.elevation(null, mi, 'en'), '—');
    expect(UnitFormat.elevation(null, km, 'en'), '—');
  });

  test('a large gain is grouped by the locale (issue #1312)', () {
    // 3048 m is 9999.996 ft, which rounds to 10000 ft.
    expect(UnitFormat.elevation(3048, mi, 'en'), '10,000 ft');
    expect(UnitFormat.elevation(10000, km, 'en'), '10,000 m');
    expect(UnitFormat.elevation(3048, mi, 'de'), '10.000 ft');
    expect(UnitFormat.elevation(10000, km, 'de'), '10.000 m');
    expect(
      UnitFormat.elevation(3048, mi, 'fr'),
      matches(RegExp(r'^10\s000 ft$')),
    );
    expect(
      UnitFormat.elevation(10000, km, 'fr'),
      matches(RegExp(r'^10\s000 m$')),
    );
    expect(UnitFormat.elevation(999, km, 'en'), '999 m');
  });

  test('entry in the runner\'s unit round-trips through elevationToMetres', () {
    expect(UnitFormat.elevationToMetres(328.084, mi), closeTo(100, 1e-9));
    expect(UnitFormat.elevationToMetres(250, km), 250);
    for (final m in [0.0, 12.5, 100.0, 2500.0]) {
      final ft = m * 3.28084;
      expect(UnitFormat.elevationToMetres(ft, mi), closeTo(m, 1e-9));
    }
  });

  test('stride length reads two decimals in metres or feet', () {
    // 1.18 m x 3.28084 = 3.871 ft.
    expect(UnitFormat.strideLength(1.18, km, 'en'), '1.18 m');
    expect(UnitFormat.strideLength(1.18, mi, 'en'), '3.87 ft');
    expect(UnitFormat.strideLength(1.18, km, 'de'), '1,18 m');
  });
}
