import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart' show AppTheme;

import '../lib/l10n/gen/app_localizations.dart';

/// Android's 3-button navigation bar, which an edge-to-edge app draws under
/// and the platform reports as the bottom `viewPadding`.
const kThreeButtonNavBar = 48.0;

const _screen = Size(360, 780);

/// Pumps a phone with a 3-button nav bar and a button that runs [open], taps
/// it and settles, so the sheet [open] shows is on screen.
Future<void> openSheetOverNavBar(
  WidgetTester tester,
  Future<void> Function(BuildContext context) open,
) async {
  tester.view.physicalSize = _screen;
  tester.view.devicePixelRatio = 1;
  tester.view.viewPadding = const FakeViewPadding(bottom: kThreeButtonNavBar);
  tester.view.padding = const FakeViewPadding(bottom: kThreeButtonNavBar);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => open(context),
            child: const Text('open sheet'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open sheet'));
  await tester.pumpAndSettle();
}

/// Fails when [button] reaches into the nav bar, where a tap lands on Back,
/// Home or Recents instead.
void expectAboveNavBar(WidgetTester tester, Finder button) {
  expect(button, findsOneWidget);
  final rect = tester.getRect(button);
  expect(rect.bottom, lessThanOrEqualTo(_screen.height - kThreeButtonNavBar),
      reason: 'the action sits ${rect.bottom - (_screen.height - kThreeButtonNavBar)} '
          'dp under the 3-button nav bar');
}
