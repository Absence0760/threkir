import 'package:flutter_test/flutter_test.dart';

import '../lib/minor_units.dart';

// Mirrors the arithmetic cases of web's src/lib/format/minor_units.test.ts;
// that suite's source scans have no Dart analogue.
void main() {
  test('currencyFractionDigits: two-decimal currencies', () {
    expect(currencyFractionDigits('USD'), 2);
    expect(currencyFractionDigits('EUR'), 2);
    expect(currencyFractionDigits('GBP'), 2);
  });

  test('currencyFractionDigits: Stripe zero-decimal currencies carry no minor unit',
      () {
    for (final code in ['JPY', 'KRW', 'VND', 'CLP', 'XOF', 'PYG']) {
      expect(currencyFractionDigits(code), 0, reason: code);
    }
  });

  test('currencyFractionDigits: Stripe three-decimal currencies', () {
    for (final code in ['BHD', 'JOD', 'KWD', 'OMR', 'TND']) {
      expect(currencyFractionDigits(code), 3, reason: code);
    }
  });

  test('currencyFractionDigits: case- and whitespace-insensitive', () {
    expect(currencyFractionDigits('jpy'), 0);
    expect(currencyFractionDigits(' usd '), 2);
  });

  test('currencyFractionDigits: an unusable code falls back to two decimals',
      () {
    expect(currencyFractionDigits('ZZ'), 2);
    expect(currencyFractionDigits(''), 2);
  });

  test('fromMinorUnits: a two-decimal amount divides by 100', () {
    expect(fromMinorUnits(1999, 'USD'), 19.99);
    expect(fromMinorUnits(500000, 'usd'), 5000);
  });

  test('fromMinorUnits: a zero-decimal amount is already the base unit', () {
    expect(fromMinorUnits(1000, 'JPY'), 1000);
    expect(fromMinorUnits(50000, 'KRW'), 50000);
    expect(fromMinorUnits(250000, 'VND'), 250000);
  });

  test('fromMinorUnits: a three-decimal amount divides by 1000', () {
    expect(fromMinorUnits(1500, 'KWD'), 1.5);
    expect(fromMinorUnits(25000, 'BHD'), 25);
  });

  test('toMinorUnits: a two-decimal amount multiplies by 100', () {
    expect(toMinorUnits(19.99, 'USD'), 1999);
    expect(toMinorUnits(5000, 'usd'), 500000);
  });

  test('toMinorUnits: a zero-decimal amount is stored as entered', () {
    expect(toMinorUnits(1000, 'JPY'), 1000);
    expect(toMinorUnits(50000, 'KRW'), 50000);
  });

  test('toMinorUnits: a three-decimal amount stays a multiple of 10', () {
    expect(toMinorUnits(1.5, 'KWD'), 1500);
    expect(toMinorUnits(1.234, 'KWD'), 1230);
    expect(toMinorUnits(1.239, 'KWD'), 1240);
  });

  test('round trip: every currency class survives minor -> major -> minor', () {
    for (final (minor, code) in [(1999, 'USD'), (1000, 'JPY'), (1500, 'KWD')]) {
      expect(toMinorUnits(fromMinorUnits(minor, code), code), minor);
    }
  });

  test('currencyFractionDigits: currencies ISO calls zero-decimal but Stripe counts in hundredths',
      () {
    for (final code in ['COP', 'IDR', 'HUF', 'TWD', 'ALL', 'LBP', 'IQD']) {
      expect(currencyFractionDigits(code), 2, reason: code);
      expect(toMinorUnits(50000, code), 5000000, reason: code);
      expect(fromMinorUnits(5000000, code), 50000, reason: code);
    }
  });

  test('toMinorUnits: ISK and UGX are hundredths of a whole unit, never a fraction',
      () {
    for (final code in ['ISK', 'UGX', 'isk']) {
      expect(currencyFractionDigits(code), 2, reason: code);
      expect(toMinorUnits(5, code), 500, reason: code);
      expect(toMinorUnits(5.4, code), 500, reason: code);
      expect(toMinorUnits(5.5, code), 600, reason: code);
      expect(fromMinorUnits(500, code), 5, reason: code);
    }
  });
}
