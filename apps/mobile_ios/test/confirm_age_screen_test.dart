import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart' show AppTheme, PageHeader;

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/screens/confirm_age_screen.dart';
import 'editor_layout.dart';
import 'three_button_nav_bar.dart';

class _GateApi extends ApiClient {
  bool failConfirm = false;
  bool failSignOut = false;
  int confirmCalls = 0;
  int signOutCalls = 0;

  @override
  Future<void> confirmAgeAndTerms() async {
    confirmCalls++;
    if (failConfirm) throw Exception('network down');
  }

  @override
  Future<void> signOut() async {
    signOutCalls++;
    if (failSignOut) throw Exception('network down');
  }
}

/// Pushes the gate from a launcher page and records what it popped with.
Future<List<bool?>> _pumpGate(
  WidgetTester tester,
  _GateApi api, {
  bool fullscreenDialog = false,
}) async {
  final popped = <bool?>[];
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            popped.add(await Navigator.of(context).push<bool>(
              MaterialPageRoute<bool>(
                fullscreenDialog: fullscreenDialog,
                builder: (_) => ConfirmAgeScreen(apiClient: api),
              ),
            ));
          },
          child: const Text('open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return popped;
}

Future<void> _tickBoth(WidgetTester tester) async {
  await tester.tap(find.byType(Checkbox).at(0));
  await tester.pump();
  await tester.tap(find.byType(Checkbox).at(1));
  await tester.pump();
}

void main() {
  testWidgets('a failed stamp keeps the gate up and says so', (tester) async {
    final api = _GateApi()..failConfirm = true;
    final popped = await _pumpGate(tester, api);
    await _tickBoth(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pumpAndSettle();

    expect(api.confirmCalls, 1);
    expect(popped, isEmpty);
    expect(find.byType(ConfirmAgeScreen), findsOneWidget);
    expect(find.textContaining('Could not record consent.'), findsOneWidget);
  });

  testWidgets('the system back gesture cannot dismiss the gate',
      (tester) async {
    final api = _GateApi();
    final popped = await _pumpGate(tester, api);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(popped, isEmpty);
    expect(find.byType(ConfirmAgeScreen), findsOneWidget);
  });

  // Issue #1374 NS-15: Back on the gate gave no response at all.
  testWidgets('Back on the gate says how to go on and offers Sign out',
      (tester) async {
    final api = _GateApi();
    await _pumpGate(tester, api);
    await tester.binding.handlePopRoute();
    await tester.pump();
    final l10n = lookupAppLocalizations(const Locale('en'));
    expect(find.text(l10n.confirmAgeBackHint), findsOneWidget);
    expect(find.text(l10n.settingsAccountSignOut), findsNWidgets(2),
        reason: 'the page\'s own button and the banner\'s action');
    await tester.pump(const Duration(seconds: 7));
  });

  testWidgets('signing out leaves the gate without recording anything',
      (tester) async {
    final api = _GateApi();
    final popped = await _pumpGate(tester, api);
    await tester.tap(find.widgetWithText(TextButton, 'Sign out'));
    await tester.pumpAndSettle();

    expect(api.signOutCalls, 1);
    expect(api.confirmCalls, 0);
    expect(popped, [false]);
  });

  testWidgets('a failed sign-out keeps the gate up', (tester) async {
    final api = _GateApi()..failSignOut = true;
    final popped = await _pumpGate(tester, api);
    await tester.tap(find.widgetWithText(TextButton, 'Sign out'));
    await tester.pumpAndSettle();

    expect(popped, isEmpty);
    expect(find.byType(ConfirmAgeScreen), findsOneWidget);
  });

  Finder continueButton() => find.widgetWithText(FilledButton, 'Continue');

  // Pushed as HomeScreen pushes it: a full-screen dialog, which would
  // otherwise draw a close button.
  testWidgets('the gate draws no close or back button', (tester) async {
    await _pumpGate(tester, _GateApi(), fullscreenDialog: true);
    expect(find.byType(CloseButton), findsNothing);
    expect(find.byType(BackButton), findsNothing);
    expect(find.byIcon(Icons.close), findsNothing);
    expect(find.byIcon(Icons.arrow_back), findsNothing);
  });

  testWidgets('Continue stays disabled until both boxes are ticked',
      (tester) async {
    final api = _GateApi();
    await _pumpGate(tester, api, fullscreenDialog: true);
    bool enabled() =>
        tester.widget<FilledButton>(continueButton()).onPressed != null;

    expect(enabled(), isFalse);
    await tester.tap(find.byType(Checkbox).at(0));
    await tester.pump();
    expect(enabled(), isFalse, reason: 'age alone is not enough');
    await tester.tap(find.byType(Checkbox).at(0));
    await tester.tap(find.byType(Checkbox).at(1));
    await tester.pump();
    expect(enabled(), isFalse, reason: 'terms alone are not enough');
    await tester.tap(find.byType(Checkbox).at(0));
    await tester.pump();
    expect(enabled(), isTrue);

    await tester.tap(find.byType(Checkbox).at(1));
    await tester.pump();
    expect(enabled(), isFalse, reason: 'unticking takes it away again');
    await tester.tap(continueButton(), warnIfMissed: false);
    await tester.pump();
    expect(api.confirmCalls, 0);
  });

  testWidgets('Continue is reachable over the nav bar and the keyboard',
      (tester) async {
    await expectEditorSaveReachable(
      tester,
      page: () => ConfirmAgeScreen(apiClient: _GateApi()),
      save: continueButton(),
    );
  });

  testWidgets(
      'at 2.0 on 320 dp Continue and Sign out clear the 3-button bar, '
      'nothing overflows and the heading is whole', (tester) async {
    tester.view.physicalSize = kNarrowPhone;
    tester.view.devicePixelRatio = 1;
    tester.view.viewPadding =
        const FakeViewPadding(bottom: kThreeButtonNavBar);
    tester.view.padding = const FakeViewPadding(bottom: kThreeButtonNavBar);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery.withClampedTextScaling(
        minScaleFactor: 2,
        maxScaleFactor: 2,
        child: child!,
      ),
      home: ConfirmAgeScreen(apiClient: _GateApi()),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final floor = kNarrowPhone.height - kThreeButtonNavBar;
    for (final button in [
      continueButton(),
      find.widgetWithText(TextButton, 'Sign out'),
    ]) {
      expect(button.hitTestable(), findsOneWidget);
      final rect = tester.getRect(button);
      expect(rect.bottom, lessThanOrEqualTo(floor));
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(kNarrowPhone.width));
    }

    final l10n = lookupAppLocalizations(const Locale('en'));
    final heading = find.descendant(
      of: find.byType(PageHeader),
      matching: find.text(l10n.confirmAgeHeading),
    );
    expect(heading, findsOneWidget);
    final paragraph = tester.renderObject<RenderParagraph>(heading);
    expect(paragraph.didExceedMaxLines, isFalse);
    final rect = tester.getRect(heading);
    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.right, lessThanOrEqualTo(kNarrowPhone.width));
  });
}
