import 'package:flutter_test/flutter_test.dart';

import '../lib/event_pricing.dart';

void main() {
  test('the refund policies are the CHECK vocabulary, defaulting as web does', () {
    expect(kEventRefundPolicies,
        ['full_until_start', 'full_until_24h', 'no_refund']);
    expect(kEventRefundPolicies, contains(kDefaultEventRefundPolicy));
  });

  test('an optional whole number: blank is none, out of range is refused', () {
    expect(parseOptionalWhole('', min: 1), (value: null, ok: true));
    expect(parseOptionalWhole('  12 ', min: 1), (value: 12, ok: true));
    expect(parseOptionalWhole('0', min: 1).ok, isFalse);
    expect(parseOptionalWhole('2.5', min: 1).ok, isFalse);
    expect(parseOptionalWhole('abc', min: 1).ok, isFalse);
    expect(parseOptionalWhole('520', min: 1, max: 520), (value: 520, ok: true));
    expect(parseOptionalWhole('521', min: 1, max: 520).ok, isFalse);
    expect(parseOptionalWhole('0', min: 0, max: 10080), (value: 0, ok: true));
  });

  test('a price must be at least 0.50, with either decimal separator', () {
    expect(parseEventPrice('22'), 22);
    expect(parseEventPrice('0.5'), 0.5);
    expect(parseEventPrice('12,50'), 12.5);
    expect(parseEventPrice('0.49'), isNull);
    expect(parseEventPrice(''), isNull);
    expect(parseEventPrice('free'), isNull);
  });

  test('a currency is three letters, stored lowercase', () {
    expect(parseCurrencyCode('USD'), 'usd');
    expect(parseCurrencyCode(' eur '), 'eur');
    expect(parseCurrencyCode('US'), isNull);
    expect(parseCurrencyCode('US1'), isNull);
    expect(parseCurrencyCode(''), isNull);
  });
}
