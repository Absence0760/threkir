import 'package:flutter_test/flutter_test.dart';

import '../lib/workout_prescription.dart';

void expectOk(ParsedRange r, int? min, int? max) {
  expect(r.ok, isTrue);
  expect(r.min, min);
  expect(r.max, max);
}

void main() {
  test('rangeShape: both ends, one end, equal ends, none', () {
    expect(rangeShape(3, 4), RangeShape.between);
    expect(rangeShape(null, 125), RangeShape.atMost);
    expect(rangeShape(110, null), RangeShape.atLeast);
    expect(rangeShape(5, 5), RangeShape.exact);
    expect(rangeShape(null, null), isNull);
  });

  test('parseTargetRange: open ends are allowed', () {
    expectOk(parseTargetRange(null, 125, targetHrBounds), null, 125);
    expectOk(parseTargetRange(3, null, rpeBounds), 3, null);
    expectOk(parseTargetRange(null, null, rpeBounds), null, null);
  });

  test("parseTargetRange: the bounds are the columns' CHECKs, inclusive", () {
    expectOk(parseTargetRange(1, 10, rpeBounds), 1, 10);
    expect(parseTargetRange(0, 4, rpeBounds).reason, RangeRefusal.outOfRange);
    expect(parseTargetRange(3, 11, rpeBounds).reason, RangeRefusal.outOfRange);
    expectOk(parseTargetRange(30, 230, targetHrBounds), 30, 230);
    expect(parseTargetRange(null, 231, targetHrBounds).reason,
        RangeRefusal.outOfRange);
  });

  test('parseTargetRange: a fraction or a non-number is refused', () {
    expect(parseTargetRange(3.5, 4, rpeBounds).reason, RangeRefusal.notWhole);
    expect(parseTargetRange(double.nan, null, rpeBounds).reason,
        RangeRefusal.notWhole);
  });

  test('parseTargetRange: a low end above the high end is refused', () {
    expect(parseTargetRange(5, 4, rpeBounds).reason, RangeRefusal.reversed);
    expectOk(parseTargetRange(5, 5, rpeBounds), 5, 5);
  });

  test('isEditedByCoach: the owner sees an edit by someone else', () {
    expect(isEditedByCoach(updatedBy: 'coach', ownerId: 'me', viewerId: 'me'),
        isTrue);
    expect(isEditedByCoach(updatedBy: 'me', ownerId: 'me', viewerId: 'me'),
        isFalse);
    expect(isEditedByCoach(updatedBy: null, ownerId: 'me', viewerId: 'me'),
        isFalse);
  });

  test(
      'isEditedByCoach: only the owner is told, and an unknown owner or '
      'viewer is not', () {
    expect(
        isEditedByCoach(
            updatedBy: 'athlete', ownerId: 'athlete', viewerId: 'coach'),
        isFalse);
    expect(isEditedByCoach(updatedBy: 'coach', ownerId: null, viewerId: 'me'),
        isFalse);
    expect(isEditedByCoach(updatedBy: 'coach', ownerId: 'me', viewerId: null),
        isFalse);
  });
}
