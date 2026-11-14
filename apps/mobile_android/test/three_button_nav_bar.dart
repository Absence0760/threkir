import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart' show AppTheme;

import '../lib/l10n/gen/app_localizations.dart';

/// Android's 3-button navigation bar, which an edge-to-edge app draws under
/// and the platform reports as the bottom `viewPadding`.
const kThreeButtonNavBar = 48.0;

/// The phone every sheet test opens on unless it asks for another.
const kSheetTestPhone = Size(360, 780);

/// The narrowest phone the app supports, for the text-scale 2.0 checks.
const kNarrowPhone = Size(320, 780);

/// Pumps a phone with a 3-button nav bar and a button that runs [open], taps
/// it and settles, so the sheet [open] shows is on screen. [keyboard] raises
/// a soft keyboard of that height, which covers the nav bar as it does on a
/// device; [textScale] is the system font size.
Future<void> openSheetOverNavBar(
  WidgetTester tester,
  Future<void> Function(BuildContext context) open, {
  Size size = kSheetTestPhone,
  double textScale = 1,
  double keyboard = 0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.view.viewPadding = const FakeViewPadding(bottom: kThreeButtonNavBar);
  tester.view.padding = FakeViewPadding(
      bottom: keyboard > 0 ? 0 : kThreeButtonNavBar);
  tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
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
/// Home or Recents instead, or under a raised keyboard.
void expectAboveNavBar(WidgetTester tester, Finder button) {
  expect(button, findsOneWidget);
  final view = tester.view;
  final height = view.physicalSize.height / view.devicePixelRatio;
  final keyboard = view.viewInsets.bottom / view.devicePixelRatio;
  final floor = height - (keyboard > 0 ? keyboard : kThreeButtonNavBar);
  final rect = tester.getRect(button);
  expect(rect.bottom, lessThanOrEqualTo(floor),
      reason: 'the action sits ${rect.bottom - floor} dp under the '
          '${keyboard > 0 ? 'keyboard' : '3-button nav bar'}');
}
