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
}
