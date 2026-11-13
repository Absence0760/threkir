import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

Future<List<int>> _pump(WidgetTester tester, double width) async {
  final picked = <int>[];
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: width,
          child: StarRatingInput(
            value: 2,
            starLabel: (n) => 'star $n',
            onChanged: picked.add,
          ),
        ),
      ),
    ),
  ));
  return picked;
}

void main() {
  testWidgets('five stars fit a 192 dp row and the fifth is tappable',
      (tester) async {
    final picked = await _pump(tester, 192);
    expect(tester.takeException(), isNull);
    final row = tester.getRect(find.byType(StarRatingInput));
    final buttons = find.byType(IconButton);
    expect(buttons, findsNWidgets(5));
    for (var i = 0; i < 5; i++) {
      final r = tester.getRect(buttons.at(i));
      expect(r.left, greaterThanOrEqualTo(row.left - 0.01));
      expect(r.right, lessThanOrEqualTo(row.right + 0.01));
      expect(r.height, greaterThanOrEqualTo(48));
      expect(r.width, greaterThanOrEqualTo(24));
    }
    await tester.tap(find.byTooltip('star 5'));
    expect(picked, [5]);
  });

  testWidgets('cells stay 48 dp square when the row has room', (tester) async {
    await _pump(tester, 400);
    final r = tester.getRect(find.byType(IconButton).first);
    expect(r.size, const Size(48, 48));
  });

  testWidgets('stars up to the value read as selected', (tester) async {
    await _pump(tester, 300);
    final buttons =
        tester.widgetList<IconButton>(find.byType(IconButton)).toList();
    expect(buttons.map((b) => b.isSelected), [true, true, false, false, false]);
  });
}
