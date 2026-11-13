import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/screens/runs_screen.dart';

/// #1374 A11Y-10: the History range picker's day cells read a bare "12":
/// no month, and the range's start, end and the days inside it were only
/// drawn. Each cell is now one node with the full date, Material's own
/// start / end / today wording, and `selected` for every day in the range.
void main() {
  testWidgets('day cells name the date and the range they are in', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: HistoryRangeCalendarSheet(
          initialFrom: DateTime(2026, 3, 3),
          initialTo: DateTime(2026, 3, 10),
        ),
      ),
    ));
    await tester.pump();
    final ml = MaterialLocalizations.of(tester.element(find.byType(HistoryRangeCalendarSheet)));
    SemanticsData cell(int day) => tester
        .getSemantics(find.byKey(ValueKey('rangeDay-2026-3-$day')))
        .getSemanticsData();

    final start = cell(3);
    expect(start.label,
        ml.dateRangeStartDateSemanticLabel(ml.formatFullDate(DateTime(2026, 3, 3))));
    expect(start.flagsCollection.isSelected, Tristate.isTrue);
    final end = cell(10);
    expect(end.label,
        ml.dateRangeEndDateSemanticLabel(ml.formatFullDate(DateTime(2026, 3, 10))));
    expect(end.flagsCollection.isSelected, Tristate.isTrue);
    final inside = cell(6);
    expect(inside.label, ml.formatFullDate(DateTime(2026, 3, 6)));
    expect(inside.flagsCollection.isSelected, Tristate.isTrue);
    final outside = cell(12);
    expect(outside.label, ml.formatFullDate(DateTime(2026, 3, 12)));
    expect(outside.flagsCollection.isSelected, isNot(Tristate.isTrue));
    expect(outside.hasAction(SemanticsAction.tap), isTrue);
    handle.dispose();
  });
}
