import 'dart:math' as math;

import 'package:core_models/core_models.dart' show Waypoint;
import 'package:flutter_test/flutter_test.dart';

import '../lib/gate_crossing.dart';
import '../lib/race_match.dart';

// Issue #1389: the 2026 Richmond Marathon, 07:00 EST on Sat 14 Nov 2026, a
// course from a Broad St start (heading east) to a 5th & Byrd finish (heading
// south), against TFC Turkey Trot on Thanksgiving.
const raceStart = '2026-11-14T12:00:00Z';
const course = <List<double>>[
  [37.548, -77.461],
  [37.548, -77.45],
  [37.54, -77.444],
  [37.5355, -77.444],
];
const startLine =
    Gate(lat: 37.548, lng: -77.46, bearingDeg: 90, halfWidthM: 15);
const finishLine =
    Gate(lat: 37.5365, lng: -77.444, bearingDeg: 180, halfWidthM: 15);
const lines = RaceCourseLines(start: startLine, finish: finishLine);

/// The course walked at 4 m/s, one fix a second from the race start.
List<RaceMatchFix> walk(List<List<double>> points,
    [String startedAt = raceStart]) {
  final t0 = DateTime.parse(startedAt).millisecondsSinceEpoch.toDouble();
  final out = <RaceMatchFix>[];
  var t = t0;
  for (var i = 0; i < points.length - 1; i++) {
    final aLat = points[i][0], aLng = points[i][1];
    final bLat = points[i + 1][0], bLng = points[i + 1][1];
    final dy = (bLat - aLat) * 111195;
    final dx = (bLng - aLng) * 111195 * math.cos(aLat * math.pi / 180);
    final steps = math.max(1, (math.sqrt(dx * dx + dy * dy) / 4).ceil());
    for (var k = 0; k < steps; k++) {
      final f = k / steps;
      out.add(RaceMatchFix(
        lat: aLat + f * (bLat - aLat),
        lng: aLng + f * (bLng - aLng),
        tMs: t,
      ));
      t += 1000;
    }
  }
  out.add(RaceMatchFix(lat: points.last[0], lng: points.last[1], tMs: t));
  return out;
}

final richmondRun = RunMatchInput(
  startedAt: raceStart,
  distanceM: 42600,
  track: walk(course),
);

const richmond = ListingMatchInput(
  raceDate: '2026-11-14',
  distanceM: 42195,
  location: RaceMatchLocation(lat: 37.5407, lng: -77.436),
  lines: lines,
);
const turkeyTrot = ListingMatchInput(
  raceDate: '2026-11-26',
  distanceM: 5000,
  location: RaceMatchLocation(lat: 37.545, lng: -77.44),
);

ListingMatchInput withListing(
  ListingMatchInput l, {
  String? raceDate,
  num? distanceM,
  bool clearDistance = false,
  num? courseDistanceM,
  RaceMatchLocation? location,
}) =>
    ListingMatchInput(
      raceDate: raceDate ?? l.raceDate,
      distanceM: clearDistance ? null : (distanceM ?? l.distanceM),
      courseDistanceM: courseDistanceM ?? l.courseDistanceM,
      location: location ?? l.location,
      lines: l.lines,
    );

class _Named {
  final String name;
  final ListingMatchInput input;
  const _Named(this.name, this.input);
}

