import 'package:core_models/core_models.dart' show DistanceUnit;
import 'package:flutter_test/flutter_test.dart';

import '../lib/l10n/number_format.dart';
import '../lib/l10n/locale_support.dart';
import '../lib/preferences.dart';

void main() {
  tearDown(() => registerActiveLocaleTag('en'));

  group('formatFixed', () {
    test('en matches the old toStringAsFixed exactly', () {
      expect(formatFixed(5.214, 2, 'en'), '5.21');
      expect(formatFixed(5.214, 2, 'en'), 5.214.toStringAsFixed(2));
      expect(formatFixed(12.34, 1, 'en'), '12.3');
      expect(formatFixed(0, 2, 'en'), '0.00');
    });

    test('en does NOT group thousands (preserves old elevation output)', () {
      // 10000 m elevation must render "10000", not "10,000".
      expect(formatFixed(10000, 0, 'en'), '10000');
      expect(formatFixed(10000, 0, 'en'), 10000.0.round().toString());
      expect(formatFixed(1234.5, 2, 'en'), '1234.50');
    });

    test('de uses a comma decimal separator', () {
      expect(formatFixed(5.21, 2, 'de'), '5,21');
      expect(formatFixed(12.3, 1, 'de'), '12,3');
      expect(formatFixed(10000, 0, 'de'), '10000');
    });

    test('negatives keep the ASCII minus for the shipped locales', () {
      expect(formatFixed(-3.5, 1, 'en'), '-3.5');
      expect(formatFixed(-3.5, 1, 'de'), '-3,5');
    });

    test('degenerate input never reaches the label as NaN, ∞ or a signed zero',
        () {
      // A training-stress balance of -0.04 rendered "-0.0"; a 0 m distance
      // divided to NaN rendered "NaN km". Same table as the formatDecimal
      // degenerate test in web's number.test.ts.
      const cases = <(double, int, String)>[
        (double.nan, 1, '—'),
        (double.infinity, 1, '—'),
        (double.negativeInfinity, 1, '—'),
        (-0.0, 1, '0.0'),
        (-0.04, 1, '0.0'),
        (-0.05, 1, '-0.1'),
        (-0.3, 1, '-0.3'),
        (-0.004, 2, '0.00'),
        (-0.3, 0, '0'),
        (-0.5, 0, '-1'),
      ];
      for (final (value, digits, expected) in cases) {
        expect(formatFixed(value, digits, 'en'), expected,
            reason: 'formatFixed($value, $digits)');
      }
      expect(formatFixed(-0.04, 1, 'de'), '0,0');
    });
  });

  group('UnitFormat respects the active locale', () {
    test('distance renders en with a dot, de with a comma', () {
      registerActiveLocaleTag('en');
      expect(UnitFormat.distance(5210, DistanceUnit.km), '5.21 km');
      registerActiveLocaleTag('de');
      expect(UnitFormat.distance(5210, DistanceUnit.km), '5,21 km');
    });

    test('miles distance is locale-aware', () {
      registerActiveLocaleTag('en');
      expect(UnitFormat.distance(1609.344, DistanceUnit.mi), '1.00 mi');
      registerActiveLocaleTag('de');
      expect(UnitFormat.distance(1609.344, DistanceUnit.mi), '1,00 mi');
    });

    test('speed is locale-aware', () {
      registerActiveLocaleTag('en');
      expect(UnitFormat.speed(360, DistanceUnit.km), '10.0');
      registerActiveLocaleTag('de');
      expect(UnitFormat.speed(360, DistanceUnit.km), '10,0');
    });

    test('elevation is locale-aware and ungrouped', () {
      registerActiveLocaleTag('en');
      expect(UnitFormat.elevation(120, DistanceUnit.km), '120 m');
      expect(UnitFormat.elevation(10000, DistanceUnit.km), '10000 m');
      registerActiveLocaleTag('de');
      expect(UnitFormat.elevation(120, DistanceUnit.km), '120 m');
    });
  });

  group('formatPercent', () {
    test('puts the sign where each locale does', () {
      expect(formatPercent(0.42, 'en'), '42%');
      expect(formatPercent(0.42, 'de'), '42\u00a0%');
      expect(formatPercent(0.42, 'fr'), matches(RegExp(r'^42\s%$')));
      expect(formatPercent(1, 'ja'), '100%');
    });

    test('a non-finite fraction is a dash, not NaN%', () {
      expect(formatPercent(double.nan, 'en'), '—');
    });
  });
}
