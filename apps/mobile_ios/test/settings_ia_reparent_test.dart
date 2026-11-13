// Issue #666 I7 / I11 / I12: three surfaces were filed under Settings →
// Account, a screen whose subject is sign-in, backup and deletion.
//
//   - Guided runs is coach-driven training content. Web reaches it from a
//     rail on `/coach`; mobile now carries a labelled Coach peer.
//   - Privacy zones is a sharing preference. Web puts the picker on
//     `/settings/privacy`; mobile's Privacy & sharing page now matches
//     (issue #1374 split Preferences into web's five pages).
//   - "View profile" was the third differently-named link to the viewer's own
//     ProfileScreen ("Your profile" on the You tile directly above the
//     Settings body, "My profile" on the dashboard toolbar). The duplicate is
//     deleted and the remaining two say the same thing.
//
// These pin the destinations at their new homes and pin the account screen
// clear of them — a re-parent that only adds is how a surface ends up with
// three names for one screen.

import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart' show PageHeader;
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/preferences.dart';
import '../lib/screens/privacy_zones_screen.dart';
import '../lib/screens/settings_account_screen.dart';
import '../lib/screens/settings_preferences_screen.dart';
import '../lib/settings_sync.dart';

class _FakeSettingsSync extends SettingsSyncService {
  _FakeSettingsSync(Preferences prefs) : super(preferences: prefs);

  @override
  bool get synced => true;

  @override
  SettingsService? get service => null;
}

class _SignedInApi extends ApiClient {
  @override
  String? get userId => 'viewer-1';
  @override
  String? get userEmail => 'runner@test.com';
}

Future<Preferences> _prefs() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = Preferences();
  await prefs.init();
  return prefs;
}

Future<void> _pumpPreferences(WidgetTester tester, Preferences prefs) async {
  await tester.pumpWidget(MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: SettingsPreferencesScreen(
      page: PreferencesPage.privacy,
      preferences: prefs,
      settingsSync: _FakeSettingsSync(prefs),
    ),
  ));
  await tester.pump();
}

Future<void> _pumpAccount(WidgetTester tester, Preferences prefs) async {
  await tester.pumpWidget(MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: SettingsAccountScreen(
      apiClient: _SignedInApi(),
      preferences: prefs,
      settingsSync: _FakeSettingsSync(prefs),
    ),
  ));
  await tester.pump();
}

Future<void> _scrollTo(WidgetTester tester, Finder target) {
  return tester.scrollUntilVisible(
    target,
    250,
    scrollable: find.byType(Scrollable).first,
  );
}

void main() {
  group('privacy zones live on the Privacy & sharing page (#666 I11)', () {
    testWidgets('the Privacy & sharing page offers it and it opens',
        (tester) async {
      final prefs = await _prefs();
      await _pumpPreferences(tester, prefs);

      // Assert the population: the page itself is up, so a pass cannot come
      // from an empty list that scrolled past nothing.
      expect(find.widgetWithText(PageHeader, 'Privacy & sharing'),
          findsOneWidget);

      final row = find.byKey(const ValueKey('prefs-privacy-zones'));
      await _scrollTo(tester, row);
      await tester.tap(row);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(PrivacyZonesScreen), findsOneWidget);
    });

    testWidgets('the account screen no longer carries it', (tester) async {
      final prefs = await _prefs();
      await _pumpAccount(tester, prefs);

      // Population first: the account screen genuinely rendered its own body.
      // It scrolls — the AI-disclosure tile sits above this — so reach the
      // anchor the same way the sibling test reaches the privacy picker.
      await _scrollTo(tester, find.text('Delete account'));
      expect(find.text('Delete account'), findsOneWidget);
      expect(find.text('Privacy zones'), findsNothing);
      expect(find.text('Guided runs'), findsNothing);
      // The error-reports switch moved to Privacy & sharing with web's page.
      expect(find.text('Send error reports'), findsNothing);
      expect(find.text('View profile'), findsNothing);
    });
  });
}
