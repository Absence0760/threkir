import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../lib/screens/dashboard_screen.dart';
import '../lib/screens/fitness_hub_screen.dart';
import '../lib/screens/home_screen.dart';
import '../lib/screens/you_screen.dart';
import 'app_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'an onboarded launch reaches Home and the bottom nav switches '
      'destinations', (tester) async {
    await launchApp(onboarded: true);

    await pumpUntilFound(tester, find.byType(BottomAppBar),
        describe: 'the cold launch to reach the Home shell');
    final l10n = l10nOf(tester, find.byType(HomeScreen));
    await pumpUntilFound(tester, find.byType(DashboardScreen).hitTestable(),
        describe: 'the dashboard to be the visible page');

    Finder navItem(String label) => find.descendant(
        of: find.byType(BottomAppBar), matching: find.text(label));

    // The hub is captioned Training rather than Fitness while Gym and
    // Nutrition are both hidden, which depends on what this install has
    // logged, so take whichever caption the bar is wearing.
    final hubLabel = navItem(l10n.navFitness).evaluate().isNotEmpty
        ? l10n.navFitness
        : l10n.navTraining;

    // Run is left out on purpose: its page asks the OS for location, which
    // an in-process driver cannot answer.
    final stops = <(String, Type)>[
      (l10n.navYou, YouScreen),
      (hubLabel, FitnessHubScreen),
      (l10n.navHome, DashboardScreen),
    ];
    for (final (label, screen) in stops) {
      await tester.tap(navItem(label));
      await pumpUntilFound(tester, find.byType(screen).hitTestable(),
          describe: 'the $label tab to show $screen');
    }
  });
}
