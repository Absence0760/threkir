// ignore_for_file: avoid_relative_lib_imports
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/health_consent_gate.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/screens/run_screen.dart';
import 'three_button_nav_bar.dart';
import 'worst_case_layout.dart';

// Heart rate and the food log are kept only with health-data consent
// (decisions § 2514). These pin what a runner without it is told.

Widget _summary({VoidCallback? onGiveHealthConsent}) => Scaffold(
      body: FinishedSummary(
        distanceValue: '5.03',
        distanceUnit: 'km',
        timeValue: '28:41',
        movingValue: '27:12',
        primaryLabel: 'Avg pace',
        primaryValue: '5:42',
        primaryUnit: '/km',
        synced: true,
        syncError: null,
        onDone: () {},
        onGiveHealthConsent: onGiveHealthConsent,
      ),
    );

void main() {
  group('finished run without health-data consent', () {
    testWidgets('says the heart rate was not saved and offers consent',
        (tester) async {
      var opened = 0;
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: _summary(onGiveHealthConsent: () => opened++),
      ));
      await tester.pump();
      final l10n = l10nFor(const Locale('en'));
      expect(find.text(l10n.runHeartRateNotSaved), findsOneWidget);
      final give = find.widgetWithText(TextButton, l10n.healthConsentGiveAction);
      await tester.ensureVisible(give);
      await tester.tap(give);
      expect(opened, 1);
    });

    testWidgets('a run whose heart rate was kept shows no note',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: _summary(),
      ));
      await tester.pump();
      expect(find.byKey(const Key('heart-rate-not-kept')), findsNothing);
    });

    worstCaseTestWidgets('Finished summary with the heart-rate note',
        (tester, locale) async {
      await tester.pumpWidget(worstCaseApp(
        locale: locale,
        home: _summary(onGiveHealthConsent: () {}),
      ));
      await tester.pump();
      final give = find.widgetWithText(
          TextButton, l10nFor(locale).healthConsentGiveAction);
      await tester.ensureVisible(give);
      await tester.pump();
      expectAboveNavBar(tester, give);
    });
  });

  group('logging food without health-data consent', () {
    testWidgets('asks first, and Cancel stores nothing', (tester) async {
      bool? allowed;
      await openSheetOverNavBar(tester, (context) async {
        allowed = await ensureFoodLogConsent(context,
            api: null, settingsSync: null, preferences: null);
      }, size: kNarrowPhone, textScale: 2);
      final l10n = l10nFor(const Locale('en'));
      expect(find.text(l10n.healthConsentFoodTitle), findsOneWidget);
      expect(find.text(l10n.healthConsentFoodBody), findsOneWidget);
      expectAboveNavBar(
          tester, find.widgetWithText(TextButton, l10n.healthConsentGiveAction));
      await tester.tap(find.widgetWithText(TextButton, l10n.commonCancel));
      await tester.pumpAndSettle();
      expect(allowed, isFalse);
    });

    testWidgets('a second ask while one is open opens no second dialog',
        (tester) async {
      final results = <bool>[];
      await openSheetOverNavBar(tester, (context) async {
        final first = ensureFoodLogConsent(context,
            api: null, settingsSync: null, preferences: null);
        results.add(await ensureFoodLogConsent(context,
            api: null, settingsSync: null, preferences: null));
        results.add(await first);
      });
      final l10n = l10nFor(const Locale('en'));
      expect(find.text(l10n.healthConsentFoodTitle), findsOneWidget);
      expect(results, [false]);
      await tester.tap(find.widgetWithText(TextButton, l10n.commonCancel));
      await tester.pumpAndSettle();
      expect(results, [false, false]);
      expect(find.text(l10n.healthConsentFoodTitle), findsNothing);
    });

    testWidgets('signed out counts as no consent', (tester) async {
      expect(await healthDataConsented(null), isFalse);
    });
  });
}
