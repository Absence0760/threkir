import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart' show AppTheme;

import '../lib/l10n/gen/app_localizations.dart';
import 'three_button_nav_bar.dart';

/// The worst phone an editor has to work on: 320 dp wide, 568 tall, text at
/// 2.0x and a 3-button nav bar (issue #1374 TO-7, IK-11).
const kSmallPhone = Size(320, 568);

/// A soft keyboard on [kSmallPhone].
const kSmallPhoneKeyboard = 260.0;

/// Pumps [page] on [kSmallPhone] at 2.0x with the 3-button bar, first with no
/// keyboard and then with the keyboard up, and fails unless [save] is on
/// screen, whole, tappable and clear of the bar or the keyboard both times.
///
/// [page] is built fresh for each pump inside a MaterialApp; a sheet that
/// only opens through its `show…` function passes [open] instead, which runs
/// from a button on a host page. [settle] pumps whatever loading the page
/// does after it mounts.
Future<void> expectEditorSaveReachable(
  WidgetTester tester, {
  Widget Function()? page,
  Future<void> Function(BuildContext context)? open,
  required Finder save,
  Future<void> Function()? settle,
}) async {
  assert((page == null) != (open == null), 'pass page or open');
  for (final keyboard in [0.0, kSmallPhoneKeyboard]) {
    tester.view.physicalSize = kSmallPhone;
    tester.view.devicePixelRatio = 1;
    tester.view.viewPadding =
        const FakeViewPadding(bottom: kThreeButtonNavBar);
    // The engine reports `padding` net of the keyboard, which covers the bar.
    tester.view.padding =
        FakeViewPadding(bottom: keyboard > 0 ? 0 : kThreeButtonNavBar);
    tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      key: ValueKey(keyboard),
      theme: AppTheme.light,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery.withClampedTextScaling(
        minScaleFactor: 2,
        maxScaleFactor: 2,
        child: child!,
      ),
      home: page?.call() ??
          Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => open!(context),
                child: const Text('open editor'),
              ),
            ),
          ),
    ));
    await tester.pump();
    if (open != null) {
      await tester.tap(find.text('open editor'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    }
    if (settle != null) await settle();
    final floor = kSmallPhone.height -
        (keyboard > 0 ? keyboard : kThreeButtonNavBar);
    expect(save.hitTestable(), findsOneWidget,
        reason: 'Save is covered or off screen (keyboard $keyboard)');
    final rect = tester.getRect(save);
    expect(rect.bottom, lessThanOrEqualTo(floor),
        reason: 'Save sits ${rect.bottom - floor} dp under the '
            '${keyboard > 0 ? 'keyboard' : 'nav bar'}');
    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.right, lessThanOrEqualTo(kSmallPhone.width));
  }
}
