// ignore_for_file: avoid_relative_lib_imports
import 'package:flutter_test/flutter_test.dart';

import '../lib/any_time_courses.dart';

// Mirrors apps/web/src/lib/parks/any_time_courses.test.ts case for case.
AnyTimeCourseKey course(
  String slug, {
  String regionCode = 'US-VA',
  String parkName = 'Pocahontas',
  String? courseName,
  double distanceM = 5000,
  String status = 'open',
  ({double lat, double lng})? start,
}) =>
    AnyTimeCourseKey(
      regionCode: regionCode,
      parkName: parkName,
      courseName: courseName ?? slug,
      slug: slug,
      distanceM: distanceM,
      status: status,
      start: start,
    );

List<String> slugs(List<OrderedCourse<AnyTimeCourseKey>> rows) =>
    [for (final r in rows) r.course.slug];

AnyTimeCourseKey id(AnyTimeCourseKey c) => c;

void main() {
  test('without an origin, region then park then distance then name', () {
    final rows = orderAnyTimeCourses(
      [
        course('wv', regionCode: 'US-WV'),
        course('swift-10k', parkName: 'Swift Creek', distanceM: 10000),
        course('swift-5k', parkName: 'Swift Creek', distanceM: 5000),
        course('poca-b', courseName: 'B loop'),
        course('poca-a', courseName: 'A loop'),
      ],
      id,
      null,
    );
    expect(slugs(rows), ['poca-a', 'poca-b', 'swift-5k', 'swift-10k', 'wv']);
    expect(rows.every((r) => r.awayM == null), isTrue);
  });

  test('with an origin, nearest start first, with its distance', () {
    final rows = orderAnyTimeCourses(
      [
        course('far', start: (lat: 38.5, lng: -77.5)),
        course('near', start: (lat: 37.51, lng: -77.5)),
        course('mid', start: (lat: 37.6, lng: -77.5)),
      ],
      id,
      (lat: 37.5, lng: -77.5),
    );
    expect(slugs(rows), ['near', 'mid', 'far']);
    // 0.01 degrees of latitude is about 1.11 km.
    expect(rows[0].awayM, closeTo(1112, 5));
  });

  test('a course with no start follows every measured one, in stable order',
      () {
    final rows = orderAnyTimeCourses(
      [
        course('unknown-b', courseName: 'B'),
        course('measured', start: (lat: 40, lng: -77)),
        course('unknown-a', courseName: 'A'),
      ],
      id,
      (lat: 37, lng: -77),
    );
    expect(slugs(rows), ['measured', 'unknown-a', 'unknown-b']);
    expect(rows[1].awayM, isNull);
  });

  test('a closed course sinks below every runnable one, with or without an '
      'origin', () {
    final courses = [
      course('closed-near',
          status: 'closed', start: (lat: 37.5, lng: -77.5), courseName: 'A'),
      course('seasonal-far',
          status: 'seasonal', start: (lat: 39, lng: -77.5), courseName: 'B'),
      course('open-far', start: (lat: 40, lng: -77.5), courseName: 'C'),
    ];
    expect(slugs(orderAnyTimeCourses(courses, id, (lat: 37.5, lng: -77.5))),
        ['seasonal-far', 'open-far', 'closed-near']);
    expect(slugs(orderAnyTimeCourses(courses, id, null)),
        ['seasonal-far', 'open-far', 'closed-near']);
  });

  test('does not reorder its input', () {
    final input = [course('b', courseName: 'B'), course('a', courseName: 'A')];
    orderAnyTimeCourses(input, id, null);
    expect([for (final c in input) c.slug], ['b', 'a']);
  });
}
