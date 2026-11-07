import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

/// StatGrid guard (issue #666 V8 / § 502). Every assertion here is a
/// *derivation* — that the column count falls out of the width a cell needs at
/// the current text scale — never an absolute fit: `flutter_test`'s font is
/// fixed-advance, so a claim that some value fits some width cannot be made in
/// CI (§ 500).
Future<List<double>> _widths(
  WidgetTester tester, {
  required int cells,
  required double width,
  double textScale = 1.0,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              child: StatGrid(
                cells: [
                  for (var i = 0; i < cells; i++)
                    StatTile.small(
                      icon: Icons.timer,
                      label: 'S$i',
                      value: '$i',
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return [
    for (var i = 0; i < cells; i++)
      tester
          .getSize(
            find
                .ancestor(of: find.text('S$i'), matching: find.byType(SizedBox))
                .first,
          )
          .width,
  ];
}

void main() {
  testWidgets('an empty grid occupies nothing', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: StatGrid(cells: [])),
      ),
    );
    expect(tester.getSize(find.byType(StatGrid)), Size.zero);
  });

  testWidgets('four cells that fit lay out exactly as a Row of Expanded did', (tester) async {
    final widths = await _widths(tester, cells: 4, width: 360);
    expect(widths, everyElement(90.0));
    // One run, so the grid is exactly as tall as a cell — no runSpacing paid.
    final cell = tester
        .getSize(
          find
              .ancestor(of: find.text('S0'), matching: find.byType(SizedBox))
              .first,
        )
        .height;
    expect(tester.getSize(find.byType(StatGrid)).height, cell);
  });

  testWidgets('eight cells reflow instead of dividing the row eight ways', (tester) async {
    final widths = await _widths(tester, cells: 8, width: 360);
    // A Row of eight Expanded gave 45 dp each here. The grid caps at four
    // columns, so each cell keeps a quarter of the row and the eight land on
    // two runs.
    expect(widths, everyElement(90.0));
    expect(widths.every((w) => w >= kStatCellMinWidth), isTrue);
  });

  testWidgets('the column count is derived from the text scale, so a cell '
      'grows by the factor the glyphs did', (tester) async {
    final at1 = await _widths(tester, cells: 8, width: 360);
    final at2 = await _widths(tester, cells: 8, width: 360, textScale: 2.0);
    expect(at2.first, at1.first * 2);
    expect(at2.first, greaterThanOrEqualTo(kStatCellMinWidth * 2));
  });

  testWidgets('a cell never falls below the floor, even one cell per row', (tester) async {
    final widths = await _widths(tester, cells: 4, width: 100);
    expect(widths, everyElement(100.0));
  });

  testWidgets('every cell is bounded, so a hero value shrinks rather than '
      'bursting the run', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: Center(
            child: SizedBox(
              width: 240,
              child: StatGrid(
                cells: [
                  StatTile.large(
                    label: 'Distance',
                    value: '1234.56',
                    unit: 'km',
                  ),
                  StatTile.large(label: 'Time', value: '104:32:11'),
                  StatTile.large(label: 'Pace', value: '12:34', unit: '/km'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('104:32:11'), findsOneWidget);
  });
  // `Infinity.floor()` throws UnsupportedError rather than degrading, so a
  // StatGrid handed an unbounded width took the whole screen down out of
  // build() instead of laying out badly. A shared widget cannot choose its
  // parents: a horizontal scroller and a Row child with no Expanded both
  // offer one.
  group('StatGrid under an unbounded width', () {
    testWidgets('lays out inside a horizontal scroller', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: StatGrid(
                cells: const [
                  StatTile.small(
                      icon: Icons.route,
                      label: 'Distance',
                      value: '42.2',
                    ),
                  StatTile.small(
                      icon: Icons.timer,
                      label: 'Time',
                      value: '104:32:11',
                    ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('104:32:11'), findsOneWidget);
    });

    testWidgets('every cell is still bounded, so a long value can scale down',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: StatGrid(
                cells: const [
                  StatTile.small(
                      icon: Icons.timer,
                      label: 'Time',
                      value: '104:32:11',
                    ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final box = tester.renderObject<RenderBox>(
        find.ancestor(
          of: find.text('104:32:11'),
          matching: find.byType(SizedBox),
        ).first,
      );
      expect(box.size.width.isFinite, isTrue,
          reason: 'an unbounded cell is what BoxFit.scaleDown cannot work in');
      expect(box.size.width, kStatCellMinWidth);
    });

    testWidgets('a Row child with no Expanded lays out', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                StatGrid(
                  cells: const [
                    StatTile.small(
                      icon: Icons.route,
                      label: 'Distance',
                      value: '42.2',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
    });
  });

  // Issue #1300 § 2: four hero cells on a 411 dp phone got ~92 dp each, every
  // value scaled to its cell's edge so neighbours touched, and the pace —
  // scaled furthest — lifted its label above the others.
  group('a hero row', () {
    const values = ['3.21', '1:02:33', '58:10', '11:23'];
    const units = ['km', null, null, '/km'];
    const labels = ['Distance', 'Time', 'Moving', 'Pace'];

    Future<void> pumpHero(
      WidgetTester tester, {
      required double screen,
      required double textScale,
      int cells = 4,
    }) async {
      tester.view.physicalSize = Size(screen, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: MediaQuery(
            data: MediaQueryData(
              size: Size(screen, 800),
              textScaler: TextScaler.linear(textScale),
            ),
            child: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(20),
                child: StatGrid(
                  cells: [
                    for (var i = 0; i < cells; i++)
                      StatTile.large(
                        label: labels[i],
                        value: values[i],
                        unit: units[i],
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    }

    /// Cells grouped into runs by the top of their label.
    List<List<int>> runs(WidgetTester tester, int cells) {
      final byTop = <double, List<int>>{};
      for (var i = 0; i < cells; i++) {
        final top = tester.getRect(find.text(labels[i])).top;
        byTop.putIfAbsent(top, () => []).add(i);
      }
      final keys = byTop.keys.toList()..sort();
      return [for (final k in keys) byTop[k]!];
    }

    for (final screen in [411.0, 360.0]) {
      for (final textScale in [1.0, 2.0]) {
        testWidgets('at ${screen.toInt()} dp, ${textScale}x: values keep a '
            'gutter and labels share one line', (tester) async {
          await pumpHero(tester, screen: screen, textScale: textScale);
          final grid = runs(tester, 4);
          expect(grid.expand((r) => r), unorderedEquals([0, 1, 2, 3]),
              reason: 'every label belongs to exactly one run');

          for (final run in grid) {
            for (var j = 1; j < run.length; j++) {
              final left = tester.getRect(find.text(values[run[j - 1]]));
              final right = tester.getRect(find.text(values[run[j]]));
              expect(right.left - left.right, greaterThanOrEqualTo(8),
                  reason: '${values[run[j - 1]]} and ${values[run[j]]} touch');
              expect(
                tester.getRect(find.text(labels[run[j]])).top,
                tester.getRect(find.text(labels[run[0]])).top,
              );
            }
          }

          final cellWidth = (screen - 40) / grid.first.length;
          expect(cellWidth,
              greaterThanOrEqualTo(kStatLargeCellMinWidth * textScale - 1),
              reason: 'a hero cell narrower than its floor');
        });
      }
    }

    testWidgets('four hero cells that do not fit reflow two by two, not '
        'three and an orphan', (tester) async {
      await pumpHero(tester, screen: 411, textScale: 1);
      expect(runs(tester, 4), [
        [0, 1],
        [2, 3],
      ]);
    });

    testWidgets('three hero cells still share a 360 dp row', (tester) async {
      await pumpHero(tester, screen: 360, textScale: 1, cells: 3);
      expect(runs(tester, 3), [
        [0, 1, 2],
      ]);
    });

    testWidgets('at 2.0x every hero cell takes its own run', (tester) async {
      await pumpHero(tester, screen: 411, textScale: 2);
      expect(runs(tester, 4), [
        [0],
        [1],
        [2],
        [3],
      ]);
    });

    testWidgets('a value scaled furthest does not lift its label',
        (tester) async {
      await pumpHero(tester, screen: 411, textScale: 1);
      final pace = tester.getRect(find.text('11:23'));
      final time = tester.getRect(find.text('1:02:33'));
      expect(time.height, isNot(pace.height),
          reason: 'the two values must scale differently for this to test '
              'anything');
      expect(tester.getRect(find.text('Moving')).top,
          tester.getRect(find.text('Pace')).top);
      expect(pace.bottom, closeTo(tester.getRect(find.text('58:10')).bottom, 1));
    });
  });

  testWidgets('a cell wrapping a tile takes the floor it is given',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 371,
              child: StatGrid(
                minCellWidth: kStatLargeCellMinWidth,
                cells: [
                  for (var i = 0; i < 4; i++)
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [StatTile.large(label: 'L$i', value: '$i')],
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.getRect(find.text('L2')).top,
        greaterThan(tester.getRect(find.text('L0')).top));
  });
}
