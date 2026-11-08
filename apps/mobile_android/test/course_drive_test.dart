import 'package:flutter_test/flutter_test.dart';

import '../lib/course_drive.dart';
import '../lib/route_markers.dart' show CutoffParts;

/// Twin of web's `routes/course_drive.test.ts`. Keep in lockstep — same
/// cases, same tolerances.
///
/// A straight line due north from 37.5,-77.45: one point every 0.001° of
/// latitude, about 111.2 m apart.
const stepM = 111.19;

List<DrivePoint> north(int n, {double from = 37.5, double lng = -77.45}) =>
    [for (var i = 0; i < n; i++) DrivePoint(from + i * 0.001, lng)];

final line = north(41);

final outAndBack = <DrivePoint>[
  ...north(19),
  ...north(19).reversed.map((p) => DrivePoint(p.lat, p.lng + 0.00023)),
];

DriveNote note(double alongM, [String? label]) =>
    DriveNote(alongM: alongM, kind: 'note', label: label ?? 'n$alongM');

void near(double a, double b, double tol) =>
    expect((a - b).abs() <= tol, isTrue, reason: '$a is not within $tol of $b');

void main() {
  test('cumulativeM measures each point from the start', () {
    expect(cumulativeM(const []), isEmpty);
    expect(cumulativeM(const [DrivePoint(1, 1)]), [0]);
    final cum = cumulativeM(line);
    expect(cum[0], 0);
    near(cum[40], 40 * stepM, 2);
  });

  test('snapWithinAlong answers null for a degenerate line or an inverted window',
      () {
    expect(
        snapWithinAlong((lat: 37.5, lng: -77.45), [line[0]], const [0], 0, 100),
        isNull);
    final cum = cumulativeM(line);
    expect(snapWithinAlong((lat: 37.5, lng: -77.45), line, cum, 500, 100),
        isNull);
    expect(snapWithinAlong((lat: double.nan, lng: -77.45), line, cum, 0, 100),
        isNull);
  });

  test('snapWithinAlong follows the pass of an out-and-back the window names',
      () {
    final cum = cumulativeM(outAndBack);
    const p = (lat: 37.505, lng: -77.45);
    final out = snapWithinAlong(p, outAndBack, cum, 0, 1500)!;
    near(out.alongM, 5 * stepM, 3);
    final back = snapWithinAlong(p, outAndBack, cum, 2500, 4500)!;
    expect(back.alongM > 2500, isTrue, reason: '${back.alongM}');
    near(back.offsetM, 20, 3);
  });

  test('placeOnLine puts a marker on the pass its position hint names', () {
    final cum = cumulativeM(outAndBack);
    const p = (lat: 37.505, lng: -77.4499);
    final first = placeOnLine(p, outAndBack, cum, 600)!;
    near(first.alongM, 5 * stepM, 3);
    final second = placeOnLine(p, outAndBack, cum, 3400)!;
    expect(second.alongM > 3000, isTrue, reason: '${second.alongM}');
  });

  test(
      'placeOnLine without a hint takes the nearest pass, and refuses a far marker',
      () {
    final cum = cumulativeM(outAndBack);
    final nearest =
        placeOnLine((lat: 37.505, lng: -77.44995), outAndBack, cum, null)!;
    expect(nearest.alongM < 2000, isTrue, reason: '${nearest.alongM}');
    expect(
        placeOnLine((lat: 37.505, lng: -77.45 + 0.01), outAndBack, cum, null),
        isNull);
  });

  test('pointAtAlong clamps to the ends and interpolates between points', () {
    final cum = cumulativeM(line);
    expect(pointAtAlong(line, cum, -5), (lat: 37.5, lng: -77.45));
    expect(pointAtAlong(line, cum, 1e9), (lat: line[40].lat, lng: -77.45));
    final mid = pointAtAlong(line, cum, cum[1] / 2)!;
    near(mid.lat, 37.5005, 1e-9);
    expect(pointAtAlong(const [], const [], 10), isNull);
  });

  test('buildDriveNotes orders markers along the line and drops the ones off it',
      () {
    final notes = buildDriveNotes(const [
      DriveMarkerInput(
          kind: 'hazard',
          label: ' Pothole ',
          lat: 37.52,
          lng: -77.45,
          positionM: 2224,
          meta: null),
      DriveMarkerInput(
          kind: 'aid_station',
          label: 'Aid 1',
          lat: 37.505,
          lng: -77.45,
          positionM: 556,
          meta: {
            'services': ['water', 'water', 'food', 7]
          }),
      DriveMarkerInput(
          kind: 'mystery',
          label: 'Odd',
          lat: 37.51,
          lng: -77.45,
          positionM: null,
          meta: <String, Object?>{}),
      DriveMarkerInput(
          kind: 'note',
          label: 'Far away',
          lat: 37.51,
          lng: -77.4,
          positionM: 1112,
          meta: <String, Object?>{}),
      DriveMarkerInput(
          kind: 'cutoff',
          label: 'Cut',
          lat: 37.53,
          lng: -77.45,
          positionM: 3336,
          meta: {
            'cutoff_clock': '10:30',
            'services': ['water']
          }),
    ], line);
    expect([for (final n in notes) [n.kind, n.label]], [
      ['aid_station', 'Aid 1'],
      ['custom', 'Odd'],
      ['hazard', 'Pothole'],
      ['cutoff', 'Cut'],
    ]);
    expect(notes[0].services, ['water', 'food']);
    expect(notes[3].services, isEmpty);
    expect(notes[3].cutoff, const CutoffParts(clock: '10:30'));
    expect(notes[0].cutoff, isNull);
    near(notes[2].alongM, 20 * stepM, 3);
  });

  test('climbFrom measures a climb from its marker to the crest', () {
    final hill = [
      for (final (i, p) in north(20).indexed)
        DrivePoint(p.lat, p.lng,
            ele: i < 9
                ? 100
                : i <= 15
                    ? 100 + (i - 9) * 3.0
                    : 118 - (i - 15) * 6.0),
    ];
    final cum = cumulativeM(hill);
    final climb = climbFrom(hill, cum, cum[9])!;
    near(climb.lengthM, 6 * stepM, 2);
    expect(climb.gradePct, 2.7);
    expect(climbFrom(line, cumulativeM(line), 500), isNull);
    final gentle = [
      for (final (i, p) in north(20).indexed)
        DrivePoint(p.lat, p.lng, ele: 100 + i * 0.4),
    ];
    expect(climbFrom(gentle, cumulativeM(gentle), 0), isNull);
  });

  test('driveLeadM is about 15 s ahead, held between its floor and ceiling',
      () {
    expect(driveLeadM(0), kDriveLeadMinM);
    expect(driveLeadM(double.nan), kDriveLeadMinM);
    expect(driveLeadM(-3), kDriveLeadMinM);
    expect(driveLeadM(14), 210);
    expect(driveLeadM(25), 375);
    expect(driveLeadM(200), kDriveLeadMaxM);
  });

  test('driveAtM widens with speed above its 30 m floor', () {
    expect(driveAtM(0), 30);
    expect(driveAtM(5), 30);
    expect(driveAtM(20), 60);
  });

  test('the announcer speaks a note ahead, then at it, then never again', () {
    final a = DriveCueAnnouncer([note(1000)]);
    expect(a.next(0, 14), isNull);
    final ahead = a.next(800, 14)!;
    expect(ahead.band, DriveCueBand.ahead);
    expect(ahead.aheadM, 200);
    expect(a.next(850, 14), isNull);
    expect(a.next(980, 14)!.band, DriveCueBand.at);
    expect(a.next(1000, 14), isNull);
    expect(a.next(1100, 14), isNull);
    expect(a.remaining, 0);
  });

  test('a fix inside both bands at once speaks only the at cue', () {
    final a = DriveCueAnnouncer([note(1000)]);
    final cue = a.next(990, 14)!;
    expect(cue.band, DriveCueBand.at);
    expect(a.next(995, 14), isNull);
  });

  test('a note passed between fixes with nothing said is reported once', () {
    final a = DriveCueAnnouncer([note(1000), note(3000)]);
    expect(a.next(700, 14), isNull);
    final passed = a.next(1300, 14)!;
    expect(passed.band, DriveCueBand.passed);
    expect(passed.aheadM, -300);
    expect(a.next(1310, 14), isNull);
    // Far past the second (a GPS gap): retired without a word.
    expect(a.next(4000, 14), isNull);
    expect(a.remaining, 0);
  });

  test('joining mid-course retires the notes behind the join silently', () {
    final a = DriveCueAnnouncer([note(500), note(1000), note(4000)], 2000);
    expect(a.remaining, 1);
    expect(a.next(2000, 14), isNull);
    expect(a.next(3800, 14)!.note.alongM, 4000);
  });

  test('the second of two close notes waits for the first to be reached', () {
    final a = DriveCueAnnouncer([note(1000, 'a'), note(1100, 'b')]);
    expect(a.next(800, 14)!.note.label, 'a');
    expect(a.next(820, 14), isNull);
    final at = a.next(970, 14)!;
    expect([at.note.label, at.band], ['a', DriveCueBand.at]);
    final next = a.next(975, 14)!;
    expect([next.note.label, next.band], ['b', DriveCueBand.ahead]);
  });

  test('at 90 km/h with a fix every two seconds every note is still heard', () {
    final notes = [for (final d in [300, 900, 960, 2000, 2050, 3500]) note(d.toDouble())];
    final a = DriveCueAnnouncer(notes);
    final heard = <int>{};
    final cues = <DriveCue>[];
    for (var along = 0.0; along <= 4000; along += 50) {
      for (var c = a.next(along, 25); c != null; c = a.next(along, 25)) {
        heard.add(c.index);
        cues.add(c);
      }
    }
    expect(heard.length, notes.length);
    expect(cues.every((c) => c.aheadM <= driveLeadM(25)), isTrue);
  });

  test('planDriveLegs pins each Google leg every 1.5 km with nine stops', () {
    final long = north(271);
    final total = cumulativeM(long)[270];
    final legs = planDriveLegs(long, 9);
    expect(legs.length, 3);
    for (final leg in legs) {
      expect(leg.via.length, 8);
    }
    expect(legs[0].start.alongM, 0);
    near(legs[2].end.alongM, total, 1e-6);
    near(legs[1].start.alongM, legs[0].end.alongM, 1e-6);
    near(legs[0].via[0].alongM - legs[0].start.alongM, total / 3 / 9, 1e-6);
    expect([for (final l in legs) l.index], [0, 1, 2]);
  });

  test('planDriveLegs gives a single-destination app one leg every 3 km', () {
    final legs = planDriveLegs(north(271), 0);
    expect(legs.length, 11); // 30.02 km
    expect(legs.every((l) => l.via.isEmpty), isTrue);
    final mobileWeb = planDriveLegs(north(271), 3);
    expect(mobileWeb.length, 7);
    expect(mobileWeb.every((l) => l.via.length == 2), isTrue);
  });

  test('planDriveLegs never drives across a gap in the served line', () {
    final gapped = [...north(10), ...north(10, from: 37.53)];
    final cum = cumulativeM(gapped);
    expect(cum[10] - cum[9] > kDriveMaxJoinM, isTrue);
    final legs = planDriveLegs(gapped, 9);
    expect(legs.length, 2);
    near(legs[0].end.alongM, cum[9], 1e-6);
    near(legs[1].start.alongM, cum[10], 1e-6);
  });

  test('planDriveLegs has nothing to plan on a point or a stub', () {
    expect(planDriveLegs(const [], 9), isEmpty);
    expect(planDriveLegs([line[0]], 9), isEmpty);
    expect(
        planDriveLegs(
            const [DrivePoint(37.5, -77.45), DrivePoint(37.5001, -77.45)], 9),
        isEmpty);
  });

  test('googleMapsLegUrl drives from here through the leg, inside the URL cap',
      () {
    const leg = DriveLeg(
      index: 0,
      start: DriveStop(lat: 37.5, lng: -77.45, alongM: 0),
      via: [DriveStop(lat: 37.51234567, lng: -77.4, alongM: 1)],
      end: DriveStop(lat: 37.52, lng: -77.35, alongM: 2),
    );
    expect(
      googleMapsLegUrl(leg),
      'https://www.google.com/maps/dir/?api=1&destination=37.52000%2C-77.35000'
      '&waypoints=37.50000%2C-77.45000%7C37.51235%2C-77.40000&travelmode=driving',
    );
    expect(mapsLegUrl(MapsApp.google, leg), googleMapsLegUrl(leg));
    for (final l in planDriveLegs(north(271), 9)) {
      expect(googleMapsLegUrl(l).length < 2048, isTrue);
    }
  });

  test('Apple Maps, Waze and the drive-to-start links each name one destination',
      () {
    expect(appleMapsUrl(37.5, -77.45),
        'https://maps.apple.com/?daddr=37.50000%2C-77.45000&dirflg=d');
    expect(wazeUrl(37.5, -77.45),
        'https://waze.com/ul?ll=37.50000%2C-77.45000&navigate=yes');
    const leg = DriveLeg(
      index: 0,
      start: DriveStop(lat: 37.5, lng: -77.45, alongM: 0),
      via: [],
      end: DriveStop(lat: 37.6, lng: -77.45, alongM: 1),
    );
    expect(mapsLegUrl(MapsApp.apple, leg), appleMapsUrl(37.6, -77.45));
    expect(mapsLegUrl(MapsApp.waze, leg), wazeUrl(37.6, -77.45));
    expect(
      mapsStartUrl(MapsApp.google, 37.5, -77.45),
      'https://www.google.com/maps/dir/?api=1&destination=37.50000%2C-77.45000&travelmode=driving',
    );
    expect(mapsStartUrl(MapsApp.apple, 37.5, -77.45), appleMapsUrl(37.5, -77.45));
    expect(mapsStartUrl(MapsApp.waze, 37.5, -77.45), wazeUrl(37.5, -77.45));
  });

  test('undrivableStretches finds where the router leaves the course', () {
    expect(undrivableStretches(line, line), isEmpty);
    final routed = [
      for (final (i, p) in line.indexed)
        i >= 14 && i <= 22 ? DrivePoint(p.lat, p.lng + 0.0034) : p,
    ];
    final stretches = undrivableStretches(line, routed);
    expect(stretches.length, 1);
    near(stretches[0].startM, 13.5 * stepM, 60);
    near(stretches[0].endM, 22.5 * stepM, 60);
  });

  test(
      'undrivableStretches ignores a short wobble and reports all of an unrouted course',
      () {
    final wobble = [
      for (final (i, p) in line.indexed)
        i == 20 ? DrivePoint(p.lat, p.lng + 0.0034) : p,
    ];
    expect(undrivableStretches(line, wobble), isEmpty);
    final total = cumulativeM(line)[40];
    expect(undrivableStretches(line, const []),
        [CourseStretch(startM: 0, endM: total)]);
    expect(undrivableStretches([line[0]], line), isEmpty);
  });
}
