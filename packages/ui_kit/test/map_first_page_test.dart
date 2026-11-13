import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

const _bar = 48.0;
const _size = Size(320, 640);

/// A phone with a 3-button bar at the bottom, or in landscape a side bar at
/// the right.
Future<void> _pump(
  WidgetTester tester,
  Widget page, {
  Size size = _size,
  FakeViewPadding inset = const FakeViewPadding(bottom: _bar),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.view.viewPadding = inset;
  tester.view.padding = inset;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    home: MediaQuery.withClampedTextScaling(
      minScaleFactor: textScale,
      maxScaleFactor: textScale,
      child: page,
    ),
  ));
  await tester.pump();
}

const _map = ColoredBox(key: ValueKey('map'), color: Colors.green);

Widget _locate() => FloatingActionButton.small(
      heroTag: null,
      onPressed: () {},
      child: const Icon(Icons.my_location),
    );

void main() {
  testWidgets('with nothing below the map the controls stand on the nav bar',
      (tester) async {
    await _pump(
      tester,
      MapFirstPage(
        appBar: AppBar(title: const Text('Map')),
        map: _map,
        controls: [_locate()],
        footer: FilledButton(onPressed: () {}, child: const Text('Mode')),
        attribution: const Text('credit'),
      ),
      textScale: 2,
    );
    expect(tester.getRect(find.byKey(const ValueKey('map'))).bottom,
        _size.height, reason: 'the map runs edge to edge');
    expect(tester.getRect(find.text('credit')).bottom,
        lessThanOrEqualTo(_size.height - _bar));
    final mode = tester.getRect(find.widgetWithText(FilledButton, 'Mode'));
    final locate = tester.getRect(find.byType(FloatingActionButton));
    expect(locate.bottom, lessThanOrEqualTo(mode.top),
        reason: 'the map controls sit above the footer, never on it');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a pinned panel ends above the nav bar and the controls sit '
      'above the panel', (tester) async {
    await _pump(
      tester,
      MapFirstPage(
        appBar: AppBar(title: const Text('Map')),
        map: _map,
        controls: [_locate()],
        panel: Row(children: [
          const Expanded(child: Text('3 zones')),
          TextButton(onPressed: () {}, child: const Text('Clear all')),
        ]),
      ),
      textScale: 2,
    );
    final clear = tester.getRect(find.widgetWithText(TextButton, 'Clear all'));
    expect(clear.bottom, lessThanOrEqualTo(_size.height - _bar));
    final locate = tester.getRect(find.byType(FloatingActionButton));
    final panel = tester.getRect(find.byKey(const ValueKey('map-first-panel')));
    expect(locate.bottom, lessThanOrEqualTo(panel.top),
        reason: 'IK-3: Locate me covered Clear all');
    expect(find.widgetWithText(TextButton, 'Clear all').hitTestable(),
        findsOneWidget);
  });

  testWidgets('a panel taller than the page scrolls instead of overflowing',
      (tester) async {
    await _pump(
      tester,
      MapFirstPage(
        appBar: AppBar(title: const Text('Map')),
        map: _map,
        panel: Column(children: [
          for (var i = 0; i < 40; i++) Text('stat $i'),
        ]),
      ),
      textScale: 2,
    );
    expect(tester.takeException(), isNull);
    final panel = tester.getRect(find.byKey(const ValueKey('map-first-panel')));
    expect(panel.height, lessThanOrEqualTo(0.6 * (_size.height - 56) + 1));
    await tester.dragUntilVisible(find.text('stat 39'),
        find.byType(SingleChildScrollView), const Offset(0, -200));
    expect(tester.getRect(find.text('stat 39')).bottom,
        lessThanOrEqualTo(_size.height - _bar + 0.01));
  });

  testWidgets('a tall header and a tall panel share the page and the map '
      'keeps the rest', (tester) async {
    await _pump(
      tester,
      MapFirstPage(
        appBar: AppBar(title: const Text('Map')),
        map: _map,
        header: Column(children: [
          for (var i = 0; i < 30; i++) Text('hint $i'),
        ]),
        panel: Column(children: [
          for (var i = 0; i < 30; i++) Text('stat $i'),
        ]),
      ),
      textScale: 2,
    );
    expect(tester.takeException(), isNull);
    const page = 640 - 56.0;
    final map = tester.getRect(find.byKey(const ValueKey('map')));
    expect(map.height, greaterThanOrEqualTo(0.4 * page - 1));
    expect(
        tester.getRect(find.byKey(const ValueKey('map-first-header'))).height,
        lessThanOrEqualTo(0.3 * page + 1));
  });

  testWidgets('the sheet ends its list above the nav bar and the controls '
      'ride its top edge', (tester) async {
    await _pump(
      tester,
      MapFirstPage(
        appBar: AppBar(title: const Text('Map')),
        map: _map,
        controls: [_locate()],
        attribution: const Text('credit'),
        sheet: MapFirstSheet(
          initialSize: 0.3,
          slivers: [
            SliverList.list(children: [
              for (var i = 0; i < 30; i++)
                ListTile(title: Text('row $i'), onTap: () {}),
            ]),
          ],
        ),
      ),
    );
    final sheet = tester.getRect(find
        .descendant(
            of: find.byKey(const ValueKey('map-first-sheet')),
            matching: find.byType(Material))
        .first);
    expect(tester.getRect(find.text('credit')).bottom,
        lessThanOrEqualTo(sheet.top + 0.5),
        reason: 'the credit rides above the sheet, not under it');
    expect(tester.getRect(find.byType(FloatingActionButton)).bottom,
        lessThanOrEqualTo(sheet.top));

    // Raise the sheet and scroll to the end: the last row clears the bar.
    await tester.drag(find.text('row 0'), const Offset(0, -400));
    await tester.pumpAndSettle();
    await tester.dragUntilVisible(find.text('row 29'),
        find.byType(CustomScrollView), const Offset(0, -300));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.text('row 29')).bottom,
        lessThanOrEqualTo(_size.height - _bar));
    // Raised past the ride limit, the controls step aside.
    expect(find.byType(FloatingActionButton).hitTestable(), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('with semantics on, the sheet lays out without a semantics '
      'assertion', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pump(
      tester,
      MapFirstPage(
        appBar: AppBar(title: const Text('Map')),
        map: _map,
        controls: [_locate()],
        sheet: MapFirstSheet(
          slivers: [
            SliverList.list(children: [
              for (var i = 0; i < 5; i++) ListTile(title: Text('row $i')),
            ]),
          ],
        ),
      ),
    );
    await tester.drag(find.text('row 0'), const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('hosted, it draws no Scaffold and clears what the host covers',
      (tester) async {
    await _pump(
      tester,
      Scaffold(
        body: MapFirstPage(
          map: _map,
          bottomClearance: 28,
          controls: [_locate()],
          attribution: const Text('credit'),
        ),
      ),
      inset: FakeViewPadding.zero,
    );
    expect(find.byType(Scaffold), findsOneWidget);
    expect(tester.getRect(find.text('credit')).bottom,
        lessThanOrEqualTo(_size.height - 28));
  });

  testWidgets('landscape: everything but the map clears a side nav bar',
      (tester) async {
    const landscape = Size(640, 320);
    await _pump(
      tester,
      MapFirstPage(
        appBar: AppBar(title: const Text('Map')),
        map: _map,
        header: const Text('header', textAlign: TextAlign.end),
        overlays: const [
          Align(alignment: Alignment.centerRight, child: Text('pill')),
        ],
        controls: [_locate()],
        panel: Row(children: [
          const Expanded(child: Text('3 zones')),
          TextButton(onPressed: () {}, child: const Text('Clear all')),
        ]),
      ),
      size: landscape,
      inset: const FakeViewPadding(right: _bar),
    );
    final edge = landscape.width - _bar;
    expect(tester.getRect(find.byKey(const ValueKey('map'))).right,
        landscape.width, reason: 'the map stays full-bleed');
    for (final f in [
      find.byType(FloatingActionButton),
      find.widgetWithText(TextButton, 'Clear all'),
      find.text('pill'),
      find.text('header'),
    ]) {
      expect(tester.getRect(f).right, lessThanOrEqualTo(edge));
    }
  });

  testWidgets('landscape: the sheet content clears a side nav bar',
      (tester) async {
    const landscape = Size(640, 320);
    await _pump(
      tester,
      MapFirstPage(
        appBar: AppBar(title: const Text('Map')),
        map: _map,
        sheet: MapFirstSheet(
          initialSize: 0.5,
          slivers: [
            SliverToBoxAdapter(
              child: Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                    onPressed: () {}, icon: const Icon(Icons.star)),
              ),
            ),
          ],
        ),
      ),
      size: landscape,
      inset: const FakeViewPadding(left: _bar),
    );
    expect(tester.getRect(find.byType(IconButton)).left,
        greaterThanOrEqualTo(_bar));
  });
}
