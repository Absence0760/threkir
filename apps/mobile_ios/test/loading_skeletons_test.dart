import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart' show ListSkeleton, SkeletonBlock;

import '../lib/detail_map_height.dart';
import '../lib/widgets/loading_skeletons.dart';

Future<void> _pump(WidgetTester tester, Widget body, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(home: Scaffold(appBar: AppBar(), body: body)),
  );
}

void main() {
  const sizes = [Size(360, 800), Size(320, 480), Size(800, 360)];

  for (final size in sizes) {
    testWidgets('every composition lays out at $size', (tester) async {
      for (final body in const <Widget>[
        MapDetailSkeleton(label: 'Loading…'),
        TabbedDetailSkeleton(label: 'Loading…'),
        SectionedDetailSkeleton(
          label: 'Loading…',
          statCells: 3,
          hasAction: true,
        ),
      ]) {
        await _pump(tester, body, size);
        expect(tester.takeException(), isNull, reason: '$body at $size');
        await tester.pump(const Duration(milliseconds: 400));
      }
    });
  }

  testWidgets('the map block takes the height the loaded map will',
      (tester) async {
    await _pump(
      tester,
      const MapDetailSkeleton(label: 'Loading…'),
      const Size(360, 800),
    );
    final body = tester.getSize(find.byType(MapDetailSkeleton));
    final map = tester.getSize(find.byType(SkeletonBlock).first);
    expect(map.height, detailMapHeight(body.height));
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('a composition announces once', (tester) async {
    await _pump(
      tester,
      const SectionedDetailSkeleton(label: 'Chargement…', statCells: 3),
      const Size(360, 800),
    );
    expect(find.bySemanticsLabel('Chargement…'), findsOneWidget);
    expect(find.byType(ListSkeleton), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('the tabbed composition mirrors the profile load: a header band '
      'over the first tab\'s rows', (tester) async {
    await _pump(
      tester,
      const TabbedDetailSkeleton(label: 'Loading…'),
      const Size(360, 800),
    );
    expect(find.byType(ListSkeleton), findsNWidgets(2));
    expect(find.byType(Divider), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 400));
  });
}
