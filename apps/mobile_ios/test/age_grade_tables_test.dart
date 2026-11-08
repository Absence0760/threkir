import 'package:flutter_test/flutter_test.dart';

import '../lib/age_grade_tables.dart';

// Structural invariants of the generated USATF MLDR 2025 tables. A bad
// regeneration (a truncated factor list, a swapped column, a distance out of
// order) would skew every age grade silently; these fail it instead.
void main() {
  const ages = ageGradeAgeMax - ageGradeAgeMin + 1;

  test('the age range is 5..99', () {
    expect(ageGradeAgeMin, 5);
    expect(ageGradeAgeMax, 99);
    expect(ages, 95);
  });

  test('distances are unique and strictly ascending by metres', () {
    final keys = ageGradeDistances.map((d) => d.key).toList();
    expect(keys.toSet(), hasLength(keys.length));
    for (var i = 1; i < ageGradeDistances.length; i++) {
      expect(ageGradeDistances[i].distanceM,
          greaterThan(ageGradeDistances[i - 1].distanceM),
          reason: ageGradeDistances[i].key);
    }
  });

  test('the headline distances are present at their certified lengths', () {
    double metres(String key) =>
        ageGradeDistances.firstWhere((d) => d.key == key).distanceM;
    expect(metres('5k'), 5000);
    expect(metres('10k'), 10000);
    expect(metres('hm'), 21097.5);
    expect(metres('42k'), 42195);
    expect(metres('1mi'), closeTo(1609.344, 1e-9));
    expect(metres('100mi'), closeTo(160934.4, 1e-6));
  });

  test('every factor list covers every age', () {
    for (final d in ageGradeDistances) {
      expect(d.maleFactors, hasLength(ages), reason: '${d.key} male');
      expect(d.femaleFactors, hasLength(ages), reason: '${d.key} female');
    }
  });

  test('every factor is in (0, 1] and each list peaks at exactly 1', () {
    for (final d in ageGradeDistances) {
      for (final (sex, list) in [('male', d.maleFactors), ('female', d.femaleFactors)]) {
        for (var i = 0; i < list.length; i++) {
          expect(list[i] > 0 && list[i] <= 1, isTrue,
              reason: '${d.key} $sex age ${i + ageGradeAgeMin}: ${list[i]}');
        }
        expect(list.reduce((a, b) => a > b ? a : b), 1.0,
            reason: '${d.key} $sex has an open-class age');
      }
    }
  });

  test('open standards are positive, the women\'s slower, and grow with distance',
      () {
    for (final d in ageGradeDistances) {
      expect(d.openStandardSecMale, greaterThan(0), reason: d.key);
      expect(d.openStandardSecFemale, greaterThan(d.openStandardSecMale),
          reason: d.key);
    }
    for (var i = 1; i < ageGradeDistances.length; i++) {
      expect(ageGradeDistances[i].openStandardSecMale,
          greaterThan(ageGradeDistances[i - 1].openStandardSecMale),
          reason: ageGradeDistances[i].key);
    }
  });
}
