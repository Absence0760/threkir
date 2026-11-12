import 'package:core_models/core_models.dart' show DistanceUnit;
import 'package:flutter_test/flutter_test.dart';

import '../lib/weekly_goal.dart';

void main() {
  test('the goal is stored under the registered bag key', () {
    expect(kWeeklyGoalKey, 'weekly_mileage_goal_m');
  });

  test('a stored goal shows in the reader own unit, to one decimal', () {
    expect(weeklyGoalToInput(50000, DistanceUnit.km), 50);
    expect(weeklyGoalToInput(50000, DistanceUnit.mi), 31.1);
    expect(weeklyGoalToInput(42195, DistanceUnit.km), 42.2);
    expect(weeklyGoalToInput(42195, DistanceUnit.mi), 26.2);
  });

  test('an absent or unusable stored goal shows nothing', () {
    for (final stored in <Object?>[
      null,
      0,
      -5,
      double.nan,
      double.infinity,
      '50000',
    ]) {
      expect(weeklyGoalToInput(stored, DistanceUnit.km), isNull,
          reason: '$stored');
    }
  });

  test(
      'a stored goal below the display precision shows as 0, which the field refuses',
      () {
    expect(weeklyGoalToInput(1, DistanceUnit.km), 0);
    expect(
      isUsableWeeklyGoalInput(weeklyGoalToInput(1, DistanceUnit.km)),
      isFalse,
    );
  });

  test('a typed goal is stored in whole metres', () {
    expect(weeklyGoalFromInput(50, DistanceUnit.km, null), 50000);
    expect(weeklyGoalFromInput(31, DistanceUnit.mi, null), 49890);
    expect(weeklyGoalFromInput(26.2, DistanceUnit.mi, null), 42165);
    expect(weeklyGoalFromInput(0.1, DistanceUnit.mi, null), 161);
  });

  test('every one-decimal goal in range survives a save and a reload unchanged',
      () {
    for (var tenths = (kWeeklyGoalMin * 10).round();
        tenths <= kWeeklyGoalMax * 10;
        tenths++) {
      final typed = tenths / 10;
      for (final unit in DistanceUnit.values) {
        final stored = weeklyGoalFromInput(typed, unit, null);
        expect(weeklyGoalToInput(stored, unit), typed, reason: '$typed $unit');
      }
    }
  });

  test('re-saving the value the field shows keeps the stored metres', () {
    expect(weeklyGoalFromInput(31.1, DistanceUnit.mi, 50000), 50000);
    expect(weeklyGoalFromInput(31.2, DistanceUnit.mi, 50000), 50212);
    expect(weeklyGoalFromInput(50, DistanceUnit.km, '50000'), 50000);
  });

  test('an empty, unparseable or non-positive field clears the goal', () {
    for (final typed in <double?>[null, double.nan, 0, -31.1]) {
      expect(weeklyGoalFromInput(typed, DistanceUnit.mi, 50000), isNull,
          reason: '$typed');
    }
  });

  test('only a finite goal inside the range is usable', () {
    for (final typed in <double>[kWeeklyGoalMin, 1, 42.2, kWeeklyGoalMax]) {
      expect(isUsableWeeklyGoalInput(typed), isTrue, reason: '$typed');
    }
    for (final typed in <double?>[
      null,
      double.nan,
      double.infinity,
      -1,
      0,
      0.05,
      500.5,
    ]) {
      expect(isUsableWeeklyGoalInput(typed), isFalse, reason: '$typed');
    }
  });
}
