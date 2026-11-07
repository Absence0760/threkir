import 'package:core_models/core_models.dart';
import 'package:test/test.dart';

const _ok = ManualDurationResult.ok;
const _failed = ManualDurationResult.failed;

void main() {
  test('the bound is ten days and the hours box is wide enough to type it', () {
    expect(kMaxRunDurationS, 10 * 24 * 3600);
    expect('${kMaxRunDurationS ~/ 3600}'.length, kHoursMaxDigits);
    expect('59'.length, kMinutesSecondsMaxDigits);
    expect(kSlowPaceConfirmSecPerKm, 3600);
  });

  test('a typed duration sums its three boxes', () {
    expect(validateManualDuration('0', '21', '34'), _ok(1294));
    expect(validateManualDuration('', '21', ''), _ok(1260));
    expect(validateManualDuration(' 1 ', '', ''), _ok(3600));
  });

  test('the issue #1300 run — 12333 in the hours box — is refused', () {
    expect(validateManualDuration('12333', '21', '34'),
        _failed(ManualDurationError.tooLong));
  });

  test('the bound itself is allowed and one second past it is not', () {
    expect(validateManualDuration('240', '0', '0'), _ok(864000));
    expect(validateManualDuration('240', '0', '1'),
        _failed(ManualDurationError.tooLong));
    expect(validateManualDuration('112', '0', '0'), _ok(403200));
  });

  test('minutes and seconds are clock fields', () {
    expect(validateManualDuration('0', '60', '0'),
        _failed(ManualDurationError.minutesOutOfRange));
    expect(validateManualDuration('0', '0', '60'),
        _failed(ManualDurationError.secondsOutOfRange));
    expect(validateManualDuration('0', '59', '59'), _ok(3599));
  });

  test('an empty or all-zero duration is refused', () {
    expect(validateManualDuration('', '', ''),
        _failed(ManualDurationError.zero));
    expect(validateManualDuration('0', '00', '0'),
        _failed(ManualDurationError.zero));
  });

  test('anything but digits is invalid, never reinterpreted', () {
    expect(validateManualDuration('1.5', '', ''),
        _failed(ManualDurationError.invalid));
    expect(validateManualDuration('-1', '', ''),
        _failed(ManualDurationError.invalid));
    expect(validateManualDuration('', '3e1', ''),
        _failed(ManualDurationError.invalid));
  });

  test('isPlausibleRunDuration is the inclusive 0..bound range', () {
    expect(isPlausibleRunDuration(0), isTrue);
    expect(isPlausibleRunDuration(864000), isTrue);
    expect(isPlausibleRunDuration(864001), isFalse);
    expect(isPlausibleRunDuration(44400094), isFalse);
    expect(isPlausibleRunDuration(-1), isFalse);
    expect(isPlausibleRunDuration(double.nan), isFalse);
  });

  test('isImplausiblySlow flags the typo, not a real slow effort', () {
    expect(isImplausiblySlow(1294, 2000), isFalse);
    expect(isImplausiblySlow(44400094, 2000), isTrue);
    expect(isImplausiblySlow(403200, 386243), isFalse);
    expect(isImplausiblySlow(3600, 1000), isFalse);
    expect(isImplausiblySlow(3601, 1000), isTrue);
  });

  test('isImplausiblySlow has no pace to judge without a distance or a duration',
      () {
    expect(isImplausiblySlow(3600, 0), isFalse);
    expect(isImplausiblySlow(0, 1000), isFalse);
  });
}
