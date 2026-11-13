import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

/// A two-tab hub shaped like the app's: one strip, a TabBarView of scoped
/// bodies, and the active tab's action as the hub's FAB.
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
          toolbarHeight: 0,
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
