import 'package:flutter_test/flutter_test.dart';

import '../lib/screens/home_screen.dart';

void main() {
  group('bottomNavMetrics', () {
    test('keeps the shipped 64 dp bar at the default text scale', () {
      final m = bottomNavMetrics(1.0);
      expect(m.height, 64.0);
      expect(m.showLabels, isTrue);
    });

    test('grows the bar with the text scale instead of overflowing it', () {
      // The defect: a hard 64 dp box holding a 24 dp icon, a 2 dp gap and a
      // label overflowed by 12 px on Home at the largest accessibility size.
      // 64 dp is the floor, never the ceiling.
      expect(bottomNavMetrics(1.3).height, greaterThan(64.0));
      expect(bottomNavMetrics(1.6).height, greaterThan(bottomNavMetrics(1.3).height));
    });

    test('caps the growth so the bar cannot eat the screen', () {
      expect(bottomNavMetrics(1.6).height, lessThanOrEqualTo(96.0));
    });

    test('drops the label rather than showing two of its letters', () {
      // Past this point a fifth of the screen cannot hold the word, and the
      // old code ellipsised "Home" to "Ho". The icon and the Semantics label
      // both survive, so the destination is still announced in full.
      final m = bottomNavMetrics(2.0);
      expect(m.showLabels, isFalse);
      expect(m.height, 56.0);
    });

    test('treats a nonsense scale as the default rather than collapsing', () {
      for (final bad in [0.0, -1.0, double.nan, double.infinity]) {
        final m = bottomNavMetrics(bad);
        expect(m.height, 64.0, reason: 'scale=$bad');
        expect(m.showLabels, isTrue, reason: 'scale=$bad');
      }
    });
  });
}
