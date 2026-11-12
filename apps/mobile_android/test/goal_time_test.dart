import 'package:flutter_test/flutter_test.dart';

import '../lib/goal_time.dart';

void main() {
  group('parseGoalTimeS', () {
    test('three-part input is always h:mm:ss', () {
      expect(parseGoalTimeS('3:30:00'), 12600);
      expect(parseGoalTimeS('0:25:00'), 1500);
    });

    test('bare number is minutes', () {
      expect(parseGoalTimeS('90'), 5400);
      expect(parseGoalTimeS('210'), 12600);
    });

    test('two-part input defaults to h:mm without a distance', () {
      expect(parseGoalTimeS('3:30'), 12600);
      expect(parseGoalTimeS('25:00'), 90000);
    });

    test('two-part input picks the pace-plausible reading for the distance',
        () {
      // "3:30" for a marathon: 3h30 is ~4:59/km (plausible); 3.5 min is not.
      expect(parseGoalTimeS('3:30', distanceM: 42195), 12600);
      // "25:00" for a 5K: 25 hours is ~300 min/km (implausible); 25 min is
      // 5:00/km.
      expect(parseGoalTimeS('25:00', distanceM: 5000), 1500);
      // "12:30" for a 100K ultra: 12h30 is ~7:30/km (plausible) — the hours
      // reading wins even though 12.5 min would parse.
      expect(parseGoalTimeS('12:30', distanceM: 100000), 45000);
    });

    test('rejects junk, negatives, zero, and four-part input', () {
      expect(parseGoalTimeS(''), isNull);
      expect(parseGoalTimeS('abc'), isNull);
      expect(parseGoalTimeS('1:2:3:4'), isNull);
      expect(parseGoalTimeS('0'), isNull);
      expect(parseGoalTimeS('-5:30'), isNull);
      expect(parseGoalTimeS('5:-30'), isNull);
    });
  });

  group('formatGoalTimeS', () {
    test('prints a sub-hour goal as mm:ss, so a 25-minute 5K reads 25:00', () {
      expect(formatGoalTimeS(12600), '3:30:00');
      expect(formatGoalTimeS(1500), '25:00');
    });

    test('a 25-minute 5K prefill round-trips through parseGoalTimeS', () {
      expect(parseGoalTimeS(formatGoalTimeS(12600)), 12600);
      expect(parseGoalTimeS(formatGoalTimeS(1500), distanceM: 5000), 1500);
    });
  });

  group('formatRaceGoalTimeS', () {
    test('is always h:mm:ss, a sub-hour time included', () {
      expect(formatRaceGoalTimeS(12600), '3:30:00');
      expect(formatRaceGoalTimeS(2700), '0:45:00');
      expect(formatRaceGoalTimeS(45), '0:00:45');
    });
  });

  group('parseRaceGoalTimeS', () {
    test('a 45-minute race goal round-trips as 0:45:00', () {
      expect(formatRaceGoalTimeS(2700), '0:45:00');
      expect(parseRaceGoalTimeS(formatRaceGoalTimeS(2700)), 2700);
      for (final s in [45, 1500, 3599, 12600, 45000, 99 * 3600 + 3599, 105 * 3600]) {
        expect(parseRaceGoalTimeS(formatRaceGoalTimeS(s)), s);
      }
    });

    test('reads exactly h:mm:ss', () {
      expect(parseRaceGoalTimeS('6:30:00'), 23400);
      expect(parseRaceGoalTimeS('0:45:00'), 2700);
      expect(parseRaceGoalTimeS(' 3:05:09 '), 11109);
      expect(parseRaceGoalTimeS('99:59:59'), 99 * 3600 + 59 * 60 + 59);
    });

    test('takes a goal past 99 hours, up to 999, for a 240-mile race', () {
      expect(parseRaceGoalTimeS('105:00:00'), 105 * 3600);
      expect(parseRaceGoalTimeS('999:59:59'), 999 * 3600 + 59 * 60 + 59);
      expect(parseRaceGoalTimeS('1000:00:00'), isNull);
    });

    test('rejects a two-part value rather than guessing its unit', () {
      expect(parseRaceGoalTimeS('45:00'), isNull);
      expect(parseRaceGoalTimeS('6:30'), isNull);
    });

    test('rejects bare numbers, junk, zero and out-of-range fields', () {
      expect(parseRaceGoalTimeS(''), isNull);
      expect(parseRaceGoalTimeS('90'), isNull);
      expect(parseRaceGoalTimeS('abc'), isNull);
      expect(parseRaceGoalTimeS('1:2:3:4'), isNull);
      expect(parseRaceGoalTimeS('0:00:00'), isNull);
      expect(parseRaceGoalTimeS('1:60:00'), isNull);
      expect(parseRaceGoalTimeS('1:30:75'), isNull);
      expect(parseRaceGoalTimeS('1:5:00'), isNull);
      expect(parseRaceGoalTimeS('-1:30:00'), isNull);
      expect(parseRaceGoalTimeS('1::30'), isNull);
    });
  });
}
