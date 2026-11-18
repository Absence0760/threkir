import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

const _footer = Key('footer');
const _body = Key('body');
const _header = Key('header');

Widget _page({
  Widget? header,
  bool footer = true,
  Widget? drawer,
  List<Widget> actions = const [],
}) =>
    ConversationPage(
      titleSpacing: 0,
      title: const ThreadTitle(
        avatar: CircleAvatar(radius: 16),
        title: 'Alex Runner',
      ),
      actions: actions,
      drawer: drawer,
      header: header,
      body: ListView(
        key: _body,
        children: [for (var i = 0; i < 30; i++) Text('message $i')],
      ),
      footer: footer
          ? const SizedBox(
              key: _footer,
              height: 56,
              child: TextField(),
            )
          : null,
    );

void _phone(WidgetTester tester, {double navBar = 0, double keyboard = 0}) {
  tester.view.physicalSize = const Size(320, 640);
  tester.view.devicePixelRatio = 1;
  tester.view.padding = FakeViewPadding(bottom: keyboard > 0 ? 0 : navBar);
  tester.view.viewPadding = FakeViewPadding(bottom: navBar);
  tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('the footer clears a 48 dp navigation bar', (tester) async {
    _phone(tester, navBar: 48);
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: _page()));

    final footer = tester.getRect(find.byKey(_footer));
    expect(footer.bottom, lessThanOrEqualTo(640 - 48));
    expect(footer.bottom, closeTo(640 - 48, 0.5),
        reason: 'the footer sits on the bar, not floating above it');
    expect(tester.getRect(find.byKey(_body)).bottom,
        lessThanOrEqualTo(footer.top));
    expect(tester.takeException(), isNull);
  });

  testWidgets('with no footer the messages clear the navigation bar',
      (tester) async {
    _phone(tester, navBar: 48);
    await tester.pumpWidget(
        MaterialApp(theme: AppTheme.light, home: _page(footer: false)));

    expect(tester.getRect(find.byKey(_body)).bottom,
        lessThanOrEqualTo(640 - 48));
  });

  testWidgets('the footer rises above the keyboard', (tester) async {
    _phone(tester, navBar: 48, keyboard: 300);
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: _page()));

    final footer = tester.getRect(find.byKey(_footer));
    expect(footer.bottom, lessThanOrEqualTo(640 - 300));
    expect(footer.top, greaterThan(0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a tall header is capped and scrolls inside its cap, at 2x '
      'text with the keyboard up', (tester) async {
    _phone(tester, navBar: 48, keyboard: 300);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: const TextScaler.linear(2)),
        child: child!,
      ),
      home: _page(
        header: Column(
          key: _header,
          children: [for (var i = 0; i < 20; i++) Text('plan change $i')],
        ),
      ),
    ));
    expect(tester.takeException(), isNull);

    final bar = tester.getRect(find.byType(AppBar));
    final footer = tester.getRect(find.byKey(_footer));
    final available = footer.top - bar.bottom;
    final viewport = tester.getRect(find.ancestor(
        of: find.byKey(_header), matching: find.byType(SingleChildScrollView)));
    expect(viewport.height, lessThanOrEqualTo(available * 0.4 + 0.5));
    expect(tester.getRect(find.byKey(_body)).height, greaterThan(0),
        reason: 'the messages keep the rest');
    expect(footer.bottom, lessThanOrEqualTo(640 - 300));

    expect(find.text('plan change 19').hitTestable(), findsNothing);
    await tester.drag(find.text('plan change 0'), const Offset(0, -2000));
    await tester.pumpAndSettle();
    expect(find.text('plan change 19').hitTestable(), findsOneWidget,
        reason: 'the header scrolls inside its cap');
  });

  testWidgets('the drawer opens from an action, and a pushed page keeps Back',
      (tester) async {
    _phone(tester);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => _page(
              drawer: const Drawer(child: Text('history')),
              actions: [
                Builder(
                  builder: (ctx) => IconButton(
                    tooltip: 'History',
                    icon: const Icon(Icons.history),
                    onPressed: () => Scaffold.of(ctx).openDrawer(),
                  ),
                ),
              ],
            ),
          )),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byType(BackButton), findsOneWidget,
        reason: "the drawer's implied menu button must not replace Back");
    expect(find.byType(DrawerButton), findsNothing);
    expect(find.text('history'), findsNothing);

    await tester.tap(find.byTooltip('History'));
    await tester.pumpAndSettle();
    expect(find.text('history'), findsOneWidget);
  });

  testWidgets('the title keeps its whole name in a tooltip', (tester) async {
    _phone(tester);
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: _page()));

    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.byWidgetPredicate(
            (w) => w is Tooltip && w.message == 'Alex Runner'),
      ),
      findsOneWidget,
    );
  });
}
