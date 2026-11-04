import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  bool reduceMotion = false,
}) =>
    tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(disableAnimations: reduceMotion),
        child: MaterialApp(home: Scaffold(body: child)),
      ),
    );

void main() {
  testWidgets('renders one placeholder row per requested row', (tester) async {
    await _pump(tester, const ListSkeleton(label: 'Loading…', rows: 4));
    // Leading disc + two bars per row.
    expect(find.byType(FractionallySizedBox), findsNWidgets(8));
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('announces itself to a screen reader', (tester) async {
    await _pump(tester, const ListSkeleton(label: 'Loading clubs…', rows: 2));
    expect(find.bySemanticsLabel('Loading clubs…'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('drops the leading disc when the list has no leading column',
      (tester) async {
    await _pump(
      tester,
      const ListSkeleton(label: 'Loading…', rows: 3, hasLeading: false),
    );
    expect(find.byType(FractionallySizedBox), findsNWidgets(6));
    // Only the bars remain — no circular leading block.
    final circles = tester
        .widgetList<Container>(find.byType(Container))
        .where((c) => (c.decoration as BoxDecoration?)?.shape == BoxShape.circle);
    expect(circles, isEmpty);
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('holds a static pose under reduced motion', (tester) async {
    await _pump(
      tester,
      const ListSkeleton(label: 'Loading…', rows: 2),
      reduceMotion: true,
    );
    Color barColor() => (tester
            .widget<Container>(find
                .descendant(
                  of: find.byType(FractionallySizedBox),
                  matching: find.byType(Container),
                )
                .first)
            .decoration as BoxDecoration)
        .color!;
    final first = barColor();
    await tester.pump(const Duration(milliseconds: 450));
    expect(barColor(), first);
  });

  testWidgets('does not scroll — it stands in for content, it is not content',
      (tester) async {
    await _pump(tester, const ListSkeleton(label: 'Loading…', rows: 20));
    final list = tester.widget<ListView>(find.byType(ListView));
    expect(list.physics, isA<NeverScrollableScrollPhysics>());
    await tester.pump(const Duration(milliseconds: 400));
  });

  group('ListSkeleton.section', () {
    testWidgets('renders inside an unbounded host, where the viewport variant '
        'cannot', (tester) async {
      await _pump(
        tester,
        ListView(
          children: const [
            SizedBox(height: 40),
            ListSkeleton.section(label: 'Loading comments…', rows: 2),
          ],
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.bySemanticsLabel('Loading comments…'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(ListSkeleton),
          matching: find.byType(ListView),
        ),
        findsNothing,
      );
      await tester.pump(const Duration(milliseconds: 400));
    });

    testWidgets('takes exactly the height its rows and gaps need',
        (tester) async {
      const rows = 3;
      const rowHeight = 48.0;
      const gap = 10.0;
      const vertical = 8.0;
      await _pump(
        tester,
        ListView(
          children: const [
            ListSkeleton.section(
              label: 'Loading…',
              rows: rows,
              rowHeight: rowHeight,
            ),
          ],
        ),
      );
      expect(
        tester.getSize(find.byType(ListSkeleton)).height,
        rows * rowHeight + (rows - 1) * gap + 2 * vertical,
      );
      await tester.pump(const Duration(milliseconds: 400));
    });

    testWidgets('keeps the pulse and the reduced-motion pose', (tester) async {
      await _pump(
        tester,
        ListView(
          children: const [
            ListSkeleton.section(label: 'Loading…', rows: 2),
          ],
        ),
        reduceMotion: true,
      );
      Color barColor() => (tester
              .widget<Container>(find
                  .descendant(
                    of: find.byType(FractionallySizedBox),
                    matching: find.byType(Container),
                  )
                  .first)
              .decoration as BoxDecoration)
          .color!;
      final first = barColor();
      await tester.pump(const Duration(milliseconds: 450));
      expect(barColor(), first);
    });
  });

  group('SkeletonBlock', () {
    Color blockColor(WidgetTester tester) => (tester
            .widget<Container>(find.descendant(
              of: find.byType(SkeletonBlock),
              matching: find.byType(Container),
            ))
            .decoration as BoxDecoration)
        .color!;

    testWidgets('occupies the size it stands in for', (tester) async {
      await _pump(
        tester,
        const Column(children: [SkeletonBlock(height: 220)]),
      );
      final size = tester.getSize(find.byType(SkeletonBlock));
      expect(size.height, 220);
      expect(size.width, 800, reason: 'fills the width when none is given');
      await tester.pump(const Duration(milliseconds: 400));
    });

    testWidgets('is silent unless it carries the label', (tester) async {
      await _pump(
        tester,
        const Column(children: [
          SkeletonBlock(height: 40),
          SkeletonBlock(height: 40, label: 'Chargement…'),
        ]),
      );
      expect(find.bySemanticsLabel('Chargement…'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 400));
    });

    testWidgets('pulses on the same cycle as the rows', (tester) async {
      await _pump(
        tester,
        const Column(children: [SkeletonBlock(height: 40)]),
      );
      final first = blockColor(tester);
      await tester.pump(const Duration(milliseconds: 450));
      expect(blockColor(tester), isNot(first));
    });

    testWidgets('holds the same static pose as the rows under reduced motion',
        (tester) async {
      await _pump(
        tester,
        const Column(children: [
          SkeletonBlock(height: 40),
          ListSkeleton.section(label: 'Loading…', rows: 1),
        ]),
        reduceMotion: true,
      );
      final first = blockColor(tester);
      final bar = (tester
              .widget<Container>(find
                  .descendant(
                    of: find.byType(FractionallySizedBox),
                    matching: find.byType(Container),
                  )
                  .first)
              .decoration as BoxDecoration)
          .color!;
      expect(first, bar, reason: 'one surface, one pose');
      await tester.pump(const Duration(milliseconds: 450));
      expect(blockColor(tester), first);
    });
  });
}
