import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/course_drive.dart';
import '../lib/course_drive_location.dart' show DrivePosition;
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/screens/course_drive_screen.dart';

/// Due north from 37.5,-77.45, one point every ~111 m.
List<DrivePoint> north(int n) => [
  for (var i = 0; i < n; i++) DrivePoint(37.5 + i * 0.001, -77.45),
];

const _markers = [
  DriveMarkerInput(
    kind: 'aid_station',
    label: 'Aid 1',
    lat: 37.51,
    lng: -77.45,
    positionM: 1112,
    meta: {
      'services': ['water'],
    },
  ),
  DriveMarkerInput(
    kind: 'hazard',
    label: 'Rail crossing',
    lat: 37.53,
    lng: -77.45,
    positionM: 3336,
    meta: null,
  ),
];

class _Harness {
  _Harness({
    this.line,
    this.ack = true,
    this.permission = true,
    this.speechFails = false,
    this.stretches = const [],
  });

  final List<DrivePoint>? line;
  final bool ack;
  final bool permission;
  final bool speechFails;
  final List<CourseStretch>? stretches;

  final positions = StreamController<DrivePosition>.broadcast();
  final spoken = <String>[];
  final launched = <Uri>[];
  var acksWritten = 0;

  Widget app() => MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: CourseDriveScreen(
      title: 'Richmond Marathon',
      load: () async =>
          CourseDriveCourse(line: line ?? north(41), markers: _markers),
      checkDrivable: (_) async => stretches,
      positions: () => positions.stream,
      ensurePermission: () async => permission,
      speak: (text) async {
        spoken.add(text);
        if (speechFails) throw Exception('tts engine missing');
      },
      launch: (u) async {
        launched.add(u);
        return true;
      },
      readNoticeAck: () async => ack,
      writeNoticeAck: () async => acksWritten++,
    ),
  );
}

final _t0 = DateTime.utc(2026, 11, 8, 9);

/// Drive the line at about 14 m/s (50 km/h), one fix every 100 m.
Future<void> _drive(WidgetTester tester, _Harness h, double totalM) async {
  for (var along = 0.0; along <= totalM + 50; along += 100) {
    final lat = 37.5 + (along / 111.19) * 0.001;
    h.positions.add((
      lat: lat,
      lng: -77.45,
      at: _t0.add(Duration(milliseconds: (along / 14 * 1000).round())),
    ));
    await tester.pump();
  }
}

void main() {
  testWidgets(
    'the first open shows the safety notice, and accepting records it',
    (tester) async {
      final h = _Harness(ack: false);
      await tester.pumpWidget(h.app());
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const Key('course-drive-notice')), findsOneWidget);
      expect(
        find.textContaining('passenger or a mounted phone'),
        findsOneWidget,
      );
      await tester.tap(find.text('I understand'));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const Key('course-drive-notice')), findsNothing);
      expect(h.acksWritten, 1);
    },
  );

  testWidgets(
    'the hand-off lists the legs, the stretch Maps cannot follow and the notes, and opens the chosen app',
    (tester) async {
      final h = _Harness(
        stretches: const [CourseStretch(startM: 1500, endM: 2500)],
      );
      await tester.pumpWidget(h.app());
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const Key('course-drive-leg-0')), findsOneWidget);
      expect(find.byKey(const Key('course-drive-stretch')), findsOneWidget);
      expect(find.text("Maps can't follow these stretches"), findsOneWidget);
      expect(find.text('Aid station · Aid 1'), findsOneWidget);
      expect(find.text('Water'), findsOneWidget);
      expect(find.text('Hazard · Rail crossing'), findsOneWidget);

      await tester.tap(find.byKey(const Key('course-drive-leg-0')));
      await tester.pump();
      expect(h.launched.single.host, 'www.google.com');
      expect(h.launched.single.queryParameters['travelmode'], 'driving');

      await tester.tap(find.text('Waze'));
      await tester.pump();
      await tester.tap(find.byKey(const Key('course-drive-to-start')));
      await tester.pump();
      expect(
        h.launched.last.toString(),
        'https://waze.com/ul?ll=37.50000%2C-77.45000&navigate=yes',
      );
    },
  );

  testWidgets(
    'a check that could not run says so instead of claiming the course is drivable',
    (tester) async {
      final h = _Harness(stretches: null);
      await tester.pumpWidget(h.app());
      await tester.pump();
      await tester.pump();

      expect(
        find.byKey(const Key('course-drive-check-failed')),
        findsOneWidget,
      );
      expect(find.text('Maps can follow the whole course.'), findsNothing);
    },
  );

  testWidgets(
    'spoken notes: each note ahead and at it, a leg-done line, and the finish',
    (tester) async {
      final line = north(271);
      final h = _Harness(line: line);
      await tester.pumpWidget(h.app());
      await tester.pump();
      await tester.pump();

      await tester.tap(find.byKey(const Key('course-drive-start')));
      await tester.pump();
      expect(find.byKey(const Key('course-drive-stop')), findsOneWidget);
      expect(
        find.text('Head to the course. Notes start when you reach it.'),
        findsOneWidget,
      );

      await _drive(tester, h, cumulativeM(line).last);

      expect(h.spoken.first, 'Drive notes on.');
      expect(
        h.spoken,
        containsAllInOrder([
          matches(r'^In \d+ metres: Aid station, Aid 1\. Services: Water\.$'),
          'Now: Aid station, Aid 1. Services: Water.',
          matches(r'^In \d+ metres: Hazard, Rail crossing\.$'),
          'Now: Hazard, Rail crossing.',
          'Leg 1 done. Leg 2 is ready.',
          'Leg 2 done. Leg 3 is ready.',
          "You've reached the finish. Drive notes stopped.",
        ]),
      );
      expect(find.byKey(const Key('course-drive-finished')), findsOneWidget);
      expect(find.byKey(const Key('course-drive-stop')), findsNothing);
    },
  );

  testWidgets('a speech engine that fails never stops the drive', (
    tester,
  ) async {
    final h = _Harness(speechFails: true);
    await tester.pumpWidget(h.app());
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byKey(const Key('course-drive-start')));
    await tester.pump();
    await _drive(tester, h, cumulativeM(north(41)).last);

    expect(h.spoken.length, greaterThan(3));
    expect(find.byKey(const Key('course-drive-finished')), findsOneWidget);
  });

  testWidgets('Stop ends the drive and returns to the hand-off', (
    tester,
  ) async {
    final h = _Harness();
    await tester.pumpWidget(h.app());
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byKey(const Key('course-drive-start')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('course-drive-stop')));
    await tester.pump();
    expect(find.byKey(const Key('course-drive-start')), findsOneWidget);
    expect(h.positions.hasListener, isFalse);
  });

  testWidgets('without location the drive does not start and says why', (
    tester,
  ) async {
    final h = _Harness(permission: false);
    await tester.pumpWidget(h.app());
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byKey(const Key('course-drive-start')));
    await tester.pump();
    await tester.pump();
    expect(
      find.text("Location is off, so the notes can't follow you."),
      findsOneWidget,
    );
    expect(find.byKey(const Key('course-drive-stop')), findsNothing);
    expect(h.spoken, isEmpty);
    await tester.pump(const Duration(seconds: 4));
  });
}
