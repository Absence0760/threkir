import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

const _title = 'Entraînement';
const _statusBar = 24.0;

Widget _app(Widget home, {bool reduceMotion = false, double scale = 2}) =>
    MaterialApp(
      theme: AppTheme.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(scale),
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

final _heading = find.descendant(
    of: find.byType(PageHeader), matching: find.text(_title));

class _Hub extends StatefulWidget {
  const _Hub({this.onAction, this.initialIndex = 0});

  final VoidCallback? onAction;
  final int initialIndex;

  @override
  State<_Hub> createState() => _HubState();
}

class _HubState extends State<_Hub> with SingleTickerProviderStateMixin {
  late final TabController _controller = TabController(
      length: 2, vsync: this, initialIndex: widget.initialIndex);

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

Widget _plain({List<Widget> actions = const []}) => RootPage(
      title: _title,
      actions: actions,
      body: ListView(children: [
        for (var i = 0; i < 40; i++) ListTile(title: Text('row $i')),
      ]),
    );

Future<void> _phone(WidgetTester tester) async {
  tester.view.physicalSize = const Size(320, 640);
  tester.view.devicePixelRatio = 1;
  tester.view.padding = const FakeViewPadding(top: _statusBar);
  tester.view.viewPadding = const FakeViewPadding(top: _statusBar);
  addTearDown(tester.view.reset);
}

/// The title row at rest: no empty toolbar row above the heading, the
/// actions on the same row and centred on it, one copy of them, no bar.
void _expectAtRest(WidgetTester tester, Finder action) {
  final heading = tester.getRect(_heading);
  final header = tester.getRect(find.byType(PageHeader));
  expect(header.top, moreOrLessEquals(_statusBar),
      reason: 'the header starts at the status bar, with no bar row above');
  expect(heading.top - _statusBar,
      lessThanOrEqualTo(AppSpace.md + 24 + 0.5),
      reason: 'only the header padding (and centring on a 48 dp action) '
          'sits between the status bar and the title');
  expect(action, findsOneWidget);
  expect(tester.getCenter(action).dy, moreOrLessEquals(heading.center.dy),
      reason: 'the actions share the title row and its vertical centre');
  expect(tester.getRect(action).top, greaterThanOrEqualTo(_statusBar));
  expect(_barOpacity(tester), 0);
  expect(find.byType(AppBar).hitTestable(), findsNothing,
      reason: 'no compact bar at rest');
  expect(tester.getSemantics(_heading),
      matchesSemantics(isHeader: true, label: _title));
}

/// How many semantics nodes say [name], as a label or a tooltip.
int _semanticsNamed(WidgetTester tester, String name) {
  var count = 0;
  bool visit(SemanticsNode node) {
    if (node.label == name || node.tooltip == name) count++;
    node.visitChildren(visit);
    return true;
  }

  visit(tester.binding.pipelineOwner.semanticsOwner!.rootSemanticsNode!);
  return count;
}

void main() {
  testWidgets('a hub opens on its title row under the status bar, the strip '
      'right under it, and collapses into a compact bar with its action',
      (tester) async {
    await _phone(tester);
    final semantics = tester.ensureSemantics();
    var taps = 0;
    await tester.pumpWidget(_app(_Hub(onAction: () => taps++)));
    await tester.pump();

    final action = find.byKey(const ValueKey('root-action'));
    _expectAtRest(tester, action);
    expect(tester.getRect(find.byType(TabBar)).top,
        moreOrLessEquals(tester.getRect(find.byType(PageHeader)).bottom),
        reason: 'the strip follows the title row directly');
    expect(_semanticsNamed(tester, 'Bell'), 1);
    expect(_semanticsNamed(tester, _title), 1,
        reason: 'at rest the heading says the name and the bar is silent');

    await tester.drag(find.text('one row 0'), const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(_barOpacity(tester), 1, reason: 'collapsed, the bar says the name');
    final bar = tester.getRect(find.byType(AppBar));
    expect(bar.top, moreOrLessEquals(_statusBar));
    expect(tester.getRect(find.byType(TabBar)).top,
        moreOrLessEquals(bar.bottom),
        reason: 'the strip pins under the bar');
    expect(action.hitTestable(), findsOneWidget);
    expect(tester.getCenter(action).dy, moreOrLessEquals(bar.center.dy),
        reason: 'the action sits in the compact bar');
    expect(_semanticsNamed(tester, 'Bell'), 1,
        reason: 'one copy of the action, never two');
    expect(_semanticsNamed(tester, _title), 1,
        reason: 'the name is said once: the bar, the heading gone under it');
    expect(tester.takeException(), isNull);

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
    semantics.dispose();
  });

  testWidgets('the content moves with the finger as the header collapses: '
      'nothing jumps when the bar appears', (tester) async {
    await _phone(tester);
    await tester.pumpWidget(_app(const _Hub()));
    await tester.pump();

    final gesture =
        await tester.startGesture(tester.getCenter(find.byType(TabBarView)));
    await gesture.moveBy(const Offset(0, -30));
    await tester.pump();
    var strip = tester.getRect(find.byType(TabBar)).top;
    var row = tester.getRect(find.text('one row 0')).top;
    var sawBar = false;
    for (var i = 0; i < 60; i++) {
      await gesture.moveBy(const Offset(0, -4));
      await tester.pump();
      await tester.pump();
      final nextStrip = tester.getRect(find.byType(TabBar)).top;
      final nextRow = tester.getRect(find.text('one row 0')).top;
      expect(row - nextRow, moreOrLessEquals(4),
          reason: 'step $i: the row moves with the finger');
      expect(strip - nextStrip, inInclusiveRange(-0.01, 4.01),
          reason: 'step $i: the strip only ever rises, never jumps');
      strip = nextStrip;
      row = nextRow;
      sawBar = sawBar || _barOpacity(tester) == 1;
    }
    await gesture.up();
    expect(sawBar, isTrue, reason: 'the walk crossed the collapse');
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

  testWidgets('a root with a scroll view of its own opens on its title row '
      'and keeps its action in reach collapsed', (tester) async {
    await _phone(tester);
    await tester.pumpWidget(_app(_plain(actions: const [
      IconButton(
        key: ValueKey('you-action'),
        onPressed: null,
        icon: Icon(Icons.more_vert),
      ),
    ])));
    await tester.pump();
    final action = find.byKey(const ValueKey('you-action'));
    _expectAtRest(tester, action);
    expect(
        tester
            .getRect(find.ancestor(
                of: find.text('row 0'), matching: find.byType(ListTile)))
            .top,
        moreOrLessEquals(tester.getRect(find.byType(PageHeader)).bottom),
        reason: 'the body follows the title row directly');

    await tester.drag(find.text('row 3'), const Offset(0, -800));
    await tester.pumpAndSettle();
    expect(_barOpacity(tester), 1);
    expect(action.hitTestable(), findsOneWidget);
    expect(tester.getCenter(action).dy,
        moreOrLessEquals(tester.getRect(find.byType(AppBar)).center.dy));
  });

  testWidgets('a root without actions puts its title right under the status '
      'bar', (tester) async {
    await _phone(tester);
    await tester.pumpWidget(_app(_plain(), scale: 1));
    await tester.pump();
    expect(tester.getRect(_heading).top,
        moreOrLessEquals(_statusBar + AppSpace.md));
    expect(find.byType(AppBar).hitTestable(), findsNothing);
  });

  testWidgets('right to left, the actions lead the title row',
      (tester) async {
    await _phone(tester);
    await tester.pumpWidget(_app(Directionality(
      textDirection: TextDirection.rtl,
      child: _plain(actions: const [
        IconButton(
          key: ValueKey('rtl-action'),
          onPressed: null,
          icon: Icon(Icons.more_vert),
        ),
      ]),
    )));
    await tester.pump();
    final action = tester.getRect(find.byKey(const ValueKey('rtl-action')));
    expect(action.left, 0);
    expect(tester.getRect(_heading).left, greaterThanOrEqualTo(action.right));
  });

  testWidgets('the status bar keeps the colour of what is under it',
      (tester) async {
    await _phone(tester);
    await tester.pumpWidget(_app(const _Hub(), reduceMotion: true));
    await tester.pump();
    Color statusColor() {
      final box = find.byWidgetPredicate((w) =>
          w is AnimatedContainer &&
          w.constraints?.maxHeight == _statusBar);
      return (tester.widget<AnimatedContainer>(box).decoration!
              as BoxDecoration)
          .color!;
    }

    final theme = AppTheme.light.appBarTheme;
    expect(statusColor(),
        WidgetStateProperty.resolveAs(theme.backgroundColor, <WidgetState>{}));
    await tester.drag(find.text('one row 0'), const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(statusColor(),
        WidgetStateProperty.resolveAs(
            theme.backgroundColor, {WidgetState.scrolledUnder}));
  });

  testWidgets('the pinned header scope ends where the strip ends',
      (tester) async {
    await _phone(tester);
    late BuildContext tabContext;
    await tester.pumpWidget(_app(DefaultTabController(
      length: 1,
      child: Builder(
        builder: (context) => RootPage.tabbed(
          title: _title,
          controller: DefaultTabController.of(context),
          labels: const ['One'],
          children: [
            Builder(builder: (context) {
              tabContext = context;
              return const SizedBox();
            }),
          ],
        ),
      ),
    )));
    await tester.pump();
    final key = PinnedHeaderScope.headerKeyOf(tabContext)!;
    final box = key.currentContext!.findRenderObject()! as RenderBox;
    expect(box.localToGlobal(Offset(0, box.size.height)).dy,
        moreOrLessEquals(tester.getRect(find.byType(TabBar)).bottom));
  });

  testWidgets('a hub opens on the tab its controller names', (tester) async {
    // In the app shell the strip's pager and the header's scroll shared a
    // PageStorage identifier, and the pager restored the header's 0.0 as its
    // page; home_screen_test's Log lift / Log food cases pin that in the
    // shell, where the stored offset exists.
    await _phone(tester);
    await tester.pumpWidget(_app(const _Hub(initialIndex: 1)));
    await tester.pump();
    expect(find.text('two row 0'), findsOneWidget);
    expect(find.text('one row 0'), findsNothing);
  });
}
