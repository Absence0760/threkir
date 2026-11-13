import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

const _title = 'Entraînement';

Widget _app(Widget home, {bool reduceMotion = false}) => MaterialApp(
      theme: AppTheme.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: const TextScaler.linear(2),
          disableAnimations: reduceMotion,
        ),
        child: child!,
      ),
      home: home,
    );

double _barOpacity(WidgetTester tester) => tester
    .widget<AnimatedOpacity>(find.descendant(
        of: find.byType(PageBarTitle), matching: find.byType(AnimatedOpacity)))
    .opacity;

class _Hub extends StatefulWidget {
  const _Hub({this.onAction});

  final VoidCallback? onAction;

  @override
  State<_Hub> createState() => _HubState();
}

class _HubState extends State<_Hub> with SingleTickerProviderStateMixin {
  late final TabController _controller =
      TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _tab(String name) => ListView(
        key: PageStorageKey(name),
        children: [
          for (var i = 0; i < 40; i++) ListTile(title: Text('$name row $i')),
        ],
      );

  @override
  Widget build(BuildContext context) => RootPage.tabbed(
        title: _title,
        controller: _controller,
        labels: const ['One', 'Two'],
        actions: [
          IconButton(
            key: const ValueKey('root-action'),
            tooltip: 'Bell',
            icon: const Icon(Icons.notifications_none),
            onPressed: widget.onAction,
          ),
        ],
        children: [_tab('one'), _tab('two')],
      );
}

Future<void> _phone(WidgetTester tester) async {
  tester.view.physicalSize = const Size(320, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('a hub opens on a large heading over its strip, and collapses '
      'into the bar as a tab scrolls, its action still tappable',
      (tester) async {
    await _phone(tester);
    var taps = 0;
    await tester.pumpWidget(_app(_Hub(onAction: () => taps++)));
    await tester.pump();

    final heading = find.descendant(
        of: find.byType(PageHeader), matching: find.text(_title));
    expect(heading, findsOneWidget);
    expect(tester.getSemantics(heading), matchesSemantics(isHeader: true,
        label: _title));
    expect(tester.getRect(heading).bottom,
        lessThanOrEqualTo(tester.getRect(find.byType(TabBar)).top),
        reason: 'the title sits above the strip');
    expect(_barOpacity(tester), 0);

    await tester.drag(find.text('one row 0'), const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(_barOpacity(tester), 1, reason: 'collapsed, the bar says the name');
    final bar = tester.getRect(find.byType(AppBar));
    expect(tester.getRect(find.byType(TabBar)).top,
        moreOrLessEquals(bar.bottom),
        reason: 'the strip pins under the bar');
    expect(tester.takeException(), isNull);

    final action = find.byKey(const ValueKey('root-action'));
    expect(action.hitTestable(), findsOneWidget);
    await tester.tap(action);
    expect(taps, 1);

    // The collapse belongs to the hub, not a tab: switching does not move
    // the strip, and the first tab keeps its place.
    final stripTop = tester.getRect(find.byType(TabBar)).top;
    await tester.tap(find.text('Two'));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byType(TabBar)).top, stripTop);
    await tester.tap(find.text('One'));
    await tester.pumpAndSettle();
    expect(find.text('one row 0'), findsNothing,
        reason: 'the first tab kept its scroll position');
  });

  testWidgets('the bar title is a heading too, and appears at once under '
      'reduce motion', (tester) async {
    await _phone(tester);
    await tester.pumpWidget(_app(const _Hub(), reduceMotion: true));
    await tester.pump();
    await tester.drag(find.text('one row 0'), const Offset(0, -600));
    await tester.pump();
    await tester.pump();
    final fade = tester.widget<AnimatedOpacity>(find.descendant(
        of: find.byType(PageBarTitle), matching: find.byType(AnimatedOpacity)));
    expect(fade.duration, Duration.zero);
    expect(fade.opacity, 1);
    final barTitle = find.descendant(
        of: find.byType(AppBar), matching: find.text(_title));
    expect(tester.getSemantics(barTitle),
        matchesSemantics(isHeader: true, label: _title, namesRoute: true));
  });

  testWidgets('a root with a scroll view of its own keeps its actions in '
      'the bar', (tester) async {
    await _phone(tester);
    await tester.pumpWidget(_app(RootPage(
      title: 'You',
      actions: const [
        IconButton(
          key: ValueKey('you-action'),
          onPressed: null,
          icon: Icon(Icons.more_vert),
        ),
      ],
      body: ListView(children: [
        const PageHeader(title: 'You'),
        for (var i = 0; i < 40; i++) ListTile(title: Text('row $i')),
      ]),
    )));
    await tester.pump();
    expect(_barOpacity(tester), 0);
    await tester.drag(find.text('row 3'), const Offset(0, -800));
    await tester.pumpAndSettle();
    expect(_barOpacity(tester), 1);
    expect(find.byKey(const ValueKey('you-action')).hitTestable(),
        findsOneWidget);
  });
}
