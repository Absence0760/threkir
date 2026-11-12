import 'package:flutter_test/flutter_test.dart';
import '../lib/coach_load.dart';

void main() {
  group('acwr', () {
    test('ratio is acute / chronic', () {
      expect(acwr(100, 80), 1.25);
    });

    test('zero chronic base returns 0 (no division)', () {
      expect(acwr(50, 0), 0);
    });

    test('non-finite inputs return 0', () {
      expect(acwr(double.nan, 80), 0);
      expect(acwr(100, double.nan), 0);
    });
  });

  group('injuryRiskBand (band edges)', () {
    test('zero chronic base is insufficient, not low', () {
      expect(injuryRiskBand(40, 0), InjuryRiskBand.insufficient);
    });

    test('just below 0.8 is low', () {
      expect(injuryRiskBand(79, 100), InjuryRiskBand.low);
    });

    test('exactly 0.8 is optimal (low is < 0.8)', () {
      expect(injuryRiskBand(80, 100), InjuryRiskBand.optimal);
    });

    test('1.0 is optimal', () {
      expect(injuryRiskBand(100, 100), InjuryRiskBand.optimal);
    });

    test('exactly 1.3 is elevated (optimal is < 1.3)', () {
      expect(injuryRiskBand(130, 100), InjuryRiskBand.elevated);
    });

    test('just below 1.5 is elevated', () {
      expect(injuryRiskBand(149, 100), InjuryRiskBand.elevated);
    });

    test('exactly 1.5 is high', () {
      expect(injuryRiskBand(150, 100), InjuryRiskBand.high);
    });

    test('a big spike is high', () {
      expect(injuryRiskBand(220, 100), InjuryRiskBand.high);
    });
  });

  group('loadTrend', () {
    test('>15% above chronic is ramping', () {
      expect(loadTrend(120, 100), LoadTrend.ramping);
    });

    test('>15% below chronic is tapering', () {
      expect(loadTrend(80, 100), LoadTrend.tapering);
    });

    test('within the deadband is steady', () {
      expect(loadTrend(100, 100), LoadTrend.steady);
    });

    test('no chronic base is steady (one week is not a trend)', () {
      expect(loadTrend(50, 0), LoadTrend.steady);
    });
  });

  RosterRecentWorkout wo(
    String date, {
    String kind = 'easy',
    bool completed = false,
    bool skipped = false,
  }) =>
      RosterRecentWorkout(
        scheduledDate: date,
        kind: kind,
        completed: completed,
        skipped: skipped,
      );

  group('consecutiveMissedWorkouts', () {
    test('counts back from yesterday until a done workout', () {
      final recent = [
        wo('2031-03-09'),
        wo('2031-03-08'),
        wo('2031-03-07', completed: true),
        wo('2031-03-06'),
      ];
      expect(consecutiveMissedWorkouts(recent, '2031-03-10'), 2);
    });

    test('a skipped workout and a rest day neither count nor end the run', () {
      final recent = [
        wo('2031-03-09'),
        wo('2031-03-08', skipped: true),
        wo('2031-03-07', kind: 'rest'),
        wo('2031-03-06'),
        wo('2031-03-05', completed: true),
      ];
      expect(consecutiveMissedWorkouts(recent, '2031-03-10'), 2);
    });

    test('today and later are not misses, and order does not matter', () {
      final recent = [
        wo('2031-03-11'),
        wo('2031-03-10'),
        wo('2031-03-08'),
        wo('2031-03-09', completed: true),
      ];
      expect(consecutiveMissedWorkouts(recent, '2031-03-10'), 0);
      expect(
        consecutiveMissedWorkouts(
            [wo('2031-03-08'), wo('2031-03-09')], '2031-03-10'),
        2,
      );
      expect(consecutiveMissedWorkouts([], '2031-03-10'), 0);
    });
  });

  test('parseRosterRecentWorkouts: drops a malformed element, reads a non-list as none',
      () {
    final parsed = parseRosterRecentWorkouts([
      {
        'scheduled_date': '2031-03-09',
        'kind': 'easy',
        'completed': true,
        'skipped': false,
      },
      {'kind': 'easy'},
      'junk',
      {'scheduled_date': '2031-03-08', 'kind': 'tempo'},
    ]);
    expect(parsed.length, 2);
    expect(parsed[0].scheduledDate, '2031-03-09');
    expect(parsed[0].completed, isTrue);
    expect(parsed[1].kind, 'tempo');
    expect(parsed[1].completed, isFalse);
    expect(parsed[1].skipped, isFalse);
    expect(parseRosterRecentWorkouts(null), isEmpty);
    expect(parseRosterRecentWorkouts(<String, Object>{}), isEmpty);
  });

  test('isEasyHrDriftFlagged: flags at 5 % and above, never on null', () {
    expect(isEasyHrDriftFlagged(5), isTrue);
    expect(isEasyHrDriftFlagged(6.7), isTrue);
    expect(isEasyHrDriftFlagged(4.99), isFalse);
    expect(isEasyHrDriftFlagged(-8), isFalse);
    expect(isEasyHrDriftFlagged(null), isFalse);
    expect(isEasyHrDriftFlagged(double.nan), isFalse);
  });
}
