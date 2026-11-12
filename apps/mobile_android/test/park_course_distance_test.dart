// ignore_for_file: avoid_relative_lib_imports
import 'package:core_models/core_models.dart' show DistanceUnit;
import 'package:flutter_test/flutter_test.dart';

import '../lib/park_course_distance.dart';

// Mirrors apps/web/src/lib/parks/park_course_distance.test.ts case for case.
const km = DistanceUnit.km;
const mi = DistanceUnit.mi;

ParkCourseSortKey key(
  String slug, {
  String? name,
  double distanceM = 5000,
  String status = 'open',
}) =>
    ParkCourseSortKey(
      distanceM: distanceM,
      name: name ?? slug,
      slug: slug,
      status: status,
    );

List<String> slugs(List<ParkCourseSortKey> keys) =>
    [for (final k in keys) k.slug];

void main() {
  test('courseDistanceLabel: whole kilometres read without decimals', () {
    expect(courseDistanceLabel(5000, km, 'en'), '5 km');
    expect(courseDistanceLabel(10000, km, 'en'), '10 km');
    expect(courseDistanceLabel(50000, km, 'en'), '50 km');
    expect(courseDistanceLabel(0, km, 'en'), '0 km');
  });

  test('courseDistanceLabel: anything else reads with one decimal, never two',
      () {
    expect(courseDistanceLabel(21100, km, 'en'), '21.1 km');
    expect(courseDistanceLabel(42200, km, 'en'), '42.2 km');
    expect(courseDistanceLabel(21097.5, km, 'en'), '21.1 km');
    expect(courseDistanceLabel(500, km, 'en'), '0.5 km');
    expect(courseDistanceLabel(4940, km, 'en'), '4.9 km');
  });

  test('courseDistanceLabel: within 0.05 of a whole number reads whole', () {
    expect(courseDistanceLabel(4960, km, 'en'), '5 km');
    expect(courseDistanceLabel(5040, km, 'en'), '5 km');
    expect(courseDistanceLabel(5060, km, 'en'), '5.1 km');
  });

  test('courseDistanceLabel: miles', () {
    expect(courseDistanceLabel(5000, mi, 'en'), '3.1 mi');
    expect(courseDistanceLabel(42195, mi, 'en'), '26.2 mi');
    expect(courseDistanceLabel(1609.344, mi, 'en'), '1 mi');
    expect(courseDistanceLabel(50000, mi, 'en'), '31.1 mi');
  });

  test('courseDistanceLabel: the decimal separator follows the locale', () {
    expect(courseDistanceLabel(21100, km, 'de'), '21,1 km');
    expect(courseDistanceLabel(5000, km, 'de'), '5 km');
  });

  test('courseDistanceLabel: an unreadable distance has no label', () {
    expect(courseDistanceLabel(double.nan, km, 'en'), isNull);
    expect(courseDistanceLabel(-1, km, 'en'), isNull);
    expect(courseDistanceLabel(double.infinity, mi, 'en'), isNull);
  });

  test('courseDistanceParts: the value is rounded to the digits it reads with',
      () {
    expect(
      courseDistanceParts(21097.5, km),
      const CourseDistanceParts(value: 21.1, fractionDigits: 1, unit: km),
    );
    expect(
      courseDistanceParts(4960, km),
      const CourseDistanceParts(value: 5, fractionDigits: 0, unit: km),
    );
  });

  test('courseDistanceRange: shortest to longest, in any input order', () {
    expect(courseDistanceRange([21100, 5000, 50000, 10000], km, 'en'),
        '5–50 km');
    expect(courseDistanceRange([5000, 50000], mi, 'en'), '3.1–31.1 mi');
  });

  test('courseDistanceRange: one label when every course reads the same', () {
    expect(courseDistanceRange([5000], km, 'en'), '5 km');
    expect(courseDistanceRange([5000, 4980], km, 'en'), '5 km');
  });

  test(
      'courseDistanceRange: unreadable distances are skipped, and none left is '
      'null', () {
    expect(courseDistanceRange([5000, double.nan, 21100], km, 'en'),
        '5–21.1 km');
    expect(courseDistanceRange(const [], km, 'en'), isNull);
    expect(courseDistanceRange([double.nan, -5], km, 'en'), isNull);
  });

  test('sortParkCourses: shortest first, not by name', () {
    final courses = [
      key('beaver-lake', name: 'Beaver Lake Trail', distanceM: 4000),
      key('10k', name: '10K', distanceM: 10000),
      key('50k', name: '50K', distanceM: 50000),
      key('5k', name: '5K', distanceM: 5000),
      key('half', name: 'Half marathon', distanceM: 21100),
      key('marathon', name: 'Marathon', distanceM: 42200),
    ];
    expect(slugs(sortParkCourses(courses, (c) => c)),
        ['beaver-lake', '5k', '10k', 'half', 'marathon', '50k']);
  });

  test(
      'sortParkCourses: closed courses come last, still shortest first among '
      'themselves', () {
    final courses = [
      key('a', distanceM: 3000, status: 'closed'),
      key('b', distanceM: 9000, status: 'seasonal'),
      key('c', distanceM: 1000, status: 'closed'),
      key('d', distanceM: 6000),
    ];
    expect(slugs(sortParkCourses(courses, (c) => c)), ['d', 'b', 'c', 'a']);
  });

  test('sortParkCourses: equal distances order by name, then slug', () {
    final courses = [
      key('z', name: 'Lake'),
      key('y', name: 'Lake'),
      key('x', name: 'Fire road'),
    ];
    expect(slugs(sortParkCourses(courses, (c) => c)), ['x', 'y', 'z']);
  });

  test('sortParkCourses: returns a new list and leaves the input alone', () {
    final courses = [key('b', distanceM: 2), key('a', distanceM: 1)];
    final sorted = sortParkCourses(courses, (c) => c);
    expect(identical(sorted, courses), isFalse);
    expect(slugs(courses), ['b', 'a']);
  });

  test('courseShapeShown: a loop goes unlabelled, the other shapes do not', () {
    expect(courseShapeShown('loop'), isFalse);
    expect(courseShapeShown('out_and_back'), isTrue);
    expect(courseShapeShown('point_to_point'), isTrue);
    expect(courseShapeShown(null), isFalse);
    expect(courseShapeShown('spiral'), isFalse);
  });

  test('courseLapsChip: a chip only for two laps or more', () {
    expect(courseLapsChip(null), isNull);
    expect(courseLapsChip(0), isNull);
    expect(courseLapsChip(1), isNull);
    expect(courseLapsChip(2), 2);
    expect(courseLapsChip(4), 4);
  });
}
