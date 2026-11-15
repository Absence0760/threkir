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
  test('parkSearchTerms: folded words, blanks dropped', () {
    expect(parkSearchTerms('  Swift   CRÉEK '), ['swift', 'creek']);
    expect(parkSearchTerms(''), isEmpty);
    expect(parkSearchTerms('   '), isEmpty);
  });

  test('parkSearchMatches: every word in the course, its park or its place',
      () {
    bool matches(String q) => parkSearchMatches(
          parkSearchTerms(q),
          courseName: 'Beaver Lake Trail',
          parkName: 'Pocahontas',
          regionCode: 'US-VA',
        );
    expect(matches('pocahontas beaver'), isTrue);
    expect(matches('Virginia lake'), isTrue);
    expect(matches('us-va'), isTrue);
    expect(matches('beaver swift'), isFalse);
    expect(matches('maryland'), isFalse);
  });

  test(
      'parkSearchMatches: no words match everything; a park alone is asked '
      'by its name and place', () {
    bool matches(List<String> terms) =>
        parkSearchMatches(terms, parkName: 'Pocahontas', regionCode: 'US-VA');
    expect(matches(const []), isTrue);
    expect(matches(parkSearchTerms('poca')), isTrue);
    expect(matches(parkSearchTerms('virginia')), isTrue);
    expect(matches(parkSearchTerms('beaver')), isFalse);
  });

  group('parks', () {
    AnyTimeParkKey park(
      String slug, {
      String regionCode = 'US-VA',
      String? parkName,
      bool allClosed = false,
      List<({double lat, double lng})> starts = const [],
      ({double lat, double lng})? location,
    }) =>
        AnyTimeParkKey(
          regionCode: regionCode,
          parkName: parkName ?? slug,
          slug: slug,
          allClosed: allClosed,
          starts: starts,
          location: location,
        );
    List<String> parkSlugs(List<OrderedPark<AnyTimeParkKey>> rows) =>
        [for (final r in rows) r.park.slug];
    AnyTimeParkKey pid(AnyTimeParkKey p) => p;

    test('without an origin, region then name', () {
      final rows = orderAnyTimeParks(
        [
          park('wv', regionCode: 'US-WV', parkName: 'A'),
          park('swift', parkName: 'Swift Creek'),
          park('poca', parkName: 'Pocahontas'),
        ],
        pid,
        null,
      );
      expect(parkSlugs(rows), ['poca', 'swift', 'wv']);
      expect(rows.every((r) => r.awayM == null), isTrue);
    });

    test(
        'with an origin, by the nearest course start, falling back to the '
        'park location', () {
      final rows = orderAnyTimeParks(
        [
          park('far-starts',
              starts: [(lat: 38.5, lng: -77.5), (lat: 39.0, lng: -77.5)]),
          park('one-near-start',
              starts: [(lat: 40.0, lng: -77.5), (lat: 37.51, lng: -77.5)]),
          park('located', location: (lat: 37.6, lng: -77.5)),
          park('nowhere'),
        ],
        pid,
        (lat: 37.5, lng: -77.5),
      );
      expect(parkSlugs(rows),
          ['one-near-start', 'located', 'far-starts', 'nowhere']);
      expect(rows[0].awayM, closeTo(1112, 5));
      expect(rows[3].awayM, isNull);
    });

    test('a course start outranks the park location', () {
      final rows = orderAnyTimeParks(
        [
          park('p',
              location: (lat: 37.5, lng: -77.5),
              starts: [(lat: 38.5, lng: -77.5)]),
        ],
        pid,
        (lat: 37.5, lng: -77.5),
      );
      expect(rows[0].awayM, greaterThan(100000));
    });

    test('a park with every course closed sinks, with or without an origin',
        () {
      final parks = [
        park('closed-near',
            parkName: 'A', allClosed: true, starts: [(lat: 37.5, lng: -77.5)]),
        park('open-far', parkName: 'B', starts: [(lat: 40.0, lng: -77.5)]),
      ];
      expect(parkSlugs(orderAnyTimeParks(parks, pid, (lat: 37.5, lng: -77.5))),
          ['open-far', 'closed-near']);
      expect(parkSlugs(orderAnyTimeParks(parks, pid, null)),
          ['open-far', 'closed-near']);
    });
  });

  group('search hits', () {
    const courses = [
      AnyTimeSearchView(
          parkId: 'poca',
          courseName: 'Beaver Lake Trail',
          parkName: 'Pocahontas',
          regionCode: 'US-VA'),
      AnyTimeSearchView(
          parkId: 'poca',
          courseName: 'Lake Trail 5k',
          parkName: 'Pocahontas',
          regionCode: 'US-VA'),
      AnyTimeSearchView(
          parkId: 'swift',
          courseName: 'Creekside Loop',
          parkName: 'Swift Creek',
          regionCode: 'US-VA'),
    ];
    AnyTimeSearchView view(AnyTimeSearchView c) => c;
    List<String> names(AnyTimeHits<AnyTimeSearchView> h) =>
        [for (final c in h.courses) c.courseName];

    test('no words lists every park once and no course on its own', () {
      final hits = anyTimeSearchHits(courses, view, const []);
      expect(hits.parkIds, ['poca', 'swift']);
      expect(hits.courses, isEmpty);
    });

    test('a park matched by name or place lists the park, not its courses',
        () {
      final poca = anyTimeSearchHits(courses, view, parkSearchTerms('pocahontas'));
      expect(poca.parkIds, ['poca']);
      expect(poca.courses, isEmpty);
      final va = anyTimeSearchHits(courses, view, parkSearchTerms('virginia'));
      expect(va.parkIds, ['poca', 'swift']);
      expect(va.courses, isEmpty);
    });

    test('a course matched by its own name is listed on its own', () {
      final hits = anyTimeSearchHits(courses, view, parkSearchTerms('beaver'));
      expect(hits.parkIds, isEmpty);
      expect(names(hits), ['Beaver Lake Trail']);
      final lake =
          anyTimeSearchHits(courses, view, parkSearchTerms('pocahontas lake'));
      expect(names(lake), ['Beaver Lake Trail', 'Lake Trail 5k']);
      // "creek" names the Swift Creek park, so its loop is not listed again.
      final creek = anyTimeSearchHits(courses, view, parkSearchTerms('creek'));
      expect(creek.parkIds, ['swift']);
      expect(creek.courses, isEmpty);
    });
  });
}
