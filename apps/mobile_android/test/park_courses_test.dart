import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_android/park_courses.dart';

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
}
