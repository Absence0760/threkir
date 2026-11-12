// Reading the cycle / pregnancy adjustment config from the synced settings
// (decisions § 231). The values are GDPR Art 9, so the gate test proves none
// is even read while the cycle-plans gate is off.

import 'package:flutter_test/flutter_test.dart';

import '../lib/cycle_plan.dart';
import '../lib/cycle_plan_config.dart';

Object? Function(String) _settings(Map<String, Object?> values) =>
    (key) => values[key];

void main() {
  group('cyclePlanConfigFrom', () {
    test('a complete cycle setting is a cycle config', () {
      final cfg = cyclePlanConfigFrom(_settings({
        'cycle_tracking_mode': 'cycle',
        'cycle_length_days': 28,
        'cycle_last_period_start': '2026-03-01',
      }))!;
      expect(cfg.mode, CyclePlanMode.cycle);
      expect(cfg.cycleLengthDays, 28);
      expect(cfg.lastPeriodStartIso, '2026-03-01');
    });

    test('a cycle length that arrives as a JSON double still reads', () {
      expect(
          cyclePlanConfigFrom(_settings({
            'cycle_tracking_mode': 'cycle',
            'cycle_length_days': 30.0,
            'cycle_last_period_start': '2026-03-01',
          }))!.cycleLengthDays,
          30);
    });

    test('an incomplete or malformed cycle setting is no config', () {
      for (final values in [
        {'cycle_tracking_mode': 'cycle', 'cycle_last_period_start': '2026-03-01'},
        {'cycle_tracking_mode': 'cycle', 'cycle_length_days': 28},
        {
          'cycle_tracking_mode': 'cycle',
          'cycle_length_days': 0,
          'cycle_last_period_start': '2026-03-01'
        },
        {
          'cycle_tracking_mode': 'cycle',
          'cycle_length_days': '28',
          'cycle_last_period_start': '2026-03-01'
        },
      ]) {
        expect(cyclePlanConfigFrom(_settings(values)), isNull, reason: '$values');
      }
    });

    test('a pregnancy setting with a due date is a pregnancy config', () {
      final cfg = cyclePlanConfigFrom(_settings({
        'cycle_tracking_mode': 'pregnancy',
        'pregnancy_due_date': '2026-09-01',
      }))!;
      expect(cfg.mode, CyclePlanMode.pregnancy);
      expect(cfg.dueDateIso, '2026-09-01');
      expect(
          cyclePlanConfigFrom(
              _settings({'cycle_tracking_mode': 'pregnancy'})),
          isNull);
    });

    test('no mode, or one it does not know, is no config', () {
      expect(cyclePlanConfigFrom(_settings({})), isNull);
      expect(cyclePlanConfigFrom(_settings({'cycle_tracking_mode': 'other'})),
          isNull);
    });
  });

  group('readCyclePlanConfig', () {
    final complete = {
      'cycle_tracking_mode': 'pregnancy',
      'pregnancy_due_date': '2026-09-01',
    };

    test('with the gate off it reads no setting at all', () {
      final read = <String>[];
      final cfg = readCyclePlanConfig(
        gate: () => false,
        read: (key) {
          read.add(key);
          return complete[key];
        },
      );
      expect(cfg, isNull);
      expect(read, isEmpty, reason: 'Art 9 values must not be read while off');
    });

    test('with the gate on it reads them', () {
      expect(
          readCyclePlanConfig(gate: () => true, read: _settings(complete))?.mode,
          CyclePlanMode.pregnancy);
    });
  });
}
