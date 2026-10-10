import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../lib/screens/onboarding_screen.dart';
import 'app_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'a first launch reaches onboarding and pages through to the location '
      'disclosure', (tester) async {
    await launchApp(onboarded: false);

    await pumpUntilFound(tester, find.byType(OnboardingScreen),
        describe: 'the cold launch to reach onboarding');
    final l10n = l10nOf(tester, find.byType(OnboardingScreen));
    expect(find.text(l10n.onboardingTrackTitle), findsOneWidget);

    final next = find.widgetWithText(FilledButton, l10n.onboardingNext);
    await tester.tap(next);
    await pumpUntilFound(tester, find.text(l10n.onboardingRoutesTitle),
        describe: 'Next to page to the routes card');

    await tester.tap(next);
    await pumpUntilFound(tester, find.text(l10n.onboardingLocationTitle),
        describe: 'Next to page to the location disclosure');
    // The disclosure must precede the OS prompt, and its copy is the one
    // place the two platforms' permission models are described differently.
    expect(
      find.text(Platform.isIOS
          ? l10n.onboardingLocationBodyIos
          : l10n.onboardingLocationBodyAndroid),
      findsOneWidget,
    );
    // Stopping here is deliberate: the page after this one asks the OS for
    // location, and an in-process driver cannot answer a system dialog.
    expect(next.hitTestable(), findsOneWidget);
  });
}
