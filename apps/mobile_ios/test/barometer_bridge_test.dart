import 'package:flutter_test/flutter_test.dart';
import '../lib/barometer_bridge.dart';

void main() {
  group('barometricAltitudeFromEvent', () {
    test('reads altitudeM as metres', () {
      expect(barometricAltitudeFromEvent({'altitudeM': 12.5}), 12.5);
      expect(barometricAltitudeFromEvent({'altitudeM': -3}), -3.0);
    });

    test('anything else is no reading', () {
      expect(barometricAltitudeFromEvent(null), isNull);
      expect(barometricAltitudeFromEvent(12.5), isNull);
      expect(barometricAltitudeFromEvent(<String, Object?>{}), isNull);
      expect(barometricAltitudeFromEvent({'altitudeM': '12'}), isNull);
      expect(barometricAltitudeFromEvent({'altitudeM': double.nan}), isNull);
      expect(
        barometricAltitudeFromEvent({'altitudeM': double.infinity}),
        isNull,
      );
    });
  });
}
