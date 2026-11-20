import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

/// A two-tab hub shaped like the app's: one strip, a TabBarView of scoped
/// bodies, the active tab's action as the hub's FAB and its menu as the
/// hub's ⋮.
class _Hub extends StatefulWidget {
  const _Hub({required this.bodies});

  final List<Widget> bodies;

  @override
  State<_Hub> createState() => _HubState();
}

class _HubState extends State<_Hub> with SingleTickerProviderStateMixin {
  late final TabController _tabs =
      TabController(length: widget.bodies.length, vsync: this)
        ..addListener(() => setState(() {}));
  final _actions = HubPrimaryActions();

  /// What a hub's host does on Back: the active tab's body first.
  bool consumeBack() => _actions.consumeBack(_tabs.index);

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          key: const Key('hub-bar'),
          actions: [HubMenu(actions: _actions, tab: _tabs.index)],
          bottom: TabBar(
            controller: _tabs,
            tabs: [for (var i = 0; i < widget.bodies.length; i++) Tab(text: 'tab $i')],
          ),
        ),
        body: TabBarView(
          controller: _tabs,
          children: [
            for (var i = 0; i < widget.bodies.length; i++)
              HubTabScope(tab: i, actions: _actions, child: widget.bodies[i]),
          ],
        ),
        floatingActionButton: HubFab(actions: _actions, tab: _tabs.index),
      );
}

