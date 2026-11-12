// Parity pair with web `training/goal_event_label.test.ts`
// (`goalEventLabel` + `planLengthLabel`): same cases, same count.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/plan_labels.dart';
import '../lib/preferences.dart';

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));

  tearDown(resetActivePreferencesForTest);

  test('named race distances read as their event, whatever distance is stored',
      () {
    expect(planGoalLabel(l10n, 'distance_5k', 5000), '5K');
    expect(planGoalLabel(l10n, 'distance_10k', null), '10K');
    expect(planGoalLabel(l10n, 'distance_half', 21097.5), 'Half marathon');
    expect(planGoalLabel(l10n, 'distance_full', 42195), 'Marathon');
  });

  test('a custom plan with a stored distance names that distance', () {
    expect(planGoalLabel(l10n, 'custom', 50000), '50.00 km');
  });

  test('the distance follows the active unit preference', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({'use_miles': true});
    final prefs = Preferences();
    await prefs.init();
    registerActivePreferences(prefs);
    expect(planGoalLabel(l10n, 'custom', 80467.2), '50.00 mi');
  });

  test('a custom plan with no usable distance falls back to Custom', () {
    expect(planGoalLabel(l10n, 'custom', null), 'Custom');
    expect(planGoalLabel(l10n, 'custom', 0), 'Custom');
    expect(planGoalLabel(l10n, 'custom', -5), 'Custom');
  });

  test('an unrecognised goal event reads as custom', () {
    expect(planGoalLabel(l10n, 'distance_ultra', null), 'Custom');
    expect(planGoalLabel(l10n, 'distance_ultra', 100000), '100.00 km');
  });

  test('plan length: singular for one week, plural otherwise', () {
    expect(planLengthLabel(l10n, 1, 3), '1 week · 3 days/week');
    expect(planLengthLabel(l10n, 12, 4), '12 weeks · 4 days/week');
  });
}
