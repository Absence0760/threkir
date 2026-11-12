import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  double width = 360,
  double textScale = 1,
}) async {
  tester.view.physicalSize = Size(width, 700);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    home: MediaQuery(
      data: MediaQueryData(
        size: Size(width, 700),
        textScaler: TextScaler.linear(textScale),
      ),
      child: Scaffold(body: Column(children: [child])),
    ),
  ));
}

List<Widget> _bands(String selected, ValueChanged<String> onChanged) => [
      for (final b in ['All', '5K', '10K', 'Half', 'Marathon', 'Ultra', 'Trail'])
        Builder(
          builder: (context) => buildChoiceChip(
              context, ChoiceChipOption(value: b, label: b), selected, onChanged),
        ),
    ];

void main() {
  testWidgets('the search field clears with one tap and reports the empty '
      'query', (tester) async {
    final ctl = TextEditingController();
    final seen = <String>[];
    await _pump(
      tester,
      FilterBar(
        search: AppSearchField(
          controller: ctl,
          hint: 'Search runs',
          clearTooltip: 'Clear search',
          onChanged: seen.add,
        ),
      ),
    );
    expect(find.byTooltip('Clear search'), findsNothing);
    await tester.enterText(find.byType(TextField), 'Richmond');
    await tester.pump();
    expect(find.byTooltip('Clear search'), findsOneWidget);
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pump();
    expect(ctl.text, isEmpty);
    expect(seen.last, '');
    expect(find.byTooltip('Clear search'), findsNothing);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('chips stay on one line at 320 dp and ${scale}x, led by the '
        'Filters button and its count', (tester) async {
      var opened = 0;
      var removed = 0;
      await _pump(
        tester,
        width: 320,
        textScale: scale,
        FilterBar(
          search: AppSearchField(
            controller: TextEditingController(),
            hint: 'Search races',
            clearTooltip: 'Clear',
          ),
          chips: _bands('All', (_) {}),
          activeFilters: [
            ActiveFilter(
                label: 'Near Richmond',
                onRemove: () => removed++,
                removeTooltip: 'Remove Near Richmond'),
          ],
          filtersLabel: 'Filters',
          filtersSemanticLabel: 'Filters, 2 active',
          activeFilterCount: 2,
          onOpenFilters: () => opened++,
        ),
      );
      expect(tester.takeException(), isNull);
      final tops = {
        for (final e in find.byType(ChoiceChip).evaluate())
          tester.getTopLeft(find.byWidget(e.widget)).dy,
      };
      expect(tops, hasLength(1), reason: 'the chips wrapped to a second line');
      final button = find.byKey(const Key('filter-bar-filters'));
      expect(tester.getRect(button).left, 16);
      expect(
          tester.getCenter(button).dy,
          closeTo(tester.getCenter(find.byType(ChoiceChip).first).dy, 1));
      expect(find.text('2'), findsOneWidget);
      expect(find.bySemanticsLabel('Filters, 2 active'), findsOneWidget);
      await tester.tap(button);
      expect(opened, 1);
      await tester.ensureVisible(find.byTooltip('Remove Near Richmond'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Remove Near Richmond'));
      expect(removed, 1);
    });
  }

  testWidgets('a bar with only Filters still gives it a line of its own',
      (tester) async {
    await _pump(
      tester,
      FilterBar(
        search: AppSearchField(
          controller: TextEditingController(),
          hint: 'Search',
          clearTooltip: 'Clear',
        ),
        filtersLabel: 'Filters',
        onOpenFilters: () {},
      ),
    );
    expect(
        tester.getTopLeft(find.byKey(const Key('filter-bar-filters'))).dy,
        greaterThan(tester.getBottomLeft(find.byType(TextField)).dy));
  });

  testWidgets('withTrailing appends a host\'s actions to the search row',
      (tester) async {
    await _pump(
      tester,
      FilterBar(
        search: AppSearchField(
          controller: TextEditingController(),
          hint: 'Search',
          clearTooltip: 'Clear',
        ),
      ).withTrailing([
        IconButton(icon: const Icon(Icons.sort), tooltip: 'Sort', onPressed: () {}),
      ]),
    );
    expect(find.byTooltip('Sort'), findsOneWidget);
  });

  testWidgets('the filter sheet\'s Done closes it and Reset resets',
      (tester) async {
    var reset = 0;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showFilterSheet(
              context: context,
              title: 'Filters',
              doneLabel: 'Done',
              resetLabel: 'Reset',
              onReset: () => reset++,
              builder: (_, _) => const Text('controls'),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('controls'), findsOneWidget);
    expect(find.byType(SheetScaffold), findsOneWidget);
    await tester.tap(find.text('Reset'));
    await tester.pump();
    expect(reset, 1);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('controls'), findsNothing);
  });
}
