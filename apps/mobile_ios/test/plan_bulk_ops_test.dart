// Twin of apps/web/src/lib/training/plan_bulk_ops.test.ts — same cases.

import 'package:flutter_test/flutter_test.dart';

import '../lib/plan_bulk_ops.dart';

void main() {
  group('shiftIsoDate', () {
    test('forward + backward', () {
      expect(shiftIsoDate('2026-06-07', 7), '2026-06-14');
      expect(shiftIsoDate('2026-06-07', -7), '2026-05-31');
    });

    test('crosses month + year boundaries', () {
      expect(shiftIsoDate('2026-06-28', 5), '2026-07-03');
      expect(shiftIsoDate('2026-12-30', 3), '2027-01-02');
    });

    test('zero is identity', () {
      expect(shiftIsoDate('2026-06-07', 0), '2026-06-07');
    });
  });

  group('recoveryWorkoutPatch', () {
    test('leaves rest + race untouched', () {
      expect(recoveryWorkoutPatch('rest', null), isNull);
      expect(recoveryWorkoutPatch('race', 42195), isNull);
    });

    test('converts a quality session to recovery + clears pace', () {
      final p = recoveryWorkoutPatch('tempo', 12000)!;
      expect(p['kind'], 'recovery');
      expect(p.containsKey('target_pace_sec_per_km'), isTrue);
      expect(p['target_pace_sec_per_km'], isNull);
      expect(p['target_distance_m'], (12000 * kRecoveryScale).round());
    });

    test('scales an easy run distance but keeps its kind', () {
      final p = recoveryWorkoutPatch('easy', 10000)!;
      expect(p.containsKey('kind'), isFalse);
      expect(p['target_distance_m'], 6000);
    });

    test('a distance-less easy run has nothing to change', () {
      expect(recoveryWorkoutPatch('easy', null), isNull);
    });

    test('long run scales but stays a long run', () {
      final p = recoveryWorkoutPatch('long', 30000)!;
      expect(p.containsKey('kind'), isFalse);
      expect(p['target_distance_m'], 18000);
    });
  });

  group('recoveryWeekVolume', () {
    test('scales volume, passes through null', () {
      expect(recoveryWeekVolume(50000), 30000);
      expect(recoveryWeekVolume(null), isNull);
    });
  });

  test('marking a week recovery strips the interval structure, not just the kind',
      () {
    final p = recoveryWorkoutPatch('interval', 8500)!;
    expect(p['kind'], 'recovery');
    expect(p['target_pace_sec_per_km'], isNull);
    expect(p.containsKey('target_pace_tolerance_sec'), isTrue);
    expect(p['target_pace_tolerance_sec'], isNull);
    expect(p.containsKey('structure'), isTrue,
        reason: 'the VO2max session must not survive the deload');
    expect(p['structure'], isNull);
    expect(p['target_distance_m'], (8500 * kRecoveryScale).round());
  });

  test('every quality kind sheds its structure on a recovery week', () {
    for (final kind in ['tempo', 'interval', 'marathon_pace']) {
      final p = recoveryWorkoutPatch(kind, 8000)!;
      expect(p.containsKey('structure'), isTrue, reason: kind);
      expect(p['structure'], isNull, reason: kind);
    }
  });

  test('a non-quality workout keeps its shape apart from the volume scale', () {
    final p = recoveryWorkoutPatch('long', 20000)!;
    expect(p.containsKey('kind'), isFalse);
    expect(p.containsKey('structure'), isFalse);
    expect(p['target_distance_m'], (20000 * kRecoveryScale).round());
  });
}
