import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

/// Issue #1374 TO-5: a term beside an Expanded, ellipsized value cut the
/// value first. The row keeps both whole, stacking the value when needed.
Future<void> _pump(WidgetTester tester, double width, double scale, String term,
        String value) =>
    tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              child: TermValueRow(term: term, value: value),
            ),
          ),
        ),
      ),
    ));

void main() {
  testWidgets('both fit: one line, the value at the end', (tester) async {
    await _pump(tester, 400, 1.0, 'Bib', '1234');
    final term = tester.getRect(find.text('Bib'));
    final value = tester.getRect(find.text('1234'));
    expect(value.center.dy, closeTo(term.center.dy, 1));
    expect(value.right, closeTo(tester.getRect(find.byType(TermValueRow)).right, 0.5));
  });

  testWidgets('they do not: the value goes under the term, whole', (tester) async {
    await _pump(tester, 288, 2.0, 'Classement dans la catégorie primée', '12 (F40-44)');
    expect(tester.takeException(), isNull);
    final term = tester.getRect(find.text('Classement dans la catégorie primée'));
    final value = tester.getRect(find.text('12 (F40-44)'));
    expect(value.top, greaterThanOrEqualTo(term.bottom - 0.5));
    final para = tester.renderObject<RenderParagraph>(find.text('12 (F40-44)'));
    expect(para.didExceedMaxLines, isFalse);
    expect(value.width, greaterThan(0));
  });

  testWidgets('it reads as one node', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, 400, 1.0, 'Chip time', '1:42:10');
    expect(
      tester.getSemantics(find.byType(TermValueRow)).getSemanticsData().label,
      contains('Chip time'),
    );
    handle.dispose();
  });
}
