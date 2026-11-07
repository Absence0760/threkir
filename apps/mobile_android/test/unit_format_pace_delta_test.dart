import 'package:core_models/core_models.dart' show DistanceUnit;
import 'package:flutter_test/flutter_test.dart';
import '../lib/preferences.dart';

// Mirrored case for case by apps/web/src/lib/format/pace_delta.test.ts.
void main() {
  String km(num d) => UnitFormat.paceDelta(d, DistanceUnit.km);
  String mi(num d) => UnitFormat.paceDelta(d, DistanceUnit.mi);

  test('per km: signed whole seconds with the unit', () {
    expect(km(12), '+12s/km');
    expect(km(-5), '−5s/km');
    expect(km(0), '0s/km');
  });

  test('per mile: converted, not relabelled', () {
    expect(mi(10), '+16s/mi');
    expect(mi(-10), '−16s/mi');
  });

  test('the "+428s" badge of issue #1300 reads +689s/mi', () {
    expect(mi(428), '+689s/mi');
  });

  test('a delta that rounds to zero carries no sign', () {
    expect(mi(0.2), '0s/mi');
    expect(km(-0.2), '0s/km');
    expect(km(-0.5), '0s/km');
  });
}
