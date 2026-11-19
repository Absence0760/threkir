import 'package:core_models/core_models.dart' show Waypoint;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/course_jump.dart';
import '../lib/gate_crossing.dart' show Gate;
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/widgets/park_course_map.dart';

const _lat = 37.4;
const _lng = -78.4;
const _mPerDegLat = 111320.0;

final _line = [
  const Waypoint(lat: _lat, lng: _lng),
  const Waypoint(lat: _lat + 500 / _mPerDegLat, lng: _lng + 0.002),
  const Waypoint(lat: _lat + 1000 / _mPerDegLat, lng: _lng),
];

Gate _gate(double lat, double bearing) =>
    Gate(lat: lat, lng: _lng, bearingDeg: bearing, halfWidthM: 15);

Future<void> _pump(
  WidgetTester tester, {
  required ({Gate start, Gate finish})? zones,
  bool reduceMotion = false,
}) async {
  await tester.pumpWidget(MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: MediaQuery(
      data: MediaQueryData(
          size: const Size(400, 800), disableAnimations: reduceMotion),
      child: Scaffold(
        body: SingleChildScrollView(
          child: SizedBox(
            width: 400,
            child: ParkCourseMap(line: _line, zones: zones),
          ),
        ),
      ),
    ),
  ));
  await tester.pump();
}

/// The tile layer's load and retry timers outlive the frame; unmount the map
/// and let them run out so the test ends with none pending.
Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 5));
}

Finder _jump(CourseJumpTarget t) =>
    find.byKey(ValueKey('park-course-jump-${t.name}'));

void main() {
  testWidgets('a point-to-point gets Start, Finish and Whole course, and each '
      'moves the map', (tester) async {
    await _pump(tester, zones: (
      start: _gate(_lat, 0),
      finish: _gate(_lat + 1000 / _mPerDegLat, 0),
    ));
    expect(find.text('Show on the map'), findsOneWidget);
    expect(_jump(CourseJumpTarget.start), findsOneWidget);
    expect(_jump(CourseJumpTarget.finish), findsOneWidget);
    expect(_jump(CourseJumpTarget.course), findsOneWidget);
    expect(_jump(CourseJumpTarget.startFinish), findsNothing);
    expect(
      find.descendant(
          of: _jump(CourseJumpTarget.course),
          matching: find.text('Whole course')),
      findsOneWidget,
    );
    // Big enough to hit.
    expect(tester.getSize(_jump(CourseJumpTarget.start)).height,
        greaterThanOrEqualTo(48));

    final state = tester.state<ParkCourseMapState>(find.byType(ParkCourseMap));
    final whole = state.camera.zoom;

    await tester.tap(_jump(CourseJumpTarget.start));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    final atStart = state.camera;
    expect(atStart.zoom, greaterThan(whole));
    expect(atStart.zoom, lessThanOrEqualTo(kCourseJumpMaxZoom));
    expect(atStart.center.latitude, closeTo(_lat, 0.001));

    await tester.tap(_jump(CourseJumpTarget.finish));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(state.camera.center.latitude,
        closeTo(_lat + 1000 / _mPerDegLat, 0.001));

    await tester.tap(_jump(CourseJumpTarget.course));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(state.camera.zoom, closeTo(whole, 0.01));
    await _unmount(tester);
  });

  testWidgets('a start and finish at one spot is one Start and finish button',
      (tester) async {
    await _pump(tester, zones: (start: _gate(_lat, 0), finish: _gate(_lat, 180)));
    expect(_jump(CourseJumpTarget.startFinish), findsOneWidget);
    expect(_jump(CourseJumpTarget.start), findsNothing);
    expect(_jump(CourseJumpTarget.finish), findsNothing);
    expect(
      find.descendant(
          of: _jump(CourseJumpTarget.startFinish),
          matching: find.text('Start and finish')),
      findsOneWidget,
    );
    await _unmount(tester);
  });

  testWidgets('with less motion asked for, a jump lands at once',
      (tester) async {
    await _pump(
      tester,
      zones: (start: _gate(_lat, 0), finish: _gate(_lat + 1000 / _mPerDegLat, 0)),
      reduceMotion: true,
    );
    final state = tester.state<ParkCourseMapState>(find.byType(ParkCourseMap));
    final whole = state.camera.zoom;
    await tester.tap(_jump(CourseJumpTarget.start));
    await tester.pump();
    expect(state.camera.zoom, greaterThan(whole));
    await _unmount(tester);
  });
}