void main() {
  testWidgets('on its own it is a pushed page: titled app bar, actions, FAB',
      (tester) async {
    var pressed = 0;
    await tester.pumpWidget(MaterialApp(
      home: HubTabBody(
        title: 'Plans',
        actions: [IconButton(icon: const Icon(Icons.sort), tooltip: 'Sort', onPressed: () {})],
        primary: PrimaryAction(
            label: 'New plan', icon: Icons.add, onPressed: () => pressed++),
        body: const Text('content'),
      ),
    ));
    expect(find.widgetWithText(AppBar, 'Plans'), findsOneWidget);
    expect(find.byTooltip('Sort'), findsOneWidget);
    await tester.tap(find.widgetWithText(FloatingActionButton, 'New plan'));
    expect(pressed, 1);
  });

  testWidgets('in a hub it draws no app bar or title, and the hub shows the '
      'active tab\'s action as its one FAB', (tester) async {
    var first = 0;
    await tester.pumpWidget(MaterialApp(
      home: _Hub(bodies: [
        HubTabBody(
          title: 'Runs',
          actions: [IconButton(icon: const Icon(Icons.sort), tooltip: 'Sort', onPressed: () {})],
          primary: PrimaryAction(
              label: 'Add past run', icon: Icons.add, onPressed: () => first++),
          body: const Text('runs'),
        ),
        const HubTabBody(title: 'Segments', body: Text('segments')),
      ]),
    ));
    await tester.pump();
    expect(find.text('Runs'), findsNothing);
    expect(find.byType(AppBar), findsOneWidget, reason: 'only the hub\'s');
    expect(find.byTooltip('Sort'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsOneWidget);
    await tester.tap(find.text('Add past run'));
    expect(first, 1);

    await tester.tap(find.text('tab 1'));
    await tester.pumpAndSettle();
    expect(find.text('segments'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing,
        reason: 'a tab with no primary action shows no FAB');
  });

  testWidgets('the FAB calls the body\'s newest callback', (tester) async {
    var which = '';
    Widget body(String tag) => HubTabBody(
          title: 't',
          primary: PrimaryAction(
              label: 'Go', icon: Icons.add, onPressed: () => which = tag),
          body: const SizedBox(),
        );
    final key = GlobalKey<_SwapState>();
    await tester.pumpWidget(MaterialApp(
      home: _Hub(bodies: [_Swap(key: key, a: body('old'), b: body('new'))]),
    ));
    await tester.pump();
    key.currentState!.swap();
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('Go'));
    expect(which, 'new');
  });

  testWidgets('selecting replaces the controls and hides the FAB',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: _Hub(bodies: [
        HubTabBody(
          title: 'Runs',
          filters: const Text('controls'),
          primary:
              PrimaryAction(label: 'Add', icon: Icons.add, onPressed: () {}),
          selection: HubSelection(
              title: '2 selected', onClose: () {}, closeTooltip: 'Cancel'),
          body: const SizedBox(),
        ),
      ]),
    ));
    await tester.pump();
    expect(find.text('2 selected'), findsOneWidget);
    expect(find.byTooltip('Cancel'), findsOneWidget);
    expect(find.text('controls'), findsNothing);
    expect(find.byType(FloatingActionButton), findsNothing);
  });

  testWidgets('turning refresh off keeps the state under the body',
      (tester) async {
    final key = GlobalKey<_SwapState>();
    Widget host(bool refreshable) => HubTabBody(
          title: 't',
          onRefresh: refreshable ? () async {} : null,
          body: _Swap(key: key, a: const Text('a'), b: const Text('b')),
        );
    await tester.pumpWidget(MaterialApp(home: host(true)));
    key.currentState!.swap();
    await tester.pump();
    await tester.pumpWidget(MaterialApp(home: host(false)));
    expect(find.text('b'), findsOneWidget, reason: 'the body was remounted');
  });

  testWidgets('it owns pull-to-refresh', (tester) async {
    var refreshed = 0;
    await tester.pumpWidget(MaterialApp(
      home: _Hub(bodies: [
        HubTabBody(
          title: 'Routes',
          onRefresh: () async => refreshed++,
          body: ListView(children: const [SizedBox(height: 2000, child: Text('row'))]),
        ),
      ]),
    ));
    await tester.pump();
    await tester.fling(find.byType(ListView), const Offset(0, 300), 1000);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(refreshed, 1);
  });

  // Issue #1374 NS-2 / NS-3: Back in select mode cleared the selection and
  // also left the tab, and Routes' selection ignored Back altogether.
  group('Back', () {
    Widget selecting(String title, VoidCallback onClose) => HubTabBody(
          title: title,
          body: ListView(children: [Text('$title row')]),
          selection: HubSelection(
            title: '1 selected',
            closeTooltip: 'Close',
            onClose: onClose,
          ),
        );

    testWidgets('in a hub, Back goes to the active tab\'s selection only',
        (tester) async {
      var closed0 = 0;
      var closed1 = 0;
      await tester.pumpWidget(MaterialApp(
        home: _Hub(bodies: [
          selecting('zero', () => closed0++),
          selecting('one', () => closed1++),
        ]),
      ));
      final hub = tester.state<_HubState>(find.byType(_Hub));
      expect(hub.consumeBack(), isTrue);
      expect((closed0, closed1), (1, 0));
    });

    testWidgets('a tab with nothing selected leaves Back to the host',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: _Hub(bodies: [
          const HubTabBody(title: 'zero', body: SizedBox()),
        ]),
      ));
      expect(tester.state<_HubState>(find.byType(_Hub)).consumeBack(), isFalse);
    });

    testWidgets('a selection that ends withdraws its handler', (tester) async {
      Widget hub(bool selected) => MaterialApp(
            home: _Hub(bodies: [
              selected
                  ? selecting('zero', () {})
                  : const HubTabBody(title: 'zero', body: SizedBox()),
            ]),
          );
      await tester.pumpWidget(hub(true));
      await tester.pumpWidget(hub(false));
      expect(tester.state<_HubState>(find.byType(_Hub)).consumeBack(), isFalse);
    });

    testWidgets('pushed on its own, Back closes the selection, not the page',
        (tester) async {
      var closed = 0;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => selecting('pushed', () => closed++))),
            child: const Text('open'),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(closed, 1);
      expect(find.text('pushed row'), findsOneWidget);
    });
  });

  testWidgets('the FAB shows its icon only while the list scrolls down, and '
      'its label again on the way up or at rest at the end', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: _Hub(bodies: [
        HubTabBody(
          title: 'Routes',
          primary:
              PrimaryAction(label: 'Build', icon: Icons.add, onPressed: () {}),
          body: ListView(children: [
            for (var i = 0; i < 40; i++) SizedBox(height: 60, child: Text('row $i')),
          ]),
        ),
      ]),
    ));
    await tester.pump();
    final fab = find.byType(FloatingActionButton);
    expect(find.descendant(of: fab, matching: find.text('Build')), findsOneWidget);

    final gesture = await tester.startGesture(const Offset(200, 400));
    await gesture.moveBy(const Offset(0, -200));
    await tester.pump();
    expect(find.descendant(of: fab, matching: find.text('Build')), findsNothing,
        reason: 'collapsed to its icon while the list moves down');
    expect(find.byTooltip('Build'), findsOneWidget,
        reason: 'the label becomes the tooltip, so the button keeps its name');
    await gesture.moveBy(const Offset(0, 80));
    await tester.pump();
    expect(find.descendant(of: fab, matching: find.text('Build')), findsOneWidget,
        reason: 'scrolling back up brings the label back');
    await gesture.up();
    await tester.pumpAndSettle();

    await tester.fling(find.byType(ListView), const Offset(0, -3000), 3000);
    await tester.pumpAndSettle();
    expect(find.descendant(of: fab, matching: find.text('Build')), findsOneWidget,
        reason: 'at rest at the end the list has scrolled clear of it');
  });

  group('Menu', () {
    final menuButton = find.byKey(const Key('hub-menu'));
    HubMenuItem item(String label, VoidCallback onSelected) => HubMenuItem(
          label: label,
          icon: Icons.add,
          onSelected: onSelected,
          itemKey: Key('item-$label'),
        );

    testWidgets('the hub shows the active tab\'s menu in its bar, and none on '
        'a tab without one', (tester) async {
      var added = 0;
      await tester.pumpWidget(MaterialApp(
        home: _Hub(bodies: [
          HubTabBody(
            title: 'Runs',
            menu: [item('Add past run', () => added++)],
            body: const Text('runs'),
          ),
          const HubTabBody(title: 'Plans', body: Text('plans')),
        ]),
      ));
      await tester.pump();
      expect(
        find.descendant(
            of: find.byKey(const Key('hub-bar')), matching: menuButton),
        findsOneWidget,
      );
      expect(find.byType(FloatingActionButton), findsNothing,
          reason: 'a menu entry is not a primary action');
      expect(find.byTooltip('Show menu'), findsOneWidget);

      await tester.tap(menuButton);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('item-Add past run')));
      await tester.pumpAndSettle();
      expect(added, 1);

      await tester.tap(find.text('tab 1'));
      await tester.pumpAndSettle();
      expect(find.text('plans'), findsOneWidget);
      expect(menuButton, findsNothing);

      await tester.tap(find.text('tab 0'));
      await tester.pumpAndSettle();
      expect(menuButton, findsOneWidget);
    });

    testWidgets('a hub can name its ⋮', (tester) async {
      final actions = HubPrimaryActions()
        ..publishMenu(0, [item('Import', () {})]);
      addTearDown(actions.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          appBar: AppBar(
              actions: [HubMenu(actions: actions, tab: 0, tooltip: 'More')]),
        ),
      ));
      expect(find.byTooltip('More'), findsOneWidget);
    });

    testWidgets('selecting hides the menu, and closing the selection brings '
        'it back', (tester) async {
      final key = GlobalKey<_SelectableState>();
      await tester.pumpWidget(MaterialApp(
        home: _Hub(bodies: [
          _Selectable(key: key, menu: [item('Import', () {})]),
        ]),
      ));
      await tester.pump();
      expect(menuButton, findsOneWidget);

      key.currentState!.select(true);
      await tester.pump();
      await tester.pump();
      expect(find.text('1 selected'), findsOneWidget);
      expect(menuButton, findsNothing);

      key.currentState!.select(false);
      await tester.pump();
      await tester.pump();
      expect(menuButton, findsOneWidget);
    });

    testWidgets('an entry calls the body\'s newest callback', (tester) async {
      var which = '';
      Widget body(String tag) => HubTabBody(
            title: 't',
            menu: [item('Go', () => which = tag)],
            body: const SizedBox(),
          );
      final key = GlobalKey<_SwapState>();
      await tester.pumpWidget(MaterialApp(
        home: _Hub(bodies: [_Swap(key: key, a: body('old'), b: body('new'))]),
      ));
      await tester.pump();
      key.currentState!.swap();
      await tester.pump();
      await tester.pump();
      await tester.tap(menuButton);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('item-Go')));
      await tester.pumpAndSettle();
      expect(which, 'new');
    });

    testWidgets('a body that leaves the hub takes its menu with it',
        (tester) async {
      final key = GlobalKey<_SwapState>();
      await tester.pumpWidget(MaterialApp(
        home: _Hub(bodies: [
          _Swap(
            key: key,
            a: HubTabBody(
              title: 't',
              menu: [item('Go', () {})],
              body: const SizedBox(),
            ),
            b: const SizedBox(),
          ),
        ]),
      ));
      await tester.pump();
      expect(menuButton, findsOneWidget);
      key.currentState!.swap();
      await tester.pump();
      await tester.pump();
      expect(menuButton, findsNothing);
    });

    testWidgets('on its own the menu is the app bar\'s ⋮', (tester) async {
      var imported = 0;
      await tester.pumpWidget(MaterialApp(
        home: HubTabBody(
          title: 'Runs',
          menu: [item('Import', () => imported++)],
          body: const Text('content'),
        ),
      ));
      expect(
        find.descendant(of: find.byType(AppBar), matching: menuButton),
        findsOneWidget,
      );
      expect(find.byType(FloatingActionButton), findsNothing);
      await tester.tap(menuButton);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('item-Import')));
      await tester.pumpAndSettle();
      expect(imported, 1);
    });
  });
}

class _Selectable extends StatefulWidget {
  const _Selectable({super.key, required this.menu});

  final List<HubMenuItem> menu;

  @override
  State<_Selectable> createState() => _SelectableState();
}

class _SelectableState extends State<_Selectable> {
  bool _selecting = false;

  void select(bool on) => setState(() => _selecting = on);

  @override
  Widget build(BuildContext context) => HubTabBody(
        title: 'Runs',
        menu: widget.menu,
        selection: _selecting
            ? HubSelection(
                title: '1 selected',
                closeTooltip: 'Close',
                onClose: () => select(false),
              )
            : null,
        body: const SizedBox(),
      );
}

class _Swap extends StatefulWidget {
  const _Swap({super.key, required this.a, required this.b});

  final Widget a;
  final Widget b;

  @override
  State<_Swap> createState() => _SwapState();
}

class _SwapState extends State<_Swap> {
  bool _b = false;

  void swap() => setState(() => _b = true);

  @override
  Widget build(BuildContext context) => _b ? widget.b : widget.a;
}
