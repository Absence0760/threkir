// ignore_for_file: avoid_relative_lib_imports
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/parkrun_barcode_cache.dart';

// The device copy is what a runner shows at a finish funnel with no signal,
// so a bad entry must read as "no copy" — never a throw, and never a code
// built from something that is not an athlete number.

const _key = ParkrunBarcodeCache.storageKey;
const _cache = ParkrunBarcodeCache();

Future<String?> _readWith(Object stored) {
  SharedPreferences.setMockInitialValues({_key: stored});
  return _cache.read('u1');
}

void main() {
  test('a truncated or non-JSON entry reads as no copy', () async {
    expect(await _readWith('{"user_id":"u1","number":"A12'), isNull);
    expect(await _readWith('not json'), isNull);
    expect(await _readWith(''), isNull);
  });

  test('JSON of the wrong shape reads as no copy', () async {
    expect(await _readWith('"A123456"'), isNull);
    expect(await _readWith('["u1","A123456"]'), isNull);
    expect(await _readWith('null'), isNull);
    expect(await _readWith(jsonEncode({'user_id': 'u1'})), isNull);
    expect(await _readWith(jsonEncode({'user_id': 'u1', 'number': 123456})),
        isNull);
    expect(await _readWith(jsonEncode({'number': 'A123456'})), isNull);
  });

  test('a value of the wrong type under the key reads as no copy', () async {
    expect(await _readWith(42), isNull);
    expect(await _readWith(<String>['A123456']), isNull);
  });

  test('a stored number that is not an athlete number is not returned',
      () async {
    for (final bad in ['B123456', '123456', 'A', 'A12345a', 'A1234567890123']) {
      expect(
        await _readWith(jsonEncode({'user_id': 'u1', 'number': bad})),
        isNull,
        reason: bad,
      );
    }
  });

  test('a stored number in a forgiven form comes back canonical', () async {
    expect(
      await _readWith(jsonEncode({'user_id': 'u1', 'number': ' a 123 456 '})),
      'A123456',
    );
  });

  test('writing an invalid or empty number forgets the copy', () async {
    for (final bad in <String?>[null, '', 'B1', '1234 5678']) {
      SharedPreferences.setMockInitialValues({
        _key: jsonEncode({'user_id': 'u1', 'number': 'A1'}),
      });
      await _cache.write('u1', bad);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey(_key), isFalse, reason: '$bad');
    }
  });

  test('a write stores the canonical number for its account only', () async {
    SharedPreferences.setMockInitialValues({});
    await _cache.write('u1', ' a42 ');
    expect(await _cache.read('u1'), 'A42');
    expect(await _cache.read('u2'), isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(jsonDecode(prefs.getString(_key)!), {'user_id': 'u1', 'number': 'A42'});
  });
}
