import 'package:core_models/core_models.dart';
import 'package:test/test.dart';

// FoodEntry.fromRow reads the food_log row the offline LocalFoodStore holds.
void main() {
  test('reads every column, widening whole-number nutrients to doubles', () {
    final e = FoodEntry.fromRow({
      'id': 'f1',
      'started_at': '2026-11-07T12:30:00Z',
      'item_name': 'Oats',
      'meal_slot': 'breakfast',
      'calories': 350,
      'protein_g': 12.5,
      'carbs_g': 60,
      'fat_g': 6,
      'fiber_g': 8,
      'sugar_g': 1.2,
      'sodium_mg': 5,
      'saturated_fat_g': 1,
      'cholesterol_mg': 0,
      'is_public': true,
      'external_id': 'off:123',
      'last_modified_at': '2026-11-07T12:31:00Z',
      'created_at': '2026-11-07T12:30:05Z',
    });
    expect(e.id, 'f1');
    expect(e.startedAt, DateTime.utc(2026, 11, 7, 12, 30));
    expect(e.itemName, 'Oats');
    expect(e.mealSlot, 'breakfast');
    expect(e.calories, 350.0);
    expect(e.calories, isA<double>());
    expect(e.proteinG, 12.5);
    expect(e.carbsG, 60.0);
    expect(e.fatG, 6.0);
    expect(e.fiberG, 8.0);
    expect(e.sugarG, 1.2);
    expect(e.sodiumMg, 5.0);
    expect(e.saturatedFatG, 1.0);
    expect(e.cholesterolMg, 0.0);
    expect(e.isPublic, isTrue);
    expect(e.externalId, 'off:123');
    expect(e.lastModifiedAt, DateTime.utc(2026, 11, 7, 12, 31));
    expect(e.createdAt, DateTime.utc(2026, 11, 7, 12, 30, 5));
  });

  test('a minimal row reads absent nutrients as null, not zero', () {
    final e = FoodEntry.fromRow({'id': 'f2'});
    expect(e.itemName, '');
    expect(e.isPublic, isFalse);
    expect(e.startedAt, isNull);
    expect(e.mealSlot, isNull);
    for (final v in [
      e.calories, e.proteinG, e.carbsG, e.fatG, e.fiberG, e.sugarG, //
      e.sodiumMg, e.saturatedFatG, e.cholesterolMg,
    ]) {
      expect(v, isNull);
    }
  });

  test('an impossible or empty timestamp is absent, never a rolled-over date',
      () {
    final e = FoodEntry.fromRow({
      'id': 'f3',
      'started_at': '2026-02-30T08:00:00Z',
      'last_modified_at': '',
      'created_at': 'yesterday',
    });
    expect(e.startedAt, isNull);
    expect(e.lastModifiedAt, isNull);
    expect(e.createdAt, isNull);
  });
}
