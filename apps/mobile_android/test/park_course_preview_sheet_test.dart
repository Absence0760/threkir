import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_android/l10n/gen/app_localizations.dart';
import 'package:mobile_android/widgets/park_course_map.dart';
import 'package:mobile_android/widgets/park_course_preview_sheet.dart';

ParkCourseListing _course({int? laps, Object? routeGuide}) => ParkCourseListing(
  course: ParkCourseRow(
    id: 'c10',
    parkId: 'p1',
    globalSegmentId: 's-c10',
    slug: 'swift-creek-10k',
    courseShape: 'loop',
    status: 'open',
    geometrySource: 'osm',
    checkpoints: const [],
    laps: laps,
    routeGuide: routeGuide,
    createdAt: DateTime.parse('2026-01-01T00:00:00Z'),
  ),
  segment: GlobalSegmentRow(
    id: 's-c10',
    name: 'Swift Creek Loop, 10 km (2 laps)',
    waypoints: const [
      {'lat': 37.38, 'lng': -77.58},
      {'lat': 37.39, 'lng': -77.58},
      {'lat': 37.39, 'lng': -77.57},
      {'lat': 37.38, 'lng': -77.58},
    ],
    distanceM: 10000,
    elevationM: 156,
    surface: 'trail',
    isActive: true,
    createdAt: DateTime.parse('2026-01-01T00:00:00Z'),
  ),
);

const _guide = {
  'version': 1,
  'lang': 'en',
  'getting_there': 'Park at the boat-ramp lot.',
  'steps': [
    {'kind': 'start', 'at_m': 0, 'name': 'Lake Trail'},
    {'kind': 'finish', 'at_m': 10000},
  ],
};

Future<void> _open(
  WidgetTester tester,
  ParkCourseListing course,
  VoidCallback onOpen,
) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showParkCoursePreviewSheet(
              context,
              course: course,
              onOpen: onOpen,
            ),
            child: const Text('preview'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('preview'));
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// The map's tile layer keeps timers alive; unmount it and let them run out.
Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 5));
}

void main() {
  setUpAll(() {
    dotenv.loadFromString(envString: '', isOptional: true);
  });

  testWidgets('the sheet previews the course: its map, its facts once, where '
      'to start, and Open course', (tester) async {
    var opened = 0;
    await _open(tester, _course(laps: 2, routeGuide: _guide), () => opened++);

    expect(find.byKey(const Key('park-course-preview')), findsOneWidget);
    expect(find.text('Swift Creek Loop'), findsOneWidget);
    expect(find.byType(ParkCourseMap), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('park-preview-distance'))).data,
      '10 km',
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('park-preview-laps'))).data,
      '2',
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('park-preview-shape'))).data,
      'Loop',
    );
    expect(find.byKey(const Key('park-preview-climb')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('park-preview-start'))).data,
      'Park at the boat-ramp lot.',
    );

    await tester.tap(find.byKey(const Key('park-preview-open')));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(opened, 1);
    expect(find.byKey(const Key('park-course-preview')), findsNothing);
    await _unmount(tester);
  });

  testWidgets('without a getting-there note the guide\'s first line says '
      'where to start; one lap shows no laps', (tester) async {
    final guide = Map<String, Object>.of(_guide)..remove('getting_there');
    await _open(tester, _course(routeGuide: guide), () {});
    expect(
      tester.widget<Text>(find.byKey(const Key('park-preview-start'))).data,
      'Start on Lake Trail.',
    );
    expect(find.byKey(const Key('park-preview-laps')), findsNothing);
    await _unmount(tester);
  });

  testWidgets('without a guide there is no start line, and Close dismisses '
      'without opening', (tester) async {
    var opened = 0;
    await _open(tester, _course(), () => opened++);
    expect(find.byKey(const Key('park-preview-start')), findsNothing);
    await tester.tap(find.byKey(const Key('park-preview-close')));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byKey(const Key('park-course-preview')), findsNothing);
    expect(opened, 0);
    await _unmount(tester);
  });
}
