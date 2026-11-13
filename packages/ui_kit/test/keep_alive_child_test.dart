import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

/// Counts how many times its State is created. Deliberately not a text
/// field: a focused `EditableText` keeps itself alive, which would hide the
/// difference this test measures.
class _Page extends StatefulWidget {
  const _Page(this.created);

  final List<int> created;

  @override
  State<_Page> createState() => _PageState();
}

class _PageState extends State<_Page> {
  @override
  void initState() {
    super.initState();
    widget.created.add(1);
  }

  @override
  Widget build(BuildContext context) => const Text('page');
}

Widget _hub(TabController tabs, List<Widget> pages) => MaterialApp(
      home: Scaffold(
        body: TabBarView(controller: tabs, children: pages),
      ),
    );

void main() {
  testWidgets('a wrapped tab page keeps its State across a switch away and back', (tester) async {
    final created = <int>[];
    final tabs = TabController(length: 3, vsync: const TestVSync());
    addTearDown(tabs.dispose);
    await tester.pumpWidget(_hub(tabs, [
      KeepAliveChild(child: _Page(created)),
      const SizedBox(),
      const SizedBox(),
    ]));

    tabs.index = 2;
    await tester.pumpAndSettle();
    tabs.index = 0;
    await tester.pumpAndSettle();

    expect(created, hasLength(1));
    expect(find.text('page'), findsOneWidget);
  });

  testWidgets('without it the page is rebuilt from scratch, which is why the hubs wrap', (tester) async {
    final created = <int>[];
    final tabs = TabController(length: 3, vsync: const TestVSync());
    addTearDown(tabs.dispose);
    await tester.pumpWidget(_hub(tabs, [
      _Page(created),
      const SizedBox(),
      const SizedBox(),
    ]));

    tabs.index = 2;
    await tester.pumpAndSettle();
    tabs.index = 0;
    await tester.pumpAndSettle();

    expect(created, hasLength(2));
    expect(find.text('page'), findsOneWidget);
  });

  // The detail screens' maps are ListView children: past the cache extent a
  // bare child is disposed, and the map reloads every tile on the way back.
  testWidgets('a wrapped ListView child keeps its State when scrolled far out of view', (tester) async {
    final created = <int>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListView(
          cacheExtent: 0,
          children: [
            KeepAliveChild(child: SizedBox(height: 100, child: _Page(created))),
            const SizedBox(height: 5000),
          ],
        ),
      ),
    ));

    await tester.drag(find.byType(ListView), const Offset(0, -3000));
    await tester.pumpAndSettle();
    expect(find.text('page', skipOffstage: false), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, 3000));
    await tester.pumpAndSettle();

    expect(created, hasLength(1));
    expect(find.text('page'), findsOneWidget);
  });
}
