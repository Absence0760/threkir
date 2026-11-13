// ignore_for_file: avoid_relative_lib_imports
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/widgets/thread_title.dart';
import 'worst_case_layout.dart';

/// Issue #1374 TO-8: a group thread's name over its member count clipped in
/// the 56 dp toolbar from 1.3x. The toolbar grows with the title's text.
void main() {
  for (final scale in const [1.0, 1.3, 2.0]) {
    testWidgets('at ${scale}x the name and the member count sit inside the toolbar',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: Builder(
            builder: (context) => Scaffold(
              appBar: AppBar(
                toolbarHeight: ThreadTitle.toolbarHeight(context, subtitle: true),
                title: const ThreadTitle(
                  avatar: CircleAvatar(radius: 16),
                  title: 'Tuesday tempo crew',
                  subtitle: '12 members',
                  titleKey: Key('t'),
                  subtitleKey: Key('s'),
                ),
              ),
            ),
          ),
        ),
      ));
      expect(tester.takeException(), isNull);
      final bar = tester.getRect(find.byType(AppBar));
      for (final k in const [Key('t'), Key('s')]) {
        final r = tester.getRect(find.byKey(k));
        expect(r.top, greaterThanOrEqualTo(bar.top));
        expect(r.bottom, lessThanOrEqualTo(bar.bottom),
            reason: '$k is clipped by the toolbar at ${scale}x');
      }
      if (scale == 1.0) {
        expect(tester.getSize(find.byType(AppBar)).height, kToolbarHeight,
            reason: 'Material height while the text fits');
      }
    });
  }

  worstCaseTestWidgets('A thread title', (tester, locale) async {
    await tester.pumpWidget(worstCaseApp(
      locale: locale,
      home: Builder(
        builder: (context) => Scaffold(
          appBar: AppBar(
            toolbarHeight: ThreadTitle.toolbarHeight(context, subtitle: true),
            title: ThreadTitle(
              avatar: const CircleAvatar(radius: 16),
              title: 'Tuesday tempo crew and friends',
              subtitle: l10nFor(locale).groupsMemberCount(12),
            ),
            actions: [
              IconButton(onPressed: () {}, icon: const Icon(Icons.group), tooltip: 'm'),
            ],
          ),
        ),
      ),
    ));
  });
}
