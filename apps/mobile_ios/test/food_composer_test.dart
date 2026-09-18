import 'package:flutter_test/flutter_test.dart';

import '../lib/food_composer.dart';
import '../lib/nutrition_totals.dart' show mealSlots;

void main() {
  group('mealSlotForTime', () {
    test('picks the slot the hour actually belongs to', () {
      String at(int hour) =>
          mealSlotForTime(DateTime(2026, 9, 17, hour, 30));
      expect(at(8), 'breakfast');
      expect(at(12), 'lunch');
      expect(at(19), 'dinner');
    });

    test('the small hours and the late evening are a snack, not a meal', () {
      // 02:00 is not breakfast: filing it there distorts the morning's
      // totals, and 22:00 is not a second dinner.
      expect(mealSlotForTime(DateTime(2026, 9, 17, 2)), 'snack');
      expect(mealSlotForTime(DateTime(2026, 9, 17, 22)), 'snack');
    });

    test('every boundary hour resolves, and only to a real slot', () {
      for (var h = 0; h < 24; h++) {
        final slot = mealSlotForTime(DateTime(2026, 9, 17, h));
        expect(mealSlots, contains(slot), reason: 'hour $h gave $slot');
      }
    });

    test('reads the local hour, never UTC', () {
      final at = DateTime(2026, 9, 17, 8, 30);
      expect(mealSlotForTime(at.toUtc()), mealSlotForTime(at));
    });
  });
}
