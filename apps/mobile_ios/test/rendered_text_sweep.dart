import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A number that should never reach a label: `NaN`, an infinity (Dart's
/// `Infinity` or intl's `∞`), or a negative zero (`-0`, `-0.00`, `-0:00`,
/// also with the U+2212 minus intl emits in some locales).
///
/// The negative-zero arm refuses a minus preceded by a letter or digit, so a
/// date (`2026-04-05`) or a zone (`UTC-0`) is not one, and refuses a zero with
/// any non-zero digit after it, so `-0.05` and a `-0:30` pace delta are not.
final degenerateNumber = RegExp(
  r'\bNaN\b|\bInfinity\b|∞|(?<![\p{L}\p{N}])[-−]0(?:[.,:]0+)*(?![.,:]?\p{N})',
  unicode: true,
);

/// Every string the tree currently paints or announces: the plain text of
/// every [RichText] (which every [Text] builds), every [EditableText]'s value,
/// every [Semantics] label and every [Tooltip] message. Offstage widgets are
/// included, so a string a lazy list has built but not scrolled to counts.
List<String> renderedStrings(WidgetTester tester) {
  final out = <String>[];
  for (final e in find.byType(RichText, skipOffstage: false).evaluate()) {
    out.add((e.widget as RichText).text.toPlainText());
  }
  for (final e in find.byType(EditableText, skipOffstage: false).evaluate()) {
    out.add((e.widget as EditableText).controller.text);
  }
  for (final e in find.byType(Semantics, skipOffstage: false).evaluate()) {
    final label = (e.widget as Semantics).properties.label;
    if (label != null && label.isNotEmpty) out.add(label);
  }
  for (final e in find.byType(Tooltip, skipOffstage: false).evaluate()) {
    final message = (e.widget as Tooltip).message;
    if (message != null && message.isNotEmpty) out.add(message);
  }
  return out;
}

/// Fail when anything [renderedStrings] collects carries a [degenerateNumber],
/// naming every offending string. Also fails on an empty sweep, so a surface
/// that rendered nothing cannot pass by having nothing to inspect.
void expectNoDegenerateNumbers(WidgetTester tester, {required String surface}) {
  final strings = renderedStrings(tester);
  expect(strings, isNotEmpty,
      reason: '$surface rendered no text at all, so the sweep proved nothing');
  final offenders = [
    for (final s in strings)
      if (degenerateNumber.hasMatch(s)) s,
  ];
  expect(offenders, isEmpty,
      reason: '$surface rendered a NaN / infinity / negative zero');
}
