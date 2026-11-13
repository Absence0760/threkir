import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

/// Issue #1374: fields that touched drew each floating label over the field
/// above. FieldColumn keeps every label clear of the field above it.
Future<void> _pump(WidgetTester tester, double scale) async {
  tester.view.physicalSize = const Size(320, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(scale)),
      child: Scaffold(
        body: SingleChildScrollView(
          child: FieldColumn(children: [
            TextField(
              key: const ValueKey('a'),
              controller: TextEditingController(text: '47.1'),
              decoration: const InputDecoration(labelText: 'Latitude'),
            ),
            TextField(
              key: const ValueKey('b'),
              controller: TextEditingController(text: '8.6'),
              decoration: const InputDecoration(labelText: 'Longitude'),
            ),
            DropdownButtonFormField<int>(
              key: const ValueKey('c'),
              initialValue: 1,
              decoration: const InputDecoration(labelText: 'Pace'),
              items: const [DropdownMenuItem(value: 1, child: Text('Run'))],
              onChanged: (_) {},
            ),
          ]),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  for (final scale in [1.0, 2.0, 3.0]) {
    testWidgets('no floating label meets the field above at ${scale}x',
        (tester) async {
      await _pump(tester, scale);
      expect(tester.takeException(), isNull);
      for (final (above, label) in [('a', 'Longitude'), ('b', 'Pace')]) {
        final field = tester.getRect(find.byKey(ValueKey(above)));
        final top = tester.getRect(find.text(label)).top;
        expect(top, greaterThanOrEqualTo(field.bottom),
            reason: '"$label" overlaps the field above at ${scale}x');
      }
    });
  }

  testWidgets('the gap is the field gap at 1x', (tester) async {
    await _pump(tester, 1.0);
    final a = tester.getRect(find.byKey(const ValueKey('a')));
    final b = tester.getRect(find.byKey(const ValueKey('b')));
    expect(b.top - a.bottom, AppInsets.fieldGap);
  });

  test('the gap grows with the text only once the label would reach it', () {
    expect(FieldColumn.gapFor(TextScaler.noScaling), AppInsets.fieldGap);
    expect(FieldColumn.gapFor(const TextScaler.linear(2)), AppInsets.fieldGap);
    expect(FieldColumn.gapFor(const TextScaler.linear(3)),
        greaterThan(AppInsets.fieldGap));
  });

  testWidgets('children stretch to the column', (tester) async {
    await _pump(tester, 1.0);
    expect(tester.getSize(find.byKey(const ValueKey('a'))).width, 320);
  });
}
