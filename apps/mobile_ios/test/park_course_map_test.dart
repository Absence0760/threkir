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

final _mapKey = GlobalKey<ParkCourseMapState>();

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
            child: Column(
              children: [
                ParkCourseMap(key: _mapKey, line: _line, zones: zones),
                ParkCourseMapLegend(
                  line: _line,
                  checkpointCount: 0,
                  zones: zones,
                  onJump: (t) => _mapKey.currentState?.jumpTo(t),
                ),
              ],
            ),
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

Finder _tag(String which) => find.byKey(ValueKey('park-course-box-$which'));
final _wholeCourse = find.byKey(const ValueKey('park-course-jump-course'));

/// Tap a tag above its middle: the start sits at the foot of this map, where
/// the map's credit line overlaps the lower half of its tag.
Future<void> _tapTag(WidgetTester tester, String which) =>
    tester.tapAt(tester.getRect(_tag(which)).center.translate(0, -12));

/// A button named [label]: its Semantics widget, read whether or not the map
/// clips its node.
Finder _named(String label) => find.byWidgetPredicate(
    (w) => w is Semantics && w.properties.button == true && w.properties.label == label);

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  testWidgets('the start and finish tags on the map, their key entries and '
      'the whole-course control each move the map', (tester) async {
    await _pump(tester, zones: (
      start: _gate(_lat, 0),
      finish: _gate(_lat + 1000 / _mPerDegLat, 0),
    ));
    // No row of buttons under the map any more.
    expect(find.text('Show on the map'), findsNothing);
    expect(find.text('Whole course'), findsNothing);
    // The tags and the key's entries are buttons named for what they do.
    expect(_named('Show the start on the map'), findsNWidgets(2));
    expect(_named('Show the finish on the map'), findsNWidgets(2));
    expect(find.byTooltip('Show the whole course'), findsOneWidget);
    // Big enough to hit, the key's entries without looking bigger.
    expect(tester.getSize(_wholeCourse).height, greaterThanOrEqualTo(48));
    final keyStart = find.byKey(const Key('park-course-legend-start-box'));
    expect(tester.getSize(keyStart).height, greaterThanOrEqualTo(48));

    final state = _mapKey.currentState!;
    final whole = state.camera.zoom;

    await _tapTag(tester, 'start');
    await _settle(tester);
    final atStart = state.camera;
    expect(atStart.zoom, greaterThan(whole));
    expect(atStart.zoom, lessThanOrEqualTo(kCourseJumpMaxZoom));
    expect(atStart.center.latitude, closeTo(_lat, 0.001));

    await tester.tap(_wholeCourse);
    await _settle(tester);
    expect(state.camera.zoom, closeTo(whole, 0.01));

    await _tapTag(tester, 'finish');
    await _settle(tester);
    expect(state.camera.center.latitude,
        closeTo(_lat + 1000 / _mPerDegLat, 0.001));

    await tester.tap(_wholeCourse);
    await _settle(tester);
    await tester.tap(find.byKey(const Key('park-course-legend-finish-box')));
    await _settle(tester);
    expect(state.camera.zoom, greaterThan(whole));
    expect(state.camera.center.latitude,
        closeTo(_lat + 1000 / _mPerDegLat, 0.001));

    await tester.tap(keyStart);
    await _settle(tester);
    expect(state.camera.center.latitude, closeTo(_lat, 0.001));
    await _unmount(tester);
  });

  testWidgets('a start and finish at one spot is one Start and finish tag',
      (tester) async {
    await _pump(tester, zones: (start: _gate(_lat, 0), finish: _gate(_lat, 180)));
    expect(_tag('both'), findsOneWidget);
    expect(_tag('start'), findsNothing);
    expect(_tag('finish'), findsNothing);
    expect(_named('Show the start and finish on the map'),
        findsNWidgets(2));
    final state = _mapKey.currentState!;
    final whole = state.camera.zoom;
    await _tapTag(tester, 'both');
    await _settle(tester);
    expect(state.camera.zoom, greaterThan(whole));
    await _unmount(tester);
  });

  testWidgets('with less motion asked for, a jump lands at once',
      (tester) async {
    await _pump(
      tester,
      zones: (start: _gate(_lat, 0), finish: _gate(_lat + 1000 / _mPerDegLat, 0)),
      reduceMotion: true,
    );
    final state = _mapKey.currentState!;
    final whole = state.camera.zoom;
    await _tapTag(tester, 'start');
    await tester.pump();
    expect(state.camera.zoom, greaterThan(whole));
    await _unmount(tester);
  });
}
