import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

/// A strip over a [TabSetController] whose set a test changes from outside,
/// as a settings toggle or a session change does in the app.
class _Strip extends StatefulWidget {
  const _Strip({required this.tabs, required this.initial});

  final ValueNotifier<List<String>> tabs;
  final String initial;

  @override
  State<_Strip> createState() => _StripState();
}

class _StripState extends State<_Strip> with TickerProviderStateMixin {
  late final TabSetController<String> set = TabSetController(
    vsync: this,
    tabs: widget.tabs.value,
    initial: widget.initial,
  );

  @override
  void initState() {
    super.initState();
    widget.tabs.addListener(_changed);
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    widget.tabs.removeListener(_changed);
    set.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tabs = widget.tabs.value;
    set.update(tabs);
    return Scaffold(
      body: Column(
        children: [
          AppTabBar(controller: set.controller, labels: tabs),
          Expanded(
            child: TabBarView(
              controller: set.controller,
              children: [for (final t in tabs) Center(child: Text('body $t'))],
            ),
          ),
        ],
      ),
    );
  }
}

Future<ValueNotifier<List<String>>> _pump(
  WidgetTester tester,
  List<String> tabs, {
  required String initial,
}) async {
  final notifier = ValueNotifier(tabs);
  addTearDown(notifier.dispose);
  await tester.pumpWidget(
    MaterialApp(home: _Strip(tabs: notifier, initial: initial)),
  );
  return notifier;
}

TabController _controller(WidgetTester tester) =>
    tester.widget<TabBar>(find.byType(TabBar)).controller!;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Sentry THREKIR-CLIENT-A: a fixed-length controller under a strip that
  // lost its last tab built a tab past the end, RangeError (length) from
  // _TabBarState.
  testWidgets('the strip losing the selected last tab clamps onto the tab '
      'before it, and never builds past its end', (tester) async {
    final tabs = await _pump(tester, ['a', 'b', 'c', 'd'], initial: 'd');
    expect(_controller(tester).index, 3);

    tabs.value = ['a', 'b', 'c'];
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(_controller(tester).length, 3);
    expect(_controller(tester).index, 2);
    expect(find.text('body c'), findsOneWidget);
  });

  testWidgets('a tab that is still in the set stays selected when tabs are '
      'added or removed around it', (tester) async {
    final tabs = await _pump(tester, ['a', 'b', 'c'], initial: 'b');

    tabs.value = ['x', 'a', 'y', 'b', 'c'];
    await tester.pumpAndSettle();
    expect(_controller(tester).index, 3);
    expect(find.text('body b'), findsOneWidget);

    tabs.value = ['b', 'c'];
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(_controller(tester).index, 0);
    expect(find.text('body b'), findsOneWidget);
  });

  testWidgets('mid-animation the tab being moved to is the one kept',
      (tester) async {
    final tabs = await _pump(tester, ['a', 'b', 'c', 'd', 'e'], initial: 'a');

    await tester.tap(find.text('e'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(_controller(tester).indexIsChanging, isTrue);

    tabs.value = ['a', 'e'];
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(_controller(tester).index, 1);
    expect(find.text('body e'), findsOneWidget);
  });

  testWidgets('an unchanged set keeps the same controller', (tester) async {
    final tabs = await _pump(tester, ['a', 'b'], initial: 'b');
    final before = _controller(tester);

    tabs.value = ['a', 'b'];
    await tester.pumpAndSettle();
    expect(identical(_controller(tester), before), isTrue);
  });

  test('update takes the fallback when the selected tab goes, and select '
      'ignores a tab that is not in the set', () {
    final set = TabSetController<String>(
      vsync: const TestVSync(),
      tabs: const ['h', 'r', 'g', 'n'],
      initial: 'n',
    );
    addTearDown(set.dispose);

    expect(set.update(const ['r', 'p'], fallback: 'r'), isTrue);
    expect(set.selected, 'r');
    expect(set.controller.length, 2);

    set.select('missing', animate: false);
    expect(set.selected, 'r');
    set.select('p', animate: false);
    expect(set.selected, 'p');

    expect(set.update(const ['r', 'p']), isFalse);
  });

  test('an unknown initial tab opens on the first', () {
    final set = TabSetController<String>(
      vsync: const TestVSync(),
      tabs: const ['a', 'b'],
      initial: 'z',
    );
    addTearDown(set.dispose);
    expect(set.selected, 'a');
  });
}
