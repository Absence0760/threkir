import 'package:flutter_test/flutter_test.dart';

import '../lib/event_photo_window.dart';

final _occ = DateTime.utc(2026, 6, 20, 8);

void main() {
  test('a run that starts at the occurrence is inside the window', () {
    expect(isRunInEventPhotoWindow(DateTime.utc(2026, 6, 20, 8), _occ), isTrue);
  });

  test('the window opens exactly two hours before the occurrence', () {
    expect(isRunInEventPhotoWindow(DateTime.utc(2026, 6, 20, 6), _occ), isTrue);
    expect(isRunInEventPhotoWindow(DateTime.utc(2026, 6, 20, 5, 59, 59), _occ),
        isFalse);
  });

  test('the window closes 24 hours after the occurrence, exclusive', () {
    expect(isRunInEventPhotoWindow(DateTime.utc(2026, 6, 21, 7, 59, 59), _occ),
        isTrue);
    expect(isRunInEventPhotoWindow(DateTime.utc(2026, 6, 21, 8), _occ), isFalse);
  });

  test('a run from the previous month is outside the window', () {
    expect(isRunInEventPhotoWindow(DateTime.utc(2026, 5, 20, 8), _occ), isFalse);
  });

  test('the same instant in two renderings compares as one', () {
    expect(
        isRunInEventPhotoWindow(
            DateTime.parse('2026-06-20T09:00:00.000+01:00'), _occ),
        isTrue);
  });

  test('missing or unparseable input is outside the window', () {
    expect(isRunInEventPhotoWindow(null, _occ), isFalse);
    expect(isRunInEventPhotoWindow(DateTime.utc(2026, 6, 20, 8), null), isFalse);
    expect(isRunInEventPhotoWindow(DateTime.tryParse('not a date'), _occ),
        isFalse);
  });

  test('a steward may post from two hours before the occurrence', () {
    final opens = _occ.subtract(const Duration(hours: 2));
    expect(hasEventPhotoWindowOpened(_occ, opens), isTrue);
    expect(
        hasEventPhotoWindowOpened(
            _occ, opens.subtract(const Duration(milliseconds: 1))),
        isFalse);
    expect(hasEventPhotoWindowOpened(_occ, _occ.add(const Duration(days: 7))),
        isTrue);
  });

  test('a steward window with no parseable occurrence stays shut', () {
    expect(hasEventPhotoWindowOpened(null, DateTime.now()), isFalse);
    expect(hasEventPhotoWindowOpened(DateTime.tryParse('nope'), DateTime.now()),
        isFalse);
  });
}
