import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

import 'worst_case_layout.dart';

/// The harness's title check (issue #1374 TO-12): a pushed page whose app bar
/// cuts its title fails, and one that says its title in the body passes.
void main() {
  const locale = Locale('fr');
  final title = l10nFor(locale).planCalendarFeedTitle;

  testWidgets('a cut app-bar title fails the harness', (tester) async {
    useWorstCasePhone(tester);
    await tester.pumpWidget(worstCaseApp(
      locale: locale,
      home: Scaffold(appBar: AppBar(title: Text(title)), body: const SizedBox()),
    ));
    expect(() => expectTitlesNotCut(tester, 'bare AppBar'),
        throwsA(isA<TestFailure>()));
  });

  testWidgets('a short title that fits passes', (tester) async {
    useWorstCasePhone(tester);
    await tester.pumpWidget(worstCaseApp(
      locale: locale,
      home: Scaffold(appBar: AppBar(title: const Text('Ok')), body: const SizedBox()),
    ));
    expectTitlesNotCut(tester, 'short AppBar');
  });

  worstCaseTestWidgets('A pushed page with its title in the body',
      (tester, locale) async {
    final title = l10nFor(locale).planCalendarFeedTitle;
    await tester.pumpWidget(worstCaseApp(
      locale: locale,
      home: PushedPage(
        title: title,
        body: ListView(children: [
          PageHeader(title: title),
          for (var i = 0; i < 30; i++) ListTile(title: Text('$i')),
        ]),
      ),
    ));
    await tester.pump();
    await walkScrollable(tester, primaryScrollable(), 'pushed page');
  });
}
