import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

const _bar = 48.0;

Future<void> _open(WidgetTester tester, {double keyboard = 0}) async {
  tester.view.physicalSize = const Size(360, 740);
  tester.view.devicePixelRatio = 1;
  tester.view.viewPadding = const FakeViewPadding(bottom: _bar);
  tester.view.padding = const FakeViewPadding(bottom: _bar);
  tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    home: Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () => showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            useSafeArea: true,
            builder: (_) => SheetScaffold(
              title: const Text('Title'),
              body: Column(children: [
                for (var i = 0; i < 30; i++) Text('row $i'),
              ]),
              actions: FilledButton(onPressed: () {}, child: const Text('Save')),
            ),
          ),
          child: const Text('open'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the action row clears a 3-button nav bar', (tester) async {
    await _open(tester);
    final save = tester.getRect(find.widgetWithText(FilledButton, 'Save'));
    expect(save.bottom, lessThanOrEqualTo(740 - _bar));
  });

  testWidgets('with the keyboard up it clears the keyboard instead',
      (tester) async {
    await _open(tester, keyboard: 300);
    final save = tester.getRect(find.widgetWithText(FilledButton, 'Save'));
    expect(save.bottom, lessThanOrEqualTo(740 - 300));
  });

  testWidgets('a long body scrolls and the action row stays pinned',
      (tester) async {
    await _open(tester);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(find.text('row 29').hitTestable(), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Save').hitTestable(),
        findsOneWidget);
  });

  testWidgets('systemBottomInset takes the keyboard, else the nav bar',
      (tester) async {
    late double inset;
    Widget probe(EdgeInsets viewPadding, EdgeInsets viewInsets) => MediaQuery(
          data: MediaQueryData(viewPadding: viewPadding, viewInsets: viewInsets),
          child: Builder(builder: (context) {
            inset = systemBottomInset(context);
            return const SizedBox();
          }),
        );
    await tester.pumpWidget(
        probe(const EdgeInsets.only(bottom: 48), EdgeInsets.zero));
    expect(inset, 48);
    await tester.pumpWidget(probe(const EdgeInsets.only(bottom: 48),
        const EdgeInsets.only(bottom: 300)));
    expect(inset, 300);
  });

  testWidgets('a floating share sheet keeps its card clear of the nav bar',
      (tester) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    tester.view.viewPadding = const FakeViewPadding(bottom: _bar);
    tester.view.padding = const FakeViewPadding(bottom: _bar);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              useSafeArea: true,
              backgroundColor: Colors.transparent,
              showDragHandle: false,
              builder: (_) => SheetScaffold.floating(
                key: const Key('card'),
                title: const Text('Share'),
                body: const SizedBox(height: 200),
                actions:
                    FilledButton(onPressed: () {}, child: const Text('Go')),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final card = find.descendant(
        of: find.byKey(const Key('card')), matching: find.byType(Container));
    final rect = tester.getRect(card.first);
    expect(rect.left, 16);
    expect(rect.bottom, lessThanOrEqualTo(740 - _bar - 16));
    final go = tester.getRect(find.widgetWithText(FilledButton, 'Go'));
    expect(go.bottom, lessThanOrEqualTo(rect.bottom - 16));
  });

  group('SheetScaffold.expanding', () {
    const screen = Size(360, 740);

    Future<void> openExpanding(WidgetTester tester,
        {double keyboard = 0, int rows = 60}) async {
      tester.view.physicalSize = screen;
      tester.view.devicePixelRatio = 1;
      tester.view.viewPadding = const FakeViewPadding(bottom: _bar);
      tester.view.padding = FakeViewPadding(bottom: keyboard > 0 ? 0 : _bar);
      tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                useSafeArea: true,
                builder: (_) => SheetScaffold.expanding(
                  title: const Text('Pick one'),
                  pinned: const TextField(key: Key('search')),
                  slivers: [
                    SliverList.list(children: [
                      for (var i = 0; i < rows; i++)
                        SizedBox(height: 48, child: Text('row $i')),
                    ]),
                  ],
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    double sheetTop(WidgetTester tester) =>
        tester.getRect(find.byType(BottomSheet)).top;

    testWidgets('opens tall but short of the full screen', (tester) async {
      await openExpanding(tester);
      final sheet = tester.getRect(find.byType(DraggableScrollableSheet));
      expect(sheet.height, closeTo(0.7 * (740 - 48), 2),
          reason: '70% of the space under the drag handle');
      expect(find.text('Pick one'), findsOneWidget);
    });

    testWidgets('focusing the search snaps it to the full height',
        (tester) async {
      await openExpanding(tester);
      final before = sheetTop(tester);
      await tester.tap(find.byKey(const Key('search')));
      await tester.pumpAndSettle();
      expect(sheetTop(tester), lessThan(before - 100));
      final sheet = tester.getRect(find.byType(DraggableScrollableSheet));
      expect(sheet.bottom, closeTo(740, 1));
      expect(sheet.height, closeTo(740 - 48, 1));
    });

    testWidgets('a drag on the list grows the sheet before it scrolls, and '
        'the title and search stay pinned', (tester) async {
      await openExpanding(tester);
      await tester.drag(find.text('row 3'), const Offset(0, -500));
      await tester.pumpAndSettle();
      final sheet = tester.getRect(find.byType(DraggableScrollableSheet));
      expect(sheet.height, closeTo(740 - 48, 1));
      await tester.drag(find.text('row 6'), const Offset(0, -600));
      await tester.pumpAndSettle();
      expect(find.text('row 0').hitTestable(), findsNothing,
          reason: 'the list scrolled');
      expect(find.text('Pick one').hitTestable(), findsOneWidget);
      expect(find.byKey(const Key('search')).hitTestable(), findsOneWidget);
    });

    testWidgets('a scroll that skips the drag still takes the whole screen',
        (tester) async {
      await openExpanding(tester);
      final list = tester.state<ScrollableState>(find
          .descendant(
              of: find.byType(CustomScrollView),
              matching: find.byType(Scrollable))
          .first);
      list.position.jumpTo(200);
      await tester.pumpAndSettle();
      final sheet = tester.getRect(find.byType(DraggableScrollableSheet));
      expect(sheet.height, closeTo(740 - 48, 1));
    });

    testWidgets('the keyboard lifts the sheet instead of covering the list',
        (tester) async {
      await openExpanding(tester, keyboard: 300);
      final sheet = tester.getRect(find.byType(DraggableScrollableSheet));
      expect(sheet.bottom, lessThanOrEqualTo(740 - 300));
    });

    testWidgets('the end of the list clears the 3-button nav bar',
        (tester) async {
      await openExpanding(tester, rows: 20);
      await tester.drag(find.text('row 3'), const Offset(0, -500));
      await tester.pumpAndSettle();
      await tester.drag(find.text('row 6'), const Offset(0, -3000));
      await tester.pumpAndSettle();
      expect(tester.getRect(find.text('row 19')).bottom,
          lessThanOrEqualTo(740 - _bar));
    });
  });
}
