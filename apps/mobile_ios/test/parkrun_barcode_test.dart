import 'package:flutter_test/flutter_test.dart';

import '../lib/parkrun_barcode.dart';

// Reference module strings built from JsBarcode's CODE128 `BARS` table, an
// encoder independent of the width table under test.
const _refA123456 =
    '1101001000010100011000100111001101100111001011001011100110010011101101110010011001110100101001100001100011101011';
const _refA4027501 =
    '110100100001010001100011001001110100111011001100111001011101101110110111001001001110110010011100110100101100001100011101011';
const _refA1 = '110100100001010001100010011100110100001001101100011101011';

void main() {
  test('athlete number: canonical numbers pass unchanged', () {
    expect(normalizeParkrunAthleteNumber('A123456'), 'A123456');
    expect(normalizeParkrunAthleteNumber('A1'), 'A1');
    expect(normalizeParkrunAthleteNumber('A123456789012'), 'A123456789012');
  });

  test('athlete number: whitespace and a lowercase a are forgiven', () {
    expect(normalizeParkrunAthleteNumber('  a123456 '), 'A123456');
    expect(normalizeParkrunAthleteNumber('A 123 456'), 'A123456');
  });

  test('athlete number: anything else is refused', () {
    expect(normalizeParkrunAthleteNumber(null), isNull);
    expect(normalizeParkrunAthleteNumber(''), isNull);
    expect(normalizeParkrunAthleteNumber('   '), isNull);
    expect(normalizeParkrunAthleteNumber('123456'), isNull);
    expect(normalizeParkrunAthleteNumber('A'), isNull);
    expect(normalizeParkrunAthleteNumber('B123456'), isNull);
    expect(normalizeParkrunAthleteNumber('A12345a'), isNull);
    expect(normalizeParkrunAthleteNumber('A1234567890123'), isNull);
    expect(normalizeParkrunAthleteNumber('A١٢٣'), isNull);
  });

  test('pattern table: 107 symbols, 11 modules each, STOP 13', () {
    expect(kCode128Patterns.length, 107);
    for (var i = 0; i < kCode128Patterns.length; i++) {
      final p = kCode128Patterns[i];
      final sum = p.split('').fold<int>(0, (s, d) => s + int.parse(d));
      expect(sum, i == kCode128Stop ? 13 : 11, reason: 'symbol $i');
      expect(p.length, i == kCode128Stop ? 7 : 6, reason: 'symbol $i');
    }
    expect(kCode128Patterns.toSet().length, 107);
  });

  test('symbols: START B, set-B values, mod-103 check, STOP', () {
    expect(code128BSymbols('A123456'),
        [104, 33, 17, 18, 19, 20, 21, 22, 63, 106]);
    expect(code128BSymbols('A1'), [104, 33, 17, 68, 106]);
  });

  test('symbols: refuses empty and non-printable input', () {
    expect(() => code128BSymbols(''), throwsRangeError);
    expect(() => code128BSymbols('A\n1'), throwsRangeError);
    expect(() => code128BSymbols('Aé'), throwsRangeError);
  });

  test('modules match the reference encodings', () {
    expect(code128BModules('A123456'), _refA123456);
    expect(code128BModules('A4027501'), _refA4027501);
    expect(code128BModules('A1'), _refA1);
  });

  test('modules: 11 per symbol plus 13 for STOP, bar at both ends', () {
    final modules = code128BModules('A123456');
    expect(modules.length, 11 * 9 + 13);
    expect(modules[0], '1');
    expect(modules[modules.length - 1], '1');
  });

  test('bars: one run per contiguous bar', () {
    expect(barcodeBars('0110100111'), const [
      BarcodeBar(start: 1, width: 2),
      BarcodeBar(start: 4, width: 1),
      BarcodeBar(start: 7, width: 3),
    ]);
    expect(barcodeBars(''), isEmpty);
    final bars = barcodeBars(_refA1);
    expect(bars.fold<int>(0, (s, b) => s + b.width),
        _refA1.split('').where((c) => c == '1').length);
  });
}
