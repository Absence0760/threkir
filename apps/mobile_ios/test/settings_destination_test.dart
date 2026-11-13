// The route/intent seam an embedded surface uses to open a Settings
// sub-screen it holds none of the dependencies for (decisions § 710).
//
// This file covers the intent half — parking, draining, and re-requesting.
// The host half (a parked destination becoming the right pushed screen) is
// pinned against a real shell in `home_screen_test.dart`, and the first
// consumer's affordance in `people_screen_test.dart`.

import 'package:flutter_test/flutter_test.dart';

import '../lib/preferences_page.dart';
import '../lib/settings_destination.dart';

void main() {
  setUp(() {
    pendingSettingsDestination.value = null;
    takePendingSettingsRow();
  });
  tearDown(() => pendingSettingsDestination.value = null);

  test('openSettings parks the destination for the shell to drain', () {
    openSettings(SettingsDestination.privacy);
    expect(pendingSettingsDestination.value, SettingsDestination.privacy);
  });

  test('each Preferences page is its own destination, in page order', () {
    // Preferences is five pages (issue #1374), so a link names the one whose
    // setting it is about rather than a single long page.
    expect(
      [
        for (final d in SettingsDestination.values)
          if (d.preferencesPage case final page?) page,
      ],
      PreferencesPage.values,
    );
    expect(SettingsDestination.account.preferencesPage, isNull);
  });

  test('openSettingsRow parks the page the row is on, and the row', () {
    // A link about one setting lands on it, not at the top of its page
    // (decisions § 2494, amended).
    openSettingsRow(PreferencesRow.showNutrition);
    expect(pendingSettingsDestination.value, SettingsDestination.display);
    expect(pendingSettingsRow, PreferencesRow.showNutrition);
    expect(takePendingSettingsRow(), PreferencesRow.showNutrition);
    expect(pendingSettingsRow, isNull, reason: 'taken once');
  });

  test('a page-only request drops a row parked before it', () {
    openSettingsRow(PreferencesRow.maxHr);
    pendingSettingsDestination.value = null;
    openSettings(SettingsDestination.training);
    expect(pendingSettingsRow, isNull);
  });

  test('every row has a destination for its page', () {
    for (final row in PreferencesRow.values) {
      expect(SettingsDestination.of(row.page).preferencesPage, row.page);
    }
  });

  test('nothing is parked until a surface asks', () {
    expect(pendingSettingsDestination.value, isNull);
  });

  test('a request notifies listeners exactly once', () {
    final seen = <SettingsDestination?>[];
    void listener() => seen.add(pendingSettingsDestination.value);
    pendingSettingsDestination.addListener(listener);
    addTearDown(() => pendingSettingsDestination.removeListener(listener));

    openSettings(SettingsDestination.safety);
    expect(seen, [SettingsDestination.safety]);
  });

  test('the same destination can be requested again after a drain', () {
    final seen = <SettingsDestination?>[];
    void listener() => seen.add(pendingSettingsDestination.value);
    pendingSettingsDestination.addListener(listener);
    addTearDown(() => pendingSettingsDestination.removeListener(listener));

    openSettings(SettingsDestination.privacy);
    // The host clears the slot as it navigates — which is precisely what lets
    // a second identical request notify, since a ValueNotifier is silent on an
    // unchanged value.
    pendingSettingsDestination.value = null;
    openSettings(SettingsDestination.privacy);

    expect(seen, [
      SettingsDestination.privacy,
      null,
      SettingsDestination.privacy,
    ]);
  });

  test('a request made with no shell listening stays parked', () {
    // A surface can ask before the shell is up (or from a host that never
    // drains); the request waits rather than being dropped on the floor.
    openSettings(SettingsDestination.about);
    expect(pendingSettingsDestination.value, SettingsDestination.about);
  });

  test('a later request replaces an undrained one', () {
    openSettings(SettingsDestination.about);
    openSettings(SettingsDestination.pro);
    expect(pendingSettingsDestination.value, SettingsDestination.pro,
        reason: 'one slot — the newest intent is the one the runner meant');
  });
}
