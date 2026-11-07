import 'package:core_models/core_models.dart' show DistanceUnit;
import 'package:flutter_test/flutter_test.dart';
import '../lib/preferences.dart';

// The live Elevation tile and every elevation readout format through these,
// so an imperial runner reads feet (issue #1300 section 1). Expected values
// are hand-computed at 3.28084 ft per metre.
void main() {
  const km = DistanceUnit.km;
  const mi = DistanceUnit.mi;

  test('metric reads whole metres', () {
    expect(UnitFormat.elevationValue(0, km), '0');
    expect(UnitFormat.elevationValue(0.4, km), '0');
    expect(UnitFormat.elevationValue(120.6, km), '121');
    expect(UnitFormat.elevationLabel(km), 'm');
  });

  test('imperial converts to whole feet', () {
    // 1 m = 3.28 ft; 100 m = 328.08 ft; 120 m = 393.70 ft.
    expect(UnitFormat.elevationValue(1, mi), '3');
    expect(UnitFormat.elevationValue(100, mi), '328');
    expect(UnitFormat.elevationValue(120, mi), '394');
    expect(UnitFormat.elevationLabel(mi), 'ft');
  });

  test('elevation joins value and unit, and a missing gain is a dash', () {
    expect(UnitFormat.elevation(120, km), '120 m');
    expect(UnitFormat.elevation(120, mi), '394 ft');
    expect(UnitFormat.elevation(null, mi), '—');
  });

  test('entry in the runner\'s unit round-trips through elevationToMetres', () {
    expect(UnitFormat.elevationToMetres(328.084, mi), closeTo(100, 1e-9));
    expect(UnitFormat.elevationToMetres(250, km), 250);
    for (final m in [0.0, 12.5, 100.0, 2500.0]) {
      final ft = m * 3.28084;
      expect(UnitFormat.elevationToMetres(ft, mi), closeTo(m, 1e-9));
    }
  });
}
