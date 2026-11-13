// You's settings search finds a Preferences row without opening its page, so
// it reads `preferencesRowTitles`, a list beside the page builders. These
// keep the list and the pages in step: every row a page draws is in its
// page's list, and every listed title is drawn by a default mount or named
// here as gated, with the gate.

import 'package:api_client/api_client.dart' show SettingsService;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ui_kit/ui_kit.dart' show ListRow;

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/preferences.dart';
import '../lib/screens/settings_preferences_screen.dart';
import '../lib/settings_sync.dart';
import '../lib/widgets/async_switch_tile.dart';

class _SyncedNoBag extends SettingsSyncService {
  _SyncedNoBag(Preferences prefs) : super(preferences: prefs);

  @override
  bool get synced => true;

  @override
  SettingsService? get service => null;
}

/// Rows a default mount (no API, no stores, nearby gate off, medication
/// unset) cannot show, each with what shows it.
Map<String, String> _gated(AppLocalizations l) => {
      l.prefsShowGym: 'the Gym and Nutrition stores',
      l.prefsShowNutrition: 'the Gym and Nutrition stores',
      l.prefsHrMedicationSetMaxHr: 'medication on with no max HR',
      l.prefsPrivateProfile: 'an ApiClient',
      l.followRequestsTitle: 'an ApiClient and a private profile',
      l.prefsDiscoverableNearby: 'the nearby deploy gate',
      l.nearbyAreaTitle: 'the nearby deploy gate and an ApiClient',
      l.prefsReadReceipts: 'an ApiClient',
      l.prefsMessageRequests: 'an ApiClient',
    };

Future<Set<String>> _drawn(WidgetTester tester, PreferencesPage page) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = Preferences();
  await prefs.init();
  tester.view.physicalSize = const Size(400, 12000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: SettingsPreferencesScreen(
      page: page,
      preferences: prefs,
      settingsSync: _SyncedNoBag(prefs),
      hrPrescription: true,
    ),
  ));
  await tester.pumpAndSettle();
  return {
    for (final r in tester.widgetList<ListRow>(find.byType(ListRow))) r.title,
    for (final r
        in tester.widgetList<AsyncSwitchTile>(find.byType(AsyncSwitchTile)))
      r.title,
  };
}

void main() {
  late AppLocalizations l10n;
  setUpAll(() async {
    await initializeDateFormatting();
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  for (final page in PreferencesPage.values) {
    testWidgets('${page.name}: the search index matches the drawn rows',
        (tester) async {
      final drawn = await _drawn(tester, page);
      final index = preferencesRowTitles(l10n, page).toSet();
      expect(drawn, isNotEmpty);
      expect(drawn.difference(index), isEmpty,
          reason: 'a row the search cannot find: add it to '
              'preferencesRowTitles');
      final gated = _gated(l10n);
      expect(
        index.difference(drawn).where((t) => !gated.containsKey(t)),
        isEmpty,
        reason: 'a listed title no page draws: drop it, or name its gate',
      );
    });
  }

  test('a title belongs to one page, so a result opens one place', () {
    final seen = <String, PreferencesPage>{};
    for (final page in PreferencesPage.values) {
      for (final t in preferencesRowTitles(l10n, page)) {
        expect(seen[t], isNull, reason: '"$t" is on ${seen[t]} and $page');
        seen[t] = page;
      }
    }
  });
}