void main() {
  test('startedOnRaceDay: the race morning is on the day, Thanksgiving is not',
      () {
    expect(startedOnRaceDay(raceStart, '2026-11-14'), isTrue);
    expect(startedOnRaceDay(raceStart, '2026-11-26'), isFalse);
  });

  test('startedOnRaceDay: the window is the day from UTC+14 to UTC-12', () {
    expect(startedOnRaceDay('2026-11-13T10:00:00Z', '2026-11-14'), isTrue);
    expect(startedOnRaceDay('2026-11-13T09:59:59Z', '2026-11-14'), isFalse);
    expect(startedOnRaceDay('2026-11-15T11:59:59Z', '2026-11-14'), isTrue);
    expect(startedOnRaceDay('2026-11-15T12:00:00Z', '2026-11-14'), isFalse);
  });

  test('startedOnRaceDay: a malformed date or start is never on the day', () {
    expect(startedOnRaceDay(raceStart, '14/11/2026'), isFalse);
    expect(startedOnRaceDay('not a time', '2026-11-14'), isFalse);
  });

  test('a race on another date is excluded whatever else matches', () {
    expect(raceMatch(richmondRun, turkeyTrot), isNull);
    expect(raceMatch(richmondRun, withListing(richmond, raceDate: '2026-11-26')),
        isNull);
    expect(raceMatchScore(richmondRun, turkeyTrot), 0);
  });

  test('a same-day race of a different distance is excluded', () {
    expect(
        raceMatch(richmondRun, withListing(turkeyTrot, raceDate: '2026-11-14')),
        isNull);
    expect(raceMatch(richmondRun, withListing(richmond, distanceM: 21097)),
        isNull);
  });

  test('the course distance stands in for a listing with none', () {
    expect(
      raceMatch(richmondRun,
          withListing(richmond, clearDistance: true, courseDistanceM: 42195)),
      isNotNull,
    );
    expect(
      raceMatch(richmondRun,
          withListing(richmond, clearDistance: true, courseDistanceM: 5000)),
      isNull,
    );
  });

  test('a start more than 50 km from the race is excluded', () {
    // Virginia Beach, about 150 km east.
    expect(
      raceMatch(
          richmondRun,
          withListing(richmond,
              location: const RaceMatchLocation(lat: 36.8529, lng: -75.978))),
      isNull,
    );
  });

  test('runCrossesCourse: start line then finish line in order', () {
    expect(runCrossesCourse(richmondRun.track, lines), isTrue);
    expect(runCrossesCourse(walk(course.reversed.toList()), lines), isFalse);
    expect(runCrossesCourse(richmondRun.track, null), isNull);
    expect(runCrossesCourse(const [], lines), isNull);
  });

  test('runCrossesCourse: a course with one usable line is judged on that line',
      () {
    const noStart = RaceCourseLines(
      start: Gate(lat: 37.548, lng: -77.46, bearingDeg: 90, halfWidthM: 0),
      finish: finishLine,
    );
    expect(runCrossesCourse(richmondRun.track, noStart), isTrue);
    expect(runCrossesCourse(walk(course.sublist(0, 2)), noStart), isFalse);
  });

  test('issue #1389: the Richmond Marathon is offered, not the Turkey Trot', () {
    const sameDayUnknown = ListingMatchInput(
      raceDate: '2026-11-14',
      distanceM: null,
      location: RaceMatchLocation(lat: 37.549, lng: -77.462),
    );
    const listings = [
      _Named('TFC Turkey Trot', turkeyTrot),
      _Named('Saturday race, no distance', sameDayUnknown),
      _Named('Richmond Marathon', richmond),
    ];
    expect(bestRaceMatch(richmondRun, listings, (l) => l.input)?.name,
        'Richmond Marathon');
  });

  test('a crossed course ranks above a higher score without lines', () {
    const exact = ListingMatchInput(
      raceDate: '2026-11-14',
      distanceM: 42600,
      location: RaceMatchLocation(lat: 37.548, lng: -77.461),
    );
    final exactScore = raceMatchScore(richmondRun, exact);
    final richmondScore = raceMatchScore(richmondRun, richmond);
    expect(exactScore, greaterThan(richmondScore));
    const listings = [
      _Named('exact', exact),
      _Named('Richmond Marathon', richmond),
    ];
    expect(bestRaceMatch(richmondRun, listings, (l) => l.input)?.name,
        'Richmond Marathon');
  });

  test('the score weighs day, proximity, distance and course', () {
    // Location at the radius' midpoint from the first fix, distance 5 % long
    // (a third of the tolerance), course crossed:
    // (0.5 + 0.3 * 0.5 + 0.2 * (2 / 3) + 0.5) / (0.5 + 0.3 + 0.2 + 0.5).
    final first = richmondRun.track!.first;
    final north = (raceMatchRadiusM / 2) / 6371000 * (180 / math.pi);
    final m = raceMatch(
      RunMatchInput(
        startedAt: raceStart,
        distanceM: 42195 * 1.05,
        track: richmondRun.track,
      ),
      withListing(richmond,
          location: RaceMatchLocation(lat: first.lat + north, lng: first.lng)),
    );
    expect(m, isNotNull);
    const expected = (0.5 + 0.15 + 0.2 * (2 / 3) + 0.5) / 1.5;
    expect(m!.score, closeTo(expected, 1e-6));
    expect(m.crossesCourse, isTrue);
  });

  test('a run that misses the lines is still a candidate, ranked by score', () {
    final late = walk(course.sublist(1));
    final m = raceMatch(
      RunMatchInput(startedAt: raceStart, distanceM: 42600, track: late),
      richmond,
    );
    expect(m, isNotNull);
    expect(m!.crossesCourse, isFalse);
    expect(m.score, greaterThanOrEqualTo(raceMatchThreshold));
    expect(m.score, lessThan(raceMatchScore(richmondRun, richmond)));
  });

  test('raceMatchFixes keeps timed on-track fixes at their line position', () {
    final fixes = raceMatchFixes([
      Waypoint(lat: 1, lng: 2, timestamp: DateTime.utc(2026, 11, 14, 12)),
      Waypoint(lat: 1.1, lng: 2.1),
      Waypoint(
        lat: 1.2,
        lng: 2.2,
        timestamp: DateTime.utc(2026, 11, 14, 12, 0, 2),
        offTrack: true,
      ),
      Waypoint(
        lat: 1.3,
        lng: 2.3,
        smoothedLat: 1.31,
        smoothedLng: 2.31,
        timestamp: DateTime.utc(2026, 11, 14, 12, 0, 3),
      ),
    ]);
    expect(fixes, [
      RaceMatchFix(
        lat: 1,
        lng: 2,
        tMs: DateTime.utc(2026, 11, 14, 12).millisecondsSinceEpoch.toDouble(),
      ),
      RaceMatchFix(
        lat: 1.31,
        lng: 2.31,
        tMs: DateTime.utc(2026, 11, 14, 12, 0, 3)
            .millisecondsSinceEpoch
            .toDouble(),
      ),
    ]);
    expect(raceMatchFixes(null), isEmpty);
  });

  test('isRaceMatchCandidate gates on the documented 0.5 threshold', () {
    expect(raceMatchThreshold, 0.5);
    expect(isRaceMatchCandidate(richmondRun, richmond), isTrue);
    expect(isRaceMatchCandidate(richmondRun, turkeyTrot), isFalse);
  });

  test('the date alone is never enough', () {
    const unknown = ListingMatchInput(raceDate: '2026-11-14', distanceM: null);
    expect(raceMatch(richmondRun, unknown), isNull);
    expect(
      raceMatch(
          const RunMatchInput(startedAt: raceStart, distanceM: null), unknown),
      isNull,
    );
    expect(
      raceMatch(
        const RunMatchInput(startedAt: raceStart, distanceM: 42100),
        const ListingMatchInput(raceDate: '2026-11-14', distanceM: 42195),
      ),
      isNotNull,
    );
  });

  test('bestRaceMatch is null when nothing passes', () {
    expect(
        bestRaceMatch(richmondRun, const [turkeyTrot], (l) => l), isNull);
    expect(bestRaceMatch(richmondRun, const <ListingMatchInput>[], (l) => l),
        isNull);
  });
}
