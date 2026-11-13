import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_android/park_courses.dart';
import 'package:mobile_android/route_guide.dart';

class _Park {
  final String regionCode;
  final String name;
  const _Park(this.regionCode, this.name);
}

void main() {
  test('parseCourseCheckpoints: reads an ordered list of points', () {
    expect(
      parseCourseCheckpoints([
        {'lat': 37.5, 'lng': -77.4},
        {'lat': 37.6, 'lng': -77.3},
      ]),
      const [
        CourseCheckpoint(lat: 37.5, lng: -77.4),
        CourseCheckpoint(lat: 37.6, lng: -77.3),
      ],
    );
  });

  test(
    'parseCourseCheckpoints: an empty list is a course with no checkpoints',
    () {
      expect(parseCourseCheckpoints(<Object?>[]), isEmpty);
    },
  );

  test('parseCourseCheckpoints: a non-list refuses the course', () {
    expect(parseCourseCheckpoints({'lat': 1, 'lng': 2}), isNull);
    expect(parseCourseCheckpoints(null), isNull);
    expect(parseCourseCheckpoints('[]'), isNull);
  });

  test(
    'parseCourseCheckpoints: one bad entry refuses the whole list, never a shorter one',
    () {
      expect(
        parseCourseCheckpoints([
          {'lat': 37.5, 'lng': -77.4},
          {'lat': '37.6', 'lng': -77.3},
        ]),
        isNull,
      );
      expect(
        parseCourseCheckpoints([
          {'lat': 37.5},
        ]),
        isNull,
      );
      expect(
        parseCourseCheckpoints([
          [37.5, -77.4],
        ]),
        isNull,
      );
    },
  );

  test('parseCourseCheckpoints: out-of-range coordinates refuse the list', () {
    expect(
      parseCourseCheckpoints([
        {'lat': 91, 'lng': 0},
      ]),
      isNull,
    );
    expect(
      parseCourseCheckpoints([
        {'lat': 0, 'lng': -181},
      ]),
      isNull,
    );
  });

  test('parseCourseCheckpoints: more than the cap refuses the list', () {
    final many = List.generate(
      kMaxCourseCheckpoints + 1,
      (_) => {'lat': 1, 'lng': 1},
    );
    expect(parseCourseCheckpoints(many), isNull);
    expect(
      parseCourseCheckpoints(many.sublist(1))?.length,
      kMaxCourseCheckpoints,
    );
  });

  test('regionSlug / regionCodeFromSlug round-trip an ISO 3166-2 code', () {
    expect(regionSlug('US-VA'), 'us-va');
    expect(regionCodeFromSlug('us-va'), 'US-VA');
    expect(regionCodeFromSlug('virginia'), isNull);
    expect(regionCodeFromSlug('us-va/../x'), isNull);
  });

  test('regionName names a US state and falls back to the code', () {
    expect(regionName('US-VA'), 'Virginia');
    expect(regionName('GB-ENG'), 'GB-ENG');
  });

  test(
    'courseIsCountable: a closed course drops out of counts, a seasonal one stays',
    () {
      expect(courseIsCountable('open'), isTrue);
      expect(courseIsCountable('seasonal'), isTrue);
      expect(courseIsCountable('closed'), isFalse);
    },
  );

  test(
    'courseOffersWayfinding: a closed course offers no Navigate, GPX or route guide',
    () {
      expect(courseOffersWayfinding('open'), isTrue);
      expect(courseOffersWayfinding('seasonal'), isTrue);
      expect(courseOffersWayfinding('closed'), isFalse);
    },
  );

  test(
    'isLongCourse: only a course over 15 km carries the long-course notice',
    () {
      expect(kLongCourseThresholdM, 15000);
      expect(isLongCourse(5000), isFalse);
      expect(isLongCourse(15000), isFalse);
      expect(isLongCourse(15001), isTrue);
      expect(isLongCourse(50000), isTrue);
      expect(isLongCourse(double.nan), isFalse);
    },
  );

  test(
    'groupParksByRegion: regions in code order, parks by name within each',
    () {
      final groups = groupParksByRegion<_Park>(
        const [
          _Park('US-VA', 'Pocahontas'),
          _Park('US-NC', 'Umstead'),
          _Park('US-VA', 'Douthat'),
        ],
        regionCodeOf: (p) => p.regionCode,
        nameOf: (p) => p.name,
      );
      expect(
        groups.map((g) => [g.regionCode, g.parks.map((p) => p.name).toList()]),
        [
          [
            'US-NC',
            ['Umstead'],
          ],
          [
            'US-VA',
            ['Douthat', 'Pocahontas'],
          ],
        ],
      );
    },
  );

  test('kCourseShapes matches the course_shape CHECK', () {
    expect(kCourseShapes, ['loop', 'out_and_back', 'point_to_point']);
  });

  const parkName = 'Fixture State Park';
  const parkSite = 'https://example.gov/fixture';

  test('courseAttribution: osm names the ODbL and links the OpenStreetMap copyright page', () {
    final a = courseAttribution('osm', parkName: parkName, parkWebsiteUrl: parkSite);
    expect(a?.author, 'OpenStreetMap contributors');
    expect(a?.licenseUrl, 'https://opendatacommons.org/licenses/odbl/1-0/');
    expect(a?.linkHref, 'https://www.openstreetmap.org/copyright');
    expect(a?.linkText, '© OpenStreetMap contributors');
    expect(a?.notice, contains('© OpenStreetMap contributors'));
  });

  test('courseAttribution: nps credits the National Park Service with no licence claim', () {
    final a = courseAttribution('nps', parkName: parkName, parkWebsiteUrl: parkSite);
    expect(a?.author, 'National Park Service');
    expect(a?.licenseUrl, isNull);
    expect(a?.linkHref, 'https://www.nps.gov/');
    expect(a?.notice, 'Course line from National Park Service trail data.');
  });

  test('courseAttribution: agency credits the park and links its site only over https', () {
    final a = courseAttribution('agency', parkName: parkName, parkWebsiteUrl: parkSite);
    expect(a?.author, 'Fixture State Park');
    expect(a?.linkHref, 'https://example.gov/fixture');
    expect(a?.notice, 'Course line from trail data published by Fixture State Park.');
    expect(
      courseAttribution('agency', parkName: 'P', parkWebsiteUrl: 'http://x.test')?.linkHref,
      isNull,
    );
    expect(courseAttribution('agency', parkName: 'P', parkWebsiteUrl: null)?.linkHref, isNull);
  });

  test('courseAttribution: a park the reader cannot see still yields an unnamed credit', () {
    expect(
      courseAttribution('osm', parkName: null, parkWebsiteUrl: null)?.author,
      'OpenStreetMap contributors',
    );
    final a = courseAttribution('agency', parkName: null, parkWebsiteUrl: null);
    expect(a?.author, isNull);
    expect(a?.linkHref, isNull);
    expect(a?.notice, 'Course line from trail data published by the park.');
  });

  test('courseAttribution: traced names no rights holder', () {
    final a = courseAttribution('traced', parkName: parkName, parkWebsiteUrl: parkSite);
    expect(a?.author, isNull);
    expect(
      a?.notice,
      'Course line traced against the published trail map of Fixture State Park.',
    );
  });

  test('courseAttribution: a value outside the vocabulary, or none, has no attribution', () {
    expect(courseAttribution('strava', parkName: parkName, parkWebsiteUrl: parkSite), isNull);
    expect(courseAttribution(null, parkName: parkName, parkWebsiteUrl: parkSite), isNull);
  });

  test('parkCourseGpx: the line, one waypoint per checkpoint in order, and the credit', () {
    final xml = parkCourseGpx(
      name: 'Lake Loop',
      waypoints: const [
        (lat: 37.1, lng: -77.5, ele: 50.0),
        (lat: 37.2, lng: -77.6, ele: null),
      ],
      checkpoints: const [
        CourseCheckpoint(lat: 37.11, lng: -77.51),
        CourseCheckpoint(lat: 37.15, lng: -77.55),
      ],
      attribution: courseAttribution('osm', parkName: parkName, parkWebsiteUrl: parkSite),
    );
    expect(xml, contains('<trkpt lat="37.1" lon="-77.5"><ele>50</ele></trkpt>'));
    expect(xml, contains('<trkpt lat="37.2" lon="-77.6"><ele>0</ele></trkpt>'));
    final first = xml.indexOf('<name>Checkpoint 1</name>');
    final second = xml.indexOf('<name>Checkpoint 2</name>');
    expect(first > 0 && second > first, isTrue);
    expect(
      xml,
      contains('<wpt lat="37.11" lon="-77.51"><name>Checkpoint 1</name><type>checkpoint</type></wpt>'),
    );
    expect(xml, contains('<copyright author="OpenStreetMap contributors">'));
  });

  test('parkCourseGpx: the route guide is the track desc, in English, led by its ground-check status', () {
    final guide = parseRouteGuide({
      'version': 1,
      'lang': 'en',
      'getting_there': 'Park by the boathouse.',
      'steps': [
        {'kind': 'start', 'at_m': 0, 'name': 'Lake Trail'},
        {'kind': 'junction', 'at_m': 400, 'turn': 'left', 'name': 'Ridge Trail'},
        {'kind': 'finish', 'at_m': 1990},
      ],
    });
    expect(guide, isNotNull);
    final xml = parkCourseGpx(
      name: 'Lake Loop',
      waypoints: const [(lat: 37.1, lng: -77.5, ele: null)],
      checkpoints: const [],
      attribution: null,
      guide: (guide: guide!, checkedAt: null),
    );
    expect(
      xml,
      contains('<desc>Drafted from map data, not yet checked on the ground.\nPark by the boathouse.\nStart on Lake Trail.\n'
          '400 m: turn left onto Ridge Trail.\n2.0 km: finish.</desc>'),
    );
  });

  test('parkCourseGpx: an unreadable checkpoint list writes no waypoints, never a partial set', () {
    final xml = parkCourseGpx(
      name: 'Lake Loop',
      waypoints: const [(lat: 37.1, lng: -77.5, ele: null)],
      checkpoints: null,
      attribution: null,
    );
    expect(xml, isNot(contains('<wpt')));
    expect(xml, isNot(contains('<desc>')));
  });

  RecapParkRow row(String park, String name, String course) =>
      RecapParkRow(parkId: park, parkName: name, regionCode: 'US-VA', courseId: course);

  test('recapParkSummary: no efforts is an empty summary', () {
    final s = recapParkSummary(const []);
    expect(s.courseCount, 0);
    expect(s.parkCount, 0);
    expect(s.parks, isEmpty);
  });

  test('recapParkSummary: a course run twice counts once', () {
    final s = recapParkSummary([row('p1', 'Lake', 'c1'), row('p1', 'Lake', 'c1'), row('p1', 'Lake', 'c2')]);
    expect(s.courseCount, 2);
    expect(s.parkCount, 1);
    expect(s.parks.single.courseCount, 2);
  });

  test('recapParkSummary: parks are ordered by courses run, then name', () {
    final s = recapParkSummary([
      row('p2', 'Bluff', 'c3'),
      row('p1', 'Alder', 'c4'),
      row('p3', 'Cove', 'c5'),
      row('p3', 'Cove', 'c6'),
    ]);
    expect(s.parks.map((p) => p.name).toList(), ['Cove', 'Alder', 'Bluff']);
  });

  RunParkCourseTime time(String name, int? monthRank, [int? seasonRank]) =>
      RunParkCourseTime(
        effortId: 'e-$name',
        courseName: name,
        courseSlug: 'lake-loop',
        parkName: 'Park',
        parkSlug: 'park',
        regionCode: 'US-VA',
        timeSeconds: 600,
        season: 2027,
        seasonRank: seasonRank,
        month: 11,
        monthRank: monthRank,
      );

  test('pickShareCourse: no course is null', () {
    expect(pickShareCourse(const []), isNull);
  });

  test('pickShareCourse: the best month place wins', () {
    expect(pickShareCourse([time('A', 7, 1), time('B', 2, 40), time('C', null)])?.courseName, 'B');
  });

  test('pickShareCourse: a tied month place goes to the better year place', () {
    expect(pickShareCourse([time('A', 1), time('B', 1, 12), time('C', 1, 3)])?.courseName, 'C');
  });

  test('pickShareCourse: with no placed course the first one is printed', () {
    expect(pickShareCourse([time('A', null), time('B', null)])?.courseName, 'A');
  });

  test('shareCoursePlaces: the year place only when it is in the top 10', () {
    expect(kShareCourseYearPlaceMax, 10);
    expect(shareCoursePlaces(time('A', 2, 9)), (monthRank: 2, seasonRank: 9));
    expect(shareCoursePlaces(time('A', 2, 10)), (monthRank: 2, seasonRank: 10));
    expect(shareCoursePlaces(time('A', 4, 11)), (monthRank: 4, seasonRank: null));
    expect(shareCoursePlaces(time('A', null)), (monthRank: null, seasonRank: null));
  });

  const ParkNow now = (season: 2026, month: 11);

  test('parseBoardPeriod: a month and all time', () {
    expect(parseBoardPeriod('2026-11', now), const BoardPeriod.month(2026, 11));
    expect(parseBoardPeriod('2025-01', now), const BoardPeriod.month(2025, 1));
    expect(parseBoardPeriod('2000-01', now), const BoardPeriod.month(2000, 1));
    expect(parseBoardPeriod('all', now), const BoardPeriod.all());
  });

  test('parseBoardPeriod: anything else, an impossible month or a month still to come is null', () {
    for (final raw in <String?>[null, '', '2026', '2026-1', '2026-001', '26-11', '2026-00', '2026-13', '1999-12', '2026-12', '2027-01', 'ALL', ' 2026-11', '2026-11 ']) {
      expect(parseBoardPeriod(raw, now), isNull, reason: '$raw');
    }
  });

  test('boardPeriodParam: a month is zero-padded, all time is all, the year has none', () {
    expect(boardPeriodParam(const BoardPeriod.month(2026, 3)), '2026-03');
    expect(boardPeriodParam(const BoardPeriod.month(2026, 11)), '2026-11');
    expect(boardPeriodParam(const BoardPeriod.all()), 'all');
    expect(boardPeriodParam(const BoardPeriod.year(2026)), isNull);
    expect(parseBoardPeriod(boardPeriodParam(const BoardPeriod.month(2026, 3)), now), const BoardPeriod.month(2026, 3));
  });

  test('boardPeriodArgs: the season and month each board call passes', () {
    expect(boardPeriodArgs(const BoardPeriod.month(2026, 10)), (season: 2026, month: 10));
    expect(boardPeriodArgs(const BoardPeriod.year(2026)), (season: 2026, month: null));
    expect(boardPeriodArgs(const BoardPeriod.all()), (season: null, month: null));
  });

  test('stepBoardMonth: steps across a year in both directions', () {
    expect(stepBoardMonth(const BoardPeriod.month(2026, 1), -1, now), const BoardPeriod.month(2025, 12));
    expect(stepBoardMonth(const BoardPeriod.month(2025, 12), 1, now), const BoardPeriod.month(2026, 1));
    expect(stepBoardMonth(const BoardPeriod.month(2026, 10), 1, now), const BoardPeriod.month(2026, 11));
  });

  test("stepBoardMonth: never past the park's month, nor before 2000, and only from a month", () {
    expect(stepBoardMonth(const BoardPeriod.month(2026, 11), 1, now), isNull);
    expect(stepBoardMonth(const BoardPeriod.month(2000, 1), -1, now), isNull);
    expect(stepBoardMonth(const BoardPeriod.year(2026), -1, now), isNull);
    expect(stepBoardMonth(const BoardPeriod.all(), 1, now), isNull);
  });

  test('parseSharedUse: reads a known key and nothing else', () {
    expect(kSharedUses, ['saturday_morning_group']);
    expect(parseSharedUse('saturday_morning_group'), 'saturday_morning_group');
    for (final raw in <Object?>[null, '', 'Saturday group', 'SATURDAY_MORNING_GROUP', 1, <String, Object>{}]) {
      expect(parseSharedUse(raw), isNull, reason: '$raw');
    }
  });
}
