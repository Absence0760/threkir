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
    test('is always h:mm:ss, a sub-hour time included', () {
      expect(formatGoalTimeS(12600), '3:30:00');
      expect(formatGoalTimeS(1500), '0:25:00');
      expect(formatGoalTimeS(2700), '0:45:00');
      expect(formatGoalTimeS(45), '0:00:45');
    });

    test('round-trips through parseGoalTimeS with or without a distance', () {
      for (final s in [45, 1500, 2700, 3599, 12600, 45000]) {
        expect(parseGoalTimeS(formatGoalTimeS(s)), s);
        expect(parseGoalTimeS(formatGoalTimeS(s), distanceM: 5000), s);
      }
    });
  });

  group('parseRaceGoalTimeS', () {
    test('a 45-minute goal round-trips unchanged with no distance', () {
      expect(parseRaceGoalTimeS(formatGoalTimeS(2700)), 2700);
    });

    test('reads h:mm:ss and an explicit h:mm, both in hours', () {
      expect(parseRaceGoalTimeS('6:30:00'), 23400);
      expect(parseRaceGoalTimeS('0:45:00'), 2700);
      expect(parseRaceGoalTimeS('6:30'), 23400);
      expect(parseRaceGoalTimeS(' 3:05:09 '), 11109);
    });

    test('never pace-guesses a two-part value into minutes', () {
      expect(parseRaceGoalTimeS('45:00'), 45 * 3600);
    });

    test('rejects bare numbers, junk, zero and out-of-range fields', () {
      expect(parseRaceGoalTimeS(''), isNull);
      expect(parseRaceGoalTimeS('90'), isNull);
      expect(parseRaceGoalTimeS('abc'), isNull);
      expect(parseRaceGoalTimeS('1:2:3:4'), isNull);
      expect(parseRaceGoalTimeS('0:00:00'), isNull);
      expect(parseRaceGoalTimeS('1:60:00'), isNull);
      expect(parseRaceGoalTimeS('1:30:75'), isNull);
      expect(parseRaceGoalTimeS('-1:30'), isNull);
      expect(parseRaceGoalTimeS('1::30'), isNull);
    });
  });
}
